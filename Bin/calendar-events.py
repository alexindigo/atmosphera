#!/usr/bin/env python3
import gi

gi.require_version('EDataServer', '1.2')
import json
import re
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

from gi.repository import EDataServer

start_time = int(sys.argv[1])
end_time = int(sys.argv[2])

all_events = []

def safe_get_time(ical_time_str):
    """Parse iCalendar time string"""
    try:
        if not ical_time_str:
            return None

        ical_time_str = ical_time_str.strip().replace('\r', '').replace('\n', '')

        # Check for TZID parameter (format: TZID=America/Los_Angeles:20240822T180000)
        if 'TZID=' in ical_time_str:
            # Split on the colon that comes after the TZID value
            match = re.match(r'TZID=([^:]+):(.+)', ical_time_str)
            if match:
                ical_time_str = match.group(2)
        elif ';' in ical_time_str and ':' in ical_time_str:
            ical_time_str = ical_time_str.split(':', 1)[1]

        ical_time_str = ical_time_str.strip()

        if len(ical_time_str) == 8 and ical_time_str.isdigit():
            dt = datetime.strptime(ical_time_str, '%Y%m%d')
            return int(dt.timestamp())

        # DateTime (YYYYMMDDTHHMMSS or YYYYMMDDTHHMMSSZ)
        is_utc = ical_time_str.endswith('Z')
        ical_time_str = ical_time_str.rstrip('Z')
        dt = datetime.strptime(ical_time_str, '%Y%m%dT%H%M%S')

        if not is_utc:
            return int(dt.timestamp())

        from datetime import timezone
        dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())
    except Exception:
        return None

def parse_ical_component(ical_string, calendar_name):
    """Parse an iCalendar component"""
    try:
        lines = ical_string.split('\n')
        event = {}
        current_key = None
        current_value = []

        for line in lines:
            line = line.replace('\r', '')

            if line.startswith(' ') and current_key:
                current_value.append(line[1:])
                continue

            if current_key:
                full_value = ''.join(current_value)
                event[current_key] = full_value
                current_value = []

            if ':' in line:
                key_part, value_part = line.split(':', 1)

                key = key_part.split(';')[0]

                current_key = key
                current_value = [line]

        if current_key:
            event[current_key] = ''.join(current_value)

        if 'DTSTART' not in event:
            return None

        dtstart_line = event.get('DTSTART', '')
        if ':' in dtstart_line:
            dtstart_value = dtstart_line.split('DTSTART', 1)[1]
        else:
            dtstart_value = dtstart_line

        start_timestamp = safe_get_time(dtstart_value)
        if not start_timestamp:
            return None

        if start_timestamp < start_time or start_timestamp > end_time:
            return None

        dtend_line = event.get('DTEND', '')
        if dtend_line and ':' in dtend_line:
            dtend_value = dtend_line.split('DTEND', 1)[1]
            end_timestamp = safe_get_time(dtend_value)
        else:
            end_timestamp = None

        if not end_timestamp or end_timestamp == start_timestamp:
            end_timestamp = start_timestamp + 3600

        summary_line = event.get('SUMMARY', '(No title)')
        if 'SUMMARY:' in summary_line:
            summary = summary_line.split('SUMMARY:', 1)[1].strip()
        else:
            summary = summary_line.strip() or '(No title)'

        location_line = event.get('LOCATION', '')
        if 'LOCATION:' in location_line:
            location = location_line.split('LOCATION:', 1)[1].strip()
        else:
            location = location_line.strip()

        desc_line = event.get('DESCRIPTION', '')
        if 'DESCRIPTION:' in desc_line:
            description = desc_line.split('DESCRIPTION:', 1)[1].strip()
        else:
            description = desc_line.strip()

        return {
            'summary': summary,
            'start': start_timestamp,
            'end': end_timestamp,
            'location': location,
            'description': description,
            'calendar': calendar_name
        }
    except Exception:
        return None

registry = EDataServer.SourceRegistry.new_sync(None)
sources = registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR)

cache_base = Path.home() / ".cache/evolution/calendar"

for source in sources:
    if not source.get_enabled():
        continue

    calendar_name = source.get_display_name()
    source_uid = source.get_uid()

    cache_file = cache_base / source_uid / "cache.db"

    if not cache_file.exists():
        cache_file = Path.home() / ".local/share/evolution/calendar" / source_uid / "calendar.ics"
        if cache_file.exists():
            try:
                with open(cache_file, 'r') as f:
                    content = f.read()
                    events = content.split('BEGIN:VEVENT')
                    for event_str in events[1:]:
                        event_str = 'BEGIN:VEVENT' + event_str.split('END:VEVENT')[0] + 'END:VEVENT'
                        event = parse_ical_component(event_str, calendar_name)
                        if event:
                            all_events.append(event)
            except Exception:
                pass
        continue

    try:
        conn = sqlite3.connect(str(cache_file))
        cursor = conn.cursor()

        cursor.execute("SELECT ECacheOBJ FROM ECacheObjects")
        rows = cursor.fetchall()

        for row in rows:
            ical_string = row[0]
            if ical_string and 'BEGIN:VEVENT' in str(ical_string):
                event = parse_ical_component(str(ical_string), calendar_name)
                if event:
                    all_events.append(event)

        conn.close()
    except Exception as e:
        print(f"Error processing {calendar_name}: {e}", file=sys.stderr)

all_events.sort(key=lambda x: x['start'])
print(json.dumps(all_events))
