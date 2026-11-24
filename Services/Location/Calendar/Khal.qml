pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Location

Singleton {
  id: root

  readonly property string khalEventsScript: Quickshell.shellDir + '/Scripts/python/src/calendar/khal-events.py'

  function init() {
    availabilityCheckProcess.running = true;
  }
  function loadCalendars() {
    listCalendarsProcess.running = true;
  }
  function loadEvents(daysAhead, daysBehind, complete) {
    const now = new Date();
    const startDate = new Date(now.getTime() - (daysBehind * 24 * 60 * 60 * 1000));
    loadEventsProcess.start(["python3", root.khalEventsScript, formatDateYMD(startDate), `${daysAhead + daysBehind + 1}d`], complete);
  }

  // Process to check for khal installation
  Process {
    id: availabilityCheckProcess
    running: false
    command: ["sh", "-c", "command -v khal >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1"]
    onExited: function (exitCode) {
      if (exitCode === 0) {
        CalendarService.dataProvider = CalendarService.dataProvider || root;
        CalendarService.available = true;
      }

      if (CalendarService.available) {
        Logger.i("Calendar", "Khal available");
        loadCalendars();
      } else {
        Logger.w("Calendar", "Khal not available");
        CalendarService.lastError = "khal binary not installed";
      }
    }
  }

  // Process to list available calendars
  Process {
    id: listCalendarsProcess
    running: false
    command: ["khal", "printcalendars"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const calendars = text.trim().split("\n");
          CalendarService.setCalendars(calendars);

          Logger.d("Calendar", `Found ${calendars.length} calendar(s)`);

          // Auto-load events after discovering calendars
          if (calendars.length > 0) {
            CalendarService.loadEvents();
          }
        } catch (e) {
          Logger.d("Calendar", "Failed to parse calendars: " + e);
          CalendarService.lastError = "Failed to parse calendar list";
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.d("Calendar", "List calendars error: " + text);
          CalendarService.lastError = text.trim();
        }
      }
    }
  }

  // Process to load events
  EventQuery {
    id: loadEventsProcess
    parseEvents: text => root.parseEvents(text)
  }

  function parseEvents(text) {
    const result = [];
    const duplicates = new Set();

    for (const line of text.split("\n")) {
      if (!line.trim())
        continue;
      const dayEvents = JSON.parse(line);
      for (const event of dayEvents) {
        if (event["repeat-pattern"] !== "") {
          // if there is a repeat pattern, the event must be included each time
          result.push({
                        uid: event.uid,
                        calendar: event.calendar,
                        summary: event.title,
                        start: parseTimestamp(event["start-long-full"]),
                        end: parseTimestamp(event["end-long-full"]),
                        location: event.location,
                        description: event.description
                      });
        } else if (!duplicates.has(event.uid)) {
          // in any other cases, we must remove duplicates using the uid of the event
          result.push({
                        uid: event.uid,
                        calendar: event.calendar,
                        summary: event.title,
                        start: parseTimestamp(event["start-long-full"]),
                        end: parseTimestamp(event["end-long-full"]),
                        location: event.location,
                        description: event.description
                      });
          duplicates.add(event.uid);
        }
      }
    }

    return result;
  }

  function parseTimestamp(timeStr) {
    // expects ISO8601 format
    return Math.floor((Date.parse(timeStr)).valueOf() / 1000);
  }

  function formatDateYMD(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, "0");
    const d = String(date.getDate()).padStart(2, "0");
    return y + "-" + m + "-" + d;
  }
}
