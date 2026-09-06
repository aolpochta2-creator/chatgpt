# V44 production PREP5 compiled RTL audit

Date: 2026-09-06

## Verdict and scope

The exact current production PREP5 V44 RTL passed a fresh, reproducible
multi-tool compile, simulation, lint and elaboration gate. The canonical source
commit is `c2d36e4ff1aa3015c20f5816bd0f462e99b7a64c`; the successful GitHub
Actions run is
[34008436155](https://github.com/aolpochta2-creator/chatgpt/actions/runs/34008436155).
The uploaded evidence artifact is `9981741949`, with archive digest
`sha256:2e4049767ed824899e94b2aac4e0c9f89f552464329671d7828ba306cceb55fe`.

This closes the earlier compiled-RTL/elaboration evidence gap without changing
production RTL. A committed SHA-256 manifest is checked before and after the
gate. No divider mathematics, predictor, `cut=46`, `t=32`, V43 recoder, FINAL,
or production PREP5 logic changed. No physical flow ran. `g_L` was not
implemented and V45/V46 were not created.

The result is compiled/elaborated evidence, not a complete proof. Whole-divider
formal proof and post-physical logical equivalence remain open gates.

## Reproducible tool provenance

The workflow runs on `ubuntu-24.04` and pins the exact distribution packages,
then records package and banner versions in the artifact.

| Item | Recorded value |
| --- | --- |
| GitHub runner image | `ubuntu24`, image `20260831.293.1` |
| Icarus package / banner | `iverilog 12.0-2build2`; Icarus Verilog `12.0 (stable)` |
| Verilator package / banner | `verilator 5.020-1`; Verilator `5.020 2024-01-01` |
| Yosys package / banner | `yosys 0.33-5build2`; Yosys `0.33`, git `2584903a060` |

The workflow is `.github/workflows/rtl-audit.yml`; the single entry point is
`audit/run_compiled_rtl_audit.sh`. It runs from the checked-out repository root
and stops if that cwd contract is not true.

## Gate results

| Gate | Canonical result |
| --- | --- |
| Exact model | 100,012 normalized divisions; PREP correction range observed `0..4` |
| Structural model | 200,000 signed-cut and V36/V39/V43 product identities |
| Named model vectors | 11; PREP corrections `0..4`, FINAL correction `3`, m=2048 and power boundary |
| Icarus sizing microtest | PASS |
| Icarus V43 finite directed test | PASS |
| Icarus post-NBA pipeline test | PASS, 22 checked edges |
| Icarus full V36 top | PASS, 263 back-to-back vectors |
| Icarus full V39 top | PASS, 263 back-to-back vectors |
| Icarus full V43 top | PASS, 263 back-to-back vectors |
| Icarus cross-variant equivalence | PASS, 259 back-to-back vectors |
| Verilator sizing execution | PASS |
| Verilator production lint | 43 unique diagnostics classified, 0 unresolved |
| Yosys hierarchy/proc/check | PASS on all three full tops |
| Yosys critical width/type inspection | PASS, 135 checks |
| Production RTL byte lock | PASS before and after the gate |
| Physical flow | Not run by this stage |

## Directed compiled coverage

The pipeline test instantiates V36, V39 and V43 together and checks exact Q/R,
valid/error association and internal directed conditions in compiled RTL.

| Required case | Compiled evidence |
| --- | --- |
| PREP correction 0 endpoint | `D=9340465626629537792`, `X=D-1`, checked in all three tops |
| PREP correction 1 | `D=9232379236109516799`, `X=D-1`, checked in all three tops |
| PREP correction 2 | `D=10377810952591741380`, `X=D-1`, checked in all three tops |
| PREP correction 3 | `D=9223372036854775809`, `X=D-1`, checked in all three tops |
| PREP correction 4 endpoint | `D=9232379236109516801`, `X=D-1`, checked in all three tops |
| FINAL correction 3 | `D=16960521012305199105`, `X=16475201744807867636` |
| `D=2^64-1` | Exact compiled Q/R check with `X=D-1` |
| mathematical m=2048 boundary | Both sides of the lower edge plus `D=2^64-1` |
| finite m=2048 encoding | Production 11-bit `M=0`, `Bucket=1023`, checked in all variants |
| `D=2^63, X=0` | Exact Q/R, special PREP path and `R=0` |
| `D=2^63, X=2^63-1` | Exact Q/R, special PREP path, `X=D-1` and `R=0` |
| transaction order | legal A, legal B back-to-back, bubble, invalid D, legal special, invalid `X>=D`, legal C |
| reset | Startup reset, pending-transaction flush and first post-reset transaction |

The observation point is explicitly after NBA. An input accepted at `E_t`
must produce its associated output after NBA at `E_(t+1)`. The test checks the
actual current contract in which a bubble can pipeline an error value; it does
not assume `Out_Valid=0 -> Out_Error=0`.

The V43-only compiled test exhaustively calls the production local table for
all seven legal inputs and the compose table for all 64 x 64 input pairs. It
checks carry states 0, 1 and 2, all `G=0..8` digit mappings, and specifically
`G=8 -> Digit=0`. The state `U=2^32+63`, `V=63` is explicitly labelled
synthetic, not predictor-reachable. The actual predictor witness
`D=9253963028337416818` confirms reachable carry state 2; it does not establish
actual predictor reachability of `G=8`.

## SystemVerilog sizing evidence

The audit-only microtest compiles and executes under both Icarus and Verilator.
It checks representative values as well as destination widths for:

- unsigned 64 x 32 into 96 bits and 64 x 64 into 128 bits;
- signed 44 x 31 into 75 bits;
- a chained expression analogous to `3 * signed64 * signed64`;
- an unsigned part-select assigned to a same-width signed wire;
- signed W-bit left shift and unary minus after that shift;
- generate expression `Carry_Low ? k : k-1` into signed4, including
  `k=0, Carry_Low=0 -> -1`;
- FINAL products 33 x 33 -> 66, 64 x 32 -> 96, 64 x 64 -> 128 and
  32 x 64 -> 96.

The observed `$bits` line is:

```
64x32=96/64 64x64=128/64 signed44x31=75/44 chain=64
```

The first number of each pair is the destination signal width; the second is
the self-determined raw expression width reported by `$bits`. Exact-value
assertions confirm that assignment context preserves the required full product
in the wider destination.

## Yosys elaborated widths and types

Yosys reads the production RTL, selects each full top, runs `hierarchy -check`,
`proc`, `check -assert`, and writes RTLIL. The committed inspector parses those
actual RTLIL files. The same results were obtained in all three tops.

| Scope | Node | Effective elaborated width/type |
| --- | --- | --- |
| Predictor | `M`, `Bucket` | 11u, 11u |
| Predictor | `W1..W5` | 31s, 35s, 39s, 43s, 47s |
| Predictor | `Product1..Product5` wires | 75s, 69s, 63s, 57s, 51s |
| Predictor | Product1 `$mul` | source 44s context-expanded to 75s x 31s -> 75s |
| Predictor | Product2 `$mul` | source 34s context-expanded to 69s x 35s -> 69s |
| Predictor | Product3 `$mul` | source 24s context-expanded to 63s x 39s -> 63s |
| Predictor | Product4 `$mul` | source 14s context-expanded to 57s x 43s -> 57s |
| Predictor | Product5 `$mul` | source 4s context-expanded to 51s x 47s -> 51s |
| Predictor | `Pred_Wrap`, `Low_Add`, `Carry_Low` | 8s, 47u, 1u |
| PREP | candidate `M` | 4s |
| PREP | `multiple68`, `multiple100` results | 68u, 100u |
| PREP | `Residual_Candidate`, `NX_Candidate` | 68u, 100u |
| PREP | `Correction`, selected residual/NX | 3u, 68u, 100u |
| FINAL | `G_Product`, `DL`, `RX`, `GD` | 66u, 96u, 128u, 96u |
| FINAL | `R0_Numerator` | 129u |
| FINAL | `E`, remainder candidates | 98s, 98s |
| FINAL | `Correction`, `Quotient` | 2u, 64u |
| FINAL | two quotient `$add` cells | each 64u + 64u -> 64u |

The Product1..5 input expansion is a resolved source/elaboration distinction,
not an unresolved tool disagreement. The explicitly non-negative signed
coefficient operand is extended to the context-determined product width. The
Icarus and Verilator exact-value tests agree with the Yosys RTLIL behavior.

## Verilator diagnostic classification

Production lint runs independently for all three tops. Diagnostics are
deduplicated by source header and every non-style warning must match a narrow,
committed file/line classification backed by another gate.

| Category | Count | Disposition |
| --- | ---: | --- |
| `DECLFILENAME` | 5 | harmless naming/style |
| `GENUNNAMED` | 8 | harmless generated-block naming/style |
| `UNUSEDSIGNAL` | 20 | intentional unused slices/debug outputs; style |
| `WIDTHEXPAND` | 3 | intentional and audited sizing sites |
| `WIDTHTRUNC` | 7 | intentional and audited modulo/range sites |
| unresolved correctness-relevant | 0 | PASS |

There were no production `SIGNED`, `UNSIGNED`, incomplete-case, latch or
similar unresolved warnings. The important audited sites include the modulo
11-bit m=2048 encoding, 65-bit `Bucket_Top` container, 53-bit E extraction,
V36 signed Wrap extension, parameter-width product shifts, and the power-
boundary `NX = X << 33` truncation. For the latter, legal `X<2^63` guarantees
that discarded bit 96 is zero, and both legal endpoint inputs are compiled
directed tests.

The audit-only sizing testbench has one `UNUSEDSIGNAL` warning for the upper
bits of `Unsigned_Packed`; only its same-width low part-select is intentionally
used by that probe. It is a harmless testbench diagnostic.

Icarus additionally reports that `@*` is sensitive to all five words of the
PREP arrays and that some synthesizable modules have no explicit time unit.
These are informational/style diagnostics, not unresolved semantic findings.

## ROM build contract

CI runs `scripts/gen_roms.py` and `scripts/gen_reducers.py` from the repository
root, requires every generated ROM to be nonempty with its exact line count,
checks the committed hashes, and only then compiles RTL. The canonical hashes
are:

| Generated file | SHA-256 |
| --- | --- |
| `build/coeff_rom.mem` | `f2c92f2c9f8e9c3b8c4a8d383ff0488e02f63c25f75d0966602dcf5315156b3c` |
| `build/square_a.mem` | `6b2163e923b976767352e5a531a9b293ebbbe39b2d7579efd2c2e4d398b83539` |
| `build/square_b.mem` | `1b0f928fca57a6d163e2612e67a650165d265cb4ac982fab24e910902d323453` |
| `build/cube.mem` | `27d9cc765a6c275dfc5f4eeb5cd8b9a1bbcf6b098ca91c00439a2fedbfee2284` |
| `build/hz_reducers_generated.sv` | `4520a77c30a7812ec7f8a7ffaa30c5acfca54a230af6bc13de9bce9721fa552f` |

The regression also scans Icarus logs for missing/readmem errors. Thus this
stage cannot silently pass with absent ROM files or X-filled ROM data.

## Updated audit statement and remaining gates

The earlier verdict `proof/portability gaps, no counterexample` can be upgraded
to:

> Reproducible Icarus/Verilator/Yosys compiled and elaborated evidence passes
> for the byte-locked production PREP5 V44 RTL; no source-level or compiled
> legal-input counterexample was found. Formal proof and post-physical logical
> equivalence remain open gates.

No large whole-divider SMT attempt was made in this stage. Sensible future
formal obligations remain the signed-CSA invariant, V43 finite
local/compose/prefix properties, PREP residual range under the proven
mathematical bound, and pipeline valid/error alignment. They must not be
represented as complete until a reproducible formal run exists.
