.pragma library

// Recognition/filter policy only. Actual bytes and reader outcomes decide
// decodability; this table must never select a native/fallback decoder.
var extensions = "jpg jpeg png gif bmp webp avif heic heif tiff tif pnm pgm ppm pbm svg svgz ico icns jxl jp2 j2k exr hdr dds tga";
var filters = extensions.split(" ").map(function(extension) { return "*." + extension; });
function recognizes(extension) { return extensions.split(" ").includes(extension.toLowerCase()); }
