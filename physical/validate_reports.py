"""Reject missing or non-numeric physical evidence; retain violations visibly."""
import json
import math
import os
import re
import sys
from pathlib import Path

root, top, expected_period = Path(sys.argv[1]), sys.argv[2], float(sys.argv[3])
prep_mode = os.environ['PREP_MODE']
experiment_label = os.environ['EXPERIMENT_LABEL']
source_commit = os.environ['SOURCE_COMMIT']
source_run_id = int(os.environ['SOURCE_RUN_ID'])
physical_seed = int(os.environ['PHYSICAL_SEED'])
flow_runtime_seconds = int(os.environ['FLOW_RUNTIME_SECONDS'])
assert prep_mode in {'prep5', 'prep6'}
assert experiment_label in {'paired-primary', 'v43-seed-check'}
assert re.fullmatch(r'[0-9a-f]{40}', source_commit)
assert source_run_id > 0 and physical_seed > 0 and flow_runtime_seconds > 0
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
critical_startpoint = re.search(r'^Startpoint:\s+(.+)$', setup, re.MULTILINE).group(1)
critical_endpoint = re.search(r'^Endpoint:\s+(.+)$', setup, re.MULTILINE).group(1)
next_path = setup.find('\nStartpoint:', 1)
critical_path = setup if next_path < 0 else setup[:next_path]
critical_data_path = critical_path.split('data arrival time', 1)[0]
critical_cells = []
seen_critical_instances = set()
for instance, cell_type in re.findall(
        r'[\^v]\s+(\S+)/\S+\s+\(([A-Z][A-Z0-9_]*_X\d+)\)',
        critical_data_path):
    if instance not in seen_critical_instances:
        critical_cells.append((instance, cell_type))
        seen_critical_instances.add(instance)
critical_cell_types = [cell_type for _, cell_type in critical_cells]
critical_cell_type_counts = {}
for cell_type in critical_cell_types:
    critical_cell_type_counts[cell_type] = critical_cell_type_counts.get(cell_type, 0) + 1
critical_fanouts = [int(value) for value in
                    re.findall(r'^\s+(\d+)\s+-?\d+\.\d+\s+', critical_data_path,
                               re.MULTILINE)]
critical_buffer_count = sum(cell.startswith('BUF_') for cell in critical_cell_types)
arrivals = [float(value) for value in
            re.findall(r'^\s+(-?\d+\.\d+)\s+data arrival time\s*$',
                       setup, re.MULTILINE)]
arrivals = [value for value in arrivals if value >= 0.0]
assert arrivals, 'Missing max-path data arrival'

electrical_sections = {
    'max slew': ('max_transition_violations',
                 'worst_max_transition_slack_ns'),
    'max capacitance': ('max_capacitance_violations',
                        'worst_max_capacitance_slack_ff'),
    'max fanout': ('max_fanout_violations',
                   'worst_max_fanout_slack'),
}
electrical_counts = {keys[0]: 0 for keys in electrical_sections.values()}
electrical_slacks = {keys[1]: None for keys in electrical_sections.values()}
electrical_violators = {keys[0]: [] for keys in electrical_sections.values()}
section = None
for line in electrical.splitlines():
    heading = line.strip().lower()
    if heading in electrical_sections:
        section = electrical_sections[heading]
    elif '(VIOLATED)' in line:
        assert section, f'Electrical violation outside a known section: {line}'
        electrical_counts[section[0]] += 1
        slack_match = re.search(r'(-?\d+\.\d+)\s+\(VIOLATED\)', line)
        assert slack_match, f'Missing electrical slack: {line}'
        value = float(slack_match[1])
        previous = electrical_slacks[section[1]]
        electrical_slacks[section[1]] = value if previous is None else min(previous, value)
        electrical_violators[section[0]].append(line.strip())

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
cts_setup_buffers = sum(map(int, re.findall(
    r'\[INFO RSZ-0040\] Inserted (\d+) buffers\.', cts)))
cts_hold_buffers = sum(map(int, re.findall(r'Inserted (\d+) hold buffers\.', cts)))
grt_setup_buffers = sum(map(int, re.findall(
    r'\[INFO RSZ-0040\] Inserted (\d+) buffers\.', grt)))
grt_hold_buffers = sum(map(int, re.findall(r'Inserted (\d+) hold buffers\.', grt)))
grt_design_buffers = sum(map(int, re.findall(r'Inserted (\d+) buffers in \d+ nets\.', grt)))

summary = {'experiment_label': experiment_label,
           'prep_mode': prep_mode,
           'source_commit': source_commit,
           'source_run_id': source_run_id,
           'physical_seed': physical_seed,
           'flow_runtime_seconds': flow_runtime_seconds,
           'top': top,
           'clock_period_ns': actual_period,
           **counts, **values,
           'max_data_arrival_ns': max(arrivals),
           'critical_startpoint': critical_startpoint,
           'critical_endpoint': critical_endpoint,
           'critical_path_logic_cell_count': len(critical_cell_types),
           'critical_path_buffer_count': critical_buffer_count,
           'critical_path_max_fanout': max(critical_fanouts, default=0),
           'critical_path_cell_types': critical_cell_types,
           'critical_path_cell_type_counts': critical_cell_type_counts,
           **electrical_counts,
           **electrical_slacks,
           'max_capacitance_violators': electrical_violators['max_capacitance_violations'],
           'electrical_violations': sum(electrical_counts.values()),
           'cts_repair_timing_calls': cts_repair_calls,
           'cts_setup_buffers': cts_setup_buffers,
           'cts_hold_buffers': cts_hold_buffers,
           'grt_setup_buffers': grt_setup_buffers,
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
if summary['tns_max_ns'] != 0.0:
    fail_reasons.append('setup_tns')
if summary['tns_min_ns'] != 0.0:
    fail_reasons.append('hold_tns')
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
