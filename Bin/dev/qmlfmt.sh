#!/usr/bin/env -S bash

# Uses: https://github.com/jesperhh/qmlfmt
# Can be installed from AUR "qmlfmt-git"
# Requires qt6-5compat

cd "$(git rev-parse --show-toplevel)"
echo "Formatting $(find . -name "*.qml" | wc -l) files..."
find . -name "*.qml" -print0 | xargs -0 -P "$(nproc)" -I {} qmlfmt -e -b 360 -t 2 -i 2 -w {}
