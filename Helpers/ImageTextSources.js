.pragma library

// Finds the images in rich text (HTML subset) and Markdown, and rewrites each
// one to a numbered slot so that Qt's text layout never loads the image
// itself. NImageText presents the images through the shared image owner.
//
// parse(text, format, baseUrl, slotUrl) -> { text, images }
//   format: "rich" or "markdown"
//   text:   the input with every image replaced by <slotUrl>#slot-<n>
//           (HTML: <img src=...>; Markdown: ![alt](...)). Markdown inline
//           <img> tags become Markdown images: Qt's Markdown importer drops
//           inline HTML images.
//   images: [{ source, alt, title, width, height }] in document order;
//           width/height are 0 when the markup does not declare them.
// Code spans, fenced/indented code blocks, HTML comments and backslash
// escapes are respected. A source is resolved against baseUrl when relative.

var _entities = {
  "amp": "&",
  "lt": "<",
  "gt": ">",
  "quot": "\"",
  "apos": "'",
  "nbsp": " "
};

function decodeEntities(value) {
  return value.replace(/&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, function (match, name) {
    if (name[0] === "#") {
      var code = name[1] === "x" || name[1] === "X" ? parseInt(name.slice(2), 16) : parseInt(name.slice(1), 10);
      return code > 0 && code <= 0x10FFFF ? String.fromCodePoint(code) : match;
    }
    return Object.prototype.hasOwnProperty.call(_entities, name.toLowerCase()) ? _entities[name.toLowerCase()] : match;
  });
}

function escapeHtml(value) {
  return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function resolve(source, baseUrl) {
  source = String(source || "").trim();
  if (!source || !baseUrl)
    return source;
  // Absolute: a URI scheme, an absolute local path or a protocol-relative URL.
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(source) || source[0] === "/")
    return source;
  var base = String(baseUrl);
  var query = base.search(/[?#]/);
  if (query >= 0)
    base = base.slice(0, query);
  var origin = "";
  var match = /^([a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^\/]*)(.*)$/.exec(base);
  if (match) {
    origin = match[1];
    base = match[2] || "/";
  }
  var directory = base.slice(0, base.lastIndexOf("/") + 1);
  // Dot segments belong to the path, never to query/fragment data.
  var suffixAt = source.search(/[?#]/);
  var suffix = suffixAt < 0 ? "" : source.slice(suffixAt);
  var path = suffixAt < 0 ? source : source.slice(0, suffixAt);
  if (!path)
    return origin + base + suffix;
  var parts = (directory + path).split("/");
  var out = [];
  for (var i = 0; i < parts.length; ++i) {
    if (parts[i] === "..") {
      if (out.length > 1)
        out.pop();
    } else if (parts[i] !== ".") {
      out.push(parts[i]);
    }
  }
  return origin + out.join("/") + suffix;
}

// Attributes of one HTML start tag body (after the tag name).
function _attributes(body) {
  var attributes = {};
  var pattern = /([^\s"'>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  var match;
  while ((match = pattern.exec(body)) !== null) {
    var value = match[2] !== undefined ? match[2] : match[3] !== undefined ? match[3] : match[4] !== undefined ? match[4] : "";
    attributes[match[1].toLowerCase()] = decodeEntities(value);
  }
  return attributes;
}

// End index (exclusive) of the HTML tag starting at text[start] === "<",
// honoring quoted attribute values; -1 when unterminated.
function _tagEnd(text, start) {
  var quote = "";
  for (var i = start + 1; i < text.length; ++i) {
    var ch = text[i];
    if (quote) {
      if (ch === quote)
        quote = "";
    } else if (ch === "\"" || ch === "'") {
      quote = ch;
    } else if (ch === ">") {
      return i + 1;
    }
  }
  return -1;
}

function _dimension(value) {
  var match = /^\s*(\d+(?:\.\d+)?)\s*(px)?\s*$/.exec(value || "");
  return match ? Math.round(parseFloat(match[1])) : 0;
}

// An <img> tag at text[start]; returns { end, image } or null.
function _htmlImage(text, start, baseUrl) {
  if (!/^<img(?=[\s\/>])/i.test(text.slice(start, start + 5)))
    return null;
  var end = _tagEnd(text, start);
  if (end < 0)
    return null;
  var attributes = _attributes(text.slice(start + 4, end - 1));
  return {
    end: end,
    image: {
      source: resolve(attributes.src || attributes.source || "", baseUrl),
      alt: attributes.alt || "",
      title: attributes.title || "",
      width: _dimension(attributes.width),
      height: _dimension(attributes.height)
    }
  };
}

function _slot(slotUrl, index) {
  return slotUrl + "#slot-" + index;
}

function _parseRich(text, baseUrl, slotUrl) {
  var images = [];
  var out = "";
  var i = 0;
  while (i < text.length) {
    if (text.startsWith("<!--", i)) {
      var close = text.indexOf("-->", i + 4);
      var stop = close < 0 ? text.length : close + 3;
      out += text.slice(i, stop);
      i = stop;
      continue;
    }
    if (text[i] === "<") {
      var found = _htmlImage(text, i, baseUrl);
      if (found) {
        out += "<img src=\"" + escapeHtml(_slot(slotUrl, images.length)) + "\" />";
        images.push(found.image);
        i = found.end;
        continue;
      }
      var tag = _guardTag(text, i, slotUrl);
      if (tag) {
        out += tag.text;
        i = tag.end;
        continue;
      }
    }
    out += text[i];
    ++i;
  }
  return {
    text: out,
    images: images
  };
}

function _label(value) {
  return value.trim().replace(/\s+/g, " ").toLowerCase();
}

// Balanced [ ... ] starting at text[start] === "["; returns end index after "]".
function _bracketEnd(text, start) {
  var depth = 0;
  for (var i = start; i < text.length; ++i) {
    if (text[i] === "\\") {
      ++i;
    } else if (text[i] === "`") {
      var run = /^`+/.exec(text.slice(i))[0];
      var close = text.indexOf(run, i + run.length);
      if (close >= 0)
        i = close + run.length - 1;
    } else if (text[i] === "[") {
      ++depth;
    } else if (text[i] === "]") {
      if (--depth === 0)
        return i + 1;
    } else if (text[i] === "\n" && text[i + 1] === "\n") {
      return -1;
    }
  }
  return -1;
}

function _unescape(value) {
  return value.replace(/\\([!-\/:-@\[-`{-~])/g, "$1");
}

// Inline destination and optional title after "(" at text[start - 1].
function _inlineTarget(text, start) {
  var i = start;
  while (i < text.length && /[ \t\n]/.test(text[i]))
    ++i;
  var destination = "";
  if (text[i] === "<") {
    var close = text.indexOf(">", i + 1);
    if (close < 0 || text.slice(i + 1, close).indexOf("\n") >= 0)
      return null;
    destination = text.slice(i + 1, close);
    i = close + 1;
  } else {
    var depth = 0;
    var from = i;
    while (i < text.length && !/[ \t\n]/.test(text[i])) {
      if (text[i] === "\\") {
        i += 2;
        continue;
      }
      if (text[i] === "(")
        ++depth;
      else if (text[i] === ")") {
        if (depth === 0)
          break;
        --depth;
      }
      ++i;
    }
    destination = text.slice(from, i);
  }
  while (i < text.length && /[ \t\n]/.test(text[i]))
    ++i;
  var title = "";
  var opener = text[i];
  if (opener === "\"" || opener === "'" || opener === "(") {
    var closer = opener === "(" ? ")" : opener;
    var j = i + 1;
    while (j < text.length && text[j] !== closer) {
      if (text[j] === "\\")
        ++j;
      ++j;
    }
    if (j >= text.length)
      return null;
    title = text.slice(i + 1, j);
    i = j + 1;
    while (i < text.length && /[ \t\n]/.test(text[i]))
      ++i;
  }
  if (text[i] !== ")")
    return null;
  return {
    end: i + 1,
    destination: decodeEntities(_unescape(destination)),
    title: decodeEntities(_unescape(title))
  };
}

// Link reference definitions: [label]: destination "title"
function _definitions(lines) {
  var definitions = Object.create(null);
  var pattern = /^ {0,3}\[((?:[^\]\\]|\\.)+)\]:[ \t]*(?:<([^>\n]*)>|(\S+))(?:[ \t]+(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|\(((?:[^)\\]|\\.)*)\)))?[ \t]*$/;
  for (var i = 0; i < lines.length; ++i) {
    if (lines[i].code)
      continue;
    var match = pattern.exec(lines[i].text);
    if (!match)
      continue;
    var label = _label(match[1]);
    if (!Object.prototype.hasOwnProperty.call(definitions, label)) {
      definitions[label] = {
        destination: decodeEntities(_unescape(match[2] !== undefined ? match[2] : match[3])),
        title: decodeEntities(_unescape(match[4] || match[5] || match[6] || ""))
      };
    }
  }
  return definitions;
}

// Lines tagged as code (fenced or indented blocks) are copied unchanged.
function _lines(text) {
  var lines = text.split("\n");
  var out = [];
  var fence = null;
  var previousBlank = true;
  var previousCode = false;
  for (var i = 0; i < lines.length; ++i) {
    var line = lines[i];
    // Fences belong to their block-quote container. Keep the original lines
    // for Qt, but recognize code after removing each quote marker.
    var content = line;
    var depth = 0;
    var quote;
    while ((quote = /^ {0,3}>[ \t]?/.exec(content)) !== null) {
      content = content.slice(quote[0].length);
      ++depth;
    }
    if (fence && depth !== fence.depth)
      fence = null;
    if (fence) {
      out.push({
                 text: line,
                 code: true
               });
      var closing = new RegExp("^ {0,3}" + fence.ticks[0] + "{" + fence.ticks.length + ",}\\s*$");
      if (closing.test(content))
        fence = null;
      continue;
    }
    var opening = /^ {0,3}(`{3,}|~{3,})/.exec(content);
    if (opening && !(opening[1][0] === "`" && content.slice(opening[0].length).indexOf("`") >= 0)) {
      fence = { ticks: opening[1], depth: depth };
      out.push({
                 text: line,
                 code: true
               });
      continue;
    }
    var indented = /^( {4}|\t)/.test(content) && content.trim() !== "" && (previousBlank || previousCode);
    out.push({
               text: line,
               code: indented,
               blank: content.trim() === ""
             });
    previousCode = indented;
    previousBlank = content.trim() === "";
  }
  return out;
}

function _markdownAlt(value) {
  return value.replace(/([\\\[\]])/g, "\\$1").replace(/\n/g, " ");
}

function _parseMarkdown(text, baseUrl, slotUrl) {
  var lines = _lines(text);
  var definitions = _definitions(lines);
  var images = [];
  var add = function (image) {
    images.push(image);
    // Qt's Markdown reader drops an image whose alt text is empty; the slot's
    // alt is never shown (the overlay keeps the real alt).
    return "![" + (_markdownAlt(image.alt) || "image") + "](<" + _slot(slotUrl, images.length - 1) + ">)";
  };
  // Inline content: consecutive non-code lines form one run, so that an
  // image spanning a soft line break is still found.
  var out = [];
  var run = [];
  var flush = function () {
    if (!run.length)
      return;
    out.push(_markdownInline(run.join("\n"), definitions, baseUrl, add));
    run = [];
  };
  for (var i = 0; i < lines.length; ++i) {
    if (lines[i].code || lines[i].blank) {
      flush();
      out.push(lines[i].text);
    } else {
      run.push(lines[i].text);
    }
  }
  flush();
  return {
    text: out.join("\n"),
    images: images
  };
}

function _markdownInline(text, definitions, baseUrl, add) {
  var out = "";
  var i = 0;
  while (i < text.length) {
    var ch = text[i];
    if (ch === "\\" && i + 1 < text.length) {
      out += text.slice(i, i + 2);
      i += 2;
      continue;
    }
    if (ch === "`") {
      var ticks = /^`+/.exec(text.slice(i))[0];
      var close = text.indexOf(ticks, i + ticks.length);
      while (close >= 0 && text[close + ticks.length] === "`")
        close = text.indexOf(ticks, close + ticks.length + 1);
      if (close >= 0) {
        out += text.slice(i, close + ticks.length);
        i = close + ticks.length;
      } else {
        out += ticks;
        i += ticks.length;
      }
      continue;
    }
    if (text.startsWith("<!--", i)) {
      var end = text.indexOf("-->", i + 4);
      var stop = end < 0 ? text.length : end + 3;
      out += text.slice(i, stop);
      i = stop;
      continue;
    }
    if (ch === "<") {
      var found = _htmlImage(text, i, baseUrl);
      if (found) {
        out += add(found.image);
        i = found.end;
        continue;
      }
      // Consume the entire tag, not image-looking text inside attributes.
      // Resource attributes are guarded here, before the Markdown converter
      // ever receives them. Code spans and fenced blocks bypass this walk.
      var tag = _guardTag(text, i, "");
      if (tag) {
        out += tag.text;
        i = tag.end;
        continue;
      }
    }
    if (ch === "!" && text[i + 1] === "[") {
      var altEnd = _bracketEnd(text, i + 1);
      if (altEnd > 0) {
        var alt = _unescape(text.slice(i + 2, altEnd - 1));
        if (text[altEnd] === "(") {
          var target = _inlineTarget(text, altEnd + 1);
          if (target) {
            out += add({
                         source: resolve(target.destination, baseUrl),
                         alt: alt,
                         title: target.title,
                         width: 0,
                         height: 0
                       });
            i = target.end;
            continue;
          }
        }
        var label = alt;
        var next = altEnd;
        if (text[altEnd] === "[") {
          var refEnd = _bracketEnd(text, altEnd);
          if (refEnd > 0) {
            var ref = text.slice(altEnd + 1, refEnd - 1);
            if (ref.trim() !== "")
              label = ref;
            next = refEnd;
          }
        }
        var key = _label(label);
        var definition = Object.prototype.hasOwnProperty.call(definitions, key) ? definitions[key] : null;
        if (definition) {
          out += add({
                       source: resolve(definition.destination, baseUrl),
                       alt: alt,
                       title: definition.title,
                       width: 0,
                       height: 0
                     });
          i = next;
          continue;
        }
      }
    }
    out += ch;
    ++i;
  }
  return out;
}

// Qt's StyledText keeps line breaks; its rich-text form needs <br>.
function styledToRich(text) {
  var out = "";
  var i = 0;
  while (i < text.length) {
    if (text[i] === "<") {
      var end = text.startsWith("<!--", i) ? text.indexOf("-->", i) + 3 : _tagEnd(text, i);
      if (end > i) {
        out += text.slice(i, end);
        i = end;
        continue;
      }
    }
    out += text[i] === "\n" ? "<br>" : text[i];
    ++i;
  }
  return out;
}

// Whether Qt's StyledText could load an image from this text. Conservative:
// any <img tag counts, even inside a comment.
function styledMayLoadImages(text) {
  return /<img(?=[\s\/>])/i.test(String(text || ""));
}

function parse(text, format, baseUrl, slotUrl) {
  text = String(text || "");
  if (format === "markdown")
    return _parseMarkdown(text, baseUrl || "", slotUrl);
  return _parseRich(format === "styled" ? styledToRich(text) : text, baseUrl || "", slotUrl);
}

function hasImages(text, format) {
  return parse(text, format, "", "slot:").images.length > 0;
}

// Slot indices in the order Qt laid them out (document order of the HTML).
function order(html, slotUrl) {
  var prefix = escapeHtml(slotUrl) + "#slot-";
  var found = [];
  var pattern = /<img\b[^>]*\ssrc="([^"]*)"/gi;
  var match;
  while ((match = pattern.exec(html)) !== null) {
    if (match[1].indexOf(prefix) === 0)
      found.push(parseInt(match[1].slice(prefix.length), 10));
  }
  return found;
}

// Qt's rich text loads other images by itself too: background attributes,
// CSS background images (style attributes, <style> blocks, linked style
// sheets) and any <img> that is not a slot. They cannot be laid over text as
// owner-backed images, so they are not loaded; the text stays.
function _noCssUrls(css) {
  var out = "";
  var i = 0;
  while (i < css.length) {
    if (css.startsWith("/*", i)) {
      var comment = css.indexOf("*/", i + 2);
      var stop = comment < 0 ? css.length : comment + 2;
      out += css.slice(i, stop);
      i = stop;
      continue;
    }
    if (css[i] === "\"" || css[i] === "'") {
      var end = _cssStringEnd(css, i);
      out += css.slice(i, end);
      i = end;
      continue;
    }
    var imported = css[i] === "@";
    var start = i + (imported ? 1 : 0);
    var token = /^(?:[-_a-zA-Z0-9]|\\(?:[0-9a-fA-F]{1,6}[ \t\r\n\f]?|.))+/.exec(css.slice(start));
    if (!token) {
      out += css[i++];
      continue;
    }
    var name = token[0].replace(/\\([0-9a-fA-F]{1,6})[ \t\r\n\f]?|\\(.)/g, function (_, hex, literal) {
      var code = hex ? parseInt(hex, 16) : 0;
      return hex ? String.fromCodePoint(code > 0 && code <= 0x10FFFF ? code : 0xFFFD) : literal;
    }).toLowerCase();
    var next = start + token[0].length;
    while (/\s/.test(css[next] || "") && next < css.length)
      ++next;
    // Qt's CSS parser imports quoted stylesheets too, and decodes escaped
    // function names before interpreting URLs. Guard those same tokens.
    if ((imported && name === "import") || (name === "url" && css[next] === "(")) {
      var terminator = imported ? ";" : ")";
      var cursor = imported ? next : next + 1;
      while (cursor < css.length && css[cursor] !== terminator) {
        if (css[cursor] === "\"" || css[cursor] === "'")
          cursor = _cssStringEnd(css, cursor);
        else if (css[cursor] === "\\")
          cursor += 2;
        else
          ++cursor;
      }
      out += imported ? "" : "none";
      i = Math.min(css.length, cursor + 1);
      continue;
    }
    out += css.slice(i, start + token[0].length);
    i = start + token[0].length;
  }
  return out;
}

function _cssStringEnd(css, start) {
  var quote = css[start];
  var i = start + 1;
  while (i < css.length) {
    if (css[i] === "\\")
      i += 2;
    else if (css[i++] === quote)
      return i;
  }
  return css.length;
}

// One complete HTML tag (and style body), with attribute boundaries intact.
// Operates only on markup identified by the rich/Markdown traversal: never
// on literal code, comments, or strings inside another attribute.
function _guardTag(text, start, slotUrl) {
  var end = _tagEnd(text, start);
  if (end < 0)
    return null;
  var tag = text.slice(start, end);
  var head = /^<\s*([a-zA-Z][a-zA-Z0-9]*)/.exec(tag);
  if (!head)
    return { text: tag, end: end };
  var name = head[1].toLowerCase();
  if (name === "link")
    return { text: "", end: end };
  if (name === "img") {
    var src = _attributes(tag.slice(head[0].length, -1)).src || "";
    if (!slotUrl || src.indexOf(slotUrl + "#slot-") !== 0)
      return { text: "", end: end };
  }
  var body = tag.slice(head[0].length, -1);
  var pattern = /([^\s"'>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  var out = tag.slice(0, head[0].length);
  var cursor = 0;
  var match;
  while ((match = pattern.exec(body)) !== null) {
    out += body.slice(cursor, match.index);
    var attribute = match[1].toLowerCase();
    if (attribute === "style") {
      var value = match[2] !== undefined ? match[2] : match[3] !== undefined ? match[3] : match[4] || "";
      var decoded = decodeEntities(value);
      var guarded = _noCssUrls(decoded);
      out += guarded === decoded ? match[0] : "style=\"" + escapeHtml(guarded) + "\"";
    } else if (attribute !== "background") {
      out += match[0];
    }
    cursor = pattern.lastIndex;
  }
  out += body.slice(cursor) + ">";
  if (name === "style") {
    var closing = text.slice(end).search(/<\/style\s*>/i);
    var stop = closing < 0 ? text.length : end + closing;
    out += _noCssUrls(text.slice(end, stop));
    end = stop;
  }
  return { text: out, end: end };
}

function withoutResourceImages(html, slotUrl) {
  var out = "";
  var i = 0;
  var dropped = 0;
  while (i < html.length) {
    if (html.startsWith("<!--", i)) {
      var close = html.indexOf("-->", i + 4);
      var stop = close < 0 ? html.length : close + 3;
      out += html.slice(i, stop);
      i = stop;
      continue;
    }
    var guarded = html[i] === "<" ? _guardTag(html, i, slotUrl) : null;
    if (!guarded) {
      out += html[i];
      ++i;
      continue;
    }
    if (guarded.text !== html.slice(i, guarded.end))
      ++dropped;
    out += guarded.text;
    i = guarded.end;
  }
  return {
    html: out,
    dropped: dropped
  };
}

// The slot <img> tags of Qt's serialized HTML, with the current sizes.
function sized(html, slotUrl, sizes) {
  var prefix = escapeHtml(slotUrl) + "#slot-";
  return html.replace(/<img\b[^>]*>/gi, function (tag) {
    var src = /\ssrc="([^"]*)"/i.exec(tag);
    if (!src || src[1].indexOf(prefix) !== 0)
      return tag;
    var index = parseInt(src[1].slice(prefix.length), 10);
    var size = sizes[index] || {
      width: 1,
      height: 1
    };
    return "<img src=\"" + src[1] + "\" width=\"" + Math.max(1, Math.round(size.width)) + "\" height=\"" + Math.max(1, Math.round(size.height)) + "\" style=\"vertical-align: top\" />";
  });
}
