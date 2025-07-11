# Noctalia

**_quiet by design_**

A sleek, minimal, and thoughtfully crafted setup for Wayland using **Quickshell**. This setup includes a status bar, notification system, control panel, wifi & bluetooth support, power profiles, lockscreen, tray, workspaces, and more — all styled with a warm lavender palette.

## Preview

<details>
<summary>Click to expand preview images</summary>

![Main](https://i.imgur.com/5mOIGD2.jpeg)  
</br>

![Control Panel](https://i.imgur.com/fJmCV6m.jpeg)  
</br>

![Applauncher](https://i.imgur.com/9OPV30q.jpeg)

</details>
<br>

---

> ⚠️ **Note:**  
> This setup currently requires **Niri** as your compositor, mainly due to its custom workspace indicator integration. However if you want, you can just adapt the Workspace.qml to your own compositor.

---

## Features

- **Status Bar:** Modular and informative with smooth animations.
- **Notifications:** Non-intrusive alerts styled to blend naturally.
- **Control Panel:** Centralized system controls for quick adjustments.
- **Connectivity:** Easy management of WiFi and Bluetooth devices.
- **Power Profiles:** Quick toggles for performance and battery modes.
- **Lockscreen:** Secure and visually consistent lock experience.
- **Tray & Workspaces:** Efficient workspace switching and tray icons.
- **Applauncher:** Stylized Applauncher to fit into the setup.

---

<details>
<summary><strong>Theme Colors</strong></summary>

| Color Role           | Color       | Description                     |
| -------------------- | ----------- | ------------------------------- |
| Background Primary   | `#0C0D11`   | Deep indigo-black               |
| Background Secondary | `#151720`   | Slightly lifted dark            |
| Background Tertiary  | `#1D202B`   | Soft contrast surface           |
| Surface              | `#1A1C26`   | Material-like base layer        |
| Surface Variant      | `#2A2D3A`   | Lightly elevated                |
| Text Primary         | `#CACEE2`   | Gentle off-white                |
| Text Secondary       | `#B7BBD0`   | Muted lavender-blue             |
| Text Disabled        | `#6B718A`   | Dimmed blue-gray                |
| Accent Primary       | `#A8AEFF`   | Light enchanted lavender        |
| Accent Secondary     | `#9EA0FF`   | Softer lavender hue             |
| Accent Tertiary      | `#8EABFF`   | Warm golden glow                |
| Error                | `#FF6B81`   | Soft rose red                   |
| Warning              | `#FFBB66`   | Candlelight amber-orange        |
| Highlight            | `#E3C2FF`   | Bright magical lavender         |
| Ripple Effect        | `#F3DEFF`   | Gentle soft splash              |
| On Accent            | `#1A1A1A`   | Text on accent background       |
| Outline              | `#44485A`   | Subtle bluish-gray line         |
| Shadow               | `#000000B3` | Standard soft black shadow      |
| Overlay              | `#11121ACC` | Deep bluish overlay             |

</details>

---

## Installation & Usage

<details>
<summary><strong>Installation</strong></summary>

Install quickshell:

```
yay -S quickshell-git
```

or use any other way of installing quickshell-git (flake, paru etc).

_Git clone the repo:_

```
git clone https://github.com/Ly-sec/Noctalia.git
```

_Move content to ~/.config/quickshell_

```
cd Noctalia && mv * ~/.config/quickshell/
```

</details>
</br>

<details>
<summary><strong>Usage</strong></summary>

### Start quickshell:

```
qs
```

(If you want to autostart it, just add it to your niri configuration.)

### Settings:

To make the weather widget, wallpaper manager and record button work you will have to open up the settings menu in to right panel (top right button to open panel) and edit said things accordingly.

</details>

</br>
<details>
<summary><strong>Keybinds</strong></summary>

### Open Applauncher:

```
 qs ipc call globalIPC toggleLauncher
```

You can keybind it however you want in your niri setup.

</details>

---

## Known issues

Currently the brightness indicator is very opiniated (using ddcutil with a script to log current brightness). This will be fixed **asap**!

---

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

---

## License

This project is licensed under the terms of the [MIT License](./LICENSE).
