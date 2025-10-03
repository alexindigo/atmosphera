// Material 3 Color Generator Helpers

/**
 * Convert hex color to HSL
 */
function hexToHSL(hex) {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  if (!result) return null;

  let r = parseInt(result[1], 16) / 255;
  let g = parseInt(result[2], 16) / 255;
  let b = parseInt(result[3], 16) / 255;

  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  let h,
    s,
    l = (max + min) / 2;

  if (max === min) {
    h = s = 0;
  } else {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r:
        h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
        break;
      case g:
        h = ((b - r) / d + 2) / 6;
        break;
      case b:
        h = ((r - g) / d + 4) / 6;
        break;
    }
  }

  return { h: h * 360, s: s * 100, l: l * 100 };
}

/**
 * Convert HSL to hex color
 */
function hslToHex(h, s, l) {
  s /= 100;
  l /= 100;

  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - c / 2;
  let r = 0,
    g = 0,
    b = 0;

  if (0 <= h && h < 60) {
    r = c;
    g = x;
    b = 0;
  } else if (60 <= h && h < 120) {
    r = x;
    g = c;
    b = 0;
  } else if (120 <= h && h < 180) {
    r = 0;
    g = c;
    b = x;
  } else if (180 <= h && h < 240) {
    r = 0;
    g = x;
    b = c;
  } else if (240 <= h && h < 300) {
    r = x;
    g = 0;
    b = c;
  } else if (300 <= h && h < 360) {
    r = c;
    g = 0;
    b = x;
  }

  r = Math.round((r + m) * 255);
  g = Math.round((g + m) * 255);
  b = Math.round((b + m) * 255);

  return (
    "#" +
    [r, g, b]
      .map((x) => {
        const hex = x.toString(16);
        return hex.length === 1 ? "0" + hex : hex;
      })
      .join("")
  );
}

/**
 * Generate fixed_dim variant (darker, muted version)
 * Material 3 fixed_dim is typically 20-30% darker
 */
function generateFixedDim(hexColor) {
  const hsl = hexToHSL(hexColor);
  if (!hsl) return hexColor;

  // Reduce lightness by 25-30% and slightly reduce saturation
  const newL = Math.max(hsl.l * 0.7, 10);
  const newS = Math.max(hsl.s * 0.85, 5);

  return hslToHex(hsl.h, newS, newL);
}

/**
 * Generate bright variant (lighter, more vibrant version)
 * Material 3 bright is typically 15-25% lighter with boosted saturation
 */
function generateBright(hexColor) {
  const hsl = hexToHSL(hexColor);
  if (!hsl) return hexColor;

  // Increase lightness by 20-25% and boost saturation
  const newL = Math.min(hsl.l * 1.25, 90);
  const newS = Math.min(hsl.s * 1.1, 100);

  return hslToHex(hsl.h, newS, newL);
}

/**
 * Generate container variant (much lighter, desaturated version)
 * Material 3 container is typically used for backgrounds, much lighter with reduced saturation
 */
function generateContainer(hexColor, isDarkTheme = false) {
  const hsl = hexToHSL(hexColor);
  if (!hsl) return hexColor;

  let newL, newS;
  
  if (isDarkTheme) {
    // Dark theme: darken the color (aim for 10-20 lightness)
    newL = Math.max(hsl.l - (hsl.l - 15) * 0.85, 10);
    newS = Math.max(hsl.s * 0.4, 10);
  } else {
    // Light theme: lighten the color (aim for 85-90 lightness)
    newL = Math.min(hsl.l + (90 - hsl.l) * 0.85, 90);
    newS = Math.max(hsl.s * 0.4, 10);
  }

  return hslToHex(hsl.h, newS, newL);
}