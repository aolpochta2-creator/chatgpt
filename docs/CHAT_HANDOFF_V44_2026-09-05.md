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

Главный результат этого checkpoint: functional/model/mapped проверки зелёные,
но три новых physical точки не дали strict pass. Поэтому старые PREP6 Tmin/Fmax
сохраняются только как история, а новый PREP5 Tmin/Fmax пока не измерен.

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

## 11. Caveats и следующая инженерная точка

- Это isolated product-kernel boundary, не полный divider и не AXI wrapper.
- Только Nangate45 typical corner; нет PVT/OCV, power/IR/EM и foundry signoff.
- PREP6 V43@3.15 с +0.0002 ns и 317.46 MHz остаётся только исторической
  grid-defined measurement. PREP5 V43@3.15 имеет лучший setup, но один
  max-cap violation и потому не наследует этот Fmax.
- V36 электрически немонотонна: 3.45/3.40/3.30 ns имеют по одному small max-cap
  residual, но независимо перестроенная 3.25 ns точка чистая. Не интерполировать
  electrical closure между периодами.
- Текущий V39 остаётся generic 3:2 row tree, текущий V43 — generic row reducer;
  proof-level packed/Dadda структуры журналом доказаны не полностью в RTL.
- V44WAVE остаётся timing-bound study. V45/V46 не создавались.

Следующий разумный этап — не новая математика: сначала решить, нужен ли
controlled reproducibility/electrical-closure rerun тех же PREP5 points или
новый узкий bracket (например, V36 выше 3.25). Не объявлять новый Tmin до
реального strict pass и не смешивать этот шаг с `g_L`, новым cut/precision или
переделкой V43.

## 12. Готовый блок для вставки в новый чат

    Продолжаем R&D exact integer divider в https://github.com/aolpochta2-creator/chatgpt. Канонический контекст: docs/CHAT_HANDOFF_V44_2026-09-05.md.

    Текущий этап — tightening той же V44 mathematics: независимый audit доказал 0 <= floor(2^96/D)-p <= 4, оба края достижимы, p+5 никогда не выбирается. Functional commit ee7cd589dc56ca1d3414bbd39dbe65d540cec589 удалил только PREP k=5 и unreachable M=5. Predictor/p, Carry_Low, signed cut, cut=46, t=32, V43 recoder и FINAL 0..3 не менялись. g_L/FINAL 0..2 доказан как будущий experiment, но не реализован. V45/V46 не создавать.

    Directed witnesses: correction=4 при D=9232379236109516801; correction=0 при D=9340465626629537792. Model run проверил 100012 exact divisions и 200000 structural identities. Каждый full top прошёл 263 back-to-back vectors; direct V36/V39/V43 equivalence прошла 259 vectors.

    Successful paired EDA: commit e53bb9e3e6530110715e88ad6ffd3931f9e4cb4b, run 33963084077. Frozen PREP6 baseline fd4b23addc2e46a75d83a52f125b63656964c814 и PREP5 mapped одним Yosys 0.33/ABC и одним pinned OpenSTA. Cells/area: V36 55630/63203.994 -> 54618/62285.496; V39 38701/46533.774 -> 37990/45719.016; V43 17599/21837.004 -> 17106/21120.400. Arrival delta: V36 +0.0394 ns, V39 +0.0040 ns, V43 -0.0687 ns. DFF=168, mapped setup TNS=0 у всех.

    Narrow physical: commit 8af456f6feb5f80556d37e778cae7a98ffab7f1d, run 33963569490. Все jobs success как measurements и прошли полный placement/CTS/post-CTS repair/route/OpenRCX/final STA; artifacts ODB/DEF/GDS/netlist/SDC/SPEF полные. Но strict passes нет: V36@3.25 setup=-0.0538, TNS=-0.1787, hold=+0.0307, electrical clean; V43@3.20 setup=+0.0472, hold=+0.0227, max-cap=2; V43@3.15 setup=+0.0512, hold=+0.0150, max-cap=1. Max-transition/fanout/DRC/antenna=0 везде.

    Старые V36 Tmin=3.25 ns/Fmax=307.69 MHz и V43 Tmin=3.15 ns/Fmax=317.46 MHz относятся только к PREP6 history. Для PREP5 новый Tmin/Fmax не измерен. Так как V43@3.15 не strict pass, 3.10/3.05 не запускались. V39 остаётся reference/control и физически на этом узком этапе не перезапускался.

    Важно: physical/mapped boundary kernel_v* получает один Candidate_K, поэтому измеряет removal M=5 в candidate-path mux, а не полную площадь удалённой параллельной ветви hz_prep. Full tops compile/sim подтверждены; full-top standard-cell mapping был остановлен как искусственно дорогой из-за ROM и не является arithmetic fail.

    Полные данные: docs/MATH_AUDIT_V44_PREP_TIGHTENING.md, docs/RESULTS_V44_SYNTHESIS.md, docs/PHYSICAL_AUDIT_V44.md, docs/PHYSICAL_SWEEP_V44.csv (PREP6 history), docs/PHYSICAL_PREP5_V44.csv (PREP5). Следующий шаг — только controlled physical robustness/electrical closure или узкий новый bracket, без g_L/нового cut/precision/V43 restructure.

Источники: приложенный division_algorithm_research_log_v44(1).txt,
docs/ARCHITECTURE.md, docs/RESULTS_V44_SYNTHESIS.md,
docs/PHYSICAL_AUDIT_V44.md, docs/PHYSICAL_SWEEP_V44.csv,
docs/PHYSICAL_PREP5_V44.csv, docs/MATH_AUDIT_V44_PREP_TIGHTENING.md и raw
GitHub Actions reports.
