.pragma library

// Merge the ordered app stream with other providers, never sorting apps again.
// Keep existing non-app score semantics (unscored=0, opt-in usage boost).
function merge(apps, others, usageCount) {
  function score(item) {
    let value = item._score !== undefined ? item._score : 0;
    if (usageCount && item.provider && item.provider.trackUsage && item.usageKey)
      value += 0.1 * Math.log2(1 + usageCount(item.usageKey));
    return value;
  }
  const ordered = others.map((item, index) => ({item: item, score: score(item), index: index}));
  ordered.sort((a, b) => b.score - a.score || a.index - b.index);
  const result = [];
  let app = 0;
  for (const row of ordered) {
    while (app < apps.length && apps[app]._score >= row.score)
      result.push(apps[app++]);
    result.push(row.item);
  }
  return result.concat(apps.slice(app));
}
