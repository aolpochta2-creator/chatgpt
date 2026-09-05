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
- текущий main после добавления этого журнала: bda1d25be43fc70a324eba7a24df17f0eabf799f;
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

## 8. Текущий physical blocker

Последние попытки:

1. run 33944711386 — ранний сбой provenance: в Docker image нет .git для rev-parse;
2. run 33944899194 — после исправления provenance baseline не прочитал technology LEF;
3. run 33944984663 — после добавления tech/cell LEF placement завершился, но CTS helper упал с `child killed: illegal instruction`;
4. run 33945291301 — добавлены trace/toolchain diagnostics, но тот же CTS failure повторился для V36/V39/V43.

Последняя содержательная точка лога перед падением:

    No setup violations found
    Found 6 endpoints with hold violations.
    Error: cts.tcl, 83 child killed: illegal instruction

То есть route/SPEF/ODB/final extracted STA ещё не получены. Это не измеренная physical timing result и не timing closure.

Параллельный EDA regression run 33945086169 временно сломался после строгого Yosys check; commit 803aad7 исправил порядок загрузки Liberty/port directions, и последний обычный EDA run 33945386027 снова зелёный.

## 9. Точный следующий шаг

1. В physical/config.mk добавить диагностический workaround:

       export SKIP_CTS_REPAIR_TIMING = 1

   Это отключает падающий post-CTS timing-repair helper, но не отключает CTS, route или final OpenRCX/SPEF STA. В журнале явно пометить результат как physical routing/timing audit без post-CTS repair, если flow пройдёт.

2. Запустить physical workflow заново для всех трёх вариантов с теми же frozen netlists, floorplan, Liberty, ORFS image и SDC.

3. Если flow завершится, сохранить для каждого варианта final ODB, detailed route/V, SPEF, setup/hold slack, electrical violations, cell/area breakdown и physical summary. Сравнивать только одинаково измеренные данные.

4. Если следующий helper снова упадёт, взять полный job log и локализовать именно следующий failing command; не менять математику.

5. Только после реального physical comparison решать, нужны ли explicit 4:2/column-packed V39, compact V43 correction-dot matrix или дальнейшая версия. До этого V44WAVE остаётся bound study.

## 10. Готовый блок для вставки в новый чат

    Мы продолжаем R&D exact integer divider. Канонический контекст: docs/CHAT_HANDOFF_V44_2026-09-05.md в https://github.com/aolpochta2-creator/chatgpt.

    Не создавать новые математические версии до physical synthesis/STA.
    Сравнивать V36RCM+V34DX+V35FF, V39C42 и V43SJ17 одинаковым flow; V44WAVE — только timing-bound study.

    Кодовый baseline: 803aad755dd666854c70fefbb535ebffc979c8ca.
    Текущий main после handoff-коммита: bda1d25be43fc70a324eba7a24df17f0eabf799f.
    Обычный EDA run 33945386027 зелёный. Physical runs 33944711386, 33944899194, 33944984663 и 33945291301 остановились до route/SPEF; последний blocker — CTS child killed: illegal instruction после hold-repair.

    Следующее действие: добавить SKIP_CTS_REPAIR_TIMING=1 в physical/config.mk, явно записать caveat, rerun physical.yml для V36/V39/V43 и получить final routed OpenRCX/SPEF STA. Никаких новых RTL/math изменений до этого.

    Текущая mapped-таблица (cell-only, не post-route): V36 55,630 cells / 63,203.994 um² / Tmin 5.6779 ns; V39 38,701 / 46,533.774 / 5.5216 ns; V43 17,599 / 21,837.004 / 5.9923 ns. V43 — area leader, V39 — cell-only timing leader; физический победитель не выбран.

Источники: приложенный division_algorithm_research_log_v44(1).txt, docs/ARCHITECTURE.md, docs/RESULTS_V44_SYNTHESIS.md, docs/PHYSICAL_AUDIT_V44.md и raw GitHub Actions reports.
