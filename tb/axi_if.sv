`timescale 1ns / 1ps
// =============================================================================
// axi_if.sv - AXI4 signal bundle used by the layered testbench.
//   One interface type is used for master ports AND slave ports.
//   ID signals are 5 bits wide here:
//     slave ports  : all 5 bits are used  ({master index, 4-bit ID})
//     master ports : only [3:0] is used, bit 4 is always 0
// =============================================================================
`ifndef AXI_IF_SV
`define AXI_IF_SV
interface axi_if (input logic aclk, input logic arst_n);
    // write address
    logic [4:0]  awid;
    logic [31:0] awaddr;
    logic [7:0]  awlen;
    logic [2:0]  awsize;
    logic [1:0]  awburst;
    logic        awvalid;
    logic        awready;
    // write data
    logic [63:0] wdata;
    logic [7:0]  wstrb;
    logic        wlast;
    logic        wvalid;
    logic        wready;
    // write response
    logic [4:0]  bid;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    // read address
    logic [4:0]  arid;
    logic [31:0] araddr;
    logic [7:0]  arlen;
    logic [2:0]  arsize;
    logic [1:0]  arburst;
    logic        arvalid;
    logic        arready;
    // read data
    logic [4:0]  rid;
    logic [63:0] rdata;
    logic [1:0]  rresp;
    logic        rlast;
    logic        rvalid;
    logic        rready;
endinterface
`endif
