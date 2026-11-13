# Shared dialog transport. The bounded reader owns the potentially blocking
# FIFO open; delivery is checked before waiting for the user's response.
dialog_cleanup() {
  if [ -n "${dialog_reader:-}" ]; then
    kill "$dialog_reader" 2>/dev/null || true
    wait "$dialog_reader" 2>/dev/null || true
  fi
  timeout 5 "$QS" ipc --pid "$PID" call dialog cancel &>/dev/null || true
  rm -rf "$dialog_dir"
}

dialog_request() {
  local method="$1" question="$2" payload="${3:-}"
  dialog_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-/dev/shm}/atmosphera-dialog-XXXXXX")
  local fifo="$dialog_dir/reply"
  trap dialog_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  mkfifo "$fifo"
  timeout "${ATMOSPHERA_DIALOG_TIMEOUT:-30}" cat "$fifo" > "$dialog_dir/result" &
  dialog_reader=$!
  case "$method" in
    prompt) set -- "$method" "$question" "$fifo" "$payload" ;;
    survey) set -- "$method" "$question" "$payload" "$fifo" ;;
    *) set -- "$method" "$question" "$fifo" ;;
  esac
  timeout 5 "$QS" ipc --pid "$PID" call dialog "$@" &>/dev/null
}

dialog_read() {
  local status=0
  wait "$dialog_reader" || status=$?
  dialog_reader=""
  result=$(cat "$dialog_dir/result")
  return "$status"
}
