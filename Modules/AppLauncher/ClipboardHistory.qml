import QtQuick
import Quickshell
import qs.Commons
import qs.Services

QtObject {
  id: clipboardHistory

  // Copy helpers for different content types
  function copyImageBase64(mime, base64) {
    Quickshell.execDetached(["sh", "-lc", `printf %s ${base64} | base64 -d | wl-copy -t '${mime}'`])
  }

  function copyText(text) {
    // Use printf with proper quoting to handle special characters
    Quickshell.execDetached(["sh", "-c", `printf '%s' ${JSON.stringify(text)} | wl-copy -t text/plain`])
  }

  // Create clipboard entry for display
  function createClipboardEntry(clip, index) {
    if (clip.type === 'image') {
      return {
        "isClipboard": true,
        "name": "Image from " + new Date(clip.timestamp).toLocaleTimeString(),
        "content": "Image: " + clip.mimeType,
        "icon": "image",
        "type": 'image',
        "data": clip.data,
        "timestamp": clip.timestamp,
        "index": index,
        "execute": function () {
          const dataParts = clip.data.split(',')
          const base64Data = dataParts.length > 1 ? dataParts[1] : clip.data
          copyImageBase64(clip.mimeType, base64Data)
          Quickshell.execDetached(["notify-send", "Clipboard", "Image copied: " + clip.mimeType])
        }
      }
    } else {
      // Handle text content
      const textContent = clip.content || clip
      let displayContent = textContent
      let previewContent = ""

      // Normalize whitespace for display
      displayContent = displayContent.replace(/\s+/g, ' ').trim()

      // Create preview for long content
      if (displayContent.length > 50) {
        previewContent = displayContent
        displayContent = displayContent.split('\n')[0].substring(0, 50) + "..."
      }

      return {
        "isClipboard": true,
        "name": displayContent,
        "content": previewContent || textContent,
        "icon": "content_paste",
        "type": 'text',
        "timestamp": clip.timestamp,
        "index": index,
        "textData": textContent,
        "execute"// Store the text data for the execute function
        : function () {
          const text = this.textData || clip.content || clip
          Quickshell.clipboardText = String(text)
          copyText(String(text))
          var preview = (text.length > 50) ? text.slice(0, 50) + "…" : text
          Quickshell.execDetached(["notify-send", "Clipboard", "Text copied: " + preview])
        }
      }
    }
  }

  // Create empty state entry
  function createEmptyEntry() {
    return {
      "isClipboard": true,
      "name": "No clipboard history",
      "content": "No matching clipboard entries found",
      "icon": "content_paste_off",
      "execute": function () {// Do nothing for empty state
      }
    }
  }

  // Process clipboard queries
  function processQuery(query) {
    const results = []

    if (!query.startsWith(">clip")) {
      return results
    }

    // Extract search term after ">clip "
    const searchTerm = query.slice(5).trim()

    // Note: Clipboard refresh should be handled externally to avoid binding loops

    // Process each clipboard item
    ClipboardService.history.forEach(function (clip, index) {
      let searchContent = clip.type === 'image' ? clip.mimeType : clip.content || clip

      // Apply search filter if provided
      if (!searchTerm || searchContent.toLowerCase().includes(searchTerm.toLowerCase())) {
        const entry = createClipboardEntry(clip, index)
        results.push(entry)
      }
    })

    // Show empty state if no results
    if (results.length === 0) {
      results.push(createEmptyEntry())
    }

    return results
  }

  // Create command entry for clipboard mode (deprecated - use direct creation in parent)
  function createCommandEntry() {
    return {
      "isCommand": true,
      "name": ">clip",
      "content": "Clipboard history - browse and restore clipboard items",
      "icon": "content_paste",
      "execute": function () {// This should be handled by the parent component
      }
    }
  }

  // Utility function to refresh clipboard
  function refresh() {
    ClipboardService.refresh()
  }

  // Get clipboard history count
  function getHistoryCount() {
    return ClipboardService.history ? ClipboardService.history.length : 0
  }

  // Get formatted timestamp for display
  function formatTimestamp(timestamp) {
    return new Date(timestamp).toLocaleTimeString()
  }

  // Get clipboard entry by index
  function getEntryByIndex(index) {
    if (ClipboardService.history && index >= 0 && index < ClipboardService.history.length) {
      return ClipboardService.history[index]
    }
    return null
  }

  // Clear all clipboard history
  function clearAll() {
    ClipboardService.clearHistory()
  }
}
