# Image sources

Every image that can come from outside the shell (user files, theme and
tray icons, notification and media art, remote URLs, data URLs, plugin
content) is decoded through one owner, `ImageCacheService`. Qt renders an
image natively when it can; when it cannot (for example WebP without Qt's
imageformats plugin), the owner's worker produces a validated PNG, or an
animated GIF when motion is requested. A failure is shown and labelled,
never replaced by an ordinary icon that looks like success.

## Components

| Component | Use |
| --- | --- |
| `NImage` | The renderer. Takes `source`, `sourceSize`, `fillMode`, `animationIntent` (`still` or `preserve`) and reports `status`, `imageState`, `errorCode`, `errorReason`, `imageResult`. |
| `NImageRounded` | Avatars, media and other rounded artwork, with an optional fallback icon and the warning badge on failure. |
| `NImageIcon` | Small resolved icons, logos and provider textures (tray, menus), with the warning badge on failure. |
| `AtmoAppIcon` | App icons by name: XdgIcon theme lookup, then `NImageIcon`. A theme file that cannot be decoded falls back to `fallbackName` and stays marked as failed. |
| `AtmoIcon` | Icon-set glyphs; SVG/image entries render their mask through `NImage`. |
| `NImageText` | Rich text (`format: "rich"`) or Markdown (`format: "markdown"`) that can contain images. |

Rounded artwork samples the owner's texture on the hardware scene graph. On
the software scene graph, which cannot run that shader, the owner supplies a
fitted and rounded representation keyed by physical size, fill mode and corner
radius. Qt provider images stay in process and use the owner's existing Canvas
renderer. Neither path captures a live scene item or opens a second source.

## Thumbnails held by plugins

A plugin that needs a thumbnail file rather than a rendered item (a video
wallpaper that hands its frame to color generation, a card sorted by color)
asks the owner directly and holds the interest while it uses the file:

```qml
thumbnailToken = ImageCacheService.acquireSource({ source: path, width: 1024, height: 1024,
  fit: "contain", animationIntent: "still", operation: "video-thumbnail" }, reply => {
    if (reply.status === "hit" || reply.status === "generated")
      startUsingThumbnail(reply.url)
    else
      finishThumbnailUse()
  })

// Call after the last reader finishes, or on cancellation after stopping readers.
function finishThumbnailUse() {
  ImageCacheService.releaseSource(thumbnailToken)
  thumbnailToken = null
}
```

The reply has `status` (`hit`, `generated` or `unavailable`), the validated
PNG's `url`, and `code`/`reason` on failure. `retry: true` asks again even
after a stored failure (for a Refresh button). Plugins do not run their own
converters or keep their own thumbnail folders.
On a video cache miss the image owner requests one bounded frame from
`MpvQml.MpvFrameCapture` (10% of the known duration, otherwise the first
frame). Install an mpvqml build that exports this type; it is loaded lazily.
Without it the shell and existing cached thumbnails still load, but an
uncached video reports a failed preview and is not written as a cached
media failure. The owner still validates and publishes the staged PNG.
`ImageCacheService.isGeneratedImage(path)` tells a thumbnail or
representation apart from a user's own image, for example so that a
thumbnail is never saved as the wallpaper to restore.

## Text with images: NImageText, not NText

`NText` is a plain QML `Text`. Qt's text layout loads and decodes every image
in rich text or Markdown by itself, so `NText` never shows images.

- Use `NImageText` for any rich text or Markdown whose content can come from
  outside the shell: notification bodies and history, the changelog,
  tooltips with such content, plugin README, chat and quote text.
- `NText` (and `Text`) with a rich-text or Markdown format is only for
  strings the shell writes itself, such as translations with `<b>` or `<a>`.
  The image boundary checker enforces a reviewed list of these sites.

This is an orchestrator decision during the image-decoding work; the user
can override it.

Two more orchestrator decisions (the user can override them):

- Notification bodies and summaries keep their images stripped by
  `NotificationService` (`<img>` dropped, Markdown images reduced to their
  alt text). A remote image would be a read receipt and a local path would
  read arbitrary files into the shell. Their text is kept; attachments
  (`image-path`, `image-data`, the app icon) go through the owner.
- `hermes-ssh-chat`'s terminal stays an interactive rich-text `TextEdit`:
  it is plugin-generated markup in which every character of the remote
  output is escaped, so image markup in that output stays text.

Plain `Text` and `Label` default to `AutoText`, which also lays out markup
(and loads its images) when the string looks like HTML. Text that shows data
sets `textFormat: Text.PlainText`.

## Notification replacement

On an observable replacement of an existing notification, the shell attempts
a fresh producer-time image capture even if the URL did not change. A
successful capture replaces the snapshot shown in popup and history; if the
source is gone or capture fails, the previous snapshot remains.

Known limitation: Quickshell reports field changes, not identical-field
replacements. If no field changes, new pixels at a stable URL cannot be
observed. Keeping Quickshell unchanged for this publication is an orchestrator
decision; the user can override it. An upstream replacement event or content
generation would supply the missing edge.

## The boundary check

`Scripts/dev/image-decoding-boundary-check.py` parses the production QML/JS
of the shell and the plugins and lists every place where Qt or a process
would decode image bytes by itself: `Image`, `AnimatedImage`, `IconImage`
and their local wrappers, text laid out as markup, `ColorQuantizer`, QML
built from strings, direct `MpvFrameCapture` construction, and
`magick`/`ffmpeg` commands. Each must match a
reviewed entry in `Scripts/dev/fixtures/image-decoding/consumers.json`
(fixed packaged assets with their hashes, the owner's own renderers,
reviewed shell-authored markup, ...). A new site, a changed asset or a
changed exempt source fails the check. Fixed/finite asset entries also pin the
complete selecting QML file in `sourceSelectionFiles`, so a sibling handler
cannot change the source while the image node remains unchanged. Cross-file
selection helpers retain their explicit definition pins. Inventory adoption
requires an exact current owner site, not just a historical renderer name.
Run it in the dev container:

```sh
python3 -B Scripts/dev/image-decoding-boundary-check.py --source . \
  --plugins ../atmosphera-plugins \
  --manifest Scripts/dev/fixtures/image-decoding/consumers.json \
  --selftest --report "$TMPDIR/image-boundary.json"
```

`NImageText` keeps Qt's own text, link and style handling. Each image
(`<img>`, Markdown inline, reference and inline-HTML images; relative
sources resolve against `baseUrl`) becomes a sized transparent slot in the
text, and an `NImage` is laid over the slot, so fallback decoding and
animation work. Images inside links still activate the link. An image that
cannot be displayed is a labelled placeholder. Code spans, code blocks,
comments and escaped image syntax stay text. Text without images creates no
image work.

Qt's rich text would also load background images by itself (`background`
attributes, CSS `background-image` in style attributes, `<style>` blocks and
linked style sheets). `NImageText` does not load those; the text stays.
With `maximumLineCount`, rich text with images is cut after that many lines
(no ellipsis); styled text without images keeps Qt's elide.

## End-consumer qualification

Run builds and probes inside the owned `atmosphera-image-decoding` VM on
`ark.home`, workspace `/home/tester/Projects/image-decoding`, using its pinned
`ark-user-vms` access route. Set `TMPDIR` inside that disk workspace. The
headless Wayland CI profile is a separate, additive container route; see
[regression profiles](regression-profiles.md).

`Scripts/dev/image-decoding-regression.py` provides `owner`,
`chooser-wallpaper`, `shell`, `plugins`, `packaging`, `all` and `review-results`.
Use genuine installed/removed `qt6-imageformats` conditions, never a simulated
Qt error. Every invocation needs explicit `--guest-profile`, `--source`,
`--plugins`, `--qt-webp`, fresh `--work-root` and `--output` paths.
Plugin cohorts also need `--baseline-plugins`. For changed-QML reporting use
`--lint-baseline-source`; `--baseline-source` instead requests historical red
controls in cases that support them.

Long cohorts run in an owned guest user unit with an exclusive lock, captured
PID/start/cgroup, durable logs and exit receipts. Repeating the identical
invocation joins that run; it does not retry a failed run or start a duplicate.
The last owned job restores the original Linger value. Private notification
buses use the profile's short runtime root, independent of evidence path depth.
Their explicit bus configuration exposes only fixture-owned servers/producers,
not login-session service directories or portal/a11y activation. The original
consumer watchdogs and ten-second bus teardown deadline are unchanged. A cleanup
failure retains the primary consumer error and reaps only the captured daemon
group; activation-isolation and failure controls run in
`Scripts/dev/image-decoding-bus-selftest.py` and the final `all` aggregate.

Run source/setup cohorts before package installation: the wizard fixture needs
no managed keyd layer or installed xremap unit. Packaging builds and installs
the actual AUR candidate, builds the locked Nix candidate, invokes both installed
shell and locker image graphs, and builds the tooling container. Nix-on-Arch
image probes use software rendering on real Wayland, not incidental host GPU
drivers, Qt imports or PATH entries.

`review-results --results <saved-artifacts>` checks exact current input hashes,
all IDs in `fixtures/image-decoding/required-cases.json`, raw Qt observations,
saved PNGs, animation frame colors and actual package receipts. Historical trees
cannot satisfy a current cohort. Its rejection controls and real guest Linger
lease checks are in `Scripts/dev/image-decoding-review-selftest.py`.

## Source resources and fixture preservation

The originating image-decoding orchestrator made these decisions, both
overridable by the user:

- Remote source bytes are bounded by the image owner's existing decode
  allocation limit, or Qt's `QImageReader` allocation limit when the owner has
  no separate limit. `images/limits.py` derives bytes from Qt 6's 256 MiB
  default allocation budget and honors positive `QT_IMAGEIO_MAXALLOC` (MiB)
  overrides. A disabled Qt allocation check retains that finite default for
  network admission. One derived source-byte budget covers the declared
  Content-Length and the running streamed byte count. Exceeding it is an
  explicit `source-too-large` terminal failure; partial files are removed,
  never silently truncated or read wholly into memory by the downloader.
  HTTP(S) sources enter that owner before rendering; Qt is offered the
  validated local representation, never a second unbounded network URL.
  Container inspection uses read-only mapped views and incremental SVG root
  parsing, not a second whole-file Python allocation.
- Guest fixture retirement retains immutable content-addressed base objects
  (deduplicated) and atomic complete reconstruction receipts on the guest's
  disk workspace. Canonical source mutation and receipt-write failures must
  not destroy reconstructable fixture bytes. This is test-harness custody,
  not product cache policy.
