pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "FileIconColors.js" as IconColors

Singleton {
  id: root

  // The shared MIME database supplies name matching, including application/*
  // types. Preview support is deliberately narrower than file filtering.
  property var _mimeGlobs: []
  property var _mimeAliases: ({})
  property var _mimeParents: ({})
  signal filtersChanged

  // Role ownership is independent of classification, drawing and tone generation.
  readonly property color folderRole: AtmoColor.mPrimary
  readonly property color networkRole: AtmoColor.mStandout
  readonly property color mediaRole: AtmoColor.mPrimary
  readonly property color textRole: AtmoColor.mSecondary
  readonly property color restRole: AtmoColor.mTertiary
  readonly property color archiveRole: AtmoColor.mStandout
  // The approved light audio mark needs the deeper end of the media tones.
  readonly property var groups: ({media: ["audio", "video", "image"], text: ["text", "markdown", "pdf", "document", "spreadsheet", "presentation", "ebook", "web", "code", "data"], rest: ["executable", "disk", "font", "unknown"], archives: ["zip", "tar", "gzip", "xz", "bzip", "zstd", "sevenzip", "rar", "archive"]})
  readonly property var extensions: ({
    image: "png jpg jpeg gif webp bmp svg avif tif tiff ico heic jxl",
    video: "mp4 mkv webm mov avi m4v mpeg mpg",
    audio: "mp3 flac wav ogg opus m4a aac aiff",
    text: "txt log rst", markdown: "md markdown mdx", pdf: "pdf",
    document: "odt doc docx pages rtf", spreadsheet: "csv tsv ods xls xlsx xlsm",
    presentation: "odp ppt pptx key", ebook: "epub mobi azw azw3 cbz cbr",
    web: "html htm css scss sass less",
    code: "js ts jsx tsx qml py c cpp cc cxx h hpp rs go java kt kts swift rb php lua sql vue svelte",
    data: "json jsonc yaml yml toml ini conf cfg xml env properties lock",
    executable: "sh bash zsh fish exe appimage run bat cmd ps1 desktop",
    disk: "iso img qcow2 vhd vhdx vdi dmg", font: "otf ttf woff woff2",
    zip: "zip", tar: "tar", gzip: "gz tgz", xz: "xz txz", bzip: "bz2 tbz2", zstd: "zst", sevenzip: "7z", rar: "rar",
    archive: "lz lzma lz4 br cab deb rpm"
  })
  property var _mounts: []
  FileView {
    id: mountInfo
    path: "/proc/self/mountinfo"
    printErrors: false
    onLoaded: root._mounts = root.parseMounts(text())
  }
  Timer { interval: 10000; repeat: true; running: true; onTriggered: mountInfo.reload() }

  function fileType(name) {
    var lower = name.toLowerCase();
    if ([".env", ".gitconfig", ".editorconfig"].includes(lower)) return "data";
    if (["makefile", "dockerfile", "cmakelists.txt"].includes(lower)) return "code";
    if (["readme", "license", "changelog"].includes(lower)) return "text";
    var ext = extension(name);
    for (var type of Object.keys(extensions))
      if (extensions[type].split(" ").includes(ext)) return type;
    return "unknown";
  }
  function group(type) {
    for (var key of Object.keys(groups))
      if (groups[key].includes(type)) return key;
    return "rest";
  }
  function isHidden(name) { return name.startsWith("."); }
  function parseMounts(text) {
    return text.split("\n").filter(line => line.includes(" - ")).map(line => {
      var halves = line.split(" - "), fields = halves[0].split(" ");
      var path = fields[4].replace(/\\([0-7]{3})/g, (_, octal) => String.fromCharCode(parseInt(octal, 8)));
      var fs = halves[1].split(" ")[0];
      return {path: path, network: /^(cifs|smb3?|nfs4?|sshfs|sftp|davfs2?|webdav|fuse\.(sshfs|rclone|gvfsd-fuse))$/.test(fs)};
    });
  }
  function folderKind(path, mounts, xdg) {
    mounts = mounts === undefined ? _mounts : mounts;
    xdg = xdg === undefined ? FilePlaces.xdgFolders : xdg;
    path = path.length > 1 ? path.replace(/\/+$/, "") : path;
    var covering = null;
    for (var mount of mounts)
      if ((path === mount.path || path.startsWith(mount.path === "/" ? "/" : mount.path + "/")) && (!covering || mount.path.length > covering.path.length)) covering = mount;
    if (covering && covering.network) return "network";
    for (var key of Object.keys(xdg))
      if (path === xdg[key]) return key.toLowerCase();
    return "ordinary";
  }
  function artwork(name, directory, path) {
    var type = directory ? "folder" : fileType(name);
    return {type: type, group: directory ? "folder" : group(type), folder: directory ? folderKind(path) : "", hidden: isHidden(name)};
  }
  function iconColors(descriptor) {
    var role = descriptor.type === "folder" ? (descriptor.folder === "network" ? networkRole : folderRole) : ({media: mediaRole, text: textRole, rest: restRole, archives: archiveRole})[descriptor.group];
    var types = groups[descriptor.group] || ["folder"];
    return IconColors.palette(role, Math.max(0, types.indexOf(descriptor.type)), types.length);
  }

  FileView {
    id: mimeView
    path: "/usr/share/mime/globs2"
    printErrors: false
    onLoaded: {
      var entries = [];
      for (var line of text().split("\n")) {
        if (!line || line[0] === "#")
          continue;
        var fields = line.split(":");
        if (fields.length >= 3)
          entries.push({mime: fields[1], pattern: fields[2], sensitive: fields[3] === "cs"});
      }
      root._mimeGlobs = entries;
      root.filtersChanged();
    }
  }

  FileView {
    path: "/usr/share/mime/aliases"
    printErrors: false
    onLoaded: {
      var aliases = {};
      for (var line of text().split("\n")) {
        var pair = line.trim().split(/\s+/);
        if (pair.length === 2 && !line.startsWith("#"))
          aliases[pair[0]] = pair[1];
      }
      root._mimeAliases = aliases;
      root.filtersChanged();
    }
  }

  FileView {
    path: "/usr/share/mime/subclasses"
    printErrors: false
    onLoaded: {
      var parents = {};
      for (var line of text().split("\n")) {
        var pair = line.trim().split(/\s+/);
        if (pair.length === 2 && !line.startsWith("#"))
          parents[pair[0]] = (parents[pair[0]] || []).concat([pair[1]]);
      }
      root._mimeParents = parents;
      root.filtersChanged();
    }
  }

  function _matchesMime(actual, requested, seen) {
    actual = _mimeAliases[actual] || actual;
    requested = _mimeAliases[requested] || requested;
    if (matchesGlob(actual, requested, true))
      return true;
    if (seen.includes(actual))
      return false;
    var visited = seen.concat([actual]);
    return (_mimeParents[actual] || []).some(parent => _matchesMime(parent, requested, visited));
  }

  function extension(name) {
    var dot = name.lastIndexOf(".");
    return dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
  }

  function previewKind(name) {
    var ext = extension(name);
    if (["gif", "webp"].includes(ext))
      return "animatedImage";
    if (["png", "jpg", "jpeg", "bmp", "svg", "avif", "tif", "tiff", "ico"].includes(ext))
      return "image";
    if (["mp4", "mkv", "webm", "mov", "avi", "m4v", "mpeg"].includes(ext))
      return "video";
    if (["mp3", "flac", "wav", "ogg", "opus", "m4a", "aac"].includes(ext))
      return "audio";
    if (ext === "pdf")
      return "pdf";
    if (["txt", "md", "log", "json", "js", "ts", "qml", "py", "sh", "c", "cpp", "h", "rs", "html", "css", "xml", "yaml", "yml", "toml", "ini", "conf", "csv"].includes(ext) || ["Makefile", "LICENSE", "README"].includes(name))
      return "text";
    return "none";
  }

  function icon(name, directory) {
    if (directory)
      return "filepicker-folder";
    var kind = previewKind(name);
    return ({image: "filepicker-photo", animatedImage: "filepicker-photo", video: "filepicker-video", audio: "filepicker-music", text: "filepicker-file-text", pdf: "filepicker-text"})[kind] || "filepicker-file";
  }

  function matchesGlob(name, pattern, sensitive) {
    // Shell-style patterns, including bracket expressions; never execute a
    // caller's pattern as a regular expression.
    var expression = "^";
    for (var i = 0; i < pattern.length; i++) {
      var ch = pattern[i];
      if (ch === "*")
        expression += ".*";
      else if (ch === "?")
        expression += ".";
      else if (ch === "[" && pattern.indexOf("]", i + 1) > i + 1) {
        var end = pattern.indexOf("]", i + 1);
        var range = pattern.slice(i + 1, end);
        expression += "[" + (range[0] === "!" ? "^" + range.slice(1) : range) + "]";
        i = end;
      } else
        expression += ch.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
    }
    try {
      return new RegExp(expression + "$", sensitive ? "" : "i").test(name);
    } catch (e) {
      return false;
    }
  }

  function matchesFilter(name, filter) {
    if (!filter || !filter[1] || filter[1].length === 0)
      return true;
    for (var rule of filter[1]) {
      if (rule[0] === 0 && matchesGlob(name, rule[1], true))
        return true;
      if (rule[0] === 1) {
        for (var entry of _mimeGlobs) {
          if (_matchesMime(entry.mime, rule[1], []) && matchesGlob(name, entry.pattern, entry.sensitive))
            return true;
        }
      }
    }
    return false;
  }

  function formatSize(bytes, locale) {
    var size = Math.max(0, bytes);
    var unit = size < 1024 ? 0 : Math.min(4, Math.floor(Math.log(size) / Math.log(1024)));
    // QML's Number.toLocaleString defaults to two decimal places, unlike the
    // browser API. Precision belongs here, not in a pre-rounded intermediate.
    return (size / Math.pow(1024, unit)).toLocaleString(locale || Qt.locale(), "f", unit === 0 ? 0 : 1) + " " + ["B", "KiB", "MiB", "GiB", "TiB"][unit];
  }

  function formatDate(value, locale) {
    return new Date(value).toLocaleString(locale || Qt.locale(), Locale.ShortFormat);
  }
}
