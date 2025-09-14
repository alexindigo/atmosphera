pragma Singleton

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  property ListModel availableFonts: ListModel {}
  property ListModel monospaceFonts: ListModel {}
  property ListModel displayFonts: ListModel {}
  property bool fontsLoaded: false
  property var fontconfigMonospaceFonts: []

  // -------------------------------------------
  function init() {
    Logger.log("Font", "Service started")
    loadFontconfigMonospaceFonts()
    loadSystemFonts()
  }

  function loadFontconfigMonospaceFonts() {
    Logger.log("Font", "Loading monospace fonts via fontconfig...")

    // Use fc-list :mono to get all monospace fonts
    fontconfigProcess.command = ["fc-list", ":mono", "family"]
    fontconfigProcess.running = true
  }

  function loadSystemFonts() {
    Logger.log("Font", "Loading system fonts...")

    var fontFamilies = Qt.fontFamilies()

    availableFonts.clear()
    monospaceFonts.clear()
    displayFonts.clear()

    for (var i = 0; i < fontFamilies.length; i++) {
      var fontName = fontFamilies[i]
      if (fontName && fontName.trim() !== "") {
        availableFonts.append({
                                "key": fontName,
                                "name": fontName
                              })

        if (isMonospaceFont(fontName)) {
          monospaceFonts.append({
                                  "key": fontName,
                                  "name": fontName
                                })
        }

        if (isDisplayFont(fontName)) {
          displayFonts.append({
                                "key": fontName,
                                "name": fontName
                              })
        }
      }
    }

    sortModel(availableFonts)
    sortModel(monospaceFonts)
    sortModel(displayFonts)

    if (monospaceFonts.count === 0) {
      Logger.log("Font", "No monospace fonts detected, adding fallbacks")
      addFallbackFonts(monospaceFonts, ["DejaVu Sans Mono", "Liberation Mono", "Courier New", "Courier", "Monaco", "Consolas", "Lucida Console", "Monaco", "Andale Mono"])
    }

    if (displayFonts.count === 0) {
      Logger.log("Font", "No display fonts detected, adding fallbacks")
      addFallbackFonts(displayFonts, ["Inter", "Roboto", "Open Sans", "Arial", "Helvetica", "Verdana", "Segoe UI", "SF Pro Display", "Ubuntu", "Noto Sans"])
    }

    fontsLoaded = true
    Logger.log("Font", "Loaded", availableFonts.count, "fonts:", monospaceFonts.count, "monospace,", displayFonts.count, "display")
  }

  function isMonospaceFont(fontName) {
    // First, check if fontconfig detected this as monospace
    if (fontconfigMonospaceFonts.indexOf(fontName) !== -1) {
      return true
    }

    // Fallback to pattern matching if fontconfig is not available or didn't detect it
    var patterns = ["mono", "monospace", "fixed", "console", "terminal", "typewriter", "courier", "dejavu", "liberation", "source code", "fira code", "jetbrains", "cascadia", "hack", "inconsolata", "roboto mono", "ubuntu mono", "menlo", "consolas", "monaco", "andale mono"]
    var lowerFontName = fontName.toLowerCase()

    for (var i = 0; i < patterns.length; i++) {
      if (lowerFontName.includes(patterns[i]))
        return true
    }

    var commonFonts = ["DejaVu Sans Mono", "Liberation Mono", "Source Code Pro", "Fira Code", "JetBrains Mono", "Cascadia Code", "Hack", "Inconsolata", "Roboto Mono", "Ubuntu Mono", "Menlo", "Consolas", "Monaco", "Andale Mono", "Courier New", "Courier", "Lucida Console", "Monaco", "MS Gothic", "MS Mincho"]
    return commonFonts.includes(fontName)
  }

  function isDisplayFont(fontName) {
    var patterns = ["display", "headline", "title", "hero", "showcase", "brand", "inter", "roboto", "open sans", "lato", "montserrat", "poppins", "raleway", "nunito", "source sans", "ubuntu", "noto sans", "work sans", "dm sans", "manrope", "plus jakarta", "figtree"]
    var lowerFontName = fontName.toLowerCase()

    for (var i = 0; i < patterns.length; i++) {
      if (lowerFontName.includes(patterns[i]))
        return true
    }

    var commonFonts = ["Inter", "Roboto", "Open Sans", "Lato", "Montserrat", "Poppins", "Raleway", "Nunito", "Source Sans Pro", "Ubuntu", "Noto Sans", "Work Sans", "DM Sans", "Manrope", "Plus Jakarta Sans", "Figtree", "SF Pro Display", "Segoe UI", "Arial", "Helvetica", "Verdana"]
    return commonFonts.includes(fontName)
  }

  function sortModel(model) {
    var fontsArray = []
    for (var i = 0; i < model.count; i++) {
      fontsArray.push({
                        "key": model.get(i).key,
                        "name": model.get(i).name
                      })
    }

    fontsArray.sort(function (a, b) {
      return a.name.localeCompare(b.name)
    })

    model.clear()
    for (var j = 0; j < fontsArray.length; j++) {
      model.append(fontsArray[j])
    }
  }

  function addFallbackFonts(model, fallbackFonts) {
    for (var i = 0; i < fallbackFonts.length; i++) {
      var fontName = fallbackFonts[i]
      var exists = false
      for (var j = 0; j < model.count; j++) {
        if (model.get(j).name === fontName) {
          exists = true
          break
        }
      }

      if (!exists) {
        model.append({
                       "key": fontName,
                       "name": fontName
                     })
      }
    }

    sortModel(model)
  }

  function searchFonts(query) {
    if (!query || query.trim() === "")
      return availableFonts

    var results = []
    var lowerQuery = query.toLowerCase()

    for (var i = 0; i < availableFonts.count; i++) {
      var font = availableFonts.get(i)
      if (font.name.toLowerCase().includes(lowerQuery)) {
        results.push(font)
      }
    }

    return results
  }

  // Process for fontconfig commands
  Process {
    id: fontconfigProcess
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text !== "") {
          var lines = this.text.split('\n')
          fontconfigMonospaceFonts = []

          for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line && line !== "") {
              // Extract font family name (remove any style info in brackets)
              var familyName = line.split(',')[0].trim()
              if (familyName && fontconfigMonospaceFonts.indexOf(familyName) === -1) {
                fontconfigMonospaceFonts.push(familyName)
              }
            }
          }

          Logger.log("Font", "Found", fontconfigMonospaceFonts.length, "monospace fonts via fontconfig")
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text !== "") {
          Logger.log("Font", "Fontconfig stderr:", this.text)
        }
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0) {
        Logger.log("Font", "Fontconfig not available or failed, falling back to pattern matching")
        fontconfigMonospaceFonts = []
      }
    }
  }
}
