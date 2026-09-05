"""Reject missing or non-numeric physical evidence; retain violations visibly."""
import json
import math
import re
import sys
from pathlib import Path

root, top, expected_period = Path(sys.argv[1]), sys.argv[2], float(sys.argv[3])
reports = root / 'reports' / 'nangate45' / top / 'base'
results = root / 'results' / 'nangate45' / top / 'base'
evidence_files = ['6_final.odb', '6_final.def', '6_final.gds',
                  '6_final.v', '6_final.sdc', '6_final.spef']
evidence_sizes = {}
for name in evidence_files:
    p = results / name
    assert p.is_file() and p.stat().st_size > 0, f'Missing evidence: {p}'
    evidence_sizes[name] = p.stat().st_size

final_sdc = (results/'6_final.sdc').read_text()
period_match = re.search(r'create_clock\s+.*?-period\s+([0-9.]+)', final_sdc)
assert period_match, 'Missing clock period in final SDC'
actual_period = float(period_match[1])
assert math.isclose(actual_period, expected_period, abs_tol=0.0001), \
       f'Final SDC period {actual_period} != requested {expected_period}'
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
for kind in ['max', 'min']:
    match = re.search(rf'tns {kind}\s+(-?\d+\.\d+)', slack)
    assert match, f'Missing numeric {kind} TNS'
    value = float(match[1])
    assert math.isfinite(value)
    values[f'tns_{kind}_ns'] = value
electrical = (reports/'physical_electrical.rpt').read_text()
setup = (reports/'physical_setup.rpt').read_text()
hold = (reports/'physical_hold.rpt').read_text()
assert 'Startpoint:' in setup and 'Endpoint:' in setup
assert 'Startpoint:' in hold and 'Endpoint:' in hold
arrivals = [float(value) for value in
            re.findall(r'^\s+(-?\d+\.\d+)\s+data arrival time\s*$',
                       setup, re.MULTILINE)]
arrivals = [value for value in arrivals if value >= 0.0]
assert arrivals, 'Missing max-path data arrival'

electrical_keys = {
    'max slew': 'max_transition_violations',
    'max capacitance': 'max_capacitance_violations',
    'max fanout': 'max_fanout_violations',
}
electrical_counts = {value: 0 for value in electrical_keys.values()}
section = None
for line in electrical.splitlines():
    heading = line.strip().lower()
    if heading in electrical_keys:
        section = electrical_keys[heading]
    elif '(VIOLATED)' in line:
        assert section, f'Electrical violation outside a known section: {line}'
        electrical_counts[section] += 1

route = (root/'logs'/'nangate45'/top/'base'/'5_2_route.log').read_text()
wire = re.findall(r'Total wire length =\s*(\d+)\s*um\.', route)
vias = re.findall(r'Total number of vias =\s*(\d+)\.', route)
assert wire and vias, 'Missing detailed-route wire/via metrics'
antenna_nets = re.findall(r'Found (\d+) net violations\.', route)
antenna_pins = re.findall(r'Found (\d+) pin violations\.', route)
assert antenna_nets and antenna_pins, 'Missing antenna metrics'
drc = (reports/'5_route_drc.rpt').read_text()
drc_violations = len(re.findall(r'^violation type:', drc, re.MULTILINE))

cts = (root/'logs'/'nangate45'/top/'base'/'4_1_cts.log').read_text()
grt = (root/'logs'/'nangate45'/top/'base'/'5_1_grt.log').read_text()
cts_repair_calls = len(re.findall(r'^repair_timing\s', cts, re.MULTILINE))
assert cts_repair_calls > 0, 'Post-CTS repair_timing did not run'
cts_hold_buffers = sum(map(int, re.findall(r'Inserted (\d+) hold buffers\.', cts)))
grt_hold_buffers = sum(map(int, re.findall(r'Inserted (\d+) hold buffers\.', grt)))
grt_design_buffers = sum(map(int, re.findall(r'Inserted (\d+) buffers in \d+ nets\.', grt)))

summary = {'top': top,
           'clock_period_ns': actual_period,
           **counts, **values,
           'max_data_arrival_ns': max(arrivals),
           **electrical_counts,
           'electrical_violations': sum(electrical_counts.values()),
           'cts_repair_timing_calls': cts_repair_calls,
           'cts_hold_buffers': cts_hold_buffers,
           'grt_hold_buffers': grt_hold_buffers,
           'grt_repair_design_buffers': grt_design_buffers,
           'routed_wire_length_um': int(wire[-1]),
           'vias': int(vias[-1]),
           'detailed_route_drc_violations': drc_violations,
           'antenna_net_violations': int(antenna_nets[-1]),
           'antenna_pin_violations': int(antenna_pins[-1]),
           'final_evidence_bytes': evidence_sizes,
           'evidence': 'detailed-route OpenRCX SPEF, single typical corner'}
# Collect the physical experiment even if timing is not closed.  A successful
# measurement must never be labeled timing signoff without these checks.
fail_reasons = []
if summary['worst_slack_max_ns'] < 0:
    fail_reasons.append('setup')
if summary['worst_slack_min_ns'] < 0:
    fail_reasons.append('hold')
if summary['detailed_route_drc_violations']:
    fail_reasons.append('detailed_route_drc')
if summary['antenna_net_violations'] or summary['antenna_pin_violations']:
    fail_reasons.append('antenna')
if summary['electrical_violations']:
    fail_reasons.append('electrical')
closed = not fail_reasons
summary['physical_pass'] = closed
summary['physical_fail_reasons'] = fail_reasons
(root/'physical_summary.json').write_text(json.dumps(summary, indent=2)+'\n')
print(json.dumps(summary, indent=2))
if not closed:
    print('PHYSICAL_MEASUREMENT_VALID_BUT_TIMING_OR_ELECTRICAL_NOT_CLOSED')
else:
    print('PHYSICAL_TIMING_AND_ELECTRICAL_CHECKS_MET')
