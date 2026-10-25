.pragma library

// Lower keys are better. This is the only application membership/ranking path.
function normalize(value) {
  // QV4 does not implement Unicode property escapes in RegExp. Normalize
  // directly rather than silently depending on an unsupported Latin matcher.
  return String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim().replace(/\s+/g, " ");
}

function quality(query, value) {
  const text = normalize(value);
  if (!text)
    return -1;
  if (text === query)
    return 0;
  if (text.startsWith(query))
    return 1;
  let index = text.indexOf(query);
  if (index >= 0) {
    while (index >= 0) {
      // Whitespace, ASCII punctuation (except underscore), and common Unicode
      // punctuation separate words. Non-ASCII letters remain inside a word.
      if (/[^\w\u0080-\uffff]|[\s\u2000-\u206f\u3000-\u303f]/.test(text[index - 1]))
        return 2;
      index = text.indexOf(query, index + 1);
    }
    return 3;
  }
  let cursor = 0;
  const letters = Array.from(query);
  for (const letter of text) {
    if (letter === letters[cursor])
      cursor++;
    if (cursor === letters.length)
      return 4;
  }
  return -1;
}

function bestQuality(query, values) {
  let best = -1;
  for (const value of values) {
    const match = quality(query, value);
    if (match >= 0 && (best < 0 || match < best))
      best = match;
  }
  return best;
}

function match(query, app) {
  const keywords = typeof app.keywords === "string" ? app.keywords.split(";") : Array.from(app.keywords || []);
  const fields = [[app.name], [app.executableName], keywords, [app.comment], [app.genericName]];
  const words = normalize(query).split(" ");
  let field = 0;
  let weakest = 0;
  // Every word must match. Its best field wins first, then quality. For a
  // multi-field query the weakest word determines rank; token order is free.
  for (const word of words) {
    let found = false;
    for (let i = 0; i < fields.length; i++) {
      const q = bestQuality(word, fields[i]);
      if (q >= 0) {
        field = Math.max(field, i);
        weakest = Math.max(weakest, q);
        found = true;
        break;
      }
    }
    if (!found)
      return null;
  }
  // A phrase contained in one eligible field retains whole/prefix quality.
  // Split/reordered words are at best word-start matches, never whole fields.
  let phrase = -1;
  for (let i = 0; i <= field; i++) {
    const q = bestQuality(normalize(query), fields[i]);
    if (q >= 0 && (phrase < 0 || q < phrase))
      phrase = q;
  }
  return {field: field, quality: phrase >= 0 ? phrase : Math.max(2, weakest)};
}

function compareText(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

function rank(entries, query, options) {
  const searching = normalize(query) !== "";
  const matches = [];
  for (const app of entries) {
    if (options.accept && !options.accept(app))
      continue;
    const key = searching ? match(query, app) : {field: 0, quality: 0};
    if (!key)
      continue;
    matches.push({app: app, field: key.field, quality: key.quality,
      pinned: options.pinned(app), usage: options.usage(app),
      name: normalize(app.name), id: String(options.id(app))});
  }
  matches.sort((a, b) => a.field - b.field || a.quality - b.quality || Number(b.pinned) - Number(a.pinned) || b.usage - a.usage || compareText(a.name, b.name) || compareText(String(a.app.name), String(b.app.name)) || compareText(a.id, b.id));
  return matches.map(row => ({app: row.app,
    // Only for inter-provider merging. Pin/usage/name remain provider-owned.
    score: searching ? (25 - row.field * 5 - row.quality) / 25 : 0}));
}
