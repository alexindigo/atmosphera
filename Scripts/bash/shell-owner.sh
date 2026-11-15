# Shared shell discovery. Pin the unique bus owner before resolving its PID;
# never guess a process from argv (Quickshell execs itself after a crash).
shell_owner_pid() {
  local reply owner pid
  reply=$(timeout 2 busctl --user --timeout=1 call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s app.atmosphera.Shell 2>/dev/null) || return 1
  if [[ "$reply" =~ ^s[[:space:]]\"(:[0-9]+\.[0-9]+)\"$ ]]; then
    owner=${BASH_REMATCH[1]}
  else
    return 1
  fi
  reply=$(timeout 2 busctl --user --timeout=1 call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s "$owner" 2>/dev/null) || return 1
  if [[ "$reply" =~ ^u[[:space:]]([1-9][0-9]*)$ ]]; then
    pid=${BASH_REMATCH[1]}
  else
    return 1
  fi
  if [ "${1:-}" = ready ]; then
    reply=$(timeout 2 busctl --user --timeout=1 get-property "$owner" /app/atmosphera/Shell app.atmosphera.Shell1 IpcReady 2>/dev/null) || return 1
    [ "$reply" = 'b true' ] || return 1
  fi
  printf '%s\n' "$pid"
}

shell_owner_require() {
  shell_owner_pid ready || {
    echo 'atmosphera: no ready registered shell; start or restart Atmosphera first' >&2
    return 1
  }
}

shell_owner_stop() {
  python3 -B "$(dirname "${BASH_SOURCE[0]}")/shell-owner.py" stop
}

shell_owner_prepare() {
  python3 -B "$(dirname "${BASH_SOURCE[0]}")/shell-owner.py" prepare
}
