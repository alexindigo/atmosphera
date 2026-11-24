"""Build a task-owned v0.4-derived physical US Wayland fixture injector.

The ordinary wtype assigns printable text physical keycodes starting at Escape
and writes its keymap to /tmp. Qt modal popups may interpret those physical codes
instead of the uploaded arbitrary keymap. This guest-only fixture uses standard
US physical keys and a standard libxkbcommon keymap with an anonymous memfd. It
does not install or change a system tool, keyboard configuration or base VM.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request
from guest_profile import activate_profile, profile_argument

parser = argparse.ArgumentParser(description=__doc__)
profile_argument(parser)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
profile = activate_profile(args.guest_profile)
profile.prepare_roots()
ROOT = args.output
if ROOT != ROOT.resolve() or ROOT == profile.work_base or not ROOT.is_relative_to(profile.work_base):
    parser.error('output must be a fresh directory in the verified guest work root')
ROOT.mkdir(exist_ok=False)
sources = {}
for name in ('main.c', 'protocol/virtual-keyboard-unstable-v1.xml'):
    url = 'https://raw.githubusercontent.com/atx/wtype/v0.4/' + name
    data = urllib.request.urlopen(url, timeout=30).read()
    expected = {'main.c': '713597abfc049196864ffcc041bb6683c761b71d68ed2da86cdcfc6b7ed3d244',
                'protocol/virtual-keyboard-unstable-v1.xml': '7ad7870003ecd592cae47dc19d277a609b7f18fd7b7be012623cf3225a7294f5'}
    assert hashlib.sha256(data).hexdigest() == expected[name], 'pinned upstream bytes changed'
    target = ROOT / Path(name).name
    target.write_bytes(data)
    sources[name] = dict(url=url, sha256=hashlib.sha256(data).hexdigest())

path = ROOT / 'main.c'
text = path.read_text()
def replace(old, new):
    global text
    assert text.count(old) == 1, old
    text = text.replace(old, new)

replace('#include <fcntl.h>', '#define _GNU_SOURCE\n#include <stdarg.h>\n#include <fcntl.h>')
replace('struct keymap_entry {\n', 'struct keymap_entry {\n\tunsigned int physical;\n\tunsigned int shift;\n')
replace('static unsigned int append_keymap_entry', '''static unsigned int physical_code(struct wtype *wtype, xkb_keysym_t key)
{
    switch (key) {
    case XKB_KEY_Escape: return 1;
    case XKB_KEY_BackSpace: return 14;
    case XKB_KEY_Tab: return 15;
    case XKB_KEY_Return: return 28;
    case XKB_KEY_space: return 57;
    case XKB_KEY_Home: return 102;
    case XKB_KEY_Up: return 103;
    case XKB_KEY_Page_Up: return 104;
    case XKB_KEY_Left: return 105;
    case XKB_KEY_Right: return 106;
    case XKB_KEY_End: return 107;
    case XKB_KEY_Down: return 108;
    case XKB_KEY_Page_Down: return 109;
    case XKB_KEY_Insert: return 110;
    case XKB_KEY_Delete: return 111;
    default: break;
    }
    const char *plain[] = {"1234567890-=", "qwertyuiop[]", "asdfghjkl;'", "`", "\\\\", "zxcvbnm,./"};
    const char *shifted[] = {"!@#$%^&*()_+", "QWERTYUIOP{}", "ASDFGHJKL:\\"", "~", "|", "ZXCVBNM<>?"};
    const unsigned int start[] = {2,16,30,41,43,44};
    unsigned int character = xkb_keysym_to_utf32(key);
    for (size_t row=0; row<ARRAY_SIZE(start); row++) {
        for (size_t column=0; plain[row][column]; column++) {
            if (character == (unsigned char)plain[row][column]) return start[row]+column;
            if (character == (unsigned char)shifted[row][column]) return (start[row]+column) | 256;
        }
    }
    fail("This task input batch requires an unsupported physical US key");
    return 0;
}

static unsigned int append_keymap_entry''')
replace('wtype->keymap = realloc(\n', 'unsigned int physical = physical_code(wtype, xkb);\n\twtype->keymap = realloc(\n')
replace('wtype->keymap[wtype->keymap_len - 1].wchr = ch;', 'wtype->keymap[wtype->keymap_len - 1].physical = physical & 255;\n\twtype->keymap[wtype->keymap_len - 1].shift = (physical & 256) ? WTYPE_MOD_SHIFT : 0;\n\twtype->keymap[wtype->keymap_len - 1].wchr = ch;')
replace('wtype->keyboard, 0, cmd->single_key_code,', 'wtype->keyboard, 0, wtype->keymap[cmd->single_key_code - 1].physical,')
replace('static void type_keycode(struct wtype *wtype, unsigned int key_code)\n{', '''static void type_keycode(struct wtype *wtype, unsigned int key_code)
{
    unsigned int shifted = wtype->keymap[key_code - 1].shift;
    key_code = wtype->keymap[key_code - 1].physical;
    zwp_virtual_keyboard_v1_modifiers(wtype->keyboard, wtype->mod_status | shifted, 0, 0, 0);
    wl_display_roundtrip(wtype->display);''')
replace('\t\tusleep(cmd->delay_ms * 1000);\n\t}\n}\n\nstatic void run_text_stdin', '\t\tusleep(cmd->delay_ms * 1000);\n\t}\n\tzwp_virtual_keyboard_v1_modifiers(wtype->keyboard, wtype->mod_status, 0, 0, 0);\n\twl_display_roundtrip(wtype->display);\n}\n\nstatic void run_text_stdin')
start = text.index('static void upload_keymap(struct wtype *wtype)\n{')
end = text.index('\n\nint main(', start)
text = text[:start] + '''static void upload_keymap(struct wtype *wtype)
{
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = {.rules="evdev", .model="pc105", .layout="us"};
    struct xkb_keymap *map = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (!map) fail("Cannot compile task US keymap");
    char *body = xkb_keymap_get_as_string(map, XKB_KEYMAP_FORMAT_TEXT_V1);
    size_t size = strlen(body) + 1;
    int fd = memfd_create("atmosphera-test-keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, body, size) != (ssize_t)size) fail("Cannot prepare anonymous keymap");
    zwp_virtual_keyboard_v1_keymap(wtype->keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
    wl_display_roundtrip(wtype->display);
    close(fd); free(body); xkb_keymap_unref(map); xkb_context_unref(context);
}
''' + text[end:]
path.write_text(text)
sources['candidate'] = dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(), changes=['anonymous memfd', 'standard physical US literal and control codes', 'standard libxkbcommon US keymap', 'explicit Shift for punctuation/case'])

def run(args):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    with (ROOT / 'build.log').open('a') as log:
        log.write(' '.join(args) + '\n' + result.stdout + result.stderr)
    result.check_returncode()

run(['wayland-scanner', 'client-header', 'virtual-keyboard-unstable-v1.xml', 'virtual-keyboard-unstable-v1-client-protocol.h'])
run(['wayland-scanner', 'private-code', 'virtual-keyboard-unstable-v1.xml', 'virtual-keyboard-unstable-v1-protocol.c'])
flags = subprocess.check_output(['pkg-config', '--cflags', '--libs', 'wayland-client', 'xkbcommon'], text=True).split()
run(['cc', '-O2', '-Wall', '-Wextra', '-o', 'input-injector', 'main.c', 'virtual-keyboard-unstable-v1-protocol.c', *flags])
sources['binary'] = dict(path=str(ROOT / 'input-injector'), sha256=hashlib.sha256((ROOT / 'input-injector').read_bytes()).hexdigest())
(ROOT / 'provenance.json').write_text(json.dumps(sources, indent=2) + '\n')
print(json.dumps(sources, indent=2))
