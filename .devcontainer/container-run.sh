#!/usr/bin/env bash
# container-run — shared container launcher for Atmosphera dev tooling.
#
# Selects the container engine, builds the dev image when its inputs
# changed, and runs the given command inside the repo workspace.
#
# Usage:
#   container-run.sh COMMAND [ARG...]
#
# Environment:
#   ATMOSPHERA_CONTAINER_ENGINE=podman|docker   # optional explicit override
#
# Engine selection: an explicit override wins; otherwise installed Podman
# is preferred over installed Docker. Once selected, an engine failure is
# a failure — there is no silent retry with the other engine. A `docker`
# executable backed by podman-docker is recognized as Podman for option
# handling. Selection diagnostics (requested executable, actual backend)
# are printed to stderr.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVCONTAINER_DIR="$REPO_ROOT/.devcontainer"

log() { echo "container-run: $*" >&2; }
fail() { log "$@"; exit 1; }

# --- Engine selection -------------------------------------------------------

OVERRIDE="${ATMOSPHERA_CONTAINER_ENGINE:-}"
if [ -n "$OVERRIDE" ]; then
    case "$OVERRIDE" in
        podman|docker) ;;
        *) fail "ATMOSPHERA_CONTAINER_ENGINE must be 'podman' or 'docker' (got '$OVERRIDE')." ;;
    esac
    ENGINE_EXE="$(command -v "$OVERRIDE" || true)"
    [ -n "$ENGINE_EXE" ] || fail "ATMOSPHERA_CONTAINER_ENGINE=$OVERRIDE but '$OVERRIDE' was not found in PATH. Install it or fix the override."
else
    if ENGINE_EXE="$(command -v podman 2>/dev/null)"; then
        :
    elif ENGINE_EXE="$(command -v docker 2>/dev/null)"; then
        :
    else
        fail "no container engine found. Install podman (preferred) or docker, or set ATMOSPHERA_CONTAINER_ENGINE=podman|docker."
    fi
fi

# --- Classification: requested executable vs actual backend -----------------

VERSION_OUT="$("$ENGINE_EXE" --version 2>&1)" \
    || fail "'$ENGINE_EXE --version' failed; the selected engine is not usable."
case "$VERSION_OUT" in
    "podman version "*) ENGINE_KIND=podman ;;
    "Docker version "*) ENGINE_KIND=docker ;;
    *) fail "unsupported engine implementation: '$ENGINE_EXE --version' reported '$VERSION_OUT' (expected Podman or Docker)." ;;
esac

log "engine: requested=$ENGINE_EXE backend=$ENGINE_KIND"

# --- Usability (no fallback on failure) --------------------------------------

if ! "$ENGINE_EXE" info >/dev/null 2>&1; then
    fail "selected engine '$ENGINE_EXE' is not usable ('info' failed). Fix the engine setup or select another engine via ATMOSPHERA_CONTAINER_ENGINE."
fi

# --- Image identity ----------------------------------------------------------

# Podman runs the image's fixed dev account (1000:1000) and maps the caller
# onto it with keep-id. Docker-daemon runs build dev with the caller's IDs so
# bind-mount writes are owned by the invoking user on the host.
if [ "$ENGINE_KIND" = podman ]; then
    ROOTLESS="$("$ENGINE_EXE" info --format '{{.Host.Security.Rootless}}')" \
        || fail "could not read rootless state from '$ENGINE_EXE info'."
    [ "$ROOTLESS" = "true" ] \
        || fail "rootless Podman required, but '$ENGINE_EXE' reports rootless=$ROOTLESS. Reconcile the setup (rootful Podman is not supported by this tooling)."
    IMG_UID=1000
    IMG_GID=1000
else
    SECOPTS="$("$ENGINE_EXE" info --format '{{.SecurityOptions}}')" \
        || fail "could not read security options from '$ENGINE_EXE info'."
    case "$SECOPTS" in
        *rootless*) fail "rootless Docker detected ($SECOPTS). This tooling supports the conventional Docker daemon and rootless Podman only; see DEVELOPMENT.md." ;;
    esac
    IMG_UID="$(id -u)"
    IMG_GID="$(id -g)"
fi

FINGERPRINT="$({ sha256sum < "$DEVCONTAINER_DIR/Dockerfile"
                  sha256sum < "$DEVCONTAINER_DIR/atmo-dev.sh"
                  echo "dev uid=$IMG_UID gid=$IMG_GID"; } | sha256sum | cut -c1-16)"
IMAGE="localhost/atmosphera-dev:$FINGERPRINT"

# --- Build (cache-aware) ------------------------------------------------------

if ! "$ENGINE_EXE" image inspect "$IMAGE" >/dev/null 2>&1; then
    log "building $IMAGE (first run or image inputs changed)..."
    "$ENGINE_EXE" build \
        --file "$DEVCONTAINER_DIR/Dockerfile" \
        --tag "$IMAGE" \
        --build-arg "DEV_UID=$IMG_UID" \
        --build-arg "DEV_GID=$IMG_GID" \
        "$DEVCONTAINER_DIR" >&2 \
        || fail "image build failed with $ENGINE_KIND."
fi

# --- Run ---------------------------------------------------------------------

RUN_ARGS=(
    --rm
    --cap-add SYS_ADMIN
    --tmpfs /tmp/overlay:size=256m,mode=1777
    --memory=12g
    --memory-swap=12g
    --pids-limit=2048
    --cpus=12
    -v "$REPO_ROOT:/workspaces/atmosphera"
    -w /workspaces/atmosphera
)

if [ "$ENGINE_KIND" = podman ]; then
    # Rootless: map the caller to the image's dev account (1000:1000) and
    # tell atmo-dev the overlay needs the namespace-friendly userxattr mode.
    RUN_ARGS+=(
        --userns=keep-id:uid=1000,gid=1000
        --user dev
        --env ATMOSPHERA_DEV_USERXATTR=1
    )
else
    # Docker daemon: dev was built with the caller's UID/GID, so workspace
    # writes are owned by the invoking user. Named account, never numeric.
    RUN_ARGS+=(
        --user dev
        --env ATMOSPHERA_DEV_USERXATTR=0
    )
fi

[ $# -gt 0 ] || fail "no command given. Usage: container-run.sh COMMAND [ARG...]"

log "running with $ENGINE_KIND image $IMAGE"
exec "$ENGINE_EXE" run "${RUN_ARGS[@]}" "$IMAGE" "$@"
