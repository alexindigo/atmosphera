#!/usr/bin/env bash
# atmo-dev — makes the environment habitable for atmosphera scripts.
#
# Sets up overlay, generates VFS, exports env, then execs the given
# command. Idempotent within a container lifetime.
#
# Usage:
#   atmo-dev <command> [args...]
#
# Requires container run flags (supplied by container-run.sh and the
# devcontainer profiles):
#   --cap-add SYS_ADMIN
#   --tmpfs /tmp/overlay:size=256m,mode=1777
#
# Environment:
#   ATMOSPHERA_DEV_USERXATTR=0|1   # 1 appends the namespace-friendly
#                                  # userxattr overlay option (rootless
#                                  # Podman path); default 0 (Docker).

set -euo pipefail

REPO_MOUNT=/workspaces/atmosphera
SHELL_DIR=/home/dev/atmosphera-shell

USERXATTR="${ATMOSPHERA_DEV_USERXATTR:-0}"
case "$USERXATTR" in
    0|1) ;;
    *) echo "atmo-dev: ATMOSPHERA_DEV_USERXATTR must be 0 or 1 (got '$USERXATTR')." >&2; exit 1 ;;
esac

# --- Locale ---
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# --- Qt / Quickshell ---
export QT_QPA_PLATFORM=offscreen
export QT_LOGGING_RULES="qt.qmldom.*=false"
export XDG_RUNTIME_DIR=/tmp/qs-runtime

# --- PATH: make Scripts/dev tools directly invocable ---
[ -d "$REPO_MOUNT/Scripts/dev" ] && export PATH="$REPO_MOUNT/Scripts/dev:$PATH"

# --- Overlay (idempotent) ---
if ! mountpoint -q "$SHELL_DIR" 2>/dev/null; then
    sudo mkdir -p /tmp/overlay/upper /tmp/overlay/work "$SHELL_DIR"
    sudo chown -R "$(id -u):$(id -g)" /tmp/overlay "$SHELL_DIR"
    OVERLAY_OPTS="lowerdir=$REPO_MOUNT,upperdir=/tmp/overlay/upper,workdir=/tmp/overlay/work"
    [ "$USERXATTR" = "1" ] && OVERLAY_OPTS="$OVERLAY_OPTS,userxattr"
    if ! sudo mount -t overlay overlay -o "$OVERLAY_OPTS" "$SHELL_DIR"; then
        echo "atmo-dev: overlay mount failed (kernel error above)." >&2
        echo "atmo-dev: container needs --cap-add SYS_ADMIN --tmpfs /tmp/overlay:size=256m,mode=1777" >&2
        echo "atmo-dev: rootless engines also need tmpfs user xattr support (Linux >= 6.6) and ATMOSPHERA_DEV_USERXATTR=1." >&2
        exit 1
    fi
fi

# --- VFS (idempotent, fail loud) ---
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
if ! find "$XDG_RUNTIME_DIR/quickshell/vfs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -q .; then
    qs -p "$SHELL_DIR" >/dev/null 2>&1 || true
fi
VFS_PARENT=$(find "$XDG_RUNTIME_DIR/quickshell/vfs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
if [ -z "$VFS_PARENT" ]; then
    echo "atmo-dev: VFS generation failed." >&2
    echo "atmo-dev: check that quickshell is installed and $REPO_MOUNT contains shell.qml." >&2
    exit 1
fi
export QS_VFS="$VFS_PARENT"

# --- Exec ---
if [ $# -eq 0 ]; then
    echo "atmo-dev: no command. Try 'atmo-dev bash'." >&2
    exit 1
fi
exec "$@"
