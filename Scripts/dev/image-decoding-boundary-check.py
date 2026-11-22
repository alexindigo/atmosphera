#!/usr/bin/env python3
"""Reject image decoding outside the shared owner, in shell and plugins.

Parses the production QML/JS of both repositories (image_decoding_sources.scan)
and compares every gated site with the reviewed manifest
(Scripts/dev/fixtures/image-decoding/consumers.json). A gated site is a place
where Qt or a process would decode image bytes by itself: native image nodes
(also through local wrappers), text laid out as markup, ColorQuantizer,
QML built at run time and converter commands. Owner renderers are the
boundary and are not sites.

Every discovered site must match a manifest entry exactly (file, rule, node
text hash) with a disposition allowed for its rule, and every entry must
still exist. Fixed assets and the declarations that choose them are
re-hashed, so changing an exempt source invalidates the exemption.
--selftest adds red controls (a new plugin with each kind of bypass) that
must be rejected for their own rule, and provenance controls.
"""
import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parent))
from image_decoding_sources import Language, Parser, scan, tree_sitter_qmljs, walk  # noqa: E402

DISPOSITIONS = {
    'native-image': {'owner-renderer', 'provider-adapter', 'fixed-asset', 'finite-asset-set', 'generated-output',
                     'missing-packaged-asset'},
    'text-markup': {'owner-renderer', 'wrapper-definition', 'shell-authored-markup', 'escaped-plugin-markup', 'plugin-authored-text'},
    'color-quantizer': {'owner-output'},
    'dynamic-qml': {'reviewed-construction'},
    'converter-command': {'owner-event-name', 'generated-output-edit'},
}
SHELL_ONLY = {'owner-renderer', 'provider-adapter', 'wrapper-definition', 'shell-authored-markup', 'owner-event-name'}
OWNER_FILES = {'owner-renderer': {'Widgets/NImage.qml', 'Widgets/NImageText.qml'},
               'provider-adapter': {'Services/UI/ImageAdmission.qml'}, 'wrapper-definition': {'Widgets/NText.qml'}}
IDENTITY = ('repository', 'path', 'rule', 'node', 'nodeSha256')


def root_for(roots, repository, relative):
    """A repository may be several roots (self-test control plugins beside the
    real tree); the one containing the path's top directory owns it."""
    candidates = roots[repository] if isinstance(roots[repository], list) else [roots[repository]]
    top = Path(relative).parts[0]
    return next((root for root in candidates if (root / top).exists()), candidates[0])


def asset_problem(root, asset):
    path = (root / asset['path']).resolve()
    if asset.get('missing'):
        # A literal packaged path whose file was never shipped: nothing can be
        # decoded. If the file appears, its bytes need a reviewed hash.
        return 'missing asset now exists ' + asset['path'] if path.exists() else None
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        return 'missing asset ' + asset['path']
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != asset['sha256']:
        return 'changed asset ' + asset['path']
    if path.suffix == '.png':
        return None if data.startswith(b'\x89PNG\r\n\x1a\n') else 'asset is not a PNG ' + asset['path']
    if path.suffix == '.svg':
        tree = ET.fromstring(data)
        if tree.tag.split('}')[-1] != 'svg':
            return 'asset is not an SVG ' + asset['path']
        for node in tree.iter():
            for key, value in node.attrib.items():
                if key.split('}')[-1] == 'href' and not value.startswith('#'):
                    return 'SVG asset loads another file ' + asset['path']
        return None
    return 'asset is not a packaged PNG/SVG ' + asset['path']


def declarations(root, relative, name):
    """Hash of every function/property/binding called name in a file, in order
    ("*": the whole file, for choices made in handler code)."""
    data = (root / relative).read_bytes()
    if name == '*':
        return hashlib.sha256(data).hexdigest()
    tree = Parser(Language(tree_sitter_qmljs.language())).parse(data)
    found = []
    for node in walk(tree.root_node):
        field = None
        if node.type in ('function_declaration', 'ui_property', 'ui_binding'):
            field = node.child_by_field_name('name')
        if field is not None and data[field.start_byte:field.end_byte].decode() == name:
            found.append(data[node.start_byte:node.end_byte])
    return hashlib.sha256(b'\n'.join(found)).hexdigest() if found else None


def check(sites, manifest, roots):
    failures = []
    entries = manifest['sites']
    for entry in entries:
        rule, disposition = entry.get('rule'), entry.get('disposition')
        where = entry.get('repository', '?') + ':' + entry.get('path', '?')
        if disposition not in DISPOSITIONS.get(rule, ()):
            failures.append(dict(problem='disposition not allowed for rule', site=where, rule=rule, disposition=disposition))
        if disposition in SHELL_ONLY and entry.get('repository') != 'shell':
            failures.append(dict(problem='shell-only disposition outside the shell', site=where, disposition=disposition))
        if disposition in OWNER_FILES and entry.get('path') not in OWNER_FILES[disposition]:
            failures.append(dict(problem='owner disposition outside the owner files', site=where, disposition=disposition))
        if not entry.get('reason'):
            failures.append(dict(problem='entry without a review reason', site=where))
        if disposition in ('fixed-asset', 'finite-asset-set', 'missing-packaged-asset') and not entry.get('assets'):
            failures.append(dict(problem='asset exemption without assets', site=where))
        if disposition == 'plugin-authored-text' and not entry.get('definitions'):
            failures.append(dict(problem='exemption without pinned source definitions', site=where))
        for asset in entry.get('assets', []):
            if bool(asset.get('missing')) != (disposition == 'missing-packaged-asset'):
                failures.append(dict(problem='missing-asset marking does not match the disposition', site=where, rule=rule))
            problem = asset_problem(root_for(roots, entry.get('repository', 'shell'), asset['path']), asset)
            if problem:
                failures.append(dict(problem=problem, site=where, rule=rule))
        for definition in entry.get('definitions', []):
            root = root_for(roots, entry.get('repository', 'shell'), definition['path'])
            if not (root / definition['path']).is_file() or declarations(root, definition['path'], definition['name']) != definition['sha256']:
                failures.append(dict(problem='changed or missing source definition ' + definition['path'] + ':' + definition['name'],
                                     site=where, rule=rule))
    available = collections.Counter(tuple(entry.get(k) for k in IDENTITY) for entry in entries)
    matched = collections.Counter()
    for site in sites:
        identity = tuple(site[k] for k in IDENTITY)
        if matched[identity] < available[identity]:
            matched[identity] += 1
        else:
            failures.append(dict(problem='unclassified site', site=site['repository'] + ':' + site['path'] + ':' + str(site['line']),
                                 rule=site['rule'], node=site['node'], key=site['key']))
    for identity, count in (available - matched).items():
        failures.append(dict(problem='stale manifest entry', site=identity[0] + ':' + identity[1], rule=identity[2], node=identity[3], count=count))
    return failures


def reconcile(sites, manifest):
    """Final state of the baseline inventory and the 171 research rows."""
    current = {(s['repository'], s['path'], s['nodeSha256']) for s in sites}
    by_identity = {(e['repository'], e['path'], e['nodeSha256']): e['disposition'] for e in manifest['sites']}
    finals, by_key = collections.Counter(), {}
    for row in manifest['baseline']['sites']:
        identity = (row['repository'], row['path'], row['nodeSha256'])
        if row['node'] in ('NImageRounded', 'NImage', 'AtmoAppIcon', 'AtmoIcon', 'NImageText'):
            final = 'owner-renderer'
        elif row['disposition'] == 'explicit-plain-text' and identity not in current:
            final = 'plain-text'
        elif identity in current:
            final = 'kept:' + by_identity.get(identity, 'unclassified')
        else:
            final = 'replaced-or-removed'
        finals[final] += 1
        by_key[row['key']] = final
    research = collections.Counter()
    for row in manifest['researchRows']:
        if row.get('site'):
            research[by_key.get(row['site'], 'missing-baseline-site')] += 1
        else:
            research[row['reconciliation']] += 1
    return dict(baseline=dict(sorted(finals.items())), research=dict(sorted(research.items())),
                baselineCount=len(manifest['baseline']['sites']), researchCount=len(manifest['researchRows']))


CONTROLS = {
    'direct-file-image': ('native-image', {'Direct.qml': 'import QtQuick\nItem { property string path\n Image { source: "file://" + parent.path } }\n'}),
    'suffix-gated-animated-image': ('native-image', {'Motion.qml': 'import QtQuick\nItem { property string path\n AnimatedImage { source: path.endsWith(".gif") ? path : "" } }\n'}),
    'icon-image': ('native-image', {'Icon.qml': 'import QtQuick\nimport Quickshell.Widgets\nItem { property string iconPath\n IconImage { source: iconPath } }\n'}),
    'hidden-wrapper': ('native-image', {'Pic.qml': 'import QtQuick\nImage {}\n', 'UsePic.qml': 'import QtQuick\nItem { property string path\n Pic { source: path } }\n'}),
    'property-alias': ('native-image', {'Alias.qml': 'import QtQuick\nItem { property alias picture: img.source\n Image { id: img } }\n'}),
    'original-after-failure': ('native-image', {'Retry.qml': 'import QtQuick\nItem { property string thumb; property string original\n Image { source: thumb; onStatusChanged: if (status === Image.Error) source = original } }\n'}),
    'inline-html-text': ('text-markup', {'Message.qml': 'import QtQuick\nItem { property string message\n Text { text: message } }\n'}),
    'markdown-image-text': ('text-markup', {'Readme.qml': 'import QtQuick\nItem { property string url\n Text { textFormat: Text.MarkdownText; text: "![art](" + url + ")" } }\n'}),
    'unlisted-rich-ntext': ('text-markup', {'Rich.qml': 'import QtQuick\nimport qs.Widgets\nItem { property string body\n NText { richTextEnabled: true; text: body } }\n'}),
    'background-image-markup': ('text-markup', {'Table.qml': 'import QtQuick\nTextEdit { textFormat: TextEdit.RichText; text: "<table background=\\"x.png\\"><tr><td>a</td></tr></table>" }\n'}),
    'generated-qml-image': ('dynamic-qml', {'Generated.qml': 'import QtQuick\nItem { Component.onCompleted: Qt.createQmlObject("import QtQuick; Image { source: \\"x.png\\" }", this) }\n'}),
    'generated-qml-variable': ('dynamic-qml', {'Built.qml': 'import QtQuick\nItem { property string qml\n Component.onCompleted: Qt.createQmlObject(qml, this) }\n'}),
    'plugin-magick-converter': ('converter-command', {'Convert.qml': 'import QtQuick\nimport Quickshell.Io\nProcess { property string src\n command: ["magick", src, "png:/tmp/out.png"] }\n'}),
    'plugin-ffmpeg-template': ('converter-command', {'Frame.qml': 'import QtQuick\nimport Quickshell.Io\nProcess { property string video\n command: ["sh", "-c", `ffmpeg -y -i ${video} -vframes:v 1 out.bmp`] }\n'}),
    'arbitrary-color-quantizer': ('color-quantizer', {'Colors.qml': 'import QtQuick\nimport Quickshell\nItem { property string userPath\n ColorQuantizer { source: userPath } }\n'}),
}
PNG = bytes.fromhex('89504e470d0a1a0a0000000d4948445200000001000000010806000000'
                    '1f15c4890000000d49444154789c6360f8cfc0f01f0005000201b7f1dd4c0000000049454e44ae426082')


def selftest(sites, manifest, roots, shell_types):
    results = []
    base_failures = check(sites, manifest, roots)
    with tempfile.TemporaryDirectory(prefix='image-boundary-controls-', dir=str(roots['plugins'].parent)) as folder:
        for name, (rule, files) in CONTROLS.items():
            plugin = Path(folder) / name / 'zz-image-boundary-control'
            plugin.mkdir(parents=True)
            for filename, content in files.items():
                (plugin / filename).write_text(content)
            injected, _ = scan(plugin.parent, 'plugins', shell_types)
            failures = check(sites + injected, manifest, dict(roots, plugins=[roots['plugins'], plugin.parent]))
            own = [f for f in failures if f['problem'] == 'unclassified site' and f['site'].startswith('plugins:zz-image-boundary-control/')]
            discovered = [s for s in injected if s['rule'] == rule]
            results.append(dict(control=name, expectedRule=rule, discovered=len(discovered),
                                rejectedRules=sorted({f['rule'] for f in own}),
                                passed=bool(discovered) and rule in {f['rule'] for f in own} and len(failures) == len(base_failures) + len(own)))
        # Provenance controls: an exact fixed asset is admitted; a changed asset,
        # a changed source binding and a removed site are not.
        plugin = Path(folder) / 'provenance' / 'zz-image-boundary-control'
        (plugin / 'assets').mkdir(parents=True)
        (plugin / 'assets/logo.png').write_bytes(PNG)
        (plugin / 'Logo.qml').write_text('import QtQuick\nImage { source: Qt.resolvedUrl("assets/logo.png") }\n')
        injected, _ = scan(plugin.parent, 'plugins', shell_types)
        assert len(injected) == 1
        entry = dict({k: injected[0][k] for k in IDENTITY}, disposition='fixed-asset', reason='control logo',
                     assets=[dict(path='zz-image-boundary-control/assets/logo.png', sha256=hashlib.sha256(PNG).hexdigest())])
        controlled = dict(manifest, sites=manifest['sites'] + [entry])
        control_roots = dict(roots, plugins=[roots['plugins'], plugin.parent])
        def outcome(name, expect_admitted, rows, candidate):
            failures = check(sites + rows, candidate, control_roots)
            own = [f for f in failures if 'zz-image-boundary-control' in f['site']]
            results.append(dict(control=name, expectedAdmitted=expect_admitted, problems=sorted({f['problem'] for f in own}),
                                passed=(not own) if expect_admitted else bool(own)))
        outcome('fixed-asset-with-provenance', True, injected, controlled)
        wrong = copy.deepcopy(controlled)
        wrong['sites'][-1]['assets'][0]['sha256'] = '0' * 64
        outcome('fixed-asset-changed-bytes', False, injected, wrong)
        (plugin / 'Logo.qml').write_text('import QtQuick\nImage { property string userPath\n source: userPath }\n')
        changed, _ = scan(plugin.parent, 'plugins', shell_types)
        outcome('exempt-source-made-arbitrary', False, changed, controlled)
        outcome('exempt-site-removed', False, [], controlled)
        wrong_rule = copy.deepcopy(controlled)
        wrong_rule['sites'][-1]['disposition'] = 'shell-authored-markup'
        outcome('plugin-claims-shell-disposition', False, injected, wrong_rule)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'plugins', 'manifest', 'report'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args()
    roots = dict(shell=args.source.resolve(), plugins=args.plugins.resolve())
    manifest = json.loads(args.manifest.read_text())
    if manifest.get('schema') != 2:
        raise SystemExit('Unsupported image boundary manifest')
    shell_sites, shell_types = scan(roots['shell'], 'shell')
    plugin_sites, _ = scan(roots['plugins'], 'plugins', shell_types)
    sites = shell_sites + plugin_sites
    failures = check(sites, manifest, roots)
    report = dict(sites=len(sites), byRule=dict(collections.Counter(s['rule'] for s in sites)),
                  byDisposition=dict(collections.Counter(e['disposition'] for e in manifest['sites'])),
                  failures=failures, reconciliation=reconcile(sites, manifest))
    if args.selftest:
        report['controls'] = selftest(sites, manifest, roots, shell_types)
    passed = not failures and all(c['passed'] for c in report.get('controls', []))
    report['status'] = 'PASS' if passed else 'FAIL'
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    for failure in failures:
        print('BOUNDARY_FAIL ' + json.dumps(failure), flush=True)
    for control in report.get('controls', []):
        print(('CONTROL ' if control['passed'] else 'CONTROL_FAIL ') + json.dumps(control), flush=True)
    print('IMAGE_DECODING_BOUNDARY: ' + report['status'], flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
