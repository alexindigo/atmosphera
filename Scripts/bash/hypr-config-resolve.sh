#!/usr/bin/env bash
# Shared read-only Hyprland target resolver. Source and call hypr_config_resolve,
# or run with bash: stdout is language, absolute root path, directory (one per line).
# Never evaluate stdout as shell code. Unknown fresh versions refuse all writes.
hypr_config_resolve() {
    local base version major minor
    base="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
    version=$(timeout 5 Hyprland --version 2>/dev/null) || version=
    if [[ $version =~ Hyprland[[:space:]]+v?([0-9]+)\.([0-9]+) ]]; then
        major=$((10#${BASH_REMATCH[1]})); minor=$((10#${BASH_REMATCH[2]}))
        if (( major == 0 && minor < 53 )); then
            echo 'Atmosphera requires Hyprland >= 0.53.' >&2
            return 1
        fi
    else
        major=; minor=
    fi
    if [[ -n ${HYPRLAND_CONFIG:-} ]]; then
        HYPR_CONFIG_FILE=$HYPRLAND_CONFIG
    elif [[ -f $base/hyprland.lua ]]; then
        HYPR_CONFIG_FILE=$base/hyprland.lua
    elif [[ -f $base/hyprland.conf ]]; then
        HYPR_CONFIG_FILE=$base/hyprland.conf
    elif [[ -z $major ]]; then
        echo 'Cannot determine Hyprland version and no config exists; set HYPRLAND_CONFIG to a .lua or .conf path.' >&2
        return 1
    elif (( major > 0 || minor >= 55 )); then
        HYPR_CONFIG_FILE=$base/hyprland.lua
    else
        HYPR_CONFIG_FILE=$base/hyprland.conf
    fi
    HYPR_CONFIG_FILE=$(realpath -m -s -- "$HYPR_CONFIG_FILE") || return 1
    case "$HYPR_CONFIG_FILE" in
        *.lua) HYPR_CONFIG_LANGUAGE=lua ;;
        *.conf) HYPR_CONFIG_LANGUAGE=hyprlang ;;
        *) echo 'HYPRLAND_CONFIG must name a .lua or .conf file.' >&2; return 1 ;;
    esac
    case "$HYPR_CONFIG_FILE" in
        *$'\n'*|*$'\r'*) echo 'Hyprland config paths cannot contain line breaks.' >&2; return 1 ;;
    esac
    HYPR_CONFIG_DIR=$(dirname -- "$HYPR_CONFIG_FILE")
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    hypr_config_resolve || exit 1
    printf '%s\n' "$HYPR_CONFIG_LANGUAGE" "$HYPR_CONFIG_FILE" "$HYPR_CONFIG_DIR"
fi
