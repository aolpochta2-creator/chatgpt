# V44 compiled RTL audit gate

This directory contains audit-only tests for the production PREP5 V44 RTL.
Nothing here is instantiated by the production design or by the physical
flow. The gate deliberately combines four different kinds of evidence:

- exact Python model and structural regressions;
- Icarus compilation/simulation of every full divider top plus directed
  finite-width, V43 and post-NBA pipeline tests;
- Verilator lint with an explicit warning classification;
- Yosys elaboration of every full top and width/type inspection of critical
  production nodes.

`production_rtl_v44_prep5.sha256` locks the exact production RTL bytes audited
by this stage. `rom_v44.sha256` locks the generated ROM payloads. The GitHub
workflow records both package and tool-banner versions in its artifacts.

This is not a physical-flow gate and it is not post-physical equivalence.
Formal proof remains a separate future obligation.
