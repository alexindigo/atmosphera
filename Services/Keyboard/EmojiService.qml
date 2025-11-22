pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Manages emoji data loading, searching, and clipboard operations
Singleton {
  id: root

  // --- Public API ---

  // List of all loaded emojis after deduplication
  property var emojis: []
  // True when emojis are fully loaded
  property bool loaded: false

  // Searches emojis based on query
  function search(query) {
    if (!loaded) {
      return [];
    }

    if (!query || query.trim() === "") {
      return emojis.slice(0, 20);
    }

    const terms = query.toLowerCase().split(" ").filter(t => t);
    return emojis.filter(emoji => {
      for (let term of terms) {
        const emojiMatch = emoji.emoji.toLowerCase().includes(term);
        const nameMatch = (emoji.name || "").toLowerCase().includes(term);
        const keywordMatch = (emoji.keywords || []).some(kw => kw.toLowerCase().includes(term));
        const categoryMatch = (emoji.category || "").toLowerCase().includes(term);

        if (!emojiMatch && !nameMatch && !keywordMatch && !categoryMatch) {
          return false;
        }
      }
      return true;
    });
  }

  // Copies emoji to clipboard
  function copy(emojiChar) {
    if (emojiChar) {
      Quickshell.execDetached(["sh", "-c", `echo -n "${emojiChar}" | wl-copy`]);
    }
  }

  // --- Service Implementation ---

  // File paths
  readonly property string userEmojiPath: Settings.configDir + "emoji.json"
  readonly property string builtinEmojiPath: `${Quickshell.shellDir}/Assets/Launcher/emoji.json`

  // Internal data
  property var _userEmojiData: []
  property var _builtinEmojiData: []
  property int _pendingLoads: 0

  // Initialize on component completion
  Component.onCompleted: {
    Logger.d("EmojiService", "Starting initialization...");
    _loadEmojis();
  }

  // File loaders
  FileView {
    id: userEmojiFile
    path: root.userEmojiPath
    printErrors: false
    watchChanges: false

    onLoaded: {
      Logger.d("EmojiService", "User emoji file loaded");
      try {
        const content = text();
        if (content) {
          const parsed = JSON.parse(content);
          _userEmojiData = Array.isArray(parsed) ? parsed : [];
          Logger.d("EmojiService", `Parsed ${_userEmojiData.length} user emojis`);
        } else {
          _userEmojiData = [];
          Logger.d("EmojiService", "No user emoji content");
        }
      } catch (e) {
        _userEmojiData = [];
        Logger.w("EmojiService", "Failed to parse user emojis: " + e.message);
      }
      _onLoadComplete();
    }

    onLoadFailed: function(error) {
      Logger.d("EmojiService", "User emoji file load failed: " + error);
      _userEmojiData = [];
      _onLoadComplete();
    }
  }

  FileView {
    id: builtinEmojiFile
    path: root.builtinEmojiPath
    printErrors: false
    watchChanges: false

    onLoaded: {
      try {
        const content = text();
        if (content) {
          const parsed = JSON.parse(content);
          _builtinEmojiData = Array.isArray(parsed) ? parsed : [];
        } else {
          _builtinEmojiData = [];
          Logger.e("EmojiService", "Built-in emoji file is empty");
        }
      } catch (e) {
        _builtinEmojiData = [];
        Logger.e("EmojiService", "Failed to parse built-in emojis: " + e.message);
      }
      _onLoadComplete();
    }

    onLoadFailed: function(error) {
      _builtinEmojiData = [];
      Logger.e("EmojiService", "Failed to load built-in emojis: " + error);
      _onLoadComplete();
    }
  }

  // Load emoji files
  function _loadEmojis() {
    _pendingLoads = 2;
    userEmojiFile.reload();
    builtinEmojiFile.reload();
  }

  // Called when one file finishes loading
  function _onLoadComplete() {
    _pendingLoads--;
    if (_pendingLoads <= 0) {
      _finalizeEmojis();
    }
  }

  // Merge and deduplicate emojis
  function _finalizeEmojis() {
    const emojiMap = new Map();

    // Add built-in emojis first
    for (const emoji of _builtinEmojiData) {
      if (emoji && emoji.emoji) {
        emojiMap.set(emoji.emoji, emoji);
      }
    }

    // Add user emojis (override built-ins if duplicate)
    for (const emoji of _userEmojiData) {
      if (emoji && emoji.emoji) {
        emojiMap.set(emoji.emoji, emoji);
      }
    }

    emojis = Array.from(emojiMap.values());
    loaded = true;

    Logger.i("EmojiService", `Loaded ${emojis.length} unique emojis after deduplication (${_userEmojiData.length} user, ${_builtinEmojiData.length} built-in)`);
  }
  }
