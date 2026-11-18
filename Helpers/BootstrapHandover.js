.pragma library

// A seed hydrates a late subscriber once. After hydration, only stream events
// own that domain. A connection's state object is also its callback lifetime.
function create() {
  return {};
}

function domain(state, name) {
  if (!state[name])
    state[name] = {revision: 0, serial: 0, owned: false, pending: false};
  return state[name];
}

function observe(state, name, fullSnapshot) {
  var current = domain(state, name);
  current.revision++;
  if (fullSnapshot)
    current.owned = true;
}

function begin(state, name, refresh) {
  var current = domain(state, name);
  if (!refresh && (current.owned || current.pending))
    return null;
  current.pending = true;
  return {state: state, name: name, revision: current.revision,
    serial: ++current.serial, refresh: !!refresh};
}

function finish(state, token, succeeded) {
  if (state !== token.state)
    return "ignore";
  var current = domain(state, token.name);
  if (current.serial !== token.serial)
    return "ignore";
  current.pending = false;
  if (!token.refresh && current.owned)
    return "ignore";
  if (!succeeded)
    return "error";
  if (current.revision !== token.revision)
    return "retry";
  if (!token.refresh)
    current.owned = true;
  return "accept";
}
