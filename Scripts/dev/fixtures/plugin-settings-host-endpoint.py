#!/usr/bin/env python3
"""Inert argv endpoints for the real plugin consumer witnesses.

Installed under disposable executable names in the verified guest. Every call
is recorded; unknown requests fail rather than reaching an external service.
"""
import json
import os
from pathlib import Path
import sys
import time
from datetime import date, timedelta
from urllib.parse import parse_qs, urlparse


def held_response():
    hold_root = os.environ.get('PHA_HOLD_ROOT')
    if not hold_root or not (Path(hold_root) / 'hold').exists():
        return
    (Path(hold_root) / 'entered').write_text('entered\n')
    deadline = time.monotonic() + 30
    while not (Path(hold_root) / 'release').exists():
        if time.monotonic() > deadline:
            raise RuntimeError('fixture response barrier timed out')
        time.sleep(0.02)


def main():
    name = Path(sys.argv[0]).name
    args = sys.argv[1:]
    with Path(os.environ['PHA_CALLS']).open('a') as stream:
        stream.write(json.dumps(dict(endpoint=name, argv=args)) + '\n')
    if name == 'curl':
        urls = [a for a in args if a.startswith('https://')]
        if len(urls) != 1:
            return 90
        url = urlparse(urls[0])
        if url.netloc == 'air-quality-api.open-meteo.com':
            latitude = parse_qs(url.query).get('latitude', [''])[0]
            if latitude not in ('1', '3'):
                return 91
            if latitude == '3':
                held_response()
            print(json.dumps(dict(current=dict(us_aqi=17 if latitude == '1' else 151,
                                              european_aqi=9 if latitude == '1' else 81,
                                              pm2_5=4))))
            return 0
        if url.netloc == 'github.com' and url.path.startswith('/users/'):
            account = url.path.split('/')[2]
            if account not in ('synthetic-alpha', 'synthetic-beta'):
                return 92
            count = 7 if account == 'synthetic-alpha' else 29
            if account == 'synthetic-beta':
                held_response()
            print(f'{count} contributions in the last year')
            for index in range(365):
                day = (date(2026, 11, 18) - timedelta(days=364-index)).isoformat()
                print(f'<td data-date="{day}" id="day-{index}" data-level="2"></td>')
                print(f'<tool-tip for="day-{index}">{count} contributions</tool-tip>')
            return 0
        if url.netloc == 'api.github.com' and url.path == '/graphql':
            payload = json.loads(args[args.index('-d') + 1])
            if payload['variables']['login'] != 'synthetic-beta' or 'Authorization: Bearer synthetic' not in args:
                return 97
            held_response()
            days = [dict(date=(date(2026, 11, 18)-timedelta(days=364-i)).isoformat(),
                         contributionCount=1, contributionLevel='SECOND_QUARTILE') for i in range(365)]
            print(json.dumps(dict(data=dict(user=dict(contributionsCollection=dict(contributionCalendar=dict(
                totalContributions=31, weeks=[dict(contributionDays=days)])))))))
            return 0
        return 93
    if name in ('gh', 'glab'):
        if args == ['--version'] or args == ['auth', 'status']:
            print('inert synthetic client')
            return 0
        if args == ['api', 'user']:
            print(json.dumps(dict(login='synthetic-user', username='synthetic-user')))
            return 0
        if args[:2] == ['search', 'issues'] or args[:2] == ['search', 'prs']:
            repo = args[args.index('--repo') + 1] if '--repo' in args else 'synthetic/alpha'
            print(json.dumps([dict(number=1, title='result for ' + repo, url='',
                                   repository=dict(nameWithOwner=repo))]))
            return 0
        return 94
    if name == 'plugin-settings-endpoint':
        if args == ['system-old'] or args == ['system-new']:
            print(('synthetic-old' if args[0] == 'system-old' else 'synthetic-new') + ' 1 -> 2')
            return 0
        if args == ['aur-empty']:
            return 0
    return 95


if __name__ == '__main__':
    raise SystemExit(main())
