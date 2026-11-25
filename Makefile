# =============================================================================
# Makefile - AXI4 2x2 crossbar : RTL + layered testbench   (Vivado xsim, Linux)
#
# Before using:  source <vivado_install>/settings64.sh
#
#   make compile                          compile + elaborate the layered TB
#   make run TEST=axi_basic_rw_test       run one test (log: sim/logs/<test>_<seed>.log)
#   make run TEST=axi_stress_test SEED=7 ARGS="+STRESS_N=500 +SB_QUIET"
#   make regress                          every test x every seed in SEEDS (default 1 2 3),
#                                         table at the end: one row per test, one column per seed
#   make regress NSEEDS=10                seeds 1 .. 10
#   make regress SEEDS="7 42 1234"        exactly these seeds
#   make regress QUIET=0                  also print the full output of every run
#   make regress TESTS="axi_buffer_test axi_w_order_test"   only some tests
#   make waves TEST=axi_buffer_test       run in the xsim GUI
#   make cov                              coverage as TEXT in the terminal (after make regress):
#                                           table per test + TOTAL, covergroup scores, bins never hit,
#                                           code coverage per RTL module; also saved in
#                                           sim/cov_report/coverage_summary.txt
#   CODE_COV=0                            elaborate without code coverage (faster runs)
#   make list                             print the test names
#   make clean
# =============================================================================

TEST   ?= axi_basic_rw_test
SEED   ?= 1
ARGS   ?=
QUIET  ?= 1
CODE_COV ?= 1
NSEEDS ?= 3
SEEDS  ?= $(shell seq 1 $(NSEEDS))

ROOT    := $(abspath .)
RTL     := $(ROOT)/rtl/axi4_xbar.sv
TB_DIR  := $(ROOT)/tb
SRCS    := $(RTL) $(TB_DIR)/axi_if.sv $(TB_DIR)/axi_tb_pkg.sv $(TB_DIR)/axi_protocol_checker.sv $(TB_DIR)/tb_top.sv
SIM_DIR := $(ROOT)/sim
LOG     := $(SIM_DIR)/logs/$(TEST)_$(SEED).log
SNAP    := $(SIM_DIR)/xsim.dir/tb_snap/xsimk

# add new test names here so "make regress" runs them
TESTS ?= axi_basic_rw_test axi_decerr_test axi_burst_test axi_same_id_test \
         axi_buffer_test axi_w_order_test axi_arbitration_test \
         axi_outstanding_test axi_stress_test axi_parallel_test

ERR_PATTERN := ERROR|FAIL :|TIMEOUT

COV_DIR := $(SIM_DIR)/cov_report
CC_DIR  := $(SIM_DIR)/cov_cc

# code coverage: statement, branch, condition, toggle (switched on at elaboration)
ifeq ($(CODE_COV),1)
CC_OPTS := -cc_type sbct
else
CC_OPTS :=
endif

.PHONY: compile run regress waves cov list clean

list:
	@for t in $(TESTS); do echo $$t; done

$(SNAP): $(RTL) $(wildcard $(TB_DIR)/*.sv) $(wildcard $(TB_DIR)/tests/*.sv) $(ROOT)/Makefile
	mkdir -p $(SIM_DIR)/logs
	cd $(SIM_DIR) && xvlog -sv -i $(TB_DIR) $(SRCS) -log $(SIM_DIR)/logs/xvlog.log
	cd $(SIM_DIR) && xelab tb_top -debug typical -timescale 1ns/1ps $(CC_OPTS) -s tb_snap \
	  -log $(SIM_DIR)/logs/xelab.log
	@rm -rf $(SIM_DIR)/cc_clean; mkdir -p $(SIM_DIR)/cc_clean; \
	for d in xsim.codeCov xsim.CodeCov; do \
	  if [ -d $(SIM_DIR)/$$d ]; then cp -r $(SIM_DIR)/$$d $(SIM_DIR)/cc_clean/; fi; \
	done

compile: $(SNAP)

run: $(SNAP)
	@for d in xsim.codeCov xsim.CodeCov; do \
	  rm -rf $(SIM_DIR)/$$d; \
	  if [ -d $(SIM_DIR)/cc_clean/$$d ]; then cp -r $(SIM_DIR)/cc_clean/$$d $(SIM_DIR)/; fi; \
	done
	cd $(SIM_DIR) && xsim tb_snap -R -sv_seed $(SEED) -testplusarg TESTNAME=$(TEST) \
	  $(foreach a,$(ARGS),-testplusarg $(patsubst +%,%,$(a))) \
	  -cov_db_dir $(SIM_DIR) -cov_db_name $(TEST)_$(SEED) -log $(LOG)
	@for d in $(SIM_DIR)/xsim.codeCov $(SIM_DIR)/xsim.CodeCov; do \
	  if [ -d $$d ]; then \
	    rm -rf $(CC_DIR)/$(TEST)_$(SEED); mkdir -p $(CC_DIR)/$(TEST)_$(SEED); \
	    cp -r $$d $(CC_DIR)/$(TEST)_$(SEED)/; \
	  fi; \
	done

waves: $(SNAP)
	cd $(SIM_DIR) && xsim tb_snap -gui -sv_seed $(SEED) -testplusarg TESTNAME=$(TEST) \
	  $(foreach a,$(ARGS),-testplusarg $(patsubst +%,%,$(a)))

# functional coverage of all runs found in sim/xsim.covdb, merged
# coverage: xcrg makes one report per test (all its seeds merged) and one TOTAL report
# (all runs merged); tools/cov_text.py then prints everything as text in the terminal
# and saves it in sim/cov_report/coverage_summary.txt (no browser needed)
cov:
	@runs=$$(ls $(SIM_DIR)/xsim.covdb 2>/dev/null | grep '^axi_'); \
	if [ -z "$$runs" ]; then echo " no coverage data: run  make regress  first"; exit 1; fi; \
	rm -rf $(COV_DIR); mkdir -p $(COV_DIR); \
	for grp in $(TESTS) TOTAL; do \
	  fargs=""; cargs=""; \
	  for r in $$runs; do \
	    if [ "$$grp" = "TOTAL" ] || [ "$${r%_*}" = "$$grp" ]; then \
	      fargs="$$fargs -cov_db_dir $(SIM_DIR) -cov_db_name $$r"; \
	      for n in $$(ls $(CC_DIR)/$$r/xsim.[cC]odeCov 2>/dev/null); do \
	        cargs="$$cargs -cov_db_dir $(CC_DIR)/$$r -cov_db_name $$n"; done; \
	    fi; \
	  done; \
	  [ -z "$$fargs" ] && continue; \
	  out=$(COV_DIR)/$$grp; mkdir -p $$out; \
	  echo " xcrg: $$grp"; \
	  ( cd $(SIM_DIR) && xcrg $$fargs -merge_dir $$out/func_db -merge_db_name merged \
	      -report_dir $$out/func -report_format all ) > $$out/xcrg_func.log 2>&1; \
	  if [ -f $$out/func/functionalCoverageReport/xcrg_func_cov_report.txt ]; then echo "   functional report OK"; \
	  else echo "   functional report NOT created, last lines of $$out/xcrg_func.log:"; tail -n 5 $$out/xcrg_func.log | sed 's/^/     | /'; fi; \
	  if [ -n "$$cargs" ]; then \
	    ( cd $(SIM_DIR) && xcrg $$cargs -merge_dir $$out/code_db -merge_db_name merged_code \
	        -cc_report $$out/code -report_format all ) > $$out/xcrg_code.log 2>&1; \
	    if [ -n "$$(find $$out -name modules.html 2>/dev/null)" ] || grep -q "Line Coverage Score" $$out/xcrg_code.log; then echo "   code report OK"; \
	    else echo "   code report NOT created, last lines of $$out/xcrg_code.log:"; tail -n 5 $$out/xcrg_code.log | sed 's/^/     | /'; fi; \
	  else echo "   no code coverage data in $(CC_DIR) for $$grp"; \
	  fi; \
	done; \
	echo ""; \
	python3 $(ROOT)/tools/cov_text.py $(COV_DIR) $(TESTS)


regress: compile
	@pass=0; fail=0; fails=""; \
	header=$$(printf "%-24s" "TEST"); \
	for s in $(SEEDS); do header="$$header$$(printf " %-6s" "s$$s")"; done; \
	rows=""; \
	for t in $(TESTS); do \
	  row=$$(printf "%-24s" "$$t"); \
	  for s in $(SEEDS); do \
	    log=$(SIM_DIR)/logs/$${t}_$${s}.log; \
	    if [ "$(QUIET)" = "1" ]; then \
	      printf " running %-24s seed %-6s ... " "$$t" "$$s"; \
	      $(MAKE) --no-print-directory run TEST=$$t SEED=$$s ARGS="$(ARGS)" > /dev/null 2>&1 || true; \
	    else \
	      echo ""; echo "############################################################"; \
	      echo "#  RUNNING TEST : $$t   (seed $$s)"; \
	      echo "############################################################"; \
	      $(MAKE) --no-print-directory run TEST=$$t SEED=$$s ARGS="$(ARGS)" 2>&1 || true; \
	    fi; \
	    if grep -q "TEST $$t : PASSED" $$log 2>/dev/null; then \
	      pass=$$((pass+1)); row="$$row$$(printf " %-6s" "PASS")"; \
	      [ "$(QUIET)" = "1" ] && echo "PASS"; \
	    else \
	      fail=$$((fail+1)); row="$$row$$(printf " %-6s" "FAIL")"; \
	      [ "$(QUIET)" = "1" ] && echo "FAIL"; \
	      fails="$${fails}FAIL  $$t  seed $$s   (log: sim/logs/$${t}_$${s}.log)\n"; \
	      errs=$$(grep -E "$(ERR_PATTERN)" $$log 2>/dev/null | head -n 5 | sed 's/^/        | /'); \
	      if [ -n "$$errs" ]; then fails="$${fails}$${errs}\n"; \
	      else fails="$${fails}        | (no ERROR line found - test may have hung or not started)\n"; fi; \
	    fi; \
	  done; \
	  rows="$${rows}$${row}\n"; \
	done; \
	echo ""; \
	echo "============================================================"; \
	echo " REGRESSION SUMMARY   seeds: $(strip $(SEEDS))"; \
	echo "============================================================"; \
	echo "$$header"; \
	printf "%b" "$$rows"; \
	echo "------------------------------------------------------------"; \
	echo " RUNS: $$((pass+fail))   PASSED: $$pass   FAILED: $$fail"; \
	echo "============================================================"; \
	if [ $$fail -ne 0 ]; then echo ""; echo " WHY THE FAILED RUNS FAILED:"; printf "%b" "$$fails"; fi; \
	[ $$fail -eq 0 ]

clean:
	rm -rf $(SIM_DIR) *.jou *.log *.pb .Xil
