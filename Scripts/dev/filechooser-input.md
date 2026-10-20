# Private file chooser input

`filechooser_isolation.py` builds `filechooser-input.c` inside the assigned
guest workspace and owns its lifetime alongside the private compositor and
bus. The client keeps **one Wayland virtual keyboard** for that session.
Python command clients use its private Unix socket; they never create another
keyboard, open evdev/uinput, or discover a login-session display.

The existing Python drivers retain their Linux-keycode vocabulary through
`input_command()`. `filechooser_input.py` encodes key transitions or Unicode
codepoints and waits for the owner to acknowledge compositor dispatch. Key
commands use an XKB US map, including modifiers. Text uses single-symbol XKB
maps so spaces, punctuation and Unicode do not depend on the login layout.
Every published map is `XKB_V1`; the keyboard remains present between commands.
Temporary keymap files are unlinked disk-backed files under the session TMPDIR.

The owner validates its private namespace/display/socket environment before
connecting. The runner uses an unprivileged PID namespace with a private proc
mount, private HOME/XDG directories and a bounded transient user unit. All
builds and runtime checks happen in the assigned VM, never on the laptop or
physical VM host. Generated protocol code and binaries stay in the guest's
private runtime directory; no binaries are tracked or installed.

## Protocol provenance

`virtual-keyboard-unstable-v1.xml` is an unmodified copy of:

<https://raw.githubusercontent.com/atx/wtype/120fcf6cf9f42fa85eafda47573ddc8bb76f4b1b/protocol/virtual-keyboard-unstable-v1.xml>

Commit: `120fcf6cf9f42fa85eafda47573ddc8bb76f4b1b`.
SHA-256: `7ad7870003ecd592cae47dc19d277a609b7f18fd7b7be012623cf3225a7294f5`.
Its original copyright and MIT licence header are retained.

The build uses the guest's existing `wayland-scanner`, C compiler,
`wayland-client` and `xkbcommon` development files. The protocol's generated
client header/private code are compiled with warnings treated as errors.

## Resource regression

`filechooser-process-io-regression.py` observes the actual Qt renderer PID,
checks typed Unicode and modifier effects at a TextInput consumer, and measures
descriptor counts across repeated commands. Its `--legacy-keyboard` option
deliberately recreates the old per-command `wtype` connections for an isolated
upstream reproduction; normal drivers use the persistent owner.

`filechooser-isolation-regression.py` also exercises twelve production-portal
picker cycles, checks flat post-warm-up descriptors and bounded PSS, protects a
session-like process and companion in nested PID namespaces, and tests a
memory-hungry sibling's own cgroup limit. The outer launcher owns service-manager
access: the private test can request one fixed 64 MiB probe, whose body runs in
another bounded user unit and private PID namespace with a display-free profile.
No arbitrary command or service-manager API is exposed to the private workload.
These guest-only scripts require
fresh labels and the plan's verified delivery/access route.
