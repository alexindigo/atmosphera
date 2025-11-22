import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  // Plugin metadata and configuration
  property string name: I18n.tr("plugins.emoji")
  property var launcher: null
  property bool handleSearch: false

  // Emoji data storage
  property var allEmojis: []
  property var userEmojiData: []
  property var builtInEmojis: []
  property bool emojisLoaded: false
  property bool userEmojisLoaded: false
  property bool builtInEmojisLoaded: false

  property string userEmojiFilePath: Settings.configDir + "emoji.json"

  // Plugin initialization
  Component.onCompleted: {
    userEmojiFile.reload();
    loadBuiltInEmojis();
  }

  // User emoji file loader
  FileView {
    id: userEmojiFile
    path: userEmojiFilePath
    printErrors: false
    watchChanges: true

    onLoaded: {
      try {
        const content = text();
        if (content) {
          const parsed = JSON.parse(content);
          if (parsed && Array.isArray(parsed)) {
            root.userEmojiData = parsed;
          } else {
            root.userEmojiData = [];
          }
        } else {
          root.userEmojiData = [];
        }
      } catch (e) {
        root.userEmojiData = [];
      }
      root.userEmojisLoaded = true;
      checkAllEmojisLoaded();
    }

    onLoadFailed: function (error) {
      root.userEmojiData = [];
      root.userEmojisLoaded = true;
      checkAllEmojisLoaded();
    }
  }

  // Plugin initialization method
  function init() {
    Logger.i("EmojiPlugin", "Initialized");
  }

  // Handler when launcher opens
  function onOpened() {
    if (!emojisLoaded) {
      userEmojiFile.reload();
    }
  }

  function handleCommand(searchText) {
    return searchText.startsWith(">emoji");
  }

  function commands() {
    return [
      {
        "name": ">emoji",
        "description": I18n.tr("plugins.emoji-search-description"),
        "icon": "emote",
        "isImage": false,
        "onActivate": function () {
          launcher.setSearchText(">emoji ");
        }
      }
    ];
  }

  // Get search results
  function getResults(searchText) {
    if (!searchText.startsWith(">emoji")) {
      return [];
    }

    const query = searchText.slice(6).trim();

    if (!emojisLoaded) {
      return [
        {
          "name": I18n.tr("plugins.emoji-loading"),
          "description": I18n.tr("plugins.emoji-loading-description"),
          "icon": "view-refresh",
          "isImage": false,
          "onActivate": function () {}
        }
      ];
    }

    let results = [];

    if (!query || query === "") {
      results = allEmojis.slice(0, 20).map(emoji => formatEmojiEntry(emoji));
    } else {
      const terms = query.toLowerCase().split(" ");

      results = allEmojis.filter(emoji => {
        for (let term of terms) {
          if (term === "") continue;

          const emojiMatch = emoji.emoji.toLowerCase().includes(term);
          const nameMatch = (emoji.name || "").toLowerCase().includes(term);
          const keywordMatch = (emoji.keywords || []).some(kw => kw.toLowerCase().includes(term));
          const categoryMatch = (emoji.category || "").toLowerCase().includes(term);

          if (!emojiMatch && !nameMatch && !keywordMatch && !categoryMatch) {
            return false;
          }
        }
        return true;
      }).map(emoji => formatEmojiEntry(emoji));
    }

    if (results.length === 0 && query !== "") {
      return [
        {
          "name": I18n.tr("plugins.emoji-no-results"),
          "description": I18n.tr(`No emojis found for "${query}"`),
          "icon": "emote-rye",
          "isImage": false,
          "onActivate": function () {}
        }
      ];
    }

    return results;
  }

  // Format emoji entry
  function formatEmojiEntry(emoji) {
    let title = emoji.name;
    let description = (emoji.keywords || []).join(", ");

    if (emoji.category) {
      description += " • Category: " + emoji.category;
    }

    const emojiChar = emoji.emoji;

    return {
      "name": title,
      "description": description,
      "icon": null,
      "isImage": false,
      "emojiChar": emojiChar,
      "onActivate": function () {
        Quickshell.execDetached(["sh", "-c", `echo -n "${emojiChar}" | wl-copy`]);
        launcher.close();
      }
    };
  }

  // Check if all emojis are loaded
  function checkAllEmojisLoaded() {
    if (userEmojisLoaded && builtInEmojisLoaded) {
      finalizeEmojiLoad();
    }
  }

  // Final emoji load completion
  function finalizeEmojiLoad() {
    const emojiMap = new Map();

    for (const emoji of userEmojiData) {
      emojiMap.set(emoji.emoji, emoji);
    }

    for (const emoji of builtInEmojis) {
      if (!emojiMap.has(emoji.emoji)) {
        emojiMap.set(emoji.emoji, emoji);
      }
    }

    // Convert map back to array
    allEmojis = Array.from(emojiMap.values());
    emojisLoaded = true;
    Logger.i("EmojiPlugin", `Loaded ${allEmojis.length} total emojis`);
  }

  // Built-in emoji file loader
  FileView {
    id: builtinEmojiFile
    path: `${Quickshell.shellDir}/Assets/Launcher/emoji.json`
    watchChanges: false
    printErrors: false

    onLoaded: {
      try {
        const content = text();
        if (content) {
          const parsed = JSON.parse(content);
          if (parsed && Array.isArray(parsed)) {
            root.builtInEmojis = parsed;
          } else {
            root.builtInEmojis = [];
          }
        } else {
          root.builtInEmojis = [];
        }
      } catch (e) {
        root.builtInEmojis = [];
      }
      root.builtInEmojisLoaded = true;
      checkAllEmojisLoaded();
    }

    onLoadFailed: function(error) {
      root.builtInEmojis = [];
      root.builtInEmojisLoaded = true;
      checkAllEmojisLoaded();
    }
  }

  // Load built-in emojis
  function loadBuiltInEmojis() {
    builtinEmojiFile.reload();
  }
}
