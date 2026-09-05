# Exact integer divider — handoff-журнал V44 → physical audit

Дата среза: 2026-09-05

Это канонический handoff для продолжения R&D exact integer divider в новом чате. Он объединяет приложенный журнал V44 с фактическим состоянием GitHub, RTL, CI, synthesis/STA и physical-flow.

## 0. Последний checkpoint: PREP 6 -> 5

Независимый математический аудит доказал точный диапазон PREP correction:

    0 <= floor(2^96 / D) - p <= 4

Оба края достигаются; `p+5` никогда не выбирается. В V44 RTL удалён только
candidate `k=5` и ставший недостижимым helper case `M=5`. Predictor, `p`,
`Carry_Low`, signed cut, `cut=46`, `t=32`, V43 recoder и текущий FINAL `0..3`
не менялись. Доказанная будущая формула `g_L`/FINAL `0..2` не реализована;
V45/V46 не создавались. Точный proof baseline и witnesses находятся в
`docs/MATH_AUDIT_V44_PREP_TIGHTENING.md`.

Главный результат следующего controlled checkpoint: PREP5 даёт устойчивое
уменьшение area/wire, но не универсальный timing gain. V43@3.15 PREP5 clean при
seed=2 и имеет один max-cap residual при seed=1; fixed-seed повторяется точно.
Поэтому PREP5 остаётся engineering baseline, а новый robust Tmin/Fmax не
объявляется. Старые PREP6 Tmin/Fmax сохраняются только как история.

## 1. Цель и жёсткие правила

Цель проекта — точное многоразрядное целочисленное деление без FP-деления, с малой cold-divisor latency и приемлемыми area/energy/ROM затратами, пригодное для RTL/FPGA/ASIC.

Долгосрочный интерфейсный контракт проекта:

- параметрическая разрядность N;
- unsigned first, затем общий signed/truncation-toward-zero путь;
- AXI4-Lite slave с 32-bit WDATA/WSTRB;
- start, busy/lockout, done, quotient, remainder, error;
- dividend=0 при divisor!=0 даёт q=0, r=0;
- divisor=0 даёт error=1, q=0, r=0;
- reset проверяется отдельным тестом;
- cocotb/iverilog, directed и random tests.

Текущий synthesis milestone намеренно уже: это нормализованная 64-bit primitive, а не полный AXI4-Lite wrapper. Нормализация, общий двухсловный numerator и AXI-регистры пока находятся за пределами kernel comparison и не должны выдаваться за реализованные функции.

Главное правило остановки: до реального synthesis/STA/physical comparison не создавать новые математические версии V45/V46 и не объявлять победителя.

## 2. Математическая линия

Исходная идея пришла из точной reciprocal-инварианты. Для точности t:

    2^(64+t) = n_t D + r_t, 0 <= r_t < D

Точный self-lift строится через остаток и bounded correction. После этого были последовательно исследованы low-ROM predictor, direct two-stage cold divider, fused PREP/FINAL, signed redundant cut, radix-4 Booth, CSA-to-radix-4 recoding, 7-state prefix и arrival-aware scheduling.

Последний audit уточнил, что exact PREP correction равен `0..4`, а не
консервативному `0..5`. Witness correction=4:
`D=9232379236109516801`; witness correction=0:
`D=9340465626629537792`. Это tightening той же V44 mathematics.

Ключевая signed-safe V43 identity:

    N = s + c + o*2^80
    p = floor(N/2^46) - 1
    p = A + delta
    delta = carry_low - 1, delta in {-1,0}

Для valid predictor range joint radix-4 representation даёт ровно 17 main signed rows; top product row не нужна. Это математическое утверждение подтверждено отдельным audit; physical kernel data измеряет текущую generic-reducer реализацию, а не proof-level packed matrix.

## 3. Кандидаты, роли и честная граница реализации

| Кандидат | Идея | Роль сейчас |
| --- | --- | --- |
| V36RCM + V34DX + V35FF | signed-safe binary redundant cut, dual-fused PREP и fused FINAL | главный low-latency control |
| V39C42 | separate signed radix-4 Booth, затем fixed 3:2 row tree в текущем RTL | отдельный Booth control |
| V43SJ17 | joint radix-4, 7-state thermometer prefix, 17 rows | mathematically preferred / area-wiring candidate |
| V44WAVE | arrival-aware scheduling bound | timing-bound study, не четвёртый RTL candidate |

В журнале V37 уменьшил analytical matrix с 66 до примерно 35 Booth rows; V38 пытался слить correction/delta; V39 уточнил exact column height 36 и что generic 4:2 сам по себе не даёт выигрыша; V40 показал ограниченный выигрыш fused parity; V41/V42 вывели joint carry-save radix-4 и 7-state prefix. После найденного signed-CSA gap сначала был доказан V43, и только затем сделан V44 timing bound.

Ограничения текущего RTL:

- V39 — Booth плюс generic 3:2 reducer, не доказанная column-packed 4:2 matrix;
- V43 — явный 7-state prefix и 17 rows, но generic row reducer, не компактная proof-level correction-dot/Dadda implementation;
- common FINAL ещё содержит inferred multiplication и не является полной побитовой реализацией V35 heap;
- kernel inputs Pred_Wrap и другие predictor-boundary сигналы в isolated comparison не полностью ограничены formal proof.

## 4. Что уже есть в GitHub

Репозиторий: https://github.com/aolpochta2-creator/chatgpt

- public repository, ветка main;
- фактическая запись в GitHub подтверждена несколькими успешными commit;
- PREP5 functional/proof commit:
  `ee7cd589dc56ca1d3414bbd39dbe65d540cec589`;
- финальный successful paired EDA commit/run:
  `e53bb9e3e6530110715e88ad6ffd3931f9e4cb4b` / `33963084077`;
- PREP5 physical commit/run:
  `8af456f6feb5f80556d37e778cae7a98ffab7f1d` / `33963569490`;
- canonical same-run PREP6/PREP5 primary commit/run:
  `0ea49ea973c964ccc35f106c4cb1b7c1d89f4fd0` / `33973681605`;
- parser fix и successful V43 seed-check commit/run:
  `26494445f38875a28c76c10d7b69019cff36ee5f` / `33975505349`;
- последний physical-sweep code head до reporting:
  `2efb847b065f96e244db3b2c5a1032564a1a57e8`;
- handoff-файл и его уточнения уже закоммичены в main; ссылку на актуальный main см. в заголовке/репозитории;
- последние commits добавили README, RTL/CI, common OpenSTA, physical audit, pinned toolchain и диагностические логи.

Основные файлы:

- rtl/hz_product_v36.sv, rtl/hz_product_v39.sv, rtl/hz_product_v43.sv;
- rtl/hz_kernel_top.sv, rtl/hz_divider_core.sv, rtl/hz_prep.sv, rtl/hz_final.sv, rtl/hz_predictor_csa.sv;
- model/hz_model.py;
- scripts/validate_model.py, scripts/validate_structure.py, scripts/run_sim.sh;
- scripts/run_synth.sh, scripts/sta.tcl;
- .github/workflows/eda.yml — единый compile/simulation/Yosys/ABC/OpenSTA flow;
- .github/workflows/physical.yml — controlled physical kernel audit;
- physical/config.mk, constraints.sdc, baseline.tcl, run.sh, report.tcl, validate_reports.py, image.txt.
- docs/PHYSICAL_SWEEP_V44.csv — исторический 29-row PREP6 physical dataset;
- docs/PHYSICAL_PREP5_V44.csv — три новые PREP5 physical measurements;
- docs/PHYSICAL_PREP_PAIRED_V44.csv — controlled primary и seed-check dataset;
- docs/MATH_AUDIT_V44_PREP_TIGHTENING.md — theorem и endpoint witnesses.

Архитектурная спецификация: docs/ARCHITECTURE.md.

## 5. Функциональная и математическая проверка

В текущем зелёном CI run `33963084077`:

- model: 100,012 exact normalized divisions, включая directed correction=4/0;
- structural model: 200,000 signed-cut/V36/V39/V43 identities;
- каждый полный divider top компилируется Icarus Verilog и проходит 263
  back-to-back legal vectors: 13 directed/boundary + 250 deterministic random;
- отдельный simultaneous test подтверждает exact V36/V39/V43 equivalence на
  259 back-to-back vectors;
- Yosys/ABC и OpenSTA запускаются на одной Nangate45 typical Liberty и
  сравнивают PREP5 с frozen PREP6 в тех же jobs.

Исторические analytical checks журнала: V36 — 1,204,184 full divisions и 1,000,000 identities; V37 — 1,000,000 Booth products и 500,000 identities; V39 — 1,500,000 arithmetic checks плюс 32 exhaustive 4:2 cases; V41 — 1,000,384 products; V42 — 49/49 state compositions и 1,000,064 recoder tests; V43 — 1,000,000 signed-cut identities и 600,000 actual signed-CSA predictor tests. Это математические evidence, а не замена RTL/STA.

## 6. Первый общий mapped synthesis/STA checkpoint

Результаты относятся только к variant-specific signed cut-product kernel: от V33 predictor CSA boundary до зарегистрированного V34 candidate output. Common ROM/predictor/FINAL исключены из area/STA kernel comparison; полные tops при этом compile/sim проверяются.

Frozen mapped checkpoint: GitHub Actions run 33873719618, source commit c5ad54288c14f977506c9471b88445d2bd85af1b.

| Kernel | Cells | Area, um² | Data arrival, ns | Worst slack at 10 ns, ns | Derived Tmin, ns | Derived Fmax, MHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 55,630 | 63,203.994 | 5.6386 | 4.3221 | 5.6779 | 176.1 |
| V39C42 | 38,701 | 46,533.774 | 5.4867 | 4.4784 | 5.5216 | 181.1 |
| V43SJ17 | 17,599 | 21,837.004 | 5.9564 | 4.0077 | 5.9923 | 166.9 |

У всех трёх kernel одинаковые 168 DFFR_X1. При старом mapped SDC output load был записан как 0.005, что в Nangate45 означает 0.005 fF, а не 0.005 pF. Поэтому таблица — исторический cell-only checkpoint, не post-route Fmax. V43 лидирует по area, V39 — по cell-only timing; это не даёт права объявить победителя.

## 7. Что выяснил физический audit

Новый physical SDC исправляет load на 5 fF = 0.005 pF, задаёт 10 ns clock, input transition 0.05 ns, zero input/output delay, max fanout 20, max transition 0.20 ns и reset false path. Все варианты используют один и тот же die 520×520 um, core 500×500 um и placement density 0.45.

Сырые STA reports показывают тяжёлый unbuffered fanout: самый длинный single-cell arc — 1.8044 ns при fanout 247 для V36, 1.6208 ns при fanout 127 для V39 и 1.7178 ns при fanout 127 для V43. Это причина сначала проверить физическую буферизацию/маршрутизацию.

Physical flow импортирует frozen mapped netlist, материализует только constants в tie cells, затем запускает pinned official ORFS finish: floorplan, placement, CTS, post-CTS `repair_timing`, global route, detailed route, OpenRCX SPEF и final STA. Платформа Nangate45 зафиксирована ORFS commit 0c914a7471340da86058dfe4d25d537f0282a508; Docker image зафиксирован digest sha256:751a77afcade9882b51427e6d9d079b8e270e7a8f4aa66df2d0659457d1c29fd. `LEC_CHECK=0` отключает только Kepler LEC из-за AVX-512 crash и не отключает timing repair.

## 8. Исправленный physical baseline @ 10 ns

Подтверждённый baseline — commit
`fcf1e843a0dc6032a6208034e8b4d84d70250e14`,
[Actions run 33951165094](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33951165094).
Все jobs завершились success; post-CTS `repair_timing` реально вызван по одному
разу для V36/V39/V43. Для каждого kernel присутствуют final ODB, DEF, GDS,
Verilog netlist, SDC и nonempty SPEF.

| Kernel | Logical cells | Logical area, um² | Max data arrival, ns | Setup, ns | Hold, ns | Max-cap | Wire, um | Vias |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 58,318 | 65,615.550 | 4.9745 | +5.1915 | +0.0573 | 0 | 653,970 | 376,765 |
| V39C42 | 41,145 | 48,675.340 | 5.3119 | +4.8362 | +0.0240 | 12 | 658,374 | 314,069 |
| V43SJ17 | 18,754 | 22,823.864 | 5.0972 | +5.0363 | +0.0216 | 0 | 287,112 | 136,397 |

Setup TNS, max-transition, max-fanout, detailed-route DRC и antenna равны нулю
для всех. V36/V43 имеют полную reported electrical closure; V39 остаётся
reference с 12 max-cap violations.

## 9. Calibrated physical period sweep завершён

Каждый period прошёл отдельный полный placement-to-SPEF/STA flow. Старую
разводку ни для одной новой SDC не использовали. RTL, математика, frozen mapped
kernels, platform, die/core, density, transition/load/fanout/reset constraints
не менялись.

| Этап | Commit | Actions run | Точки |
| --- | --- | ---: | --- |
| coarse | `a8e3e327b5172952ddddb4c48a1eed7ba2fd669a` | [33953087457](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33953087457) | V36/V39/V43: 6.0, 5.5, 5.0, 4.5 ns |
| lower coarse | `a5a9e1cf39e0e1bbc2c8ed28ceccce9460e55dbf` | [33954252869](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33954252869) | V36/V43: 4.0, 3.5, 3.0 ns |
| refinement 0.1 | `9962ce98a0071f45883fb9221bb5082b972f6359` | [33955844721](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33955844721) | V36/V43: 3.1–3.4 ns |
| refinement 0.05 | `2efb847b065f96e244db3b2c5a1032564a1a57e8` | [33957430113](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33957430113) | V36: 3.25/3.45; V43: 3.15 ns |

Все четыре runs и все 29 physical jobs имеют Actions conclusion success как
валидные measurements. Во всех jobs: 168 DFF, post-CTS `repair_timing` вызван,
hold проходит, max-transition/max-fanout/DRC/antenna = 0, все final artifacts
присутствуют. Timing/electrical fail отмечается внутри summary и не смешивается
с infrastructure failure. Полная таблица с job IDs, arrival, TNS, area,
buffers, wire/vias и размерами artifacts сохранена в
`docs/PHYSICAL_SWEEP_V44.csv`.

| Kernel | Реальный bracket | Physical Tmin | Fmax | Setup @ Tmin | Hold | Max-cap | Area, um² | Wire, um | Vias |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 3.20 fail / 3.25 pass | 3.25 ns | 307.69 MHz | +0.0086 ns | +0.0500 ns | 0 | 71,996.358 | 699,584 | 398,246 |
| V43SJ17 | 3.10 fail / 3.15 pass | 3.15 ns | 317.46 MHz | +0.0002 ns | +0.0298 ns | 0 | 28,425.026 | 308,005 | 154,402 |

Fmax рассчитан только как `1000 / реально пройденный Tmin(ns)`. Значения
`10 ns - slack` для этого не использовались.

V43 имеет на 3.08% меньший Tmin и на 3.17% больший measured Fmax. В точках
собственного Tmin V43 меньше V36 на 60.52% по logical area, на 55.97% по
routed wire и на 61.23% по vias. На общем strict-pass period 3.5 ns V43 также
имеет лучший setup slack: +0.0716 против +0.0387 ns.

Следовательно, прежняя physical Pareto-пара "V36=timing, V43=area/wiring" не
сохраняется среди двух полностью swept kernels: в этом isolated Nangate45
single-corner flow V43 лидирует и по частоте, и по физическому размеру. Это не
объявление нового математического или end-to-end divider winner.

V39 остаётся reference/control. На coarse grid 6.0–4.5 ns setup/hold проходит,
но max-cap counts равны 13/3/13/6; ни одной strict electrical pass точки нет.
Его собственный Tmin не уточнялся, поэтому V39 Fmax и строгая timing-доминация
не заявляются. По area/wiring и electrical closure он остаётся существенно
хуже V43 на измеренных точках.

## 10. Измерение PREP5

Paired mapped evidence: commit
`e53bb9e3e6530110715e88ad6ffd3931f9e4cb4b`, successful run `33963084077`.
Frozen PREP6 commit `fd4b23addc2e46a75d83a52f125b63656964c814`
и текущий PREP5 были mapped одним Yosys 0.33/ABC и проверены одним pinned
OpenSTA.

| Kernel | PREP6 -> PREP5 cells | PREP6 -> PREP5 area, um² | Arrival delta |
| --- | --- | --- | ---: |
| V36 | 55,630 -> 54,618 | 63,203.994 -> 62,285.496 | +0.0394 ns |
| V39 | 38,701 -> 37,990 | 46,533.774 -> 45,719.016 | +0.0040 ns |
| V43 | 17,599 -> 17,106 | 21,837.004 -> 21,120.400 | -0.0687 ns |

Все варианты сохранили 168 DFF и setup TNS=0 при mapped 10 ns. Изолированный
kernel получает один `Candidate_K`, поэтому эти дельты измеряют удаление
`M=5` из candidate-path mux, а не полную площадь одной из шести параллельных
ветвей внутри `hz_prep`. Полные tops функционально симулируются. Попытка
standard-cell mapping полного top в run `33961763954` была отменена как
неразумно дорогая из-за разворачивания common ROM; это infrastructure/cost
boundary, не arithmetic fail.

Narrow physical evidence: commit
`8af456f6feb5f80556d37e778cae7a98ffab7f1d`, successful measurement run
`33963569490`.

| Point | Setup | Hold | Max-cap | Area, um² | Wire, um | Vias | Strict result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| V36 @ 3.25 | -0.0538 | +0.0307 | 0 | 73,608.052 | 642,838 | 393,661 | setup fail |
| V43 @ 3.20 | +0.0472 | +0.0227 | 2 | 26,131.840 | 294,633 | 143,788 | electrical fail |
| V43 @ 3.15 | +0.0512 | +0.0150 | 1 | 26,604.256 | 297,279 | 145,818 | electrical fail |

Во всех трёх jobs: max-transition=0, max-fanout=0, detailed-route DRC=0,
antenna=0, post-CTS `repair_timing` выполнен, final ODB/DEF/GDS/netlist/SDC/SPEF
присутствуют. V36 setup TNS=-0.1787 ns; остальные setup/hold TNS нулевые.

Новый PREP5 Tmin/Fmax не заявляется. Условие для V43@3.10 не выполнено,
поскольку 3.15 не является strict pass; 3.10/3.05 не запускались. V39 не
перезапускался физически и остаётся reference/control.

## 11. Controlled PREP6/PREP5 reproducibility завершён

Commit `0ea49ea973c964ccc35f106c4cb1b7c1d89f4fd0` создаёт build-only PREP6
control и шеститочечную paired matrix. Production PREP5 RTL не менялся.
PREP6 reference — literal old kernel, где относительно PREP5 восстановлен
только case `M=5`; Git blob зафиксирован как
`0f366d5ffea469f843e6c5d911e597f772443601`. Joint Icarus test прошёл 640
legal pairs и отдельную проверку M=5. Обе стороны получают одинаковое имя top,
один Yosys 0.33 mapping job и отдельный полный physical flow.

Same-run mapped data:

| Kernel | PREP6 cells / area | PREP5 cells / area |
| --- | ---: | ---: |
| V36 | 55,697 / 63,263.844 um² | 54,618 / 62,285.496 um² |
| V43 | 17,599 / 21,837.004 um² | 17,106 / 21,120.400 um² |

Primary run `33973681605`, seed=1:

| Point | Mode | Setup | Hold | TNS setup/hold | Max-cap/tran/fanout | Cells | Area, um² | Wire, um | Vias | Strict result |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| V36@3.25 | PREP6 | +0.0171 | +0.0465 | 0 / 0 | 1 / 0 / 1 | 68,644 | 75,422.970 | 732,397 | 410,614 | electrical fail |
| V36@3.25 | PREP5 | -0.0347 | +0.0292 | -0.0856 / 0 | 0 / 0 / 0 | 66,557 | 73,611.510 | 642,746 | 393,682 | setup fail |
| V43@3.20 | PREP6 | +0.0265 | +0.0194 | 0 / 0 | 0 / 0 / 0 | 24,445 | 28,123.648 | 307,596 | 153,938 | pass |
| V43@3.20 | PREP5 | +0.0437 | +0.0222 | 0 / 0 | 2 / 0 / 0 | 22,444 | 26,131.840 | 294,548 | 143,752 | electrical fail |
| V43@3.15 | PREP6 | +0.0006 | +0.0187 | 0 / 0 | 0 / 0 / 0 | 24,707 | 28,334.586 | 307,877 | 154,139 | pass |
| V43@3.15 | PREP5 | +0.0480 | +0.0156 | 0 / 0 | 1 / 0 / 0 | 22,916 | 26,605.054 | 297,259 | 145,674 | electrical fail |

Все шесть implementations дошли до final ODB/DEF/GDS/netlist/SDC/SPEF,
DRC=0, antenna=0, post-CTS `repair_timing` выполнен. Общий conclusion run —
failure только потому, что первый parser не принял целое значение `-2` в
max-fanout строке V36 PREP6. Raw artifact полный; исправленный parser
восстановил валидную measurement выше. Исправление и seed trigger находятся в
commit `26494445f38875a28c76c10d7b69019cff36ee5f`.

Главные paired PREP5-PREP6 дельты:

- V36@3.25: setup -0.0518 ns, area -2.40%, wire -12.24%, vias -4.12%; PREP5
  требует на 18 больше CTS setup buffers и на 17 больше GRT setup buffers.
- V43@3.20: setup +0.0172 ns, area -7.08%, wire -4.24%, vias -6.62%; residual
  max-cap меняется 0 -> 2.
- V43@3.15: setup +0.0474 ns, area -6.10%, wire -3.45%, vias -5.49%; residual
  max-cap меняется 0 -> 1.

Mapped structural diagnostic объясняет V36: несмотря на меньшие load/cells,
unweighted max combinational depth до DFF меняется 89 -> 96. У V43 она
остаётся 97 -> 97. Critical startpoints также меняются: V36 `D[1]` -> `X[2]`,
V43 `X[0]` -> `X[3]`. Это глобальная ABC/placement/repair topology change, не
простое вычитание одного mux leaf.

Поскольку V43@3.15 closure различалась, run `33975505349` проверил PREP6/PREP5
с seed 1 и 2. `GPL_RANDOM_SEED`, `GRT_SEED`, `OR_SEED` реально видны в logs.
Run и все четыре jobs — success.

| Mode | Seed | Setup | Hold | Max-cap/tran/fanout | Area, um² | Wire, um | Vias | Strict result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| PREP6 | 1 | +0.0006 | +0.0187 | 0 / 0 / 0 | 28,334.586 | 307,877 | 154,139 | pass |
| PREP5 | 1 | +0.0480 | +0.0156 | 1 / 0 / 0 | 26,605.054 | 297,259 | 145,674 | electrical fail |
| PREP6 | 2 | +0.0275 | +0.0193 | 0 / 0 / 0 | 28,383.530 | 307,313 | 154,061 | pass |
| PREP5 | 2 | +0.0547 | +0.0280 | 0 / 0 / 0 | 26,536.160 | 295,716 | 145,641 | pass |

Seed-1 repeat воспроизводит все physical metrics и artifact byte sizes точно.
Seed 2 убирает PREP5 max-cap residual. PREP5 setup advantage сохраняется при
обоих seeds (+47.4 ps и +27.2 ps), но spread 20.2 ps сравним с PREP6 setup
scatter 26.9 ps. Area benefit стабилен 6.10-6.51%, wire 3.45-3.77%, vias
5.46-5.49%. Значит PREP5 residual electrical fail — physical scatter, а не
устойчивый regression; Fmax improvement при этом не доказан.

PREP5 остаётся engineering baseline: это минимальная точная математика и
стабильно меньшая реализация. Один strict-clean PREP5@3.15 seed=2 существует,
но seed=1 не clean и PREP5@3.10 не запускался. Новый robust Tmin/Fmax не
объявляется; исторические PREP6 3.25/307.69 MHz и 3.15/317.46 MHz не
переписываются как PREP5 results.

Полный dataset: `docs/PHYSICAL_PREP_PAIRED_V44.csv`.

## 12. Caveats и следующая инженерная точка

- Это isolated product-kernel boundary, не полный divider и не AXI wrapper.
- Только Nangate45 typical corner; нет PVT/OCV, power/IR/EM и foundry signoff.
- V39 остаётся reference/control и в paired experiment не запускался.
- PREP6 control измеряет только восстановление M=5 внутри kernel path, а не
  физическую площадь шестой параллельной branch полного PREP.
- Fixed-seed flow детерминирован, но strict electrical closure V43@3.15
  чувствительна к seed. Нельзя выбирать лучший seed и называть это robust Fmax.
- Текущий V39 остаётся generic 3:2 row tree, текущий V43 — generic row reducer;
  proof-level packed/Dadda структуры журналом доказаны не полностью в RTL.
- V44WAVE остаётся timing-bound study. `g_L` не внедрён; V45/V46 не создавались.

Повторный Tmin search не нужен для выбора engineering baseline: PREP5 уже
остаётся им. Если проекту понадобится новый PREP5 frequency claim, сначала
нужно определить критерий — один routed instance или closure на заранее
объявленном seed set — и только затем сделать узкий boundary run. До этого не
переходить к 3.10 и не смешивать работу с новой математикой.

## 13. Готовый блок для вставки в новый чат

    Продолжаем R&D exact integer divider в https://github.com/aolpochta2-creator/chatgpt. Канонический контекст: docs/CHAT_HANDOFF_V44_2026-09-05.md.

    Математика V44 остаётся неизменной: PREP correction exact 0..4, p+5 никогда не выбирается, FINAL остаётся 0..3. PREP5 — production/engineering baseline. g_L не внедрять, V45/V46 не создавать, predictor/cut=46/t=32/V43 recoder не менять.

    Controlled same-run PREP6/PREP5 experiment: canonical primary commit 0ea49ea973c964ccc35f106c4cb1b7c1d89f4fd0, run 33973681605. Production PREP5 RTL byte-identical исходному baseline; PREP6 — build-only literal reference с единственным восстановленным M=5 case. Joint Icarus control test: 640 legal pairs plus M=5. Same-run mapped: V36 55697/63263.844 -> 54618/62285.496 cells/um²; V43 17599/21837.004 -> 17106/21120.400.

    Primary physical seed=1: V36@3.25 PREP6 setup +0.0171/hold +0.0465, max-cap=1, max-fanout=1; PREP5 setup -0.0347/TNS -0.0856, hold +0.0292, electrical clean. V43@3.20 PREP6 strict pass +0.0265/+0.0194; PREP5 +0.0437/+0.0222, max-cap=2. V43@3.15 PREP6 strict pass +0.0006/+0.0187; PREP5 +0.0480/+0.0156, max-cap=1. DRC/antenna/max-transition=0 и final artifacts полные во всех jobs. V36 PREP6 job красный только из-за parser integer-slack bug после полного flow; measurement восстановлена из raw artifact.

    PREP5-PREP6 primary deltas: V36 setup -0.0518 ns, area -2.40%, wire -12.24%; V43@3.20 setup +0.0172 ns, area -7.08%, wire -4.24%; V43@3.15 setup +0.0474 ns, area -6.10%, wire -3.45%. V36 mapped DAG стал глубже 89->96 stages; V43 остался 97->97. Поэтому PREP5 не даёт универсального timing gain, но size/wiring benefit устойчив.

    Parser/seed-check commit 26494445f38875a28c76c10d7b69019cff36ee5f, successful run 33975505349. V43@3.15: PREP6 seed1 +0.0006/clean, seed2 +0.0275/clean; PREP5 seed1 +0.0480/max-cap1, seed2 +0.0547/strict clean. Seed1 repeat воспроизводится точно. PREP5 timing advantage сохраняется +47.4/+27.2 ps, area меньше на 6.10-6.51%, wire на 3.45-3.77%. Max-cap flip доказывает seed-sensitive physical scatter, не устойчивый PREP5 regression.

    PREP5 остаётся engineering baseline, но новый robust Tmin/Fmax не объявлять: clean PREP5@3.15 есть только при seed2, seed1 electrical-fail, 3.10 не тестировался. Исторические PREP6 Tmin/Fmax V36=3.25 ns/307.69 MHz и V43=3.15 ns/317.46 MHz не relabel. Новый Tmin search сейчас не нужен; возвращаться к нему только после явного определения single-instance vs multi-seed closure criterion.

    Полные данные: docs/PHYSICAL_AUDIT_V44.md и docs/PHYSICAL_PREP_PAIRED_V44.csv. Не переходить к g_L, новой precision/cut, V43 restructure или V45/V46.

Источники: приложенный division_algorithm_research_log_v44(1).txt,
docs/ARCHITECTURE.md, docs/RESULTS_V44_SYNTHESIS.md,
docs/PHYSICAL_AUDIT_V44.md, docs/PHYSICAL_SWEEP_V44.csv,
docs/PHYSICAL_PREP5_V44.csv, docs/PHYSICAL_PREP_PAIRED_V44.csv,
docs/MATH_AUDIT_V44_PREP_TIGHTENING.md и raw GitHub Actions reports.
