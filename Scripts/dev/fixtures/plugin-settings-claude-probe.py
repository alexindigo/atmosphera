#!/usr/bin/env python3
"""Independent native-document and exact ACP process-identity endpoint checks."""
import json
from pathlib import Path
import sys
case,out,excluded=Path(sys.argv[1]),Path(sys.argv[2]),int(sys.argv[3])
expected=json.loads((case/'expected.json').read_text())
actual={name:json.loads((case/'config'/name).read_text()) for name in expected}
(out/'document-observation.json').write_text(json.dumps(dict(actual=actual,expected=expected),indent=2)+'\n')
assert actual==expected,'complete native originating writer documents'
rows=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()] if (case/'requests.jsonl').exists() else []
identities={(r['pid'],r['start']) for r in rows}
for pid,start in identities:
    if pid==excluded:continue
    stat=Path('/proc')/str(pid)/'stat'
    assert not stat.exists() or stat.read_text().split(') ',1)[1].split()[19]!=start,('retired process joined before engine exit',pid,start)
result=dict(status='PASS',excludedPid=excluded,identities=[dict(pid=p,start=s) for p,s in sorted(identities)],documents=expected)
(out/('joined.json' if excluded==0 else 'replaced.json')).write_text(json.dumps(result,indent=2)+'\n')
print('CLAUDE_PROBE: PASS',flush=True)
