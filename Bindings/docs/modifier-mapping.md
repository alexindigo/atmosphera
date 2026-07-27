# Key Layout: Physical → Logical Mapping

## Internal Laptop Keyboard

xremap `modmap` swaps Alt and Super on the internal keyboard (`/dev/input/event2`):

```
Physical key          Remapped to
─────────────         ──────────────────
Left/Right Alt   →    Super_L / Super_R   (Cmd / Win key)
Left/Right Win   →    Alt_L / Alt_R
```

### Result

```
          macOS convention         niri sees
          ───────────────          ─────────
Alt       = Cmd (⌘)               Mod = Super
Win       = Option (⌥)            Alt
Ctrl      = Ctrl (⌃)              Ctrl
Shift     = Shift (⇧)             Shift
```

### Physical key usage

| Physical | Logical | Used For |
|----------|---------|----------|
| `Alt + key` | `Super + key` | niri Mod binds **and** macOS text shortcuts (remapped by xremap) |
| `Win + key` | `Alt + key` | niri secondary modifier chords |
| `Ctrl + key` | `Ctrl + key` | App shortcuts, media keys |

## External Keyboards

No modmap is applied to external keyboards (no device restriction match).

On external keyboards:
- The physical `Win` key is `Super` (niri Mod)
- The physical `Alt` key is `Alt`

---

## How xremap and niri interact

1. **xremap** processes key events from `/dev/input/event*`
   - `modmap`: swaps key codes (Alt ↔ Super)
   - `keymap`: remaps key combinations (Super+Right → End, etc.)
   - xremap outputs remapped events via a uinput device

2. **niri** (via libinput) reads the final events
   - Sees remapped key codes
   - Processes Mod binds for window management
   - Passes unbound keys through to applications

3. **Applications** receive only what niri doesn't consume
   - Text-navigation keys (Home, End, Ctrl+Home, Ctrl+End) from xremap
   - Clipboard keys (Ctrl+Insert, Shift+Insert) from xremap


---

Your `keyd` configuration is extremely close, but it isn't working because of three specific syntax and structural issues.

---

### Why the Current Configuration Isn't Working

1. **`[aliases]` cannot handle modifier swaps:** The `[aliases]` section is strictly for assigning friendly names to raw keycodes (like mapping an unusual macro key to a standard key identifier). It doesn't understand `meta` or `alt` here because those are layer names/modifier states, not raw keycodes. The actual layout keycodes are `leftmeta` and `leftalt`.
2. **The `[main]` section is empty:** You opened the `[main]` header but left it blank, so no keys are actually being remapped or swapped.
3. **`-1234:5678` is a placeholder:** That ID is a literal example. Because it doesn’t match the actual ID of your `xremap` virtual device, `keyd` isn't excluding it. It’s still grabbing `xremap`'s output and causing a feedback loop when both run.

---

### 🛠️ The Corrected Configuration

To fix this, the Alt/Super swap needs to happen inside the `[main]` section using the correct keycodes, and you need to fetch the real ID for `xremap`.

#### Step 1: Find your real `xremap` device ID

Run this command in your terminal to see what ID `keyd` actually assigns to the `xremap` virtual device when it connects:

```bash
sudo journalctl -eu keyd | grep -i "xremap"

```

Look for a line that says something like `device added: XXXX:YYYY xremap`. Copy that 8-character alphanumeric hex ID (e.g., `1234:abcd`).

#### Step 2: Update `/etc/keyd/default.conf`

Open your configuration file and update it to look like this (making sure to replace `XXXX:YYYY` with the real ID you found in Step 1):

```ini
[ids]
*
-XXXX:YYYY          # <--- Put your actual xremap hex ID here

[main]
# Swap Alt and Super keys cleanly at the layout layer
leftalt = leftmeta
leftmeta = leftalt
rightalt = rightmeta
rightmeta = rightalt

[meta]
# When the new Meta key (physical Alt) is held, Left-Click sends Ctrl+Left-Click
leftmouse = C-leftmouse

```

#### Step 3: Apply and Test

Reload `keyd` to apply the layout fix:

```bash
sudo keyd reload

```

Now start your user-level `xremap` service:

```bash
systemctl --user start xremap.service

```

### Why this setup is perfect for your workflow:

Because `keyd` sits at the absolute bottom layer, it tricks your entire system into thinking your physical `Alt` key (next to the spacebar) is actually the `Super` key.

When you press physical `Alt`, `keyd` sends `Super` up the chain. Your user-level `xremap` daemon (which is listening to `keyd`) will catch that `Super` input perfectly, meaning all your existing `xremap` keyboard shortcuts and your Niri window management shortcuts will now seamlessly work using your physical `Alt` key, mimicking a Mac layout.


---
```
Can I catch specific mouse (touchpad)  and keyboard (laptop internal), as I have desktop real mouse, and desktop good keyboard where I don't need to swap alt with meta.
```
---

Targeting your laptop's internal hardware while leaving your desktop peripherals completely stock is a fantastic way to handle a hybrid workstation.

By explicitly specifying your laptop's internal hardware IDs, **you completely eliminate the wildcard loop danger**. Because `keyd` will be blind to everything except your laptop, you no longer need the `-1234:5678` loop prevention line, and you can let `xremap` be universal again.

---

### Step 1: Find Your Laptop's Hardware IDs

To tie `keyd` strictly to your laptop's built-in controls, you need their exact 8-character hardware hex IDs.

1. Open a terminal and run the `keyd` monitoring tool:
```bash
sudo keyd monitor

```


2. **Press a key on your laptop's internal keyboard**, then **click your laptop's touchpad**.
3. Look at the terminal output. Look for lines that look like `device added` or input events showing hex codes. It will look similar to this:
> `05ac:0281` Apple SPI Keyboard
> `05ac:0331` Apple SPI Trackpad


4. Note down those two unique `vendor:product` hex codes.

---

### Step 2: Write the Target-Specific `keyd` Config

Open your `/etc/keyd/default.conf` file and replace the `*` wildcard with your explicit hardware IDs listed line-by-line.

```ini
[ids]
# Replace these with your actual laptop IDs found in Step 1
05ac:0281  
05ac:0331  

[main]
# This Alt/Super swap will ONLY apply to the laptop keyboard
leftalt = leftmeta
leftmeta = leftalt
rightalt = rightmeta
rightmeta = rightalt

[meta]
# This Super+Click fix will ONLY apply to the laptop touchpad + keyboard combo
leftmouse = C-leftmouse

```

> 💡 **Why this fixes everything:** Because `keyd` combines the modifier states of any devices listed together in the `[ids]` block, holding `Alt` (which becomes `Super`) on your laptop keyboard will flawlessly modify a click on your laptop touchpad. Your desktop mouse and desktop keyboard are completely ignored by `keyd` and will behave normally.

Reload `keyd` to apply your hardware boundaries:

```bash
sudo keyd reload

```

---

### Step 3: Make `xremap` Universal for Both Keyboards

Since `keyd` is now strictly sandboxed to your laptop hardware, it is impossible for `xremap` to cause an input loop. This means you can drop the `--device` restriction from your user-level systemd service.

By removing that restriction, `xremap` will safely apply your app-specific shortcuts (like your browser bindings) to **both** your laptop keyboard and your premium desktop keyboard.

Open your user-level service file (`~/.config/systemd/user/xremap.service`) and update `ExecStart`:

```ini
ExecStart=/usr/bin/xremap --watch=config %h/Projects/atmosphera-bindings/niri/atmosphera-xremap.yml %h/.config/xremap/config.yml

```

Reload and restart the service:

```bash
systemctl --user daemon-reload
systemctl --user restart xremap.service

```

### The End Result

* **On your laptop:** The keys are physically swapped (macOS style), and `Cmd + Click` cleanly opens browser tabs.
* **On your desktop setup:** The layout remains standard PC style, your mouse clicks are normal, and `xremap` still runs your app shortcuts cleanly in the background.


---
```
So, this is my keyd config:
```
[ids]
0001:0001 # built-in laptop keyboard (AT Translated Set 2)
093a:0274 # touchpad (PIXA3854, listed as both Mouse and Touchpad)
0002:0006 # trackpoint/built-in mouse (ImExPS/2)

[main]
# Swap Alt and Super at the keycode level.
# Physical Alt (next to Space) → Super (Cmd)
# Physical Win/Super (left of Alt) → Alt
leftalt = leftmeta
leftmeta = leftalt
rightalt = rightmeta
rightmeta = rightalt

[meta]

# macOS Cmd+click → Ctrl+click (open link in new tab)
leftmouse = C-leftmouse
```

And this is keyd monitor and me pressing (physical)Alt+Space expecting to get Super/Meta+Space, to switch input layout, and it doesn't work, and then pressing (physical)Meta+Space, which I expect be mapped into software Alt, and it does switch input language (that is set in Niri config to switch on Super+Space).

```
$ sudo keyd monitor
device added: 1234:5678:bb6ea973 xremap (/dev/input/event18)
device added: 0fac:1ade:d2b36ae6 keyd virtual pointer (/dev/input/event17)
device added: 0fac:0ade:bea394c0 keyd virtual keyboard (/dev/input/event16)
device added: 0002:0006:e7c70575 ImExPS/2 Generic Explorer Mouse (/dev/input/event9)
device added: 2333:6666:e7fb73a9 ydotoold virtual device (/dev/input/event15)
device added: 093a:0274:f97d4846 PIXA3854:00 093A:0274 Touchpad (/dev/input/event8)
device added: 093a:0274:9e5c2492 PIXA3854:00 093A:0274 Mouse (/dev/input/event7)
device added: 32ac:0006:54f6892d FRMW0004:00 32AC:0006 Consumer Control (/dev/input/event6)
device added: 32ac:0006:33ec7f81 FRMW0004:00 32AC:0006 Wireless Radio Control (/dev/input/event5)
device added: 0000:0006:bdb72f48 Video Bus (/dev/input/event3)
device added: 0001:0001:09b4e68d AT Translated Set 2 keyboard (/dev/input/event2)
device added: 0000:0001:48a093aa Power Button (/dev/input/event1)
AT Translated Set 2 keyboard    0001:0001:09b4e68d      enter up
AT Translated Set 2 keyboard    0001:0001:09b4e68d      leftalt down
AT Translated Set 2 keyboard    0001:0001:09b4e68d      space down
AT Translated Set 2 keyboard    0001:0001:09b4e68d      space up
AT Translated Set 2 keyboard    0001:0001:09b4e68d      leftalt up
AT Translated Set 2 keyboard    0001:0001:09b4e68d      leftmeta down
AT Translated Set 2 keyboard    0001:0001:09b4e68d      space down
AT Translated Set 2 keyboard    0001:0001:09b4e68d      space up
AT Translated Set 2 keyboard    0001:0001:09b4e68d      leftmeta up
AT Translated Set 2 keyboard    0001:0001:09b4e68d      leftmeta down
AT Translated Set 2 keyboard    0001:0001:09b4e68d      space down
AT Translated Set 2 keyboard    0001:0001:09b4e68d      space up
AT Translated Set 2 keyboard    0001:0001:09b4e68d      leftmeta up
AT Translated Set 2 keyboard    0001:0001:09b4e68d      leftalt down
AT Translated Set 2 keyboard    0001:0001:09b4e68d      space down
AT Translated Set 2 keyboard    0001:0001:09b4e68d      space up
AT Translated Set 2 keyboard    0001:0001:09b4e68d      leftalt up
AT Translated Set 2 keyboard    0001:0001:09b4e68d      leftcontrol down
AT Translated Set 2 keyboard    0001:0001:09b4e68d      c down
```
---

The reason your layout swap is behaving backward or ignoring your commands is due to a fundamental rule of how `keyd` handles modifiers: **In `keyd`, modifier keys are not just basic keycodes; they are gates to built-in layers.**

By default, `keyd` translates your modifiers internally like this:

* `leftmeta` = `layer(meta)`
* `leftalt` = `layer(alt)`

When you try to do a direct bidirectional swap using raw names in `[main]` (like `leftalt = leftmeta` and `leftmeta = leftalt`), the configuration parser gets confused by the circular reference and fails to route the underlying layer logic correctly. This is why your physical Meta key was still leaking through as Super.

---

### The Fix: Route to Layers Explicitly

To cleanly swap the keys, you must explicitly assign them to their respective native destination layers using the `layer()` function.

Update your `/etc/keyd/default.conf` file to match this configuration:

```ini
[ids]
0001:0001 # built-in laptop keyboard (AT Translated Set 2)
093a:0274 # touchpad (PIXA3854, listed as both Mouse and Touchpad)
0002:0006 # trackpoint/built-in mouse (ImExPS/2)

[main]
# Swap Alt and Super bidirectionally using native layers
leftalt = layer(meta)
leftmeta = layer(alt)
rightalt = layer(meta)
rightmeta = layer(alt)

[meta]
# Inside the meta layer (triggered by physical Alt), Left-Click sends Ctrl+Click
leftmouse = C-leftmouse

```

### Why This Config works Perfectly:

1. **Physical Alt + Space:** When you press your physical Alt key, `keyd` shifts the system into the `meta` layer. When you tap Space, it outputs `Meta + Space` (Super + Space), which Niri will catch to cleanly switch your input layout.
2. **Physical Meta + Space:** When you press your physical Windows/Meta key, `keyd` shifts the system into the `alt` layer, sending a proper `Alt + Space` up the chain.
3. **The Mouse Fix:** Because your custom `[meta]` block targets the exact same `meta` layer, holding down your physical Alt key (now acting as Meta/Cmd) and left-clicking your touchpad will flawlessly trigger `Ctrl + Left-Click` to open those browser links in new tabs.

---

### Apply the Changes

Once you save the file, tell `keyd` to reload its configuration:

```bash
sudo keyd reload

```

Your `keyd monitor` stream will now accurately translate the states, your laptop keys will behave exactly like a Mac layout, and your desktop peripherals will remain completely untouched and standard.



---
```
What do you know about keyd macros?
```
---

In `keyd`, macros are a incredibly powerful way to automate text entry, chain complex keyboard shortcuts, and introduce specific temporal behavior (delays) directly at the kernel level.

Because `keyd` handles inputs so close to the metal, its macro processor is lightweight, precise, and completely agnostic to whether you are on X11, Wayland, or a virtual TTY console.

---

## 1. The Three Forms of Macro Syntax

`keyd` recognizes a macro expression in three distinct formats, ranging from simple shortcuts to complex expressions:

| Form Type | Syntax Example | What it does |
| --- | --- | --- |
| **Type 1: Explicit Expression** | `macro(C-t 50ms g o o g l e . c o m enter)` | Executes an advanced sequence of shortcuts, text, and timing delays. |
| **Type 2: Inline Modifier Shortcut** | `C-S-t` or `A-M-x` | Shorthand for simple chords. `C-S-t` tells it to depress `Control + Shift + t`. |
| **Type 3: Literal Character** | `☺` or `λ` | Sends a raw Unicode character to the active window. |

---

## 2. Advanced Tokens Inside `macro()`

When using the explicit `macro(...)` block, you write a string of **tokens** separated by spaces. `keyd` parses these tokens from left to right. Inside a single macro block, you can mix text, explicit keycodes, chords, and pauses.

### String Literal Typing

To type a simple word or sentence, you can just write the text out:

```ini
# Types out "Hello World" and presses the Enter key
capslock = macro(Hello space World enter)

```

### Chorded Keys (Simultaneous Presses)

If you want multiple keys to be pressed down *at the exact same time* inside a macro sequence, you join them with a `+` symbol:

```ini
# Simultaneously taps Left Control and Left Meta (Super)
F12 = macro(leftcontrol+leftmeta)

```

### Timeouts and Delays

You can insert micro-pauses within a sequence to give applications time to react to a UI event (e.g., waiting for a browser tab to open before pasting text). Delays are declared using `ms` (milliseconds), up to a maximum limit of `1023ms`.

```ini
# Opens a new browser tab, waits 100ms for it to load, types an address, and submits it
F1 = macro(C-t 100ms archlinux.org enter)

```

---

## 3. The Escaping Mechanism (The Space Rule)

Because `keyd` uses explicit names like `space`, `enter`, and `backspace` to represent actual physical keycodes, typing those literal words requires a clever parsing trick based on spaces.

* **Parsed as a Keycode:** If the word stands alone between spaces, it fires the key action.
```ini
macro(space)  # Hits the spacebar once
macro(3+5)    # Hits the 3 and 5 keys simultaneously

```


* **Parsed as Literal Text:** If you split or space out the characters of a keycode word, `keyd` escapes it and prints the text sequentially.
```ini
macro(s pace)  # Types out the word "space"
macro(3 + 5)   # Types out the text "3+5"

```



---

## 4. Crucial Macro Behavior to Keep in Mind

If you are transitioning to `keyd` from tools like Autokey or custom QMK firmware, there is one major architectural design choice you must be aware of: **Macros do not inherently repeat when held down.**

```
Normal Key:   [Key Down] ───────────────────────► (Repeats via OS) ──► [Key Up]
keyd Macro:   [Key Down] ──► (Fires macro sequence and releases) ────► [Key Up does nothing]

```

When you map a key to a standard macro, `keyd` executes the entire chain of downs and ups instantly on the initial keystroke. If you continue to hold the physical key down, nothing happens because the macro has already synthetically released those keys.

If you need a macro to repeat, or you want to trigger things before moving into a layer, you must pair it with helper functions like `layerm()` (execute macro then hold layer) or `repeat()` (re-execute the last macro).

Are you looking to write a specific text macro, or are you hoping to string together a complex multi-step shortcut for your desktop environment?


---
```
Can I use macros to do Meta+MouseClick to Ctrl+MouseClick?
```
---

No.



---
```
From Grok
```
---

**Keyd is an excellent choice** for this on Wayland (including Niri). It works at the kernel level via evdev/uinput, so it's compositor-agnostic and reliable under Niri.

### 1. Install keyd
On Arch-based (or similar):
```bash
sudo pacman -S keyd
```

On other distros, build from source or check packages (it's straightforward). After install:
```bash
sudo systemctl enable --now keyd
```

### 2. Swap Meta (Super) and Alt
Create/edit the config at `/etc/keyd/default.conf` (use sudo):

```ini
[ids]
# Applies to all keyboards; you can restrict by device ID if needed

[main]
leftmeta = layer(alt)
leftalt = layer(meta)
rightmeta = layer(alt)
rightalt = layer(meta)
```

- This swaps them: Physical **Left/Right Meta (Super/Windows)** now acts as **Alt**, and physical **Left/Right Alt** now acts as **Meta**.
- Reload with `sudo keyd reload`.

Test with `wev` (Wayland event viewer) or just in your apps.

**Notes on Niri**: Niri uses its own config for some bindings (often `Mod` which is Super/Meta by default). After the swap, your physical Alt key will send Meta, so update Niri bindings that used Super to expect the new behavior if needed. Niri also supports XKB remaps for some things, but keyd is more powerful for full swaps.

### 3. Meta + Mouse Click → Ctrl + Mouse Click (Mac-like new tab behavior)
Keyd excels at keyboard layers but has limited direct mouse+keyboard combo support in basic configs (it's primarily a keyboard daemon).

**Best options:**

- **Use keyd for the swap + another tool for mouse combos**, or check if keyd's layers + overload can help indirectly.
- **Recommended complementary tool: xremap** (supports Niri explicitly, mouse input, and complex remaps).

  Install via Cargo (with Niri feature):
  ```bash
  cargo install xremap --features niri
  ```
  Run it with appropriate permissions (often via `setcap` or as a service).

  Example config snippet for xremap (in `~/.config/xremap/config.yml` or similar):
  ```yaml
  modmap:
    - name: Swap Alt/Meta (if not using keyd)
      remap:
        Super_L: Alt_L
        Alt_L: Super_L
  # etc.

  keymap:
    - name: Meta+Click to Ctrl+Click
      remap:
        Super-Button1: Ctrl-Button1   # Left click with Super (your new Meta) becomes Ctrl+click
  ```

  xremap can listen to mouse devices (`--mouse` flag) and do exactly this kind of modifier+button remapping.

- **Alternative: input-remapper** (GUI, good for mouse buttons, works on Wayland).

- **For pure keyd + mouse**: You might layer a "mouse mod" but it's trickier for direct button injection. Many users combine keyd (keyboard) with tools like evremap or makima for mouse.

### Quick Test & Troubleshooting
1. After keyd config: `sudo keyd reload` and test keys.
2. Use `evtest` or `wev` to verify what events are sent.
3. For browsers: Once Meta (physical Alt) + click sends Ctrl + click, links should open in new tabs like Cmd+click on macOS.
4. Niri-specific: Check `man niri` or its config for `keyboard` / `binds` sections if you need compositor-level tweaks.

This setup gives you a Mac-like experience (swapped modifiers + Command-click behavior). Keyd is lightweight and very flexible for further custom layers (e.g., oneshot modifiers, mouse emulation with keyboard, etc.).

If you run into device-specific issues, share output from `keyd monitor` or your keyboard/mouse names.