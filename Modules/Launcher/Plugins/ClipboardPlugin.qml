import QtQuick
import Quickshell
import qs.Commons
import qs.Services

QtObject {
  id: root

  // Plugin metadata
  property string name: "Clipboard History"
  property var launcher: null

  // Plugin capabilities
  property bool handleSearch: false // Don't handle regular search

  // Initialize plugin
  function init() {
    Logger.log("ClipboardPlugin", "Initialized")
  }

  // Called when launcher opens
  function onOpened() {
    // Refresh clipboard history when launcher opens
    CliphistService.list(100)
  }

  // Check if this plugin handles the command
  function handleCommand(searchText) {
    return searchText.startsWith(">clip")
  }

  // Return available commands when user types ">"
  function commands() {
    return [{
              "name": ">clip",
              "description": "Search clipboard history",
              "icon": "content_paste",
              "isImage": false,
              "onActivate": function () {
                launcher.setSearchText(">clip ")
              }
            }, {
              "name": ">clip clear",
              "description": "Clear all clipboard history",
              "icon": "delete_sweep",
              "isImage": false,
              "onActivate": function () {
                CliphistService.wipeAll()
                launcher.close()
              }
            }]
  }

  // Get search results
  function getResults(searchText) {
    if (!searchText.startsWith(">clip")) {
      return []
    }

    const results = []
    const query = searchText.slice(5).trim()

    // Special command: clear
    if (query === "clear") {
      return [{
                "name": "Clear Clipboard History",
                "description": "Remove all items from clipboard history",
                "icon": "delete_sweep",
                "onActivate": function () {
                  CliphistService.wipeAll()
                  launcher.close()
                }
              }]
    }

    // Search clipboard items
    const searchTerm = query.toLowerCase()

    // Force dependency update
    const _rev = CliphistService.revision
    const items = CliphistService.items || []

    // Filter and format results
    items.forEach(function (item) {
      const preview = (item.preview || "").toLowerCase()

      // Skip if search term doesn't match
      if (searchTerm && preview.indexOf(searchTerm) === -1) {
        return
      }

      // Format the result based on type
      let entry
      if (item.isImage) {
        entry = formatImageEntry(item)
      } else {
        entry = formatTextEntry(item)
      }

      // Add activation handler
      entry.onActivate = function () {
        CliphistService.copyToClipboard(item.id)
        launcher.close()
      }

      results.push(entry)
    })

    // Show empty state if no results
    if (results.length === 0) {
      results.push({
                     "name": searchTerm ? "No matching clipboard items" : "Clipboard is empty",
                     "description": searchTerm ? `No items containing "${query}"` : "Copy something to see it here",
                     "icon": "content_paste_off",
                     "isImage": false,
                     "onActivate": function () {// Do nothing
                     }
                   })
    }

    return results
  }

  // Helper: Format image clipboard entry with actual image data
  function formatImageEntry(item) {
    const meta = parseImageMeta(item.preview)

    // Get the actual image data/path from the clipboard service
    // This assumes CliphistService provides either a path or base64 data
    let imageData = null

    // Try to get image data from the service
    // Method 1: If the service provides a file path
    if (item.imagePath) {
      imageData = "file://" + item.imagePath
    } // Method 2: If the service provides base64 data
    else if (item.imageData) {
      imageData = ClipHistService.getImageData(item.id)
      
      // "data:" + (item.mime || "image/png") + ";base64," + item.imageData
    } // Method 3: If we need to fetch it from the service

    // else if (item.id) {
    //   // Some clipboard services might require fetching the image separately
    //   // This would depend on your CliphistService implementation
    //   imageData = CliphistService.getImageData ? CliphistService.getImageData(item.id) : null
    // }
    return {
      "name": meta ? `Image ${meta.w}×${meta.h}` : "Image",
      "description": meta ? `${meta.fmt} • ${meta.size}` : item.mime || "Image data",
      "icon": "image",
      "isImage": true,
      "imageSource": imageData,
      "imageWidth": meta ? meta.w : 0,
      "imageHeight": meta ? meta.h : 0,
      "clipboardId"// Add clipboard item ID for potential async loading
      : item.id
    }
  }

  // Helper: Format text clipboard entry with preview
  function formatTextEntry(item) {
    const preview = (item.preview || "").trim()
    const lines = preview.split('\n').filter(l => l.trim())

    // Use first line as title, limit length
    let title = lines[0] || "Empty text"
    if (title.length > 60) {
      title = title.substring(0, 57) + "..."
    }

    // Use second line or character count as description
    let description = ""
    if (lines.length > 1) {
      description = lines[1]
      if (description.length > 80) {
        description = description.substring(0, 77) + "..."
      }
    } else {
      const chars = preview.length
      const words = preview.split(/\s+/).length
      description = `${chars} characters, ${words} word${words !== 1 ? 's' : ''}`
    }

    return {
      "name": title,
      "description": description,
      "icon": "description",
      "isImage": false
    }
  }

  // Helper: Parse image metadata from preview string
  function parseImageMeta(preview) {
    const re = /\[\[\s*binary data\s+([\d\.]+\s*(?:KiB|MiB|GiB|B))\s+(\w+)\s+(\d+)x(\d+)\s*\]\]/i
    const match = (preview || "").match(re)

    if (!match) {
      return null
    }

    return {
      "size": match[1],
      "fmt": (match[2] || "").toUpperCase(),
      "w": Number(match[3]),
      "h": Number(match[4])
    }
  }

  // Public method to get image data for a clipboard item
  // This can be called by the launcher when rendering
  function getImageForItem(clipboardId) {
    return CliphistService.getImageData ? CliphistService.getImageData(clipboardId) : null
  }
}
