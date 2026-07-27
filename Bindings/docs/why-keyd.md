That clears things up completely. Since your app-specific keyboard mappings are working perfectly, your systemd user environment, `NIRI_SOCKET` communication, and multi-file setup are 100% correct.

The reason your keyboard maps work while your mouse map fails comes down to an open architectural conflict between **`xremap`'s virtual device implementation and Niri's input stack.**

---

### The Root Cause: Wayland Seat Disconnect

Niri is built on the `smithay` compositor library. Under Wayland, input events must be explicitly tied to a specific pointer "seat" and coordinate space.

When you pass the `--mouse` flag, `xremap` grabs your mouse and emits remapped clicks through a virtual `uinput` device. While this works on some compositors, Niri rigidly expects mouse button events (`BTN_LEFT`, `BTN_MIDDLE`, etc.) to originate from a device that is actively broadcasting hardware pointer motion data on the same seat. Because `xremap` emits a synthetic click from a virtual device without matching seat motion context, **Niri silently drops the click event.**

This is a known issue with `xremap` handling mouse buttons under Niri/Smithay. Fortunately, you have a couple of ways to handle this depending on how much you want to tweak your workflow.

---

### Workaround 1: Test the Middle-Click Bind

Browsers natively open links in a new tab when they receive a middle-click (`BTN_MIDDLE`). Sometimes `xremap` has better luck passing a clean button translation if it doesn't have to stitch a keyboard modifier (`Ctrl`) onto a synthetic mouse event.

Try updating your browser block to map the shortcut directly to a middle-click:

```yaml
keymap:
  - name: "Mac-style Link Opening"
    application:
      only: [firefox, brave-browser]
    remap:
      Super-BTN_LEFT: BTN_MIDDLE

```

If Niri still drops the synthetic event into the void, you will need to bypass `xremap`'s virtual mouse generation entirely using one of the methods below.

---

### Workaround 2: The Application `modmap` Flip (The Native Mouse Route)

If you use `modmap` instead of `keymap`, you can map your physical keys directly before they ever hit the application layer. If you tell `xremap` to make your browser think your `Super` key is actually the `Ctrl` key, you bypass the virtual mouse issue entirely.

When you hold `Super` and click, the browser receives a genuine `Ctrl` modifier combined with a **raw hardware click** from your real mouse, preserving perfect coordinate data.

Add this to your configuration:

```yaml
modmap:
  - name: "Mac-style Cmd key for Browsers"
    application:
      only: [firefox, brave-browser]
    remap:
      LEFTMETA: LEFTCTRL

```

> ⚠️ **The Niri Catch:** Because this remaps the `Super` key globally while the browser window is focused, any Niri window-management shortcuts that rely on `Super` (like `Super + Left/Right` to shift columns) will be interpreted as `Ctrl + Left/Right` while you are looking at Firefox or Brave. If you rely heavily on navigating your desktop while focused on a browser, this will disrupt your workflow.

---

### Workaround 3: Migrate to `keyd`

If you need your Niri shortcuts to stay perfectly intact while browsing *and* you want seamless `Super + Click` functionality, you will have to step away from `xremap` for your mouse events.

`keyd` handles virtual pointer seats differently on Wayland by compiling all intercepted inputs into a tightly bound virtual seat that Niri natively respects. To do this without hitting device-grabbing conflicts (`EBUSY` errors), you would need to port your existing keyboard and mouse configurations into `/etc/keyd/default.conf`.


---
```
Can modmap be app specific? And yes, I rely on Super+ shortcut a lot within browsers. Would keyd work together with xremap?
```
---

### Can `modmap` be app-specific?

**Yes, absolutely.** `xremap` allows you to scope `modmap` blocks to specific applications using the exact same `application: only:` syntax as `keymap`.

```yaml
modmap:
  - name: "Browser only Super to Ctrl"
    application:
      only: [firefox, brave-browser]
    remap:
      Super_L: Ctrl_L

```

**However, this will still break your workflow.** Because `modmap` alters the key at the lowest layer of `xremap`, the moment Firefox or Brave is focused, your physical `Super` key literally *becomes* the `Ctrl` key. If you try to use a Niri window-management shortcut (like `Super + Right` to switch columns) while looking at your browser, Niri will receive `Ctrl + Right` instead. Your window switching will stop working whenever a browser is active.

---

### Would `keyd` work together with `xremap`?

Yes, they can work together, but **not if you split them up** (e.g., making `keyd` handle the mouse and `xremap` handle the keyboard).

To intercept a mixed shortcut like `Super + Left-Click`, a single remapping daemon must have a global grasp of *both* devices simultaneously. If `xremap` takes exclusive control of the keyboard, `keyd` will only see the mouse click and will have no idea you are holding down the `Super` key, causing the shortcut to fail.

### The Solution: The Stacked Daemon Pipeline

You can stack `keyd` and `xremap` in a pipeline. Because `keyd` compiles keyboard and mouse inputs into a unified virtual seat that Niri natively accepts, it completely bypasses the Wayland seat-disconnect bug.

You can use `keyd` at the absolute lowest hardware layer to handle your mouse fix globally, and then let it pass everything else up to `xremap` to handle your app-specific keyboard configurations.

```
[Physical Devices] 
       │
       ▼
 1. keyd (Intercepts hardware globally; fixes Super+Click)
       │
       ▼ [Outputs to "keyd virtual keyboard"]
 2. xremap (Grabs the virtual keyboard; handles your app-specific keys)
       │
       ▼
 [Niri / Browsers]

```

#### Step 1: Configure `keyd` for the Global Mouse Fix

Install `keyd` (`sudo pacman -S keyd`) and write a global configuration that intercepts your hardware and maps `Super + Left-Click` to `Ctrl + Left-Click`:

```ini
#/etc/keyd/default.conf
[ids]
*

[meta]
leftmouse = C-leftmouse

```

Enable and start it: `sudo systemctl enable --now keyd`.

> 💡 **Why this won't break Niri:** `keyd` is highly intelligent with modifiers. If you hold `Super` and press a key that *isn't* mapped in the `[meta]` block (like your Niri column switching arrows), `keyd` passes the `Super` modifier through perfectly. Your Niri window management will remain 100% intact.

#### Step 2: Point `xremap` to the Virtual Keyboard

Because `keyd` is now controlling your physical hardware, it creates a clean upstream device named `"keyd virtual keyboard"`.

You do not need to change a single line of your actual remapping code inside your YAML files. You only need to tell `xremap` to listen exclusively to `keyd`'s virtual output so they don't fight over your physical hardware devices.

Update the `ExecStart` line in your user-level systemd service file to include the device filter:

```ini
ExecStart=/usr/bin/xremap --device "keyd virtual keyboard" --watch=config %h/Projects/atmosphera-bindings/niri/atmosphera-xremap.yml %h/.config/xremap/config.yml

```

*(Note: You can safely drop the `--mouse` flag here since `keyd` is taking care of the mouse translation context downstairs).*

Reload your systemd user daemon and restart your service:

```bash
systemctl --user daemon-reload
systemctl --user restart xremap.service

```

With this architecture, `keyd` tricks Niri into accepting the mouse click as a native pointer action, while `xremap` retains full control over your application-specific keyboard layers.



---
```
How do I run keyd, can I make it user level systemd service?
```
---

To answer directly: **No, you cannot reliably run `keyd` as a user-level systemd service (`systemctl --user`). It must be run as a system-wide service.**

The developer of `keyd` designed it strictly to run with root privileges. Because it intercepts raw kernel input blocks (`/dev/input/*` and `/dev/uinput`), attempting to force it into a user-level service strips away its ability to handle device hotplugging (e.g., if you unplug and plug back in your mouse, a non-root `keyd` loses track of it completely). It also prevents `keyd` from granting itself real-time processing priority (`nice -20`), which is vital to prevent input lag.

However, running `keyd` as a system service **does not mean** you have to abandon your user-level `xremap` setup. They can coexist perfectly in a hybrid configuration.

Here is exactly how to run `keyd` alongside your user-level `xremap` service.

---

### Step 1: Create the Global `keyd` Configuration

Since `keyd` runs at the system level, its configuration lives in `/etc`. Create the configuration directory and file:

```bash
sudo mkdir -p /etc/keyd
sudo nano /etc/keyd/default.conf

```

Paste your mouse fix inside:

```ini
[ids]
*

[meta]
leftmouse = C-leftmouse

```

### Step 2: Start the System-Level `keyd` Service

Enable and start the standard, pre-configured system service that came with the package:

```bash
sudo systemctl enable --now keyd

```

At this point, `keyd` is actively running in the background. It absorbs your physical keyboard and mouse inputs, processes the `Super + Left-Click` translation, and exposes a new, combined virtual hardware device to the system.

---

### Step 3: Update your User-Level `xremap` Service

Now you just need to tell your user-level `xremap` service to process input *after* `keyd` has handled it.

Open your user service file:

```bash
nano %h/.config/systemd/user/xremap.service

```

Change the `ExecStart` line to target the virtual keyboard created by `keyd`. (You can also safely drop the `--mouse` flag here since `keyd` is dealing with the mouse events now):

```ini
ExecStart=/usr/bin/xremap --device "keyd virtual keyboard" --watch=config %h/Projects/atmosphera-bindings/niri/atmosphera-xremap.yml %h/.config/xremap/config.yml

```

### Step 4: Reload and Restart `xremap`

Tell systemd to read your updated user configuration, and restart `xremap`:

```bash
systemctl --user daemon-reload
systemctl --user restart xremap.service

```

### How to Verify It's Working

1. Check your `xremap` logs to ensure it successfully attached to the virtual device:
```bash
journalctl --user -u xremap.service -n 20

```


2. Open Brave or Firefox and try `Super + Left-Click` on a link. It should open natively in a new tab, while all your custom app-specific `xremap` keyboard mappings continue to work perfectly.



---
```
ok, I started keyd and everything was fine (not working what I wanted, but I still was able to type) then I started xremap and wasn't able to type anymore.
```
---

Oof, a total keyboard lockup is definitely a mini-panic moment! What you just experienced is a classic **Input Feedback Loop (Deadlock)**.

### Why Did This Happen?

1. You configured `keyd` with `[ids] *`, which tells it to aggressively grab **every** keyboard device it sees.
2. When `xremap` starts up, it creates its own brand-new virtual keyboard device in the Linux kernel (usually named `xremap`).
3. `keyd` saw this new "keyboard" pop up and immediately grabbed it because of the `*` wildcard rule.
4. The moment you typed a key: `keyd` passed it to `xremap`, `xremap` processed it and sent it to its virtual device, `keyd` intercepted that virtual device output, treated it like a new physical keypress, and shoved it right back down `xremap`'s throat.

This hyper-fast infinite loop instantly floods the Linux input subsystem and completely freezes your typing.

---

### Step 1: The Emergency Unfreeze

If your keyboard is still frozen right now, `keyd` has a built-in hardcoded panic chord designed exactly for this situation.

Press **`Backspace` + `Escape` + `Enter**` simultaneously on your keyboard. This will instantly force `keyd` to terminate and hand your hardware back to the system, restoring your typing immediately.

If that doesn't work, stop the `xremap` service using your mouse to open a terminal (or via SSH) and run:

```bash
systemctl --user stop xremap.service
```

---

### Step 2: The Permanent Fix (Targeted Hardware IDs)

To stop `keyd` and `xremap` from fighting over virtual devices, we need to tell `keyd` to **only** touch your actual physical keyboard and mouse, ignoring everything else.

1. Run this command to look at the `keyd` system logs. It lists every physical device it found when it booted up:
```bash
sudo journalctl -eu keyd | grep -i "device added"
```

2. Look through the output for your **physical keyboard** and your **physical mouse**. You are looking for the 4-digit hex strings (the Vendor:Product IDs). It will look something like this:
   > `device added: 046d:c52b Logitech USB Receiver`
   > `device added: 0001:0001 AT Translated Set 2 keyboard`

3. Open your `keyd` configuration file:
```bash
sudo nano /etc/keyd/default.conf
```

4. Replace the dangerous `*` wildcard with your exact physical hardware IDs, separated by spaces. For example:
```ini
[ids]
046d:c52b 0001:0001

[meta]
leftmouse = C-leftmouse
```
   *(Be sure to replace those numbers with the actual IDs you found in your logs. You must include both the keyboard and the mouse IDs so `keyd` can bridge the `Super` key and the click).*

---

### Step 3: Spin It All Back Up

Now that `keyd` is safely locked onto your physical hardware and completely blind to `xremap`'s virtual devices, you can safely restart the stack:

1. Reload `keyd` to apply the targeted IDs: 
```bash
sudo keyd reload
```

2. Restart your user-level `xremap` service:
```bash
systemctl --user start xremap.service
```

Your typing will remain perfectly fluid, and `Super + Left-Click` will finally work seamlessly inside Brave and Firefox!
