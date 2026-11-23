import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../Helpers/ImageBytes.js" as ImageBytes
import "../../Helpers/PortalPaths.js" as PortalPaths

// Producer-time capture only. Decoding, retained publication and Qt acceptance
// remain owned by ImageCacheService. No source URL is an immutable snapshot.
Scope {
  id: root
  readonly property bool ready: canvas.available && canvas.context !== null
  readonly property string captureNamespace: Date.now().toString(36) + "-" + Math.random().toString(36).slice(2)
  property int captureSerial: 0

  function failure(code, reason) {
    return {
      ok: false,
      code: code,
      reason: reason
    };
  }

  function capture(source) {
    source = String(source || "");
    if (!source)
      return failure("empty-source", "No image was requested");
    if (source.startsWith("/") || source.startsWith("file:")) {
      const path = source.startsWith("/") ? {
                                              ok: true,
                                              path: source
                                            } : PortalPaths.uriToPath(source);
      if (!path.ok)
        return failure("invalid-source", "The image path could not be read");
      // This read must finish during admission, before the producer can retire
      // its file. In particular, blockLoading alone can return a previous file.
      rawFile.path = "";
      rawFile.path = path.path;
      const loaded = rawFile.waitForJob() && rawFile.loaded;
      const bytes = loaded ? rawFile.data() : null;
      rawFile.path = "";
      if (!loaded || !bytes || bytes.byteLength === 0)
        return failure("source-unreadable", "The image file could not be captured");
      return {
        ok: true,
        source: ImageBytes.dataUrl(bytes),
        originalSource: source,
        captureKind: "bytes"
      };
    }
    if (!source.startsWith("image://"))
      return {
        ok: true,
        source: source,
        originalSource: source,
        captureKind: "bytes"
      };
    if (!ready)
      return failure("provider-not-ready", "The image capture surface is not ready");
    const parts = /^image:\/\/(?:[^\/?#@]*@)?([A-Za-z0-9_-]+)\/(.*)$/.exec(source);
    if (!parts)
      return failure("invalid-source", "The image provider URL is invalid");
    // Qt uses the full URL as the pixmap key, but dispatches by host and
    // passes only path/query (and fragment) to the provider. Vary the URL's
    // user-info so Image and Canvas share only this capture's fresh pixmap.
    const serial = ++captureSerial;
    const captureUrl = "image://capture-" + captureNamespace + "-" + serial + "@" + parts[1] + "/" + parts[2];
    // Providers may expose borrowed pixels. Load and detach on this call stack,
    // not from a deferred Image/worker/grab callback after replacement or close.
    provider.source = captureUrl;
    if (provider.status !== Image.Ready) {
      provider.source = "";
      return failure("provider-failed", "The image provider could not supply this image");
    }
    const context = canvas.getContext("2d");
    context.reset();
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.drawImage(provider, 0, 0, canvas.width, canvas.height);
    const captured = canvas.isImageLoaded(captureUrl) ? canvas.toDataURL("image/png") : "";
    canvas.unloadImage(captureUrl);
    provider.source = "";
    if (!captured.startsWith("data:image/png;base64,"))
      return failure("provider-failed", "The image provider pixels could not be captured");
    return {
      ok: true,
      source: captured,
      originalSource: source,
      captureKind: "provider",
      width: 64,
      height: 64
    };
  }

  FileView {
    id: rawFile
    printErrors: false
  }
  PanelWindow {
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    mask: Region {}
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "atmosphera-image-admission"
    Canvas {
      id: canvas
      width: 64
      height: 64
      opacity: 0
      renderStrategy: Canvas.Immediate
      contextType: "2d"
    }
    Image {
      id: provider
      visible: false
      asynchronous: false
      cache: true
    }
  }
}
