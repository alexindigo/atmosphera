#!/usr/bin/env python3
"""Collect source evidence for the finite generic-settings consumer review.

This is a source index, not a runtime proof or an automatic ownership verdict.
Include aliases, dynamic selectors and Main calls as review evidence rather than
silently declaring unmatched fields unused. Reviewed dispositions live alongside
the generated human-readable inventory, not in production preference metadata.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import tempfile


SOURCE_SUFFIXES = {'.qml', '.js', '.sh', '.py'}
SETTING = re.compile(r'pluginSettings|settingsView|defaultSettings|settingsConsumerFor|settingsContext')
MAIN = re.compile(r'mainInstance|mainComponent|\bmain\.|\bMain\.')


def literal_reads(text, fields):
    """Index literal namespace/alias edges, leaving dynamic evidence visible.

    This deliberately does not claim a JavaScript data-flow proof. For example,
    a field passed through a helper argument remains a hand-reviewed edge.
    """
    aliases = {'pluginSettings', 'settingsView'}
    if re.search(r'required\s+property\s+var\s+configuration\b', text):
        aliases.add('configuration')
    if re.search(r'property\s+var\s+cfg\b|function\s+\w+\s*\(\s*cfg\b', text):
        # An injected cfg parameter is an evidence edge, not an assertion that
        # its caller selected the correct context. The ownership review does that.
        aliases.add('cfg')
    lines = text.splitlines()
    for _ in range(4):
        previous = set(aliases)
        alias_reference = re.compile(r'\b(?:' + '|'.join(map(re.escape, sorted(aliases))) + r')\b')
        for line in lines:
            line = line.split('//', 1)[0].replace('?.', '.')
            match = re.search(r'(?:property\s+(?:var|QtObject)|const|let|var)\s+(\w+)\s*[:=](.*)', line)
            if match and alias_reference.search(match[2]):
                aliases.add(match[1])
        if aliases == previous:
            break
    result = {}
    helpers = []
    for match in re.finditer(r'function\s+(\w+)\s*\(\s*(\w+)[^)]*\)\s*\{([^{}]*)\}', text):
        if any(re.search(r'\b' + re.escape(alias) + r'\s*\[\s*' + re.escape(match[2]) + r'\s*\]', match[3])
               for alias in aliases):
            helpers.append(match[1])
    access = re.compile(r'\b(?:' + '|'.join(map(re.escape, sorted(aliases)))
                        + r')\s*(?:\.\s*(\w+)|\[\s*[\"\x27](\w+)[\"\x27]\s*\])')
    for number, line in enumerate(lines, 1):
        line = line.split('//', 1)[0].replace('?.', '.')
        keys = {match[1] or match[2] for match in access.finditer(line)}
        for helper in helpers:
            keys.update(re.findall(r'\b' + re.escape(helper) + r'\s*\(\s*[\"\x27](\w+)[\"\x27]', line))
        for key in sorted(keys & set(fields)):
            result.setdefault(key, []).append(number)
    return result


def scan(plugins):
    rows = []
    for manifest_path in sorted(plugins.glob('*/manifest.json')):
        manifest = json.loads(manifest_path.read_text())
        entries = manifest.get('entryPoints', {})
        if not entries.get('settings'):
            continue
        root = manifest_path.parent
        fields = manifest.get('metadata', {}).get('settingsSchema', {}).get('fields', {})
        files = []
        for path in sorted(root.rglob('*')):
            if path.suffix not in SOURCE_SUFFIXES or not path.is_file():
                continue
            relative = str(path.relative_to(plugins))
            text = path.read_text()
            evidence = []
            field_reads = {}
            for number, line in enumerate(text.splitlines(), 1):
                if SETTING.search(line) or MAIN.search(line):
                    evidence.append(dict(line=number, text=line.strip()))
                for key in fields:
                    # Include bare identifiers and quoted dynamic keys. False
                    # positives remain visible for human review; no auto-unused.
                    if re.search(r'(?<![\w])' + re.escape(key) + r'(?![\w])', line):
                        field_reads.setdefault(key, []).append(number)
            files.append(dict(path=relative, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                              evidence=evidence, fields=field_reads, literalEdges=literal_reads(text, fields)))
        rows.append(dict(plugin=root.name, id=manifest['id'], version=manifest['version'],
                         manifest=str(manifest_path.relative_to(plugins)),
                         manifestSha256=hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                         entries=entries, fields={key: value.get('editorUsage') for key, value in fields.items()},
                         files=files))
    return rows


def summary(rows):
    out = []
    for row in rows:
        out.append('\n### ' + row['plugin'] + ' | ' + json.dumps(row['entries'], sort_keys=True))
        out.append('FIELDS ' + ', '.join(key + ':' + str(value) for key, value in row['fields'].items()))
        for item in row['files']:
            # Full per-line evidence stays in JSON. The compact review groups
            # literal field occurrences and retains every Main/namespace alias.
            if not runtime_file(item['path']):
                continue
            out.append(item['path'] + ' | ' + '; '.join(key + '@' + ','.join(map(str, lines))
                       for key, lines in item['fields'].items()))
            setting_lines = [entry for entry in item['evidence'] if SETTING.search(entry['text'])]
            out.extend('  ' + str(entry['line']) + ': ' + entry['text'] for entry in setting_lines[:4])
            main_lines = [entry['line'] for entry in item['evidence'] if MAIN.search(entry['text'])]
            if main_lines:
                out.append('  Main edges @' + ','.join(map(str, main_lines)))
    return '\n'.join(out) + '\n'


def review_rows(path, rows):
    with path.open() as stream:
        records = list(csv.DictReader(stream, delimiter='\t'))
    names = [row['plugin'] for row in records]
    expected = {row['plugin'] for row in rows}
    if len(names) != len(set(names)) or set(names) != expected:
        raise ValueError('review coverage differs: missing=' + str(sorted(expected - set(names)))
                         + ', extra=' + str(sorted(set(names) - expected)) + ', duplicates='
                         + str(sorted(name for name in set(names) if names.count(name) != 1)))
    for record in records:
        if record['disposition'] not in {'port', 'ported', 'no-port', 'no-instance'}:
            raise ValueError('unreviewed disposition: ' + record['plugin'])
        if not record['ownership'].strip() or not record['pattern'].strip():
            raise ValueError('missing ownership/pattern: ' + record['plugin'])
    return {row['plugin']: row for row in records}


def runtime_file(path):
    parts = Path(path).parts[1:]
    return not any(part.lower() in {'tests', 'fixtures', 'settings'} for part in parts[:-1]) and parts[-1] not in {
        'Settings.qml', 'SettingsView.qml', 'DesktopWidgetSettings.qml'}


def manual_rows(path, rows, plugins):
    known = {row['plugin']: row for row in rows}
    with path.open() as stream:
        records = list(csv.DictReader(stream, delimiter='\t'))
    result = {}
    for record in records:
        row = known.get(record['plugin'])
        if row is None or not set(record['fields'].split(',')) <= set(row['fields']):
            raise ValueError('manual field evidence outside catalog: ' + str(record))
        source = plugins / record['path']
        if not source.resolve().is_relative_to((plugins / record['plugin']).resolve()):
            raise ValueError('manual evidence escapes plugin')
        if not 1 <= int(record['line']) <= len(source.read_text().splitlines()):
            raise ValueError('manual source line absent: ' + str(record))
        result.setdefault(record['plugin'], []).append(record)
    return result


def group_rows(path, reviewed):
    groups = json.loads(path.read_text())['groups']
    members = [name for group in groups for name in group['members']]
    if len(members) != 74 or len(set(members)) != len(members):
        raise ValueError('pass-2 groups must partition the original 74 required ports')
    if set(members) - set(reviewed) or {name for name, row in reviewed.items() if row['disposition'] == 'port'} - set(members):
        raise ValueError('required consumer absent from pass-2 groups')
    for group in groups:
        for key in ('id', 'pattern', 'approach', 'representatives', 'staticCheck', 'status'):
            if not group[key].strip():
                raise ValueError('missing group contract: ' + key)
        if any(reviewed[name]['disposition'] not in {'port', 'ported'} for name in group['members']):
            raise ValueError('pass-2 member reclassified without reviewing grouping')
    return groups


def inventory(rows, reviewed, manual, groups):
    lines = ['# Generic Settings runtime-consumer inventory', '',
             'Static classification of all manifest-declared generic entries. This is not runtime acceptance.',
             'Generated by `Scripts/dev/plugin-settings-consumer-inventory.py` from the plugins source and',
             'the hand-reviewed `Scripts/dev/fixtures/plugin-settings-consumer-review.tsv`.', '',
             'Paths and line numbers below refer to the plugins repository. `port` means required work,',
             '`ported` means existing selected-client implementation (not automatic acceptance),',
             '`no-port` means no shared-configuration mismatch at the traced boundary, and `no-instance`',
             'means no placed runtime entry. All page/native contracts still apply.', '',
             'Field maps show literal namespace/alias/injected-cfg read-or-write edges, not arbitrary token matches.',
             'An absent literal edge is not automatic proof of an unused field: dynamic helpers, inherited',
             'properties and Main-owned child inputs require the ownership note. Non-runtime Settings',
             'children/tests are excluded from these maps, but retained in the machine-readable source index.',
             'Genuinely shared content/hardware/daemon state never makes a dead instance preference valid.',
             'Shared actions must identify their effect; selected request/presentation policy still applies.', '',
             '| # | Plugin | Pattern | Disposition |', '| --- | --- | --- | --- |']
    for number, row in enumerate(rows, 1):
        review = reviewed[row['plugin']]
        lines.append(f"| {number} | `{row['plugin']}` | {review['pattern']} | {review['disposition']} |")
    lines.extend(['', '## Pass 2: implementation groups', '',
                  'Partition of the 74 required ports at `5ed97f7ab`, largest groups first.',
                  'The group file is `Scripts/dev/fixtures/plugin-settings-consumer-groups.json`.',
                  'Every row describes a proof obligation; only its explicit status records completed subgroups.',
                  'A large group may land in independently green subgroups. Unusual consumers',
                  'retain individual runtime proof. Every unit runs full VM settings contracts.', '',
                  '| # | Group / pattern | Members | Shared approach | Runtime representatives | Every-member static contract | Status |',
                  '| --- | --- | --- | --- | --- | --- | --- |'])
    for index, group in enumerate(groups, 1):
        lines.append(f"| {index} | {group['id']}: {group['pattern']} ({len(group['members'])}) | "
                     + ', '.join('`' + name + '`' for name in group['members'])
                     + f" | {group['approach']} | {group['representatives']} | {group['staticCheck']} | {group['status']} |")
    for row in rows:
        review = reviewed[row['plugin']]
        lines.extend(['', '## ' + row['plugin'], '', review['ownership'], '',
                      'Entries: ' + '; '.join('`' + key + '=' + value + '`' for key, value in sorted(row['entries'].items())) + '.', '',
                      '| # | Component | Declared-field literal edges | Context/Main evidence |',
                      '| --- | --- | --- | --- |'])
        number = 0
        seen = set()
        fingerprint = hashlib.sha256()
        fingerprint.update(row['manifestSha256'].encode())
        for item in row['files']:
            if not runtime_file(item['path']):
                continue
            fingerprint.update((item['path'] + item['sha256']).encode())
            number += 1
            for key in item['literalEdges']:
                seen.add(key)
            fields = '; '.join('`' + key + '`:' + ','.join(map(str, positions))
                               for key, positions in sorted(item['literalEdges'].items())) or 'No literal field edge'
            refs = [str(entry['line']) for entry in item['evidence'] if SETTING.search(entry['text']) or MAIN.search(entry['text'])]
            refs = refs[:8] + (['...'] if len(refs) > 8 else [])
            lines.append(f"| {number} | `{item['path']}` | {fields} | " + (', '.join(refs) or 'No namespace/Main reference') + ' |')
        remaining = sorted(set(row['fields']) - seen)
        manual_fields = {key for record in manual.get(row['plugin'], []) for key in record['fields'].split(',')}
        if set(remaining) - manual_fields:
            raise ValueError('unclassified field edges for ' + row['plugin'] + ': ' + str(sorted(set(remaining) - manual_fields)))
        lines.extend(['', 'Declared leaves without a literal runtime namespace edge: '
                      + (', '.join('`' + key + '` (' + str(row['fields'][key]) + ')' for key in remaining) or 'None') + '.'])
        if manual.get(row['plugin']):
            lines.extend(['', 'Hand-reviewed dynamic/action/unused edges (`plugin-settings-consumer-manual.tsv`):', '',
                          '| # | Fields | Source | Classification |', '| --- | --- | --- | --- |'])
            for index, record in enumerate(manual[row['plugin']], 1):
                lines.append(f"| {index} | `{record['fields']}` | `{record['path']}:{record['line']}` | {record['classification']} |")
        lines.append('Runtime-source/manifest fingerprint: `' + fingerprint.hexdigest() + '`.')
    return '\n'.join(lines) + '\n'


def selftest():
    source = '\n'.join(['property var cfg: pluginApi?.pluginSettings ?? ({})',
                        'const alias = root.cfg;', 'value: alias.zero',
                        'value: pluginApi?.settingsView?.empty',
                        'pluginApi.pluginSettings["flag"] = false;',
                        '// cfg.ignored', 'const defaults = manifest.defaultSettings;',
                        'value: defaults.unused', 'value: cfg[key]'])
    assert literal_reads(source, {'zero', 'empty', 'flag', 'ignored', 'unused'}) == {
        'zero': [3], 'empty': [4], 'flag': [5]}
    assert literal_reads('required property var configuration\nproperty var cfg: configuration\n'
                         'function pick(key) { return cfg[key]; }\nvalue: pick("flag")', {'flag'}) == {'flag': [4]}
    assert runtime_file('a/ASettingsClient.qml') and not runtime_file('a/settings/Tab.qml')
    rows = [{'plugin': 'a'}]
    with tempfile.TemporaryDirectory(prefix='consumer-review-') as work:
        path = Path(work) / 'review.tsv'
        header = 'plugin\tpattern\tdisposition\townership\n'
        valid = 'a\tdirect\tno-port\tselected API\n'
        for name, records in [('missing', ''), ('extra', valid + 'b\tdirect\tno-port\tselected\n'),
                              ('duplicate', valid + valid), ('unknown', valid.replace('no-port', 'unknown'))]:
            path.write_text(header + records)
            try:
                review_rows(path, rows)
            except ValueError:
                pass
            else:
                raise AssertionError('unreviewed coverage accepted: ' + name)
        path.write_text(header + valid)
        assert review_rows(path, rows)['a']['disposition'] == 'no-port'
    print('CONSUMER_INDEX_SELFTEST: 8 checks passed (lexical edges and review coverage)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugins', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--summary', type=Path)
    parser.add_argument('--review', type=Path, default=Path(__file__).with_name('fixtures') / 'plugin-settings-consumer-review.tsv')
    parser.add_argument('--manual', type=Path, default=Path(__file__).with_name('fixtures') / 'plugin-settings-consumer-manual.tsv')
    parser.add_argument('--groups', type=Path, default=Path(__file__).with_name('fixtures') / 'plugin-settings-consumer-groups.json')
    parser.add_argument('--inventory', type=Path)
    parser.add_argument('--check', action='store_true', help='Reject changed inventory; never refresh it automatically')
    parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args()
    if args.selftest:
        selftest()
    rows = scan(args.plugins.resolve())
    args.output.write_text(json.dumps(dict(kind='source-review-index', runtimeProof=False, entries=rows), indent=2) + '\n')
    if args.summary:
        args.summary.write_text(summary(rows))
    if args.inventory:
        reviewed = review_rows(args.review, rows)
        groups = group_rows(args.groups, reviewed)
        if args.selftest:
            with tempfile.TemporaryDirectory(prefix='consumer-groups-') as work:
                path = Path(work) / 'groups.json'
                for control in ('missing', 'duplicate', 'unknown', 'unclassified'):
                    mutated = json.loads(args.groups.read_text())
                    review_control = {name: dict(record) for name, record in reviewed.items()}
                    if control == 'missing':
                        mutated['groups'][0]['members'].pop()
                    elif control == 'duplicate':
                        mutated['groups'][0]['members'][-1] = mutated['groups'][0]['members'][0]
                    elif control == 'unknown':
                        mutated['groups'][0]['members'][-1] = 'unknown-consumer'
                    else:
                        review_control[mutated['groups'][0]['members'][0]]['disposition'] = 'no-port'
                    path.write_text(json.dumps(mutated))
                    try:
                        group_rows(path, review_control)
                    except ValueError:
                        pass
                    else:
                        raise AssertionError('invalid group coverage accepted: ' + control)
            print('CONSUMER_GROUP_SELFTEST: 4 rejecting coverage controls passed')
        rendered = inventory(rows, reviewed, manual_rows(args.manual, rows, args.plugins.resolve()), groups)
        if args.check:
            if args.inventory.read_text() != rendered:
                raise ValueError('consumer inventory stale: review changed source/fields/entries before regenerating')
        else:
            args.inventory.write_text(rendered)
    print('CONSUMER_SOURCE_INDEX: ' + str(len(rows)) + ' generic entries (source evidence only)')


if __name__ == '__main__':
    main()
