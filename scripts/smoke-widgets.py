#!/usr/bin/env python3
"""Exercise the standalone widget composition through a PTY."""
import codecs
import fcntl
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time
import unicodedata


class Screen:
    """The cursor/clear subset emitted by loom; styles and terminal modes are ignored."""

    def __init__(self, width, height):
        self.decoder = codecs.getincrementaldecoder('utf-8')()
        self.pending = ''
        self.frames = 0
        self.resize(width, height)

    def resize(self, width, height):
        self.width, self.height = width, height
        self.cells = [[' '] * width for _ in range(height)]
        self.x = self.y = 0

    @property
    def lines(self):
        return [''.join(row) for row in self.cells]

    @property
    def text(self):
        return '\n'.join(self.lines)

    def feed(self, data):
        self.pending += self.decoder.decode(data)
        position = 0
        while position < len(self.pending):
            char = self.pending[position]
            if char == '\x1b':
                match = re.match(r'\x1b\[([0-?]*)([ -/]*)([@-~])', self.pending[position:])
                if not match:
                    break
                params, _, command = match.groups()
                if command in ('H', 'f'):
                    values = [int(value or 1) for value in params.split(';')]
                    self.y = values[0] - 1
                    self.x = (values[1] if len(values) > 1 else 1) - 1
                elif command == 'J' and params == '2':
                    self.cells = [[' '] * self.width for _ in range(self.height)]
                elif command == 'l' and params == '?2026':
                    self.frames += 1
                position += len(match.group())
                continue
            position += 1
            if char == '\r':
                self.x = 0
            elif char == '\n':
                self.y += 1
            elif ord(char) >= 32:
                width = 2 if unicodedata.east_asian_width(char) in ('W', 'F') else 1
                if 0 <= self.y < self.height and 0 <= self.x < self.width:
                    self.cells[self.y][self.x] = char
                    if width == 2 and self.x + 1 < self.width:
                        self.cells[self.y][self.x + 1] = ''
                self.x += width
        self.pending = self.pending[position:]


master, slave = pty.openpty()
original = termios.tcgetattr(slave)
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 100, 0, 0))
process = subprocess.Popen([sys.argv[1]], stdin=slave, stdout=slave, stderr=slave)
screen = Screen(100, 24)
output = bytearray()


def wait_for(predicate, description, after_frame=-1):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if screen.frames > after_frame and predicate():
            return
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            data = os.read(master, 65536)
            output.extend(data)
            screen.feed(data)
        elif process.poll() is not None:
            break
    raise AssertionError(f'{description}\n{screen.text}\n{bytes(output[-500:])!r}')


def send(data, expected):
    previous = screen.frames
    os.write(master, data)
    predicate = expected if callable(expected) else lambda: expected in screen.text
    wait_for(predicate, str(expected), previous)


def resize(width, height, expected):
    previous = screen.frames
    screen.resize(width, height)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', height, width, 0, 0))
    os.kill(process.pid, signal.SIGWINCH)
    wait_for(lambda: expected in screen.text, f'resize to {width}x{height}', previous)


try:
    wait_for(lambda: 'loom widgets' in screen.text and 'job-0' in screen.text and 'Queue capacity' in screen.text, 'startup composition')
    send(b'\x1b[B', 'selected: 1')
    send(b's', lambda: 'descending' in screen.text and 'job-1' in screen.text)
    send(b'\x1b[H', 'selected: 39')
    send(b'f', lambda: 'Ready' in screen.text and 'job-38' in screen.text)
    send(b'\x1b[B', 'selected: 36')
    send(b'\t', 'focus: log')
    send(b'l', lambda: 'log 1:' in screen.text and 'log 0:' not in screen.text)
    send(b'a', 'center')
    send(b'h', 'col: 4')
    resize(54, 18, 'loom widgets')
    resize(8, 3, 'loom')
    resize(100, 24, 'selected: 36')
    send(b'd', lambda: 'loom details' in screen.text and 'Custom + shadow' in screen.text
         and 'Reverse + auto-height' in screen.text and 'Table row margins' in screen.text)
    assert '╦' in screen.text or '╤' in screen.text, 'merged junction missing'
    send(b'd', 'selected: 36')
    send(b'p', lambda: 'loom plots' in screen.text and 'Sparkline: requests' in screen.text
         and 'BarChart: workers' in screen.text and 'Chart: throughput' in screen.text
         and 'Canvas: layered shapes' in screen.text and 'October 2026' in screen.text)
    assert any('\u2800' <= char <= '\u28ff' for char in screen.text), 'plot raster missing'
    assert '█' in screen.text, 'bar or sparkline data missing'
    resize(54, 18, 'loom plots')
    resize(8, 3, 'loom plo')
    resize(100, 24, 'October 2026')
    send(b'p', 'selected: 36')
    os.write(master, b'\x1b')
    wait_for(lambda: b'\x1b[?1049l' in output, 'exit restores alternate screen')
    process.wait(timeout=8)
    while select.select([master], [], [], 0)[0]:
        output.extend(os.read(master, 65536))
    assert process.returncode == 0, bytes(output[-2000:])
    assert b'\x1b[?1049l' in output, 'alternate screen was not restored'
    assert b'\x1b[?1006l' in output, 'mouse capture was not released'
    assert termios.tcgetattr(slave) == original, 'terminal settings were not restored'
    print('Widgets PTY passed: composition, navigation, stable-ID sort/filter, log scroll, plots/calendar, resize, cleanup')
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
    os.close(slave)
