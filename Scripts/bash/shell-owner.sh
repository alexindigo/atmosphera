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
  local pid
  pid=$(shell_owner_pid) || return 1
  timeout 5 qs kill --pid "$pid"
  # Wait for the registered process to release the election, not an arbitrary
  # delay. Do not kill a new owner that takes over during this handoff.
  local current deadline=$((SECONDS + 5))
  while ((SECONDS < deadline)); do
    current=$(shell_owner_pid) || current=""
    # Name release precedes Quickshell's instance-lock teardown. Starting
    # with -n in that window would silently keep the departing instance.
    if [ "$current" != "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  echo 'atmosphera: registered shell did not stop' >&2
  return 1
}
