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
- последний кодовый baseline до handoff: 803aad755dd666854c70fefbb535ebffc979c8ca;
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

Physical flow импортирует frozen mapped netlist, материализует только constants в tie cells, затем запускает pinned official ORFS finish: floorplan, placement, CTS, route, detailed route, OpenRCX SPEF и final STA. Платформа Nangate45 зафиксирована ORFS commit 0c914a7471340da86058dfe4d25d537f0282a508; Docker image зафиксирован digest sha256:751a77afcade9882b51427e6d9d079b8e270e7a8f4aa66df2d0659457d1c29fd.

## 8. Routed physical checkpoint завершён

Диагностический workaround `SKIP_CTS_REPAIR_TIMING=1` добавлен commit
`52b78eb583e24387c63ce914f02b7c88e0f6d918`. Он отключает только падающий
post-CTS timing-repair helper. CTS, global-route repair, detailed route,
OpenRCX extraction и final STA остаются включёнными. Отдельный commit
`a0a213268ff571fefc2ae830f88da8713966affc` исправил несовместимый с pinned
OpenROAD вызов `report_units`.

[Physical run 33949336084](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33949336084)
завершился успешно для V36, V39 и V43. Для каждого варианта сохранены final
ODB, DEF, GDS, Verilog netlist, SDC, nonempty OpenRCX SPEF, setup/hold и
electrical reports. Все варианты сохранили 168 DFF.

| Kernel | Logical cells | Logical area, um² | Max data arrival, ns | Setup slack @ 10 ns, ns | Hold slack, ns | Max-cap violations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 58,318 | 65,615.550 | 4.9771 | 5.1888 | 0.0556 | 1 |
| V39C42 | 41,146 | 48,677.202 | 5.3126 | 4.8358 | 0.0223 | 11 |
| V43SJ17 | 18,754 | 22,823.864 | 5.1048 | 5.0287 | 0.0236 | 1 |

| Kernel | Routed wire, um | Vias | Detailed-route DRC | Antenna net/pin violations |
| --- | ---: | ---: | ---: | ---: |
| V36RCM | 653,873 | 376,623 | 0 | 0 / 0 |
| V39C42 | 658,451 | 314,336 | 0 | 0 / 0 |
| V43SJ17 | 287,235 | 136,321 | 0 | 0 / 0 |

Все три проходят setup и hold при фиксированном периоде 10 ns; max-path TNS
равен нулю. V36 имеет лучший setup margin. V43 лидирует по logical area и
routed wire и в этом implementation одновременно меньше и быстрее V39.
Measured physical Pareto pair: V36 по timing и V43 по area/wiring.

Это валидное физическое измерение, но не electrical signoff: оставшиеся
нарушения — max capacitance, 1/11/1 для V36/V39/V43. Validator корректно
выдаёт `PHYSICAL_MEASUREMENT_VALID_BUT_TIMING_OR_ELECTRICAL_NOT_CLOSED`.
Кроме того, post-CTS timing repair был пропущен, PVT sweep и power analysis не
проводились, а boundary остаётся isolated kernel, не end-to-end divider.

## 9. Следующая инженерная точка

1. Считать run 33949336084 первым общим routed/SPEF-aware checkpoint и не
   смешивать его с исторической unbuffered mapped-таблицей.
2. Перед новым архитектурным выводом закрыть одинаковым способом max-cap
   violations или повторить flow с рабочим post-CTS repair build.
3. После electrical cleanup провести калиброванный sweep period, если нужен
   сравнительный physical Tmin. Значения `10 ns - slack` сами по себе не
   являются re-optimized Fmax.
4. Если работа возвращается к RTL fidelity, отдельно реализовать и измерить
   explicit column-packed/4:2 V39 и compact correction-dot/Dadda V43. Текущий
   V39 использует generic 3:2 row tree, текущий V43 — generic row reducer.
5. V44WAVE сохранять как timing-bound study. Не вводить новую математическую
   версию без измеримого инженерного вопроса и одинакового validation flow.

## 10. Готовый блок для вставки в новый чат

    Мы продолжаем R&D exact integer divider. Канонический контекст: docs/CHAT_HANDOFF_V44_2026-09-05.md в https://github.com/aolpochta2-creator/chatgpt.

    Сравниваем V36RCM+V34DX+V35FF, V39C42 и V43SJ17 одинаковым flow; V44WAVE остаётся timing-bound study.

    Общий routed/OpenRCX checkpoint завершён: GitHub Actions run 33949336084, flow commit a0a213268ff571fefc2ae830f88da8713966affc. CTS, detailed route и final SPEF-aware STA прошли для всех трёх; post-CTS timing-repair helper отключён через SKIP_CTS_REPAIR_TIMING=1 из-за воспроизводимого illegal-instruction crash.

    Physical результаты @10 ns: V36 58,318 logical cells / 65,615.550 um² / setup slack 5.1888 ns / hold 0.0556 ns; V39 41,146 / 48,677.202 / 4.8358 / 0.0223; V43 18,754 / 22,823.864 / 5.0287 / 0.0236. V36 — timing leader; V43 — area/wiring leader и быстрее V39 в этом run.

    Setup/hold, detailed-route DRC и antenna checks проходят. Electrical closure не завершён: max-cap violations V36/V39/V43 = 1/11/1. Не называть checkpoint signoff или end-to-end divider Fmax.

    Следующее действие: одинаково закрыть max-cap violations или перейти на рабочий post-CTS repair build; затем при необходимости сделать period sweep. Новую математическую версию пока не создавать.

Источники: приложенный division_algorithm_research_log_v44(1).txt,
docs/ARCHITECTURE.md, docs/RESULTS_V44_SYNTHESIS.md,
docs/PHYSICAL_AUDIT_V44.md и raw GitHub Actions reports.
