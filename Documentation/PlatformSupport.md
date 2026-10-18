# Platform correctness and Windows integration

The platform increment pins Swift 6.4.1 in CI instead of assuming the latest
installed Xcode has a compatible compiler. Linux runs separate C and C.UTF-8
locale jobs. Windows builds/tests the library and every example using the native
console and ConPTY infrastructure in the matching weft dependency.

The initial dependency pin is an exact candidate commit while both repositories
are validated together. It must not be described as a semver release until that
release exists and the package is switched back to a version requirement.

## Unicode geometry

The matched weft implementation makes character width independent of libc locale.
Combining marks/default-ignorables contribute zero cells; Wide/Fullwidth and emoji
presentation handling are deterministic. This fixes the published Linux failure
where combining marks changed layout, selection, and symbol validation. Existing
loom paint, selection/copy, collection, panel, and plotting tests exercise that
same shared width function. Custom text measurement remains available.

## Windows boundary

loom still paints buffers and encodes ANSI output. weft owns native raw console
modes, UTF-16 console record input, resize/readiness and restoration. Child PTYs
use ConPTY. No duplicate input reader or application routing moves into loom.

Windows raw console sessions are supported; canonical input and POSIX shell
job-control suspension explicitly return unsupported errors. Native record input
is reconstructed UTF-8/VT rather than an original byte stream, and does not
promise original Kitty or bracketed-paste framing. Editors/pagers can use normal
terminal handoff. Native console support and ConPTY require actual Windows tests;
headless cell tests alone do not establish mode restoration or process behavior.

## Validation record

Local on 2026-10-18:

- macOS arm64: 283 loom tests passed in an isolated checkout against the patched weft.
- Linux arm64 Swift 6.4.1: 65 weft and 283 loom tests passed under both C and C.UTF-8.
- Linux PTY: weft standard/extended Escape, feature/handoff, and job-control checks passed;
  all four loom PTY checks, including plots/calendar and inline/fixed viewports, passed.

Hosted macOS/Linux/Windows runs validate the exact published candidate commits.
Record those results after completion; configuring the jobs is not a passing result.
