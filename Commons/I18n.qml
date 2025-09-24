pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  property bool debug: true
  property string debugForceLanguage: ""

  property bool isLoaded: false
  property string langCode: ""
  readonly property var availableLanguages: ["en", "fr"]
  property var translations: ({})
  property var fallbackTranslations: ({})

  // Signals for reactive updates
  signal languageChanged(string newLanguage)
  signal translationsLoaded

  // FileView to load translation files
  property FileView translationFile: FileView {
    id: fileView
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        root.translations = data
        root.isLoaded = true
        root.translationsLoaded()
        Logger.log("I18n", `Loaded translations for "${root.langCode}"`)
      } catch (e) {
        Logger.error("I18n", `Failed to parse translation file: ${e}`)
        setLanguage("en")
      }
    }
    onLoadFailed: function (error) {
      setLanguage("en")
      Logger.error("I18n", `Failed to load translation file: ${error}`)
    }
  }

  // FileView to load translation files
  property FileView fallbackTranslationFile: FileView {
    id: fallbackFileView
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        root.fallbackTranslations = data
        Logger.log("I18n", `Loaded english fallback translations`)
      } catch (e) {
        Logger.error("I18n", `Failed to parse fallback translation file: ${e}`)
      }
    }
    onLoadFailed: function (error) {
      Logger.error("I18n", `Failed to load fallback translation file: ${error}`)
    }
  }

  // -------------------------------------------
  function init() {
    Logger.log("I18n", "Service started")
    detectLanguage()
  }

  // -------------------------------------------
  function detectLanguage() {

    if (debug && debugForceLanguage !== "") {
      setLanguage(debugForceLanguage)
      return
    }

    // Detect user's favorite locale - languages
    for (var i = 0; i < Qt.locale().uiLanguages.length; i++) {
      const userLang = Qt.locale().uiLanguages[i].substring(0, 2)
      if (availableLanguages.includes(userLang)) {
        setLanguage(userLang)
        return
      }
    }

    // Fallback to english
    setLanguage("en")
  }

  // -------------------------------------------
  function setLanguage(newLangCode) {
    if (newLangCode !== langCode && availableLanguages.includes(newLangCode)) {
      langCode = newLangCode
      Logger.log("I18n", `Language set to "${langCode}"`)
      languageChanged(langCode)
      loadTranslations()
    }
  }

  // -------------------------------------------
  function loadTranslations() {
    if (langCode === "")
      return

    const filePath = `file://${Quickshell.shellDir}/Assets/Translations/${langCode}.json`
    fileView.path = filePath
    isLoaded = false
    Logger.log("I18n", `Loading translations from: ${filePath}`)

    // Only load fallback translations if we are not using enlgish
    if (langCode !== "en") {
      fallbackFileView.path = `file://${Quickshell.shellDir}/Assets/Translations/en.json`
    }
  }

  // -------------------------------------------
  // Check if a translation exists
  function hasTranslation(key) {
    if (!isLoaded)
      return false

    const keys = key.split(".")
    var value = translations

    for (var i = 0; i < keys.length; i++) {
      if (value && typeof value === "object" && keys[i] in value) {
        value = value[keys[i]]
      } else {
        return false
      }
    }

    return typeof value === "string"
  }

  // -------------------------------------------
  // Get all translation keys (useful for debugging)
  function getAllKeys(obj, prefix) {
    if (typeof obj === "undefined")
      obj = translations
    if (typeof prefix === "undefined")
      prefix = ""

    var keys = []
    for (var key in (obj || {})) {
      const value = obj[key]
      const fullKey = prefix ? `${prefix}.${key}` : key
      if (typeof value === "object" && value !== null) {
        keys = keys.concat(getAllKeys(value, fullKey))
      } else if (typeof value === "string") {
        keys.push(fullKey)
      }
    }
    return keys
  }

  // -------------------------------------------
  // Reload translations (useful for development)
  function reload() {
    Logger.log("I18n", "Reloading translations")
    loadTranslations()
  }

  // -------------------------------------------
  // Main translation function
  function tr(key, interpolations) {
    if (typeof interpolations === "undefined")
      interpolations = {}

    if (!isLoaded) {
      Logger.warn("I18n", "Translations not loaded yet")
      return key
    }

    // Navigate nested keys (e.g., "menu.file.open")
    const keys = key.split(".")

    // Look-up translation in the active language
    var value = translations
    var notFound = false
    for (var i = 0; i < keys.length; i++) {
      if (value && typeof value === "object" && keys[i] in value) {
        value = value[keys[i]]
      } else {
        if (debug) {
          Logger.warn("I18n", `Translation key "${key}" not found`)
        }
        notFound = true
        break
      }
    }

    // Fallback to english if not found
    if (notFound) {
      value = fallbackTranslations
      for (var i = 0; i < keys.length; i++) {
        if (value && typeof value === "object" && keys[i] in value) {
          value = value[keys[i]]
        } else {
          // Indicate this key does not even exists in the english fallback
          return `## ${key} ##`
        }
      }

      // Make untranslated string easy to spot
      value = `<i>${value}</i>`
    }

    if (typeof value !== "string") {
      if (debug) {
        Logger.warn("I18n", `Translation key "${key}" is not a string`)
      }
      return key
    }

    // Handle interpolations (e.g., "Hello {name}!")
    var result = value
    for (var placeholder in interpolations) {
      const regex = new RegExp(`\\{${placeholder}\\}`, 'g')
      result = result.replace(regex, interpolations[placeholder])
    }

    return result
  }

  // -------------------------------------------
  // Plural translation function
  function trp(key, count, defaultSingular, defaultPlural, interpolations) {
    if (typeof defaultSingular === "undefined")
      defaultSingular = ""
    if (typeof defaultPlural === "undefined")
      defaultPlural = ""
    if (typeof interpolations === "undefined")
      interpolations = {}

    const pluralKey = count === 1 ? key : `${key}_plural`
    const defaultValue = count === 1 ? defaultSingular : defaultPlural

    // Merge interpolations with count (QML doesn't support spread operator)
    var finalInterpolations = {
      "count": count
    }
    for (var prop in interpolations) {
      finalInterpolations[prop] = interpolations[prop]
    }

    return t(pluralKey, defaultValue, finalInterpolations)
  }
}
