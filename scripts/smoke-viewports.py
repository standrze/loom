#!/usr/bin/env python3
"""PTY evidence for primary-screen viewports and query/mode lifecycle.

The small ASCII screen model recognizes only output used by this fixture; it is
not a terminal emulator and does not establish real-emulator scrollback behavior.
"""
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time


class Screen:
    def __init__(self, width=80, height=24):
        self.width, self.height = width, height
        self.rows = [list(" " * width) for _ in range(height)]
        self.x, self.y = 0, height - 4
        self.pending = bytearray()
        self.scrollback = []
        self.queries = 0

    def resize(self, width, height):
        self.rows = [row[:width] + [" "] * max(0, width - len(row))
                     for row in self.rows[:height]]
        self.rows += [list(" " * width) for _ in range(height - len(self.rows))]
        self.width, self.height = width, height
        self.x, self.y = min(self.x, width - 1), min(self.y, height - 1)

    def feed(self, data, reply):
        self.pending.extend(data)
        while self.pending:
            if self.pending[0] == 27:
                if len(self.pending) < 2:
                    break
                assert self.pending[1] == 91, bytes(self.pending[:100])
                end = next((i for i in range(2, len(self.pending))
                            if 64 <= self.pending[i] <= 126), None)
                if end is None:
                    break
                parameters = bytes(self.pending[2:end]).decode("ascii")
                command = chr(self.pending[end])
                del self.pending[:end + 1]
                if command == "H":
                    parts = parameters.split(";")
                    self.y = min(self.height - 1, max(0, int(parts[0] or 1) - 1))
                    self.x = min(self.width - 1, max(0, int(parts[-1] or 1) - 1))
                elif command == "n" and parameters == "6":
                    self.queries += 1
                    reply(f"\x1b[{self.y + 1};{min(self.x, self.width - 1) + 1}R".encode())
                elif command == "J":
                    raise AssertionError("primary viewport emitted screen clear")
                continue
            value = self.pending.pop(0)
            if value == 13:
                self.x = 0
            elif value == 10:
                self.linefeed()
            elif 32 <= value < 127:
                if self.x == self.width:
                    self.x = 0
                    self.linefeed()
                self.rows[self.y][self.x] = chr(value)
                self.x += 1

    def linefeed(self):
        if self.y == self.height - 1:
            self.scrollback.append("".join(self.rows.pop(0)))
            self.rows.append(list(" " * self.width))
        else:
            self.y += 1

    @property
    def text(self):
        return "\n".join("".join(row) for row in self.rows)


class Fixture:
    def __init__(self, binary, arguments=(), answer_queries=True):
        self.master, self.slave = pty.openpty()
        self.original = termios.tcgetattr(self.slave)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        self.process = subprocess.Popen([binary, *arguments], stdin=self.slave,
                                        stdout=self.slave, stderr=self.slave)
        self.output = bytearray()
        self.screen = Screen()
        self.answer_queries = answer_queries
        self.hold_queries = False
        self.deferred_reports = []

    def pump(self):
        if select.select([self.master], [], [], 0.05)[0]:
            data = os.read(self.master, 65536)
            self.output.extend(data)
            self.screen.feed(data, self.reply)

    def reply(self, report):
        if not self.answer_queries:
            return
        if self.hold_queries:
            self.deferred_reports.append(report)
        else:
            os.write(self.master, report)

    def release_query_after(self, typed_input):
        assert self.deferred_reports, "no withheld cursor report"
        # Deliver submission keys before CPR in the same ordered byte stream.
        # This causally exercises Enter while the application still awaits its query.
        os.write(self.master, typed_input + b"".join(self.deferred_reports))
        self.deferred_reports.clear()
        self.hold_queries = False

    def wait(self, predicate, description, timeout=10):
        deadline = time.monotonic() + timeout
        while not predicate() and time.monotonic() < deadline:
            self.pump()
            if self.process.poll() is not None:
                self.pump()
                break
        assert predicate(), (description, bytes(self.output[-3000:]))

    def send(self, text):
        os.write(self.master, text)

    def resize(self, width, height):
        self.screen.resize(width, height)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", height, width, 0, 0))
        os.kill(self.process.pid, signal.SIGWINCH)

    def finish(self):
        self.wait(lambda: self.process.poll() is not None, "clean process exit")
        while select.select([self.master], [], [], 0)[0]:
            self.pump()
        assert self.process.returncode == 0, bytes(self.output[-3000:])
        assert termios.tcgetattr(self.slave) == self.original, "termios not restored"
        assert b"\x1b[?2004l" in self.output, "bracketed paste not released"
        assert b"\x1b[?25h" in self.output, "cursor visibility not restored"
        assert b"\x1b[?1049h" not in self.output, "unexpected alternate screen"
        assert b"\x1b[2J" not in self.output, "unexpected ED2"

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        os.close(self.master)
        os.close(self.slave)


def inline(binary):
    fixture = Fixture(binary)
    try:
        fixture.wait(lambda: "INLINE" in fixture.screen.text, "queried inline startup")
        for number in range(5):
            message = f"log-{number}"
            fixture.send(message.encode() + b"\r")
            fixture.wait(lambda: ("committed: " + message).encode() in fixture.output,
                         "committed styled transcript")
        fixture.wait(lambda: "committed rows: 5" in fixture.screen.text, "retained UI state")
        transcript = "\n".join(fixture.screen.scrollback) + "\n" + fixture.screen.text
        assert "committed: log-0" in transcript and "committed: log-4" in transcript
        queries = fixture.screen.queries
        fixture.hold_queries = True
        fixture.resize(100, 30)
        fixture.wait(lambda: fixture.screen.queries > queries, "resize cursor query")
        fixture.release_query_after(b"after-resize\rqueued-second\r")
        fixture.wait(lambda: b"committed: after-resize" in fixture.output, "deferred post-resize insertion")
        fixture.wait(lambda: b"committed: queued-second" in fixture.output, "second deferred insertion")
        fixture.wait(lambda: "committed rows: 7" in fixture.screen.text, "exactly-once queued commits")
        assert fixture.output.count(b"committed: after-resize") == 1
        assert fixture.output.count(b"committed: queued-second") == 1
        fixture.send(b"q\r")
        fixture.finish()
        assert fixture.screen.queries >= 2
    finally:
        fixture.close()


def fixed(binary):
    fixture = Fixture(binary, ("--fixed",))
    try:
        fixture.wait(lambda: "FIXED" in fixture.screen.text, "fixed startup")
        for key in (b"m", b"s", b"r"):
            previous = len(fixture.output)
            fixture.send(key)
            fixture.wait(lambda: len(fixture.output) > previous, "fixed move/shrink/repaint")
            assert "TOP-SENTINEL" in fixture.screen.text
            assert "BOTTOM-SENTINEL" in fixture.screen.text
        fixture.send(b"q")
        fixture.finish()
        assert fixture.screen.queries == 0
    finally:
        fixture.close()


def query_timeout(binary):
    fixture = Fixture(binary, answer_queries=False)
    try:
        fixture.wait(lambda: fixture.screen.queries == 1, "initial cursor query")
        fixture.send(b"never-commit\r")
        fixture.wait(lambda: b"Cursor query timed out; exiting." in fixture.output,
                     "bounded query timeout")
        fixture.finish()
        assert fixture.screen.queries == 1
        assert b"Pending submissions discarded without insertion: 1." in fixture.output
        assert b"committed: never-commit" not in fixture.output
        assert b"INLINE" not in fixture.output
    finally:
        fixture.close()


if __name__ == "__main__":
    binary = sys.argv[1]
    inline(binary)
    fixed(binary)
    query_timeout(binary)
    print("Viewport PTY smoke passed: inline commit/resize, fixed sentinels, query timeout, mode restoration")
