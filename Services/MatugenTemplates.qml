pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

// Central place to define which templates we generate and where they write.
// Users can extend it by dropping additional templates into:
//  - Assets/MatugenTemplates/
//  - ~/.config/matugen/ (when enableUserTemplates is true)
Singleton {
  id: root

  // Build the base TOML using current settings
  function buildConfigToml() {
    var lines = []
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    lines.push("[config]")

    if (Settings.data.colorSchemes.useWallpaperColors) {
      // Only generate colors for Noctalia if the colors are wallpaper based
      // or this will conflict with our predefined colors
      lines.push("[templates.noctalia]")
      lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/noctalia.json"')
      lines.push('output_path = "' + Settings.configDir + 'colors.json"')

      // Only generate colors for terminalk if the colors are wallpaper based
      // predefined color schemes use a different approach for better result
      if (Settings.data.templates.foot) {
        lines.push("\n[templates.foot]")
        lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/Terminal/foot"')
        lines.push('output_path = "~/.config/foot/themes/noctalia"')
        lines.push(`post_hook = "${MatugenService.colorsApplyScript} foot"`)
      }

      if (Settings.data.templates.ghostty) {
        lines.push("\n[templates.ghostty]")
        lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/Terminal/ghostty"')
        lines.push('output_path = "~/.config/ghostty/themes/noctalia"')
        lines.push(`post_hook = "${MatugenService.colorsApplyScript} ghostty"`)
      }

      if (Settings.data.templates.kitty) {
        lines.push("\n[templates.kitty]")
        lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/Terminal/kitty.conf"')
        lines.push('output_path = "~/.config/kitty/themes/noctalia.conf"')
        lines.push(`post_hook = "${MatugenService.colorsApplyScript} kitty"`)
      }
    }

    if (Settings.data.templates.gtk) {
      lines.push("\n[templates.gtk3]")
      lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/gtk.css"')
      lines.push('output_path = "~/.config/gtk-3.0/gtk.css"')
      lines.push("post_hook = 'gsettings set org.gnome.desktop.interface color-scheme prefer-" + mode + "'")

      lines.push("\n[templates.gtk4]")
      lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/gtk.css"')
      lines.push('output_path = "~/.config/gtk-4.0/gtk.css"')
      lines.push("post_hook = 'gsettings set org.gnome.desktop.interface color-scheme prefer-" + mode + "'")
    }

    if (Settings.data.templates.qt) {
      lines.push("\n[templates.qt5]")
      lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/qtct.conf"')
      lines.push('output_path = "~/.config/qt5ct/colors/noctalia.conf"')

      lines.push("\n[templates.qt6]")
      lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/qtct.conf"')
      lines.push('output_path = "~/.config/qt6ct/colors/noctalia.conf"')
    }

    if (Settings.data.templates.fuzzel) {
      lines.push("\n[templates.fuzzel]")
      lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/fuzzel.conf"')
      lines.push('output_path = "~/.config/fuzzel/themes/noctalia"')
      lines.push(`post_hook = "${MatugenService.colorsApplyScript} fuzzel"`)
    }

    if (Settings.data.templates.pywalfox) {
      lines.push("\n[templates.pywalfox]")
      lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/pywalfox.json"')
      lines.push('output_path = "~/.cache/wal/colors.json"')
      lines.push(`post_hook = "${MatugenService.colorsApplyScript} pywalfox"`)
    }

    if (Settings.data.templates.vesktop) {
      lines.push("\n[templates.vesktop]")
      lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/vesktop.css"')
      lines.push('output_path = "~/.config/vesktop/themes/noctalia.theme.css"')
    }

    return lines.join("\n") + "\n"
  }
}
