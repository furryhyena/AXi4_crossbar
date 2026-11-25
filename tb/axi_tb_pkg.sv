`timescale 1ns / 1ps
// =============================================================================
// axi_tb_pkg.sv - package with all testbench classes (classic layered TB,
//                 no UVM):  txn -> generator -> driver -> DUT -> monitor ->
//                 scoreboard, all built and connected in axi_env.
// Compile order: axi_if.sv, axi_tb_pkg.sv, axi_protocol_checker.sv, tb_top.sv
//                (tb/ on the include path)
// =============================================================================
`ifndef AXI_TB_PKG_SV
`define AXI_TB_PKG_SV
package axi_tb_pkg;

    localparam bit [1:0] RESP_OKAY   = 2'b00;
    localparam bit [1:0] RESP_SLVERR = 2'b10;
    localparam bit [1:0] RESP_DECERR = 2'b11;

    function automatic string resp_name(bit [1:0] r);
        case (r)
            2'b00:   return "OKAY";
            2'b01:   return "EXOKAY";
            2'b10:   return "SLVERR";
            default: return "DECERR";
        endcase
    endfunction

    `include "axi_txn.sv"
    `include "axi_agent_cfg.sv"
    `include "axi_generator.sv"
    `include "axi_master_driver.sv"
    `include "axi_slave_driver.sv"
    `include "axi_coverage.sv"
    `include "axi_monitor.sv"
    `include "axi_scoreboard.sv"
    `include "axi_env.sv"
    `include "axi_assert_stats.sv"
    `include "axi_base_test.sv"
    `include "axi_test_list.sv"

endpackage
`endif
