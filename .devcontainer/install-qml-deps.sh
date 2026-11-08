#!/usr/bin/env bash
set -euo pipefail

# Released shell dependencies, pinned to source archive checksums.
# The compositor libraries are also required to resolve the full lint tree.
work=$(mktemp -d /var/cache/atmosphera-qml.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/tmp"
export TMPDIR="$work/tmp"

install_module() {
    local repo=$1 version=$2 checksum=$3
    local source="$work/$repo" archive="$work/$repo.tar.gz"
    curl --fail --location --retry 3 --max-time 120 \
        "https://github.com/alexindigo/$repo/archive/refs/tags/v$version.tar.gz" \
        --output "$archive"
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --strict
    mkdir "$source"
    tar -xzf "$archive" --strip-components=1 -C "$source"
    cmake -S "$source" -B "$source/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_TEST_MODE=OFF \
        -DCMAKE_SKIP_RPATH=ON -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib
    cmake --build "$source/build" --parallel 2
    cmake --install "$source/build"
}

install_module dbusqml 1.1.2 00c7ec63c3407a53c0b43c5bfdec81f1a3f23f71aa757fab97ba24dacd2d7681
install_module xdgiconqml 0.1.0 4017958aaba9791e5799fc72ae8447ed0db4026de741ade50e4e94abe5b955e9
install_module pipewirespectrum 0.1.0 9c1be44521c2386f7a2190e6ca07b9eec692c4ed765faa29331ea4815d080544
install_module niriqml 0.2.0 59079deeeed8dc245e35ee91846f0f7b32e005cc6ff716a1b05ed68de64e0b4f
install_module mangowcqml 0.1.0 1e92e9ec4e7b274b2c0a4e28ee377cc08c026f1c364d6e1a66b62576578dc7b8
