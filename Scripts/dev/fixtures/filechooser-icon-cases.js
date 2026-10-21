// Invoked by the existing QML unit suite: exercise the real singleton, not a
// second extension classifier or a Python translation of the colour maths.
function run(types, places, colors, schemes, report, same) {
  var specimens = {image: "Photo.HEIC", video: "Movie.mpg", audio: "Song.aiff", text: "README", markdown: "Notes.mdx", pdf: "Print.PDF", document: "Letter.docx", spreadsheet: "Table.csv", presentation: "Talk.key", ebook: "Book.cbz", web: "Style.scss", code: "CMakeLists.txt", data: ".env", zip: "Pack.ZIP", tar: "Pack.tar", gzip: "Pack.tar.gz", xz: "Pack.xz", bzip: "Pack.bz2", zstd: "Pack.zst", sevenzip: "Pack.7z", rar: "Pack.rar", archive: "Pack.cab", executable: "Run.AppImage", disk: "Disk.qcow2", font: "Type.woff2", unknown: "Mystery.xyz"};
  for (var type of Object.keys(specimens)) {
    same("icons.type." + type, types.fileType(specimens[type]), type);
    report("icons.group." + type, types.groups[types.group(type)].includes(type), types.group(type));
  }
  same("icons.basename-precedes-extension", types.fileType("CMakeLists.txt"), "code");
  same("icons.preview-independent", [types.fileType("Photo.heic"), types.previewKind("Photo.heic")], ["image", "none"]);
  same("icons.directory-precedence", types.artwork("folder.pdf", true, "/example").type, "folder");
  same("icons.hidden", [types.isHidden(".folder"), types.isHidden(".secret.md"), types.isHidden("visible.txt")], [true, true, false]);
  var mounts = types.parseMounts("1 0 0:1 / / rw - ext4 /dev/vda rw\n2 1 0:2 / /network\\040share rw - cifs //server/share rw\n3 2 0:3 / /network\\040share/local rw - ext4 /dev/vdb rw\n");
  same("icons.network-mount", [types.folderKind("/network share/sub", mounts, {}), types.folderKind("/network shareish", mounts, {}), types.folderKind("/network share/local/sub", mounts, {})], ["network", "ordinary", "ordinary"]);
  for (var fs of ["smb3", "nfs", "nfs4", "fuse.sshfs", "sftp", "davfs", "davfs2", "webdav", "fuse.gvfsd-fuse"])
    same("icons.network." + fs, types.folderKind("/remote/child", types.parseMounts("2 1 0:2 / /remote rw - " + fs + " remote rw"), {}), "network");
  for (var key of ["DESKTOP", "DOCUMENTS", "DOWNLOAD", "MUSIC", "PICTURES", "VIDEOS", "TEMPLATES", "PUBLICSHARE"]) {
    var xdg = {}; xdg[key] = "/custom/" + key;
    same("icons.xdg." + key, types.folderKind(xdg[key], [], xdg), key.toLowerCase());
    same("icons.xdg-not-basename." + key, types.folderKind("/elsewhere/" + key, [], xdg), "ordinary");
  }
  report("icons.xdg-settings", places.xdgFolders.DOCUMENTS && types.folderKind(places.xdgFolders.DOCUMENTS) === "documents", places.xdgFolders);
  var before = {mPrimary: colors.mPrimary, mSecondary: colors.mSecondary, mTertiary: colors.mTertiary, mError: colors.mError};
  colors.skipTransition = true;
  function luminance(c) {
    function lin(v) { return v <= .04045 ? v / 12.92 : Math.pow((v + .055) / 1.055, 2.4); }
    return .2126 * lin(c.r) + .7152 * lin(c.g) + .0722 * lin(c.b);
  }
  function contrast(a, b) { var x = luminance(a), y = luminance(b); return (Math.max(x, y) + .05) / (Math.min(x, y) + .05); }
  for (var scheme of schemes) {
    for (var role of Object.keys(before)) colors[role] = scheme.colors[role];
    for (var group of Object.keys(types.groups)) {
      var faces = [], values = [], minimum = 100;
      for (var type of types.groups[group]) {
        var paints = types.iconColors({type: type, group: group, folder: ""});
        faces.push(paints.face.toString()); values.push(luminance(paints.face));
        minimum = Math.min(minimum, contrast(paints.ink, paints.face), contrast(paints.ink, paints.shadow), contrast(paints.ink, paints.haze));
      }
      report("icons.tones." + scheme.name + "." + group, new Set(faces).size === faces.length && values.every((v, i) => !i || v > values[i - 1]), faces);
      report("icons.ink." + scheme.name + "." + group, minimum >= 3, minimum);
    }
  }
  for (var role of Object.keys(before)) colors[role] = before[role];
}
