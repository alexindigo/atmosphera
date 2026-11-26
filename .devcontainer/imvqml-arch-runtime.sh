# Arch runtime dependencies for qt6-imvqml. Keep this aligned with its PKGBUILD.
# Readers are classified separately only so CI can remove them for its negative
# control without upgrading Qt or changing any other runtime dependency.
imvqml_core=(qt6-base qt6-declarative libvips libwebp mpv)
imvqml_readers=(qt6-imageformats kimageformats)
