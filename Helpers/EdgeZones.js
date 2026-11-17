// Logical screen coordinates in; screen-local, non-overlapping rectangles out.
// Contacts are split into spans so a partially touching side is not all "inner".
function subtractRect(rect, cut) {
  if (!cut)
    return [rect];
  var x1 = Math.max(rect.x, cut.x);
  var y1 = Math.max(rect.y, cut.y);
  var x2 = Math.min(rect.x + rect.width, cut.x + cut.width);
  var y2 = Math.min(rect.y + rect.height, cut.y + cut.height);
  if (x1 >= x2 || y1 >= y2)
    return [rect];
  return [
    {x: rect.x, y: rect.y, width: rect.width, height: y1 - rect.y},
    {x: rect.x, y: y2, width: rect.width, height: rect.y + rect.height - y2},
    {x: rect.x, y: y1, width: x1 - rect.x, height: y2 - y1},
    {x: x2, y: y1, width: rect.x + rect.width - x2, height: y2 - y1}
  ].filter(function (part) { return part.width > 0 && part.height > 0; });
}

function zones(screen, screens, frame, barPosition, barThickness, dockReveal) {
  if (!screen || screen.width <= 0 || screen.height <= 0 || frame <= 0)
    return [];
  var sides = {left: frame, right: frame, top: frame, bottom: frame};
  if (Object.prototype.hasOwnProperty.call(sides, barPosition))
    sides[barPosition] = Math.max(frame, barThickness);
  var result = [];
  ["left", "right", "top", "bottom"].forEach(function (edge) {
    var vertical = edge === "left" || edge === "right";
    var start = vertical ? sides.top : sides.left;
    var end = vertical ? screen.height - sides.bottom : screen.width - sides.right;
    if (end <= start)
      return;
    var origin = vertical ? screen.y : screen.x;
    var contacts = [];
    (screens || []).forEach(function (other) {
      if (other.name === screen.name || other.width <= 0 || other.height <= 0)
        return;
      var touches = edge === "left" ? other.x + other.width === screen.x
                  : edge === "right" ? other.x === screen.x + screen.width
                  : edge === "top" ? other.y + other.height === screen.y
                  : other.y === screen.y + screen.height;
      if (!touches)
        return;
      var a = Math.max(start, (vertical ? other.y : other.x) - origin);
      var b = Math.min(end, (vertical ? other.y + other.height : other.x + other.width) - origin);
      if (b > a)
        contacts.push([a, b]);
    });
    var stops = [start, end];
    contacts.forEach(function (span) { stops.push(span[0], span[1]); });
    stops = stops.sort(function (a, b) { return a - b; }).filter(function (value, index, all) {
      return index === 0 || value !== all[index - 1];
    });
    for (var i = 0; i < stops.length - 1; ++i) {
      var from = stops[i], to = stops[i + 1];
      var inner = contacts.some(function (span) { return span[0] <= from && span[1] >= to; });
      var thickness = inner ? frame : 1;
      var rect = vertical
          ? {x: edge === "left" ? 0 : screen.width - thickness, y: from, width: thickness, height: to - from}
          : {x: from, y: edge === "top" ? 0 : screen.height - thickness, width: to - from, height: thickness};
      subtractRect(rect, dockReveal).forEach(function (part) {
        result.push({edge: edge, inner: inner, screenName: screen.name, rect: part,
                     key: [screen.name, edge, inner, part.x, part.y, part.width, part.height].join(":")});
      });
    }
  });
  return result;
}
