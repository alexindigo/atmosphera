// Unit fixture: portal byte path and file URI helper (M17). Run in a private
// guest copy by portal-paths-unit.py. Prints one PORTAL_PATHS|<json> line per
// case (ASCII-only JSON, so non-ASCII and NUL never reach the log raw), then
// the DONE marker. Inputs are literal hex or escapes, not produced by the
// helper under test; expectations live in the Python runner.
import QtQuick
import "../../../Helpers/PortalPaths.js" as PortalPaths

Item {
  id: probe

  readonly property string root: "/home/tester/Projects/qt612-atmocolor/081-integrity"
  readonly property string nul: "\u0000"
  readonly property string jp: "\u65e5\u672c\u8a9e"
  readonly property string emoji: "\ud83d\ude00"

  function bytesFromHex(hex) {
    var out = [];
    for (var i = 0; i < hex.length; i += 2)
      out.push(parseInt(hex.slice(i, i + 2), 16));
    return out;
  }

  function bufferFromHex(hex) {
    return new Uint8Array(bytesFromHex(hex)).buffer;
  }

  function asciiJson(value) {
    return JSON.stringify(value).replace(/[\u007f-\uffff]/g, function (c) {
      return "\\u" + ("000" + c.charCodeAt(0).toString(16)).slice(-4);
    });
  }

  function emit(name, fn) {
    var output;
    try {
      output = fn();
    } catch (e) {
      output = {
        "threw": String(e)
      };
    }
    console.log("PORTAL_PATHS|" + asciiJson({
                                              "case": name,
                                              "output": output
                                            }));
  }

  // Round-trip cases: the closure captures the path through a parameter.
  function roundTripBytes(path) {
    return function () {
      return PortalPaths.decodeBytePath(PortalPaths.encodeBytePath(path).bytes);
    };
  }

  function roundTripUri(path) {
    return function () {
      return PortalPaths.uriToPath(PortalPaths.pathToUri(path).uri);
    };
  }

  function runAll() {
    var P = PortalPaths;

    // Byte input forms, folder "/tmp/a" (hex 2f746d702f61), with and without NUL.
    emit("ab-ascii-nul", function () {
      return P.decodeBytePath(bufferFromHex("2f746d702f6100"));
    });
    emit("ab-ascii", function () {
      return P.decodeBytePath(bufferFromHex("2f746d702f61"));
    });
    emit("u8-ascii-nul", function () {
      return P.decodeBytePath(new Uint8Array(bytesFromHex("2f746d702f6100")));
    });
    emit("u8-ascii", function () {
      return P.decodeBytePath(new Uint8Array(bytesFromHex("2f746d702f61")));
    });
    emit("arr-ascii-nul", function () {
      return P.decodeBytePath(bytesFromHex("2f746d702f6100"));
    });
    emit("arr-ascii", function () {
      return P.decodeBytePath(bytesFromHex("2f746d702f61"));
    });

    // Embedded and doubled NUL bytes.
    emit("ab-embedded-nul", function () {
      return P.decodeBytePath(bufferFromHex("2f746d702f0062"));
    });
    emit("ab-two-trailing-nul", function () {
      return P.decodeBytePath(bufferFromHex("2f746d702f610000"));
    });
    emit("ab-empty", function () {
      return P.decodeBytePath(bufferFromHex(""));
    });
    emit("arr-lone-nul", function () {
      return P.decodeBytePath([0]);
    });

    // Multibyte folder: /tmp/日本語 (e6 97 a5 e6 9c ac e8 aa 9e).
    emit("ab-jp-nul", function () {
      return P.decodeBytePath(bufferFromHex("2f746d702fe697a5e69cace8aa9e00"));
    });
    emit("ab-jp", function () {
      return P.decodeBytePath(bufferFromHex("2f746d702fe697a5e69cace8aa9e"));
    });
    // 4-byte character: /tmp/😀 (f0 9f 98 80), a surrogate pair in JS.
    emit("arr-emoji-nul", function () {
      return P.decodeBytePath(bytesFromHex("2f746d702ff09f988000"));
    });

    // Strict UTF-8 rejections (each with the NUL terminator, so the decoder is reached).
    emit("ab-invalid-ff", function () {
      return P.decodeBytePath(bufferFromHex("2f746d702fff00"));
    });
    emit("ab-truncated", function () {
      return P.decodeBytePath(bufferFromHex("2f746d702fe69700"));
    });
    emit("ab-overlong", function () {
      return P.decodeBytePath(bufferFromHex("2f746d702fc0af00"));
    });
    emit("ab-surrogate", function () {
      return P.decodeBytePath(bufferFromHex("2f746d702feda08000"));
    });

    // Input types that are not bytes must fail, never String() into a path.
    emit("type-number", function () {
      return P.decodeBytePath(42);
    });
    emit("type-object", function () {
      return P.decodeBytePath({});
    });
    emit("type-null", function () {
      return P.decodeBytePath(null);
    });
    emit("arr-bad-value", function () {
      return P.decodeBytePath([256]);
    });

    // String inputs (the M16 table, as strings).
    emit("str-nul-trailing", function () {
      return P.decodeBytePath(root + "/fc/downloads" + nul);
    });
    emit("str-plain", function () {
      return P.decodeBytePath(root + "/fc/downloads");
    });
    emit("str-embedded-nul", function () {
      return P.decodeBytePath(root + "/fc/downloads" + nul + "/plain.html");
    });
    emit("str-lone-nul", function () {
      return P.decodeBytePath(nul);
    });
    emit("str-leading-nul", function () {
      return P.decodeBytePath(nul + "/plain.html");
    });
    emit("str-file-nul", function () {
      return P.decodeBytePath(root + "/fc/downloads/existing.html" + nul);
    });
    emit("str-two-nul", function () {
      return P.decodeBytePath("/tmp/a" + nul + nul);
    });
    emit("str-jp-nul", function () {
      return P.decodeBytePath("/tmp/" + jp + nul);
    });
    emit("str-hash-plain", function () {
      return P.decodeBytePath("/tmp/a#b?c%20d e");
    });

    // encodeBytePath: exact bytes with the terminator.
    emit("enc-ascii", function () {
      return P.encodeBytePath("/tmp/a");
    });
    emit("enc-jp", function () {
      return P.encodeBytePath("/tmp/" + jp);
    });
    emit("enc-emoji", function () {
      return P.encodeBytePath("/tmp/" + emoji);
    });
    emit("enc-embedded-nul", function () {
      return P.encodeBytePath("/tmp/a" + nul + "b");
    });
    emit("enc-lone-surrogate", function () {
      return P.encodeBytePath("/tmp/\ud83d");
    });

    // pathToUri: exact outputs.
    emit("uri-hash-space-percent", function () {
      return P.pathToUri("/tmp/a#b?c%20d e");
    });
    emit("uri-jp", function () {
      return P.pathToUri("/tmp/" + jp);
    });
    emit("uri-unreserved", function () {
      return P.pathToUri("/tmp/A-z_0.9~");
    });
    emit("uri-emoji", function () {
      return P.pathToUri("/tmp/" + emoji);
    });
    emit("uri-relative", function () {
      return P.pathToUri("tmp/x");
    });
    emit("uri-empty", function () {
      return P.pathToUri("");
    });
    emit("uri-embedded-nul", function () {
      return P.pathToUri("/tmp/a" + nul);
    });
    emit("uri-type-number", function () {
      return P.pathToUri(5);
    });

    // uriToPath: accepted forms.
    emit("path-plain", function () {
      return P.uriToPath("file:///tmp/x");
    });
    emit("path-localhost", function () {
      return P.uriToPath("file://localhost/tmp/x");
    });
    emit("path-jp", function () {
      return P.uriToPath("file:///tmp/%E6%97%A5%E6%9C%AC%E8%AA%9E");
    });
    emit("path-lowercase", function () {
      return P.uriToPath("file:///tmp/%e6%97%a5");
    });
    emit("path-escapes", function () {
      return P.uriToPath("file:///tmp/a%23b%3Fc%2520d%20e");
    });
    emit("path-raw-utf8", function () {
      return P.uriToPath("file:///tmp/" + jp);
    });

    // uriToPath: rejected forms.
    emit("path-bad-hex", function () {
      return P.uriToPath("file:///tmp/%zz");
    });
    emit("path-lone-percent", function () {
      return P.uriToPath("file:///tmp/a%");
    });
    emit("path-truncated-utf8", function () {
      return P.uriToPath("file:///tmp/%E6%97");
    });
    emit("path-overlong", function () {
      return P.uriToPath("file:///tmp/%C0%AF");
    });
    emit("path-escaped-nul", function () {
      return P.uriToPath("file:///tmp/a%00b");
    });
    emit("path-other-host", function () {
      return P.uriToPath("file://otherhost/x");
    });
    emit("path-localhost-lookalike", function () {
      return P.uriToPath("file://localhost.evil/x");
    });
    emit("path-http", function () {
      return P.uriToPath("http://x/y");
    });
    emit("path-relative", function () {
      return P.uriToPath("file:relative");
    });
    emit("path-raw-hash", function () {
      return P.uriToPath("file:///tmp/a#frag");
    });
    emit("path-raw-query", function () {
      return P.uriToPath("file:///tmp/a?q=1");
    });
    emit("path-raw-space", function () {
      return P.uriToPath("file:///tmp/a b");
    });
    emit("path-type-number", function () {
      return P.uriToPath(5);
    });

    // Round trips over a shared list. Index k matches the Python list.
    var rt = ["/tmp/a", "/tmp/" + jp, "/tmp/a#b?c%20d e", "/tmp/A-z_0.9~", "/tmp/" + emoji];
    for (var k = 0; k < rt.length; k++) {
      emit("rt-bytes-" + k, roundTripBytes(rt[k]));
      emit("rt-uri-" + k, roundTripUri(rt[k]));
    }

    console.log("PORTAL_PATHS_DONE");
    finish.start();
  }

  Component.onCompleted: runAll()

  Timer {
    id: finish
    interval: 100
    onTriggered: Qt.exit(0)
  }

  Timer {
    interval: 15000
    running: true
    onTriggered: Qt.exit(2)
  }
}
