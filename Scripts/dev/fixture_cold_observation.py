"""Cross-process observations; the parent owns the verdict receipt."""
import json
import re


def write_cold_observation(output, identity, before, after):
    # The child has completed its engine, cleanup and local checks. This is
    # input to the parent, not a verdict or a receipt_run scope of its own.
    with (output / 'observation.json').open('x') as stream:
        json.dump(dict(identity=identity, before=before, after=after), stream)


def read_cold_observation(output, identity, marker, rejected):
    text = (output / 'runtime.log').read_text()
    evidence = json.loads((output / 'observation.json').read_text())
    before = evidence.get('before')
    if ((output / 'runtime.exit').read_text().strip() != '0'
            or not any(line.endswith(marker) for line in text.splitlines())
            or any(token in text for token in rejected)
            or evidence.get('identity') != identity
            or not isinstance(before, dict) or not before or before != evidence.get('after')
            or not all(isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value)
                       for value in before.values())):
        raise RuntimeError('invalid independent cold observation: ' + repr(identity))
    return before
