# Exact integer divider — handoff-журнал V44 → physical audit

Дата среза: 2026-09-05

Это канонический handoff для продолжения R&D exact integer divider в новом чате. Он объединяет приложенный журнал V44 с фактическим состоянием GitHub, RTL, CI, synthesis/STA и physical-flow.

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

Ключевая signed-safe V43 identity:

    N = s + c + o*2^80
    p = floor(N/2^46) - 1
    p = A + delta
    delta = carry_low - 1, delta in {-1,0}

Для valid predictor range joint radix-4 representation даёт ровно 17 main signed rows; top product row не нужна. Это математическое утверждение проверено отдельно, но его timing/area ещё не подтверждены физическим flow.

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
- docs/PHYSICAL_SWEEP_V44.csv — полный 29-row physical dataset.

Архитектурная спецификация: docs/ARCHITECTURE.md.

## 5. Функциональная и математическая проверка

В текущем зелёном CI:

- model: 100,004 exact normalized divisions;
- structural model: 200,000 signed-cut/V36/V39/V43 identities;
- каждый полный divider top компилируется Icarus Verilog и проходит одинаковые 5 directed + 25 deterministic pseudo-random vectors;
- Yosys/ABC и OpenSTA запускаются на одной Nangate45 typical Liberty.

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

## 10. Caveats и следующая инженерная точка

- Это isolated product-kernel boundary, не полный divider и не AXI wrapper.
- Только Nangate45 typical corner; нет PVT/OCV, power/IR/EM и foundry signoff.
- V43@3.15 имеет всего +0.0002 ns setup margin, поэтому 317.46 MHz —
  grid-defined measurement, а не robust operating target. 3.20 ns даёт более
  практичный measured margin +0.0468 ns.
- V36 электрически немонотонна: 3.45/3.40/3.30 ns имеют по одному small max-cap
  residual, но независимо перестроенная 3.25 ns точка чистая. Не интерполировать
  electrical closure между периодами.
- Текущий V39 остаётся generic 3:2 row tree, текущий V43 — generic row reducer;
  proof-level packed/Dadda структуры журналом доказаны не полностью в RTL.
- V44WAVE остаётся timing-bound study. V45/V46 не создавались.

Следующий разумный этап — не новая математика, а robustness: выбрать 3.20 ns
как рабочую V43 point либо повторить boundary на дополнительных corners/seeds,
затем при необходимости расширить timing boundary до полного divider. Только
после этого решать, нужна ли proof-faithful compact V43 reducer RTL.

## 11. Готовый блок для вставки в новый чат

    Мы продолжаем R&D exact integer divider. Канонический контекст: docs/CHAT_HANDOFF_V44_2026-09-05.md в https://github.com/aolpochta2-creator/chatgpt.

    Сравниваем V36RCM+V34DX+V35FF, V39C42 и V43SJ17; V44WAVE остаётся timing-bound study. RTL/математика не менялись, V45/V46 не создавались. Frozen mapped kernels взяты из Actions run 33873719618.

    Исправленный 10 ns baseline: commit fcf1e843a0dc6032a6208034e8b4d84d70250e14, run 33951165094. Post-CTS repair_timing включён и реально выполняется. LEC_CHECK=0 отключает только Kepler LEC из-за AVX-512 crash. V36/V43 имеют max-cap=0; V39 остаётся reference с 12 max-cap.

    Calibrated full physical sweep завершён. Runs: coarse 33953087457, lower coarse 33954252869, refinement 0.1 ns 33955844721, refinement 0.05 ns 33957430113. Каждый period заново прошёл placement, CTS, post-CTS repair, global/detailed route, OpenRCX SPEF и final STA. Все 29 jobs завершились success как measurements; infrastructure failures не было; все final ODB/DEF/GDS/netlist/SDC/SPEF присутствуют.

    Итог: V36 strict physical Tmin=3.25 ns, Fmax≈307.69 MHz, bracket 3.20 fail/3.25 pass, setup +0.0086 ns, hold +0.0500 ns, area 71,996.358 um², wire 699,584 um, vias 398,246. V43 Tmin=3.15 ns, Fmax≈317.46 MHz, bracket 3.10 fail/3.15 pass, setup +0.0002 ns, hold +0.0298 ns, area 28,425.026 um², wire 308,005 um, vias 154,402. Electrical/DRC/antenna at обеих Tmin точках равны 0.

    V43 быстрее V36 по measured Fmax на 3.17%, меньше по area на 60.52% и по wire на 55.97%. Поэтому прежняя Pareto-пара V36=timing/V43=area не сохраняется среди полностью swept kernels: isolated physical data ставит V43 впереди по обоим направлениям. Это не mathematical/end-to-end/PVT winner; V43@3.15 имеет всего 0.2 ps setup margin, практичнее считать 3.20 ns подтверждённой point с +0.0468 ns.

    V39 запускался как coarse control на 6.0/5.5/5.0/4.5 ns: timing проходит, max-cap=13/3/13/6, strict pass нет. V39 Tmin/Fmax не измерен, поэтому строгую timing-доминацию не заявлять; оставить reference.

    Полные данные: docs/PHYSICAL_AUDIT_V44.md и docs/PHYSICAL_SWEEP_V44.csv. Следующий этап — robustness/multi-corner или full-divider physical boundary, не V45.

Источники: приложенный division_algorithm_research_log_v44(1).txt,
docs/ARCHITECTURE.md, docs/RESULTS_V44_SYNTHESIS.md,
docs/PHYSICAL_AUDIT_V44.md, docs/PHYSICAL_SWEEP_V44.csv и raw GitHub Actions
reports.
