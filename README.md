# Exact Integer Divider R&D

Research RTL for an exact 64-bit integer divider aimed at low cold-divisor latency.

## Status

This repository starts at the V44 research checkpoint. Mathematical and randomized model validation has been completed for the current architecture family, but real synthesis and static timing analysis have not yet selected a winner.

Current comparison set:

- **V36RCM + V34DX + V35FF** — low-latency redundant-cut control.
- **V39C42** — separate radix-4 Booth / column-level 4:2 control.
- **V43SJ17** — signed-safe joint radix-4 candidate with 17 main rows.
- **V44WAVE** — arrival-aware timing-bound study, not a separate implementation candidate.

## Immediate objective

Implement structurally honest, functionally equivalent RTL for V36, V39, and V43, then run all three through the same flow:

1. Icarus Verilog compile and randomized exact quotient/remainder tests.
2. Yosys synthesis with identical scripts and options.
3. Mapping to the same open standard-cell library.
4. Static timing and mapped-cell area reporting.
5. Only then compare latency, area, area × latency, throughput, and power proxies.

No new mathematical version should be promoted before this comparison is complete.

## Scope and claims

The target niche is exact unsigned 64-bit cold division with a changing divisor. Warm or cached reciprocal division is a separate comparison case.

Structural depth, row counts, and multiplier proxies from the research journal are analytical estimates, not synthesis or STA results. This repository will not claim superiority over SRT, Möller–Granlund, commercial dividers, or any other implementation until a fair physical comparison exists.
