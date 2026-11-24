.pragma library

// Scope retained replies to their QML owner. Connect before checking completed
// so one path handles both normal completion and a late observer.
function observe(pending, reply, consume) {
  if (!reply)
    return false;
  function finish() {
    if (!pending.delete(reply))
      return;
    reply.finished.disconnect(finish);
    consume(reply);
  }
  pending.set(reply, finish);
  reply.finished.connect(finish);
  if (reply.completed)
    finish();
  return true;
}

function cancel(pending) {
  const entries = Array.from(pending.entries());
  pending.clear();
  for (const [reply, finish] of entries) {
    reply.finished.disconnect(finish);
    reply.cancel();
  }
}
