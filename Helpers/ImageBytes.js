.pragma library

// Binary bytes must never go through Qt.btoa(string), whose UTF-8 conversion
// changes values above 127. Keep this portable to the existing Qt floor.
function base64(buffer) {
    var bytes = new Uint8Array(buffer);
    var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var chunks = [];
    for (var i = 0; i < bytes.length; i += 3) {
        var a = bytes[i];
        var b = i + 1 < bytes.length ? bytes[i + 1] : 0;
        var c = i + 2 < bytes.length ? bytes[i + 2] : 0;
        chunks.push(alphabet[a >> 2] + alphabet[((a & 3) << 4) | (b >> 4)]
                    + (i + 1 < bytes.length ? alphabet[((b & 15) << 2) | (c >> 6)] : "=")
                    + (i + 2 < bytes.length ? alphabet[c & 63] : "="));
    }
    return chunks.join("");
}

function dataUrl(buffer) {
    return "data:application/octet-stream;base64," + base64(buffer);
}
