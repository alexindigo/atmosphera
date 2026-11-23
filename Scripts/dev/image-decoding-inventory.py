#!/usr/bin/env python3
"""Reconcile historical image sites against parsed exact shell/plugin sources.

The output is a migration ledger, not a claim that pending consumers are fixed.
Fixed/generated candidates remain pending until finite input provenance is
reviewed. Every inherited renderer and dynamic-QML constructor is included too.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from guest_profile import activate_profile, profile_argument
from image_decoding_sources import discover, RENDERERS, TEXT_TYPES


def fixed_provenance(row, root):
    """Only finite, literal packaged PNG/SVG paths qualify without dataflow audit."""
    if row['node'] not in ('Image', 'AnimatedImage'):
        return None
    source = row['bindings'].get('source', '').strip().rstrip(';')
    literal = re.fullmatch(r'"([^"\\]+)"', source)
    resolved = re.fullmatch(r'Qt\.resolvedUrl\("([^"\\]+)"\)', source)
    shell_dir = re.fullmatch(r'Qt\.resolvedUrl\(Quickshell\.shellDir \+ "([^"\\]+)"\)', source)
    if literal or resolved:
        value = (literal or resolved)[1]
        target = (root / row['path']).parent / value
    elif shell_dir:
        target = root / shell_dir[1].lstrip('/')
    else:
        return None
    target = target.resolve()
    if not target.is_relative_to(root) or target.suffix not in ('.png', '.svg') or not target.is_file():
        return None
    data = target.read_bytes()
    if target.suffix == '.png':
        if not data.startswith(b'\x89PNG\r\n\x1a\n'):
            return None
    else:
        tree = ET.fromstring(data)
        if tree.tag.split('}')[-1] != 'svg':
            return None
        # An SVG that imports another file is not a finite self-contained asset
        # under this simple proof. It needs the regular explicit owner/audit.
        for node in tree.iter():
            for key, value in node.attrib.items():
                if key.split('}')[-1] == 'href' and not value.startswith('#'):
                    return None
    return dict(kind='finite-packaged-asset', sourceBinding=source,
                assets=[dict(path=str(target.relative_to(root)), sha256=hashlib.sha256(data).hexdigest())])


def classify(row):
    path, node, bindings = row['path'], row['node'], row['bindings']
    kinds = {node} | set(row.get('inheritedFrom', []))
    if kinds & TEXT_TYPES:
        origin = bindings.get('text', '')
        fmt = bindings.get('textFormat', '')
        if fmt in ('Text.PlainText', 'TextEdit.PlainText'):
            return dict(sourceOrigin=origin, sourceClass='plain-text', adapter='none', animationIntent='none',
                        cohort='text', disposition='explicit-plain-text', endpoint='plain-text-no-image-interests')
        return dict(sourceOrigin=origin, sourceClass='markup', adapter='NImageText', animationIntent='preserve',
                    cohort='text', disposition='pending-adoption', endpoint='inline-' + row['repository'] + ':' + path)
    if node == 'dynamic-qml':
        return dict(sourceOrigin='Qt.createQmlObject arguments', sourceClass='dynamic-qml', adapter='review-construction',
                    animationIntent='unknown', cohort='boundary', disposition='pending-construction-audit', endpoint='dynamic-qml-boundary')
    if node == 'converter-command':
        return dict(sourceOrigin=bindings.get('command', ''), sourceClass='decoder-command', adapter='ImageCacheService',
                    animationIntent='operation-dependent', cohort='worker' if row['repository'] == 'shell' else 'plugins',
                    disposition='pending-decoder-ownership-audit', endpoint='single-decoder-owner:' + path)
    origin = bindings.get('source', bindings.get('imagePath', bindings.get('icon', bindings.get('name', ''))))
    animation = 'preserve' if kinds & {'AnimatedImage', 'NImageRounded'} else 'still'
    if any(part in path for part in ('FileChooser', 'Wallpaper', 'Background', 'LockScreen')):
        cohort = 'chooser-wallpaper'
    else:
        cohort = 'shell' if row['repository'] == 'shell' else 'plugins'
    if row['repository'] == 'plugins':
        cohort = 'plugins'
    if kinds & {'AtmoAppIcon', 'AtmoIcon'}:
        adapter = next(name for name in ('AtmoAppIcon', 'AtmoIcon') if name in kinds)
        disposition = 'inherited-owner-pending'
        source_class = 'icon-lookup'
    elif kinds & {'NImageRounded', 'NImageIcon'}:
        adapter = next(name for name in ('NImageRounded', 'NImageIcon') if name in kinds)
        disposition = 'inherited-owner-pending'
        source_class = 'arbitrary'
    else:
        adapter = 'NImage'
        disposition = 'pending-adoption'
        source_class = 'arbitrary'
    return dict(sourceOrigin=origin, sourceClass=source_class, adapter=adapter, animationIntent=animation,
                cohort=cohort, disposition=disposition, endpoint=cohort + ':' + path + ':' + (row['identity'] or str(row['line'])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'research', 'manifest'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    for path in (args.source, args.plugins, args.research, args.manifest):
        if path != path.resolve() or not path.is_relative_to(profile.workspace):
            raise ValueError('Inventory paths must be canonical inside the named guest workspace')
    if args.manifest.exists():
        raise ValueError('Refusing to overwrite an existing reviewed inventory')
    historical = json.loads(args.research.read_text())
    if len(historical) != 171:
        raise ValueError('Historical inventory must contain all 171 rows')
    rows = discover(args.source, 'shell') + discover(args.plugins, 'plugins')
    by_file = {}
    for index, row in enumerate(rows):
        row['id'] = row['key']
        row.update(classify(row))
        row['sourceKinds'] = ['file', 'data', 'http', 'provider'] if row['sourceClass'] in ('arbitrary', 'icon-lookup', 'markup') else [row['sourceClass']]
        provenance = fixed_provenance(row, args.source if row['repository'] == 'shell' else args.plugins)
        if provenance:
            row.update(sourceClass='fixed', sourceKinds=['packaged'], disposition='fixed-provenance',
                       adapter='native-fixed', provenance=provenance, endpoint='fixed-asset-decode:' + row['path'])
        row['bindings'] = {key: value for key, value in row['bindings'].items()
                           if key in ('source', 'imagePath', 'icon', 'name', 'text', 'textFormat', 'richTextEnabled',
                                      'markdownTextEnabled', 'enableDescriptionRichText', 'command')}
        row['researchRows'] = []
        by_file.setdefault((row['repository'], row['path']), []).append(row)
    reconciled = []
    for index, old in enumerate(historical):
        repository = 'shell' if old['repository'] == 'atmosphera' else 'plugins'
        candidates = by_file.get((repository, old['file']), [])
        context_lines = old['context'].splitlines()
        anchor = context_lines[2] if len(context_lines) > 2 else ''
        declared = re.match(r'\s*(Image|AnimatedImage|IconImage|NImageRounded|AtmoAppIcon)\s*\{', anchor)
        if declared:
            candidates = [r for r in candidates if r['node'] == declared[1]]
        # A historical rich-text match may name the format binding rather than
        # its Text start. Use the smallest enclosing parsed node first. Source
        # movements stay visible as a nearest-node reconciliation, never silently
        # certify the old source expression as the current one.
        enclosing = [r for r in candidates if r['line'] <= old['line'] <= r['endLine']]
        chosen = min(enclosing, key=lambda r: r['endLine'] - r['line']) if enclosing else (
            min(candidates, key=lambda r: abs(r['line'] - old['line'])) if candidates else None)
        record = dict(id=index + 1, repository=repository, path=old['file'], historicalLine=old['line'],
                      historicalRevision=old['revision'], contextSha256=hashlib.sha256(old['context'].encode()).hexdigest(),
                      site=chosen['id'] if chosen else None,
                      reconciliation='enclosing-node' if enclosing else 'line-moved-review' if chosen else 'non-image-source-review')
        # These two original rows are a PDF page renderer and a format-source
        # property, not image-node declarations. Their dispositions are explicit
        # rather than mapping the latter to the nearest unrelated bell icon.
        if index + 1 == 28:
            record.update(site=None, reconciliation='audited-pdf-not-raster-image',
                          reason='PdfDocument/PdfPageImage operate on PDFs; no arbitrary raster input',
                          fileSha256=hashlib.sha256((args.source / old['file']).read_bytes()).hexdigest())
            chosen = None
        elif index + 1 == 46:
            targets = [r for r in by_file[(repository, old['file'])]
                       if r['identity'] in ('summaryText', 'bodyText')]
            record.update(site=None, sites=[r['id'] for r in targets], reconciliation='audited-format-source-to-two-text-consumers',
                          reason='notificationTextFormat at line 594 drives summaryText and bodyText')
            for target in targets:
                target['researchRows'].append(index + 1)
            chosen = None
        if chosen:
            chosen['researchRows'].append(index + 1)
        reconciled.append(record)
    result = dict(schema=1, researchSha256=hashlib.sha256(args.research.read_bytes()).hexdigest(),
                  sourcePins={'shell': '702b62f2212a319fd0667386e93e1be8c7f2f4c4', 'plugins': '685169497bd4b0cffe3b6d3aaa6b1225caed474d'},
                  researchRows=reconciled, sites=rows,
                  status='inventory-candidate; pending audit/adoption/endpoint qualification is not an exemption')
    args.manifest.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(dict(sites=len(rows), historical=len(reconciled),
                          moved=[r for r in reconciled if r['reconciliation'] != 'enclosing-node']), indent=2))


if __name__ == '__main__':
    main()
