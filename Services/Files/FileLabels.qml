pragma Singleton

import QtQuick
import Quickshell

Singleton {
  // Only whitespace separates filename words. Punctuation, extensions and CJK
  // stay in their token; the view elides an over-wide line without splitting it.
  function lines(name, width, measure) {
    var tokens = name.split(/(\s+)/);
    var first = "";
    for (var i = 0; i < tokens.length; ++i) {
      var next = first + tokens[i];
      if (/\S/.test(tokens[i]) && /\S/.test(first) && measure(next) > width)
        return [first.replace(/\s+$/, ""), tokens.slice(i).join("")];
      first = next;
    }
    return [first];
  }
}
