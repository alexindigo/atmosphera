// Oklab (Björn Ottosson's D65 matrices). Lightness steps are perceptual;
// out-of-sRGB colours lose chroma, never clip individual channels. The source
// role supplies hue/chroma; no palette-specific paint lives in the drawings.
function linear(v) {
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}

function luminance(color) {
  return .2126 * linear(color.r) + .7152 * linear(color.g) + .0722 * linear(color.b);
}

function contrast(a, b) {
  var x = luminance(a), y = luminance(b);
  return (Math.max(x, y) + .05) / (Math.min(x, y) + .05);
}

function lab(color) {
  var r = linear(color.r), g = linear(color.g), b = linear(color.b);
  var l = Math.cbrt(.4122214708 * r + .5363325363 * g + .0514459929 * b);
  var m = Math.cbrt(.2119034982 * r + .6806995451 * g + .1073969566 * b);
  var s = Math.cbrt(.0883024619 * r + .2817188376 * g + .6299787005 * b);
  return {l: .2104542553 * l + .793617785 * m - .0040720468 * s,
          a: 1.9779984951 * l - 2.428592205 * m + .4505937099 * s,
          b: .0259040371 * l + .7827717662 * m - .808675766 * s};
}

function rgb(l, a, b) {
  var x = Math.pow(l + .3963377774 * a + .2158037573 * b, 3);
  var y = Math.pow(l - .1055613458 * a - .0638541728 * b, 3);
  var z = Math.pow(l - .0894841775 * a - 1.291485548 * b, 3);
  return [4.0767416621 * x - 3.3077115913 * y + .2309699292 * z,
          -1.2684380046 * x + 2.6097574011 * y - .3413193965 * z,
          -.0041960863 * x - .7034186147 * y + 1.707614701 * z];
}

function tone(l, a, b) {
  var low = 0, high = 1, channels;
  for (var i = 0; i < 14; i++) {
    var scale = (low + high) / 2;
    channels = rgb(l, a * scale, b * scale);
    if (channels.every(v => v >= 0 && v <= 1)) low = scale;
    else high = scale;
  }
  channels = rgb(l, a * low, b * low).map(v => v <= .0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - .055);
  return Qt.rgba(channels[0], channels[1], channels[2], 1);
}

function palette(source, index, count) {
  var c = lab(source);
  var t = count > 1 ? index / (count - 1) : .5;
  // Related hues, visibly separated values; keep enough body even for pale
  // dark-scheme roles, and enough light for the same ink in light schemes.
  var l = .64 + .20 * t;
  var angle = (t - .5) * .36;
  var a = c.a * Math.cos(angle) - c.b * Math.sin(angle);
  var b = c.a * Math.sin(angle) + c.b * Math.cos(angle);
  var paints = {face: tone(l, a, b), lit: tone(Math.min(.91, l + .065), a * .85, b * .85),
          shadow: tone(l - .12, a * .85, b * .85),
          haze: tone(.88, a * .30, b * .30 - .018),
          highlight: tone(.96, a * .12, b * .12 - .018),
          ink: tone(.22, a * .30, b * .30),
          emboss: tone(Math.min(.95, l + .13), a * .50, b * .50),
          embossShadow: tone(l - .09, a * .70, b * .70)};
  // Oklab L is perceptual, not WCAG luminance. Enforce the ink contract on
  // the actual gamut-mapped paints, including very saturated source roles.
  var inkL = .22;
  // Compare QColor channels directly: hex serialization rounds to 8 bits and
  // can round a just-below-threshold pair up past the threshold.
  while ([paints.face, paints.shadow, paints.haze].some(p => contrast(paints.ink, p) < 3) && inkL > .02) {
    inkL -= .01;
    paints.ink = tone(inkL, a * .30, b * .30);
  }
  return paints;
}
