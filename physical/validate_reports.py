"""Reject missing or non-numeric physical evidence; retain violations visibly."""
import json
import math
import re
import sys
from pathlib import Path

root, top = Path(sys.argv[1]), sys.argv[2]
reports = root / 'reports' / 'nangate45' / top / 'base'
results = root / 'results' / 'nangate45' / top / 'base'
for name in ['6_final.spef', '6_final.odb', '6_final.v', '6_final.sdc']:
    p = results / name
    assert p.is_file() and p.stat().st_size > 0, f'Missing evidence: {p}'
counts = dict(line.split('\t') for line in (reports/'physical_counts.tsv').read_text().splitlines())
assert int(counts['dffs']) == 168
slack = (reports/'physical_slack.rpt').read_text()
values = {}
for kind in ['max', 'min']:
    match = re.search(rf'worst slack {kind}\s+(-?\d+\.\d+)', slack)
    assert match, f'Missing numeric {kind} slack'
    value = float(match[1])
    assert math.isfinite(value)
    values[f'worst_slack_{kind}_ns'] = value
electrical = (reports/'physical_electrical.rpt').read_text()
setup = (reports/'physical_setup.rpt').read_text()
assert 'Startpoint:' in setup and 'Endpoint:' in setup
summary = {'top': top, **counts, **values,
           'electrical_violations': electrical.count('(VIOLATED)'),
           'evidence': 'detailed-route OpenRCX SPEF, single typical corner'}
(root/'physical_summary.json').write_text(json.dumps(summary, indent=2)+'\n')
print(json.dumps(summary, indent=2))
# Collect the physical experiment even if timing is not closed.  A successful
# measurement must never be labeled timing signoff without these checks.
if summary['electrical_violations'] or min(values.values()) < 0:
    print('PHYSICAL_MEASUREMENT_VALID_BUT_TIMING_OR_ELECTRICAL_NOT_CLOSED')
else:
    print('PHYSICAL_TIMING_AND_ELECTRICAL_CHECKS_MET')

