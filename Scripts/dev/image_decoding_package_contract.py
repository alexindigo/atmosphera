"""The direct runtime dependency policy shared by qualification and review."""

AUR_VARIANTS = ('atmosphera', 'atmosphera-git')
AUR_REQUIRED = {'qt6-imvqml', 'qt6-mpvqml', 'quickshell', 'python'}
AUR_REMOVED = {'imagemagick', 'ffmpeg', 'qt6-imageformats', 'qtimageformats'}
NIX_DECODER = 'qt6-imvqml'
NIX_REMOVED = {'imagemagick', 'ffmpeg', 'qtimageformats'}
