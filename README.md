# AXI4 2x2 Crossbar - RTL and Layered SystemVerilog Testbench

```
axi4_xbar_project/
├── Makefile                 compile / run / regression (Vivado xsim)
├── README.md
├── rtl/
│   └── axi4_xbar.sv         crossbar RTL (v3.3)
├── tb/
│   ├── tb_top.sv            top of the layered testbench
│   ├── axi_if.sv            AXI4 interface
│   ├── axi_tb_pkg.sv        package, includes all classes below
│   ├── axi_txn.sv           transaction (one whole burst)
│   ├── axi_agent_cfg.sv     knobs: gaps, backpressure, stall, SLVERR
│   ├── axi_generator.sv     creates transactions (directed + random)
│   ├── axi_master_driver.sv drives a master port (5 channel threads)
│   ├── axi_slave_driver.sv  slave model: byte memory + responder
│   ├── axi_monitor.sv       passive monitor + protocol checks
│   ├── axi_coverage.sv      functional coverage
│   ├── axi_scoreboard.sv    master side vs slave side vs reference memory
│   ├── axi_env.sv           builds and connects everything
│   ├── axi_base_test.sv     base test
│   ├── axi_test_list.sv     includes every test file + test factory
│   └── tests/               one file per test (9 tests)
└── doc/
    └── axi4_xbar_microarchitecture.xml   draw.io diagram of the design
```

## Design summary

* 2 masters, 2 slaves, one clock `aclk`, active-low asynchronous reset `arst_n`.
* Address map: `0x0xxx_xxxx` -> S0, `0x1xxx_xxxx` -> S1, anything else -> internal DECERR responder (T2).
* **Channel buffers** (`xbar_fifo`, depth `BUF_DEPTH` = 2): AW, W, AR per master; B, R per slave.
  `READY = NOT full`. A request or response that cannot move on waits inside the crossbar.
* **Widened slave-side ID**: slave ID = `{master index, master ID}` (5 bits). B / R are routed with
  the top bit, which is removed before the response is given to the master.
* **Arbitration**: one round-robin arbiter per target for AW and one for AR, grant locked until the handshake.
* **W ordering** (AXI4 has no WID): per-master FIFO (`u_wsel`, "M fifo") remembers the target of every
  forwarded AW; per-target FIFO (`u_tq`, "T fifo") remembers the master of every accepted AW.
  A W beat moves only when both FIFO heads agree; both pop on WLAST.
* **`UNIQUE_IDS = 1` (default)**: the crossbar does not check IDs. **Rule for the master:** transactions
  with the same ID that are outstanding at the same time must go to ONE slave. With `UNIQUE_IDS = 0`
  an ID tracker is generated and the crossbar keeps the same-ID order itself.

Known limits: fixed 2x2; head-of-line blocking inside one master's AW / AR buffer; W data reaches
a slave only after that slave accepted the AW; AxLOCK / AxCACHE / AxPROT / AxQOS are not implemented.

## Quick start (Linux + Vivado)

```bash
source /tools/Xilinx/Vivado/2025.1/settings64.sh   # adjust to your install path
cd axi4_xbar_project
make compile
make run TEST=axi_basic_rw_test
make regress
```

Plusargs (through `ARGS=`): `+SB_QUIET` (no scoreboard line per transaction),
`+STRESS_N=<n>`, `+DUMP` (writes `sim/dump.vcd`). Define `AXI_NO_COV` to compile without the covergroup.

Without the Makefile:

```bash
xvlog -sv -i tb rtl/axi4_xbar.sv tb/axi_if.sv tb/axi_tb_pkg.sv tb/tb_top.sv
xelab tb_top -debug typical -timescale 1ns/1ps -s tb_snap
xsim tb_snap -R -testplusarg TESTNAME=axi_basic_rw_test
```

## Testbench structure

```
gen[m] --mailbox--> m_drv[m] ==> axi4_xbar ==> s_drv[s] (memory model)
                       |                          |
                    m_mon[m] ---> scoreboard <--- s_mon[s]
```

Stimulus rules of the generator:

* ID rule (needed for `UNIQUE_IDS = 1`): `ID[1:0]` = target (S0 -> 0, S1 -> 1, unmapped -> 2), `ID[3:2]` random.
* Master m only uses addresses with `addr[16] = m`; a burst never crosses 4 KB.
* All beats are 8 bytes (`AxSIZE = 3`), `INCR` bursts, 1 to 256 beats, optional random strobes.

## Tests

| ID | `TEST=` | What it shows |
|---|---|---|
| TC-01 | `axi_basic_rw_test` | write + read-back on M0->S0, M0->S1, M1->S0, M1->S1 |
| TC-02 | `axi_decerr_test` | DECERR for unmapped addresses, nothing reaches a slave |
| TC-03 | `axi_burst_test` | 1 / 2 / 16 / 256 beats, full and random strobes |
| TC-04 | `axi_same_id_test` | both masters use the same ID at one slave (widened slave-side ID) |
| TC-05 | `axi_buffer_test` | stalled slave / stalled master: requests and responses wait in the buffers |
| TC-06 | `axi_w_order_test` | M W-order FIFO and T W-order FIFO keep the W order |
| TC-07 | `axi_arbitration_test` | round-robin, no starvation, grant held until the handshake |
| TC-08 | `axi_outstanding_test` | many outstanding transactions, slow + fast slave |
| TC-09 | `axi_stress_test` | long random mix with 70 % READY, DECERR and SLVERR, then read-back |

Every test prints `[CHECK] PASS/FAIL` lines with the compared values, one `[SB]` line per transaction,
a scoreboard summary and a "WHAT THIS TEST PROVED" list, and ends with `TEST <name> : PASSED` or `FAILED`.

## What the scoreboard checks

* `[ROUTE]` every request reaches the slave selected by the address map, unchanged
* `[ID]` slave-side ID is `{master, id}`; the master gets its own ID back
* `[WDATA]` / `[RDATA]` data and strobes are unchanged in both directions
* `[RESP]` response at the master equals the response the slave gave
* `[DECERR]` unmapped requests get DECERR and never reach a slave
* `[REF]` read-back data equals the byte-level reference memory
* `[GHOST]` nothing completes on a slave that no master received a response for
* `[PROTO]` (monitors) VALID and payload stay stable until READY; burst length matches AxLEN

## Adding a test

1. Create `tb/tests/my_test.sv` with `class my_test extends axi_base_test;` and override `configure()` and `main()`.
2. In `tb/axi_test_list.sv` add `` `include "tests/my_test.sv" `` and one line in `axi_create_test()`.
3. Add the name to `TESTS` in the Makefile.

```systemverilog
class my_test extends axi_base_test;
    function new(string name); super.new(name); endfunction
    virtual task configure();
        env.s_cfg[0].wready_pct = 30;              // S0: WREADY high 30 % of the time
    endtask
    virtual task main();
        axi_txn t;
        t = env.gen[0].write(0, 4'h0, 8'd7);       // M0 -> S0, ID 0, 8 beats
        readback_all();
        prove("8-beat write to a slow S0 reads back correctly");
    endtask
endclass
```
