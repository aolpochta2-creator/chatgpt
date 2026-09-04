# Exact Integer Divider R&D

This repository turns the V44 research checkpoint into a reproducible RTL and
open-source ASIC synthesis experiment.

## Current comparison

- **V36RCM + V34DX control**: signed-safe binary redundant-cut products.
- **V39C42 control**: separate signed radix-4 Booth products.
- **V43SJ17 candidate**: signed-safe joint radix-4 recoder with 17 main rows.
- **V44WAVE** remains a timing-bound study, not a fourth RTL candidate.

The immediate rule is unchanged: do not promote a new mathematical version
before the same compile, simulation, synthesis, mapping and STA flow has run on
V36, V39 and V43.

## Implemented operation

The first milestone is the exact normalized primitive

```
{Quotient, Remainder} = (Dividend_Hi * 2^64) divmod Divisor
```

with `Divisor[63] = 1` and `Dividend_Hi < Divisor`. It is framed as two
pipeline stages and accepts one input per cycle. See
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the comparison contract,
signed-CSA correction and present implementation boundary.

## Reproduce

```bash
make model
make structure
make test TESTS=5000

# For mapped runs:
export LIBERTY=/path/to/NangateOpenCellLibrary_typical.lib
make synth-v36
make synth-v39
make synth-v43
```

The GitHub Actions matrix installs Icarus Verilog, Yosys and OpenSTA, maps every
variant to the same pinned Nangate45 Liberty file, and uploads the raw reports.

## Evidence level

The Python model currently passes 100,004 randomized/directed exact divisions.
The signed-cut, separate-Booth and joint-prefix identities pass another 200,000
randomized structural cases. These are pre-RTL mathematical checks, not a
substitute for compiled RTL simulation.

No candidate is declared fastest or smallest until the CI reports complete and
the mapped netlists are reviewed for an equivalent comparison.
