pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Location.Calendar
import qs.Services.System

Singleton {
  id: root

  // Core state
  property var events: ([])
  property bool loading: false
  property bool available: false
  property string lastError: ""
  property var calendars: ([])

  property var dataProvider: null
  property var _ranges: new Map()
  property int _revision: 0
  property var _activeQuery: null
  property int _pendingAhead: -1
  property int _pendingBehind: -1
  property bool _hasFreshEvents: false

  onAvailableChanged: {
    if (!available)
      ++_revision;
    else
      Qt.callLater(root._startEventQuery);
  }
  onDataProviderChanged: {
    ++_revision;
    if (available && dataProvider)
      loadEvents();
  }

  // Persistent cache
  property string cacheFile: Settings.cacheDir + "calendar.json"

  // Cache file handling
  FileView {
    id: cacheFileView
    path: root.cacheFile
    printErrors: false

    JsonAdapter {
      id: cacheAdapter
      property var cachedEvents: ([])
      property var cachedCalendars: ([])
      property string lastUpdate: ""
    }

    onLoadFailed: {
      cacheAdapter.cachedEvents = ([]);
      cacheAdapter.cachedCalendars = ([]);
      cacheAdapter.lastUpdate = "";
    }

    onLoaded: {
      loadFromCache();
    }
  }

  Component.onCompleted: {
    Logger.i("Calendar", "Service started");
    loadFromCache();
    checkAvailability();
  }

  // Save cache with debounce
  Timer {
    id: saveDebounce
    interval: 1000
    onTriggered: cacheFileView.writeAdapter()
  }

  function setEvents(newEvents) {
    _hasFreshEvents = true;
    root.events = newEvents;
    cacheAdapter.cachedEvents = newEvents;
    cacheAdapter.lastUpdate = new Date().toISOString();
    saveCache();
  }

  function setCalendars(newCalendars) {
    root.calendars = newCalendars;
    cacheAdapter.cachedCalendars = newCalendars;
    saveCache();
  }

  function saveCache() {
    saveDebounce.restart();
  }

  // Load events and calendars from cache
  function loadFromCache() {
    if (!_hasFreshEvents && cacheAdapter.cachedEvents && cacheAdapter.cachedEvents.length > 0) {
      root.events = cacheAdapter.cachedEvents;
      Logger.d("Calendar", `Loaded ${cacheAdapter.cachedEvents.length} cached event(s)`);
    }

    if (cacheAdapter.cachedCalendars && cacheAdapter.cachedCalendars.length > 0) {
      root.calendars = cacheAdapter.cachedCalendars;
      Logger.d("Calendar", `Loaded ${cacheAdapter.cachedCalendars.length} cached calendar(s)`);
    }

    if (cacheAdapter.lastUpdate) {
      Logger.d("Calendar", `Cache last updated: ${cacheAdapter.lastUpdate}`);
    }
  }

  // Auto-refresh timer (every 5 minutes)
  Timer {
    id: refreshTimer
    interval: 300000
    running: true
    repeat: true
    onTriggered: loadEvents()
  }

  // Core functions
  function checkAvailability() {
    if (!Settings.data.location.showCalendarEvents) {
      root.available = false;
      return;
    }

    Khal.init();
    EvolutionDataServer.init();
  }

  function loadCalendars() {
    if (!root.available || !dataProvider) {
      return;
    }

    dataProvider.loadCalendars();
  }
  // Every refresh covers the normal window and each live projection's range.
  // A successful snapshot replaces the previous one, including real deletions.
  function setEventRange(owner, first, last) {
    const start = Number(first), end = Number(last);
    if (!owner || !Number.isFinite(start) || !Number.isFinite(end) || start >= end)
      return;
    const previous = _ranges.get(owner);
    if (previous?.start === start && previous?.end === end)
      return;
    _ranges.set(owner, {
                  start: start,
                  end: end
                });
    ++_revision;
    loadEvents();
  }

  function clearEventRange(owner) {
    if (!_ranges.delete(owner))
      return;
    ++_revision;
    // Invalidate work already in flight, without issuing a request just for a
    // closed view. An in-flight query must be replaced for surviving views.
    if (_activeQuery && _ranges.size)
      loadEvents();
  }

  function loadEvents(daysAhead = 31, daysBehind = 14) {
    _pendingAhead = Math.max(_pendingAhead, daysAhead);
    _pendingBehind = Math.max(_pendingBehind, daysBehind);
    Qt.callLater(root._startEventQuery);
  }

  function _startEventQuery() {
    if (!available || !dataProvider || _activeQuery || _pendingAhead < 0)
      return;
    const now = Date.now(), day = 86400000;
    let ahead = Math.max(31, _pendingAhead), behind = Math.max(14, _pendingBehind);
    for (const range of _ranges.values()) {
      ahead = Math.max(ahead, Math.ceil((range.end - now) / day));
      behind = Math.max(behind, Math.ceil((now - range.start) / day));
    }
    _pendingAhead = _pendingBehind = -1;
    const query = {
      revision: _revision
    };
    _activeQuery = query;
    loading = true;
    lastError = "";
    dataProvider.loadEvents(ahead, behind, (result, error) => root._finishEventQuery(query, result, error));
  }

  function _finishEventQuery(query, result, error) {
    if (_activeQuery !== query)
      return;
    _activeQuery = null;
    loading = false;
    if (available && query.revision === _revision) {
      if (error) {
        lastError = error;
        Logger.w("Calendar", error);
      } else {
        setEvents(result);
      }
    }
    Qt.callLater(root._startEventQuery);
  }
}
