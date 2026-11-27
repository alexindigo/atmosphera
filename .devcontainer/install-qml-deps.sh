#!/usr/bin/env bash
set -euo pipefail

# Released shell dependencies, pinned to source archive checksums.
# The compositor libraries are also required to resolve the full lint tree.
work=$(mktemp -d /var/cache/atmosphera-qml.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/tmp"
export TMPDIR="$work/tmp"

# Generated IPC sources can use more than two cores, but keep cold builds
# bounded on smaller development machines and memory-limited builders.
jobs=$(nproc)
memory_jobs=$(awk '/^MemTotal:/ { print int($2 / 1048576); exit }' /proc/meminfo)
if [[ -r /sys/fs/cgroup/memory.max ]]; then
    read -r memory_limit < /sys/fs/cgroup/memory.max
    if [[ $memory_limit != max ]]; then
        limit_jobs=$((memory_limit / 1073741824))
        (( memory_jobs <= limit_jobs )) || memory_jobs=$limit_jobs
    fi
fi
(( jobs <= 4 )) || jobs=4
(( jobs <= memory_jobs )) || jobs=$memory_jobs
(( jobs >= 1 )) || jobs=1
printf 'Building QML dependencies with up to %s parallel jobs\n' "$jobs"

install_module() {
    local repo=$1 version=$2 checksum=$3 ref=${4:-refs/tags/v$2}
    local source="$work/$repo" archive="$work/$repo.tar.gz"
    curl --fail --location --retry 3 --max-time 120 \
        "https://codeload.github.com/alexindigo/$repo/tar.gz/$ref" \
        --output "$archive"
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --strict
    mkdir "$source"
    tar -xzf "$archive" --strip-components=1 -C "$source"
    if [[ $repo == configqml ]]; then
        # Keep Core, CorePrivate and Qml on the exact tested private ABI.
        git -C "$source" apply /usr/local/share/atmosphera/configqml-qt-6.12.1.patch
    fi
    cmake -S "$source" -B "$source/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_TEST_MODE=OFF -DBUILD_TESTING=OFF \
        -DCMAKE_SKIP_RPATH=ON -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib
    cmake --build "$source/build" --parallel "$jobs"
    cmake --install "$source/build"
}

install_module dbusqml 1.1.2 00c7ec63c3407a53c0b43c5bfdec81f1a3f23f71aa757fab97ba24dacd2d7681
install_module configqml 0.5.5 b30d66b2f3f3a1b6edd8cd8c6fd45e4743bf17589b82c0c8bf1996ea4b2ec550
install_module xdgiconqml 0.1.0 4017958aaba9791e5799fc72ae8447ed0db4026de741ade50e4e94abe5b955e9
install_module pipewirespectrum 0.1.0 9c1be44521c2386f7a2190e6ca07b9eec692c4ed765faa29331ea4815d080544
install_module niriqml 0.3.0 d843571a03ee278d96e24e6dac7ca03194ccd2b532fcdac1cc981e721a17d3f8
install_module mangowcqml 0.1.0 1e92e9ec4e7b274b2c0a4e28ee377cc08c026f1c364d6e1a66b62576578dc7b8
install_module mpvqml 0.3.0 ce15ef421edfb770befbe801529b2073d4f93ee5581122c6d0d1cd3ec03acfc9
install_module imvqml 0.1.5 59cc363fa25b52e860148b1c113c1c321efe339dde07a4242ceeae1022f13ca3
