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

## Thumbnails held by plugins

A plugin that needs a thumbnail file rather than a rendered item (a video
wallpaper that hands its frame to color generation, a card sorted by color)
asks the owner directly and holds the interest while it uses the file:

```qml
token = ImageCacheService.acquireSource({ source: path, width: 1024, height: 1024,
  fit: "contain", animationIntent: "still", operation: "video-thumbnail" }, reply => { ... })
ImageCacheService.releaseSource(token)
```

The reply has `status` (`hit`, `generated` or `unavailable`), the validated
PNG's `url`, and `code`/`reason` on failure. `retry: true` asks again even
after a stored failure (for a Refresh button). Plugins do not run their own
converters or keep their own thumbnail folders.
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
