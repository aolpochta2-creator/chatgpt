.PHONY: generate model structure test test-v36 test-v39 test-v43 synth-v36 synth-v39 synth-v43 synth-full-v36 synth-full-v39 synth-full-v43

TESTS ?= 2000

generate:
	python3 scripts/gen_roms.py
	python3 scripts/gen_reducers.py

model:
	PYTHONPATH=. python3 scripts/validate_model.py

structure:
	PYTHONPATH=. python3 scripts/validate_structure.py

test: test-v36 test-v39 test-v43

test-v36: generate
	bash scripts/run_sim.sh 36 $(TESTS)

test-v39: generate
	bash scripts/run_sim.sh 39 $(TESTS)

test-v43: generate
	bash scripts/run_sim.sh 43 $(TESTS)

synth-v36: generate
	bash scripts/run_synth.sh kernel_v36rcm

synth-v39: generate
	bash scripts/run_synth.sh kernel_v39c42

synth-v43: generate
	bash scripts/run_synth.sh kernel_v43sj17

# Full-top mapping is separate: kernel timing constraints do not apply to it.
synth-full-v36: generate
	SKIP_OPENSTA=1 bash scripts/run_synth.sh divider_v36rcm

synth-full-v39: generate
	SKIP_OPENSTA=1 bash scripts/run_synth.sh divider_v39c42

synth-full-v43: generate
	SKIP_OPENSTA=1 bash scripts/run_synth.sh divider_v43sj17
