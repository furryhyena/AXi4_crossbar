`timescale 1ns / 1ps
// =============================================================================
// tb_top.sv - top of the layered testbench: clock, reset, four AXI interfaces,
//             the crossbar, and the test selected with +TESTNAME=<name>.
//   +TESTNAME=axi_basic_rw_test   which test to run (default axi_basic_rw_test)
//   +SB_QUIET                     no scoreboard line per transaction
//   +STRESS_N=<n>                 transactions per master in axi_stress_test
//   +DUMP                         write dump.vcd
// =============================================================================
module tb_top;
    import axi_tb_pkg::*;

    logic aclk = 1'b0;
    logic arst_n;
    always #5 aclk = ~aclk;

    axi_if m0_if (.aclk(aclk), .arst_n(arst_n));
    axi_if m1_if (.aclk(aclk), .arst_n(arst_n));
    axi_if s0_if (.aclk(aclk), .arst_n(arst_n));
    axi_if s1_if (.aclk(aclk), .arst_n(arst_n));

    // ---------------------------------------------------------------- DUT pins
    logic [1:0][3:0]  m_awid,  m_arid,  m_bid,  m_rid;        // master side: 4-bit ID
    logic [1:0][31:0] m_awaddr, m_araddr;
    logic [1:0][7:0]  m_awlen,  m_arlen,  m_wstrb;
    logic [1:0][2:0]  m_awsize, m_arsize;
    logic [1:0][1:0]  m_awburst, m_arburst, m_bresp, m_rresp;
    logic [1:0][63:0] m_wdata,  m_rdata;
    logic [1:0]       m_awvalid, m_awready, m_wlast, m_wvalid, m_wready;
    logic [1:0]       m_bvalid,  m_bready,  m_arvalid, m_arready;
    logic [1:0]       m_rlast,   m_rvalid,  m_rready;

    logic [1:0][4:0]  s_awid,  s_arid,  s_bid,  s_rid;        // slave side: 5-bit ID
    logic [1:0][31:0] s_awaddr, s_araddr;
    logic [1:0][7:0]  s_awlen,  s_arlen,  s_wstrb;
    logic [1:0][2:0]  s_awsize, s_arsize;
    logic [1:0][1:0]  s_awburst, s_arburst, s_bresp, s_rresp;
    logic [1:0][63:0] s_wdata,  s_rdata;
    logic [1:0]       s_awvalid, s_awready, s_wlast, s_wvalid, s_wready;
    logic [1:0]       s_bvalid,  s_bready,  s_arvalid, s_arready;
    logic [1:0]       s_rlast,   s_rvalid,  s_rready;

    axi4_xbar #(.BUF_DEPTH(2)) dut (.*);

    // protocol assertions (tb/axi_protocol_checker.sv) on all four ports
    axi_protocol_checker #(.PORT("M0")) u_chk_m0 (.bus(m0_if));
    axi_protocol_checker #(.PORT("M1")) u_chk_m1 (.bus(m1_if));
    axi_protocol_checker #(.PORT("S0")) u_chk_s0 (.bus(s0_if));
    axi_protocol_checker #(.PORT("S1")) u_chk_s1 (.bus(s1_if));

    // ---------------------------------------------------------------- master port 0
    assign m_awid[0]    = m0_if.awid[3:0];  assign m_awaddr[0]  = m0_if.awaddr;
    assign m_awlen[0]   = m0_if.awlen;      assign m_awsize[0]  = m0_if.awsize;
    assign m_awburst[0] = m0_if.awburst;    assign m_awvalid[0] = m0_if.awvalid;
    assign m0_if.awready = m_awready[0];
    assign m_wdata[0]   = m0_if.wdata;      assign m_wstrb[0]   = m0_if.wstrb;
    assign m_wlast[0]   = m0_if.wlast;      assign m_wvalid[0]  = m0_if.wvalid;
    assign m0_if.wready  = m_wready[0];
    assign m0_if.bid     = {1'b0, m_bid[0]};  assign m0_if.bresp = m_bresp[0];
    assign m0_if.bvalid  = m_bvalid[0];       assign m_bready[0] = m0_if.bready;
    assign m_arid[0]    = m0_if.arid[3:0];  assign m_araddr[0]  = m0_if.araddr;
    assign m_arlen[0]   = m0_if.arlen;      assign m_arsize[0]  = m0_if.arsize;
    assign m_arburst[0] = m0_if.arburst;    assign m_arvalid[0] = m0_if.arvalid;
    assign m0_if.arready = m_arready[0];
    assign m0_if.rid     = {1'b0, m_rid[0]};  assign m0_if.rdata = m_rdata[0];
    assign m0_if.rresp   = m_rresp[0];        assign m0_if.rlast = m_rlast[0];
    assign m0_if.rvalid  = m_rvalid[0];       assign m_rready[0] = m0_if.rready;

    // ---------------------------------------------------------------- master port 1
    assign m_awid[1]    = m1_if.awid[3:0];  assign m_awaddr[1]  = m1_if.awaddr;
    assign m_awlen[1]   = m1_if.awlen;      assign m_awsize[1]  = m1_if.awsize;
    assign m_awburst[1] = m1_if.awburst;    assign m_awvalid[1] = m1_if.awvalid;
    assign m1_if.awready = m_awready[1];
    assign m_wdata[1]   = m1_if.wdata;      assign m_wstrb[1]   = m1_if.wstrb;
    assign m_wlast[1]   = m1_if.wlast;      assign m_wvalid[1]  = m1_if.wvalid;
    assign m1_if.wready  = m_wready[1];
    assign m1_if.bid     = {1'b0, m_bid[1]};  assign m1_if.bresp = m_bresp[1];
    assign m1_if.bvalid  = m_bvalid[1];       assign m_bready[1] = m1_if.bready;
    assign m_arid[1]    = m1_if.arid[3:0];  assign m_araddr[1]  = m1_if.araddr;
    assign m_arlen[1]   = m1_if.arlen;      assign m_arsize[1]  = m1_if.arsize;
    assign m_arburst[1] = m1_if.arburst;    assign m_arvalid[1] = m1_if.arvalid;
    assign m1_if.arready = m_arready[1];
    assign m1_if.rid     = {1'b0, m_rid[1]};  assign m1_if.rdata = m_rdata[1];
    assign m1_if.rresp   = m_rresp[1];        assign m1_if.rlast = m_rlast[1];
    assign m1_if.rvalid  = m_rvalid[1];       assign m_rready[1] = m1_if.rready;

    // ---------------------------------------------------------------- slave port 0
    assign s0_if.awid    = s_awid[0];       assign s0_if.awaddr  = s_awaddr[0];
    assign s0_if.awlen   = s_awlen[0];      assign s0_if.awsize  = s_awsize[0];
    assign s0_if.awburst = s_awburst[0];    assign s0_if.awvalid = s_awvalid[0];
    assign s_awready[0]  = s0_if.awready;
    assign s0_if.wdata   = s_wdata[0];      assign s0_if.wstrb   = s_wstrb[0];
    assign s0_if.wlast   = s_wlast[0];      assign s0_if.wvalid  = s_wvalid[0];
    assign s_wready[0]   = s0_if.wready;
    assign s_bid[0]      = s0_if.bid;       assign s_bresp[0]    = s0_if.bresp;
    assign s_bvalid[0]   = s0_if.bvalid;    assign s0_if.bready  = s_bready[0];
    assign s0_if.arid    = s_arid[0];       assign s0_if.araddr  = s_araddr[0];
    assign s0_if.arlen   = s_arlen[0];      assign s0_if.arsize  = s_arsize[0];
    assign s0_if.arburst = s_arburst[0];    assign s0_if.arvalid = s_arvalid[0];
    assign s_arready[0]  = s0_if.arready;
    assign s_rid[0]      = s0_if.rid;       assign s_rdata[0]    = s0_if.rdata;
    assign s_rresp[0]    = s0_if.rresp;     assign s_rlast[0]    = s0_if.rlast;
    assign s_rvalid[0]   = s0_if.rvalid;    assign s0_if.rready  = s_rready[0];

    // ---------------------------------------------------------------- slave port 1
    assign s1_if.awid    = s_awid[1];       assign s1_if.awaddr  = s_awaddr[1];
    assign s1_if.awlen   = s_awlen[1];      assign s1_if.awsize  = s_awsize[1];
    assign s1_if.awburst = s_awburst[1];    assign s1_if.awvalid = s_awvalid[1];
    assign s_awready[1]  = s1_if.awready;
    assign s1_if.wdata   = s_wdata[1];      assign s1_if.wstrb   = s_wstrb[1];
    assign s1_if.wlast   = s_wlast[1];      assign s1_if.wvalid  = s_wvalid[1];
    assign s_wready[1]   = s1_if.wready;
    assign s_bid[1]      = s1_if.bid;       assign s_bresp[1]    = s1_if.bresp;
    assign s_bvalid[1]   = s1_if.bvalid;    assign s1_if.bready  = s_bready[1];
    assign s1_if.arid    = s_arid[1];       assign s1_if.araddr  = s_araddr[1];
    assign s1_if.arlen   = s_arlen[1];      assign s1_if.arsize  = s_arsize[1];
    assign s1_if.arburst = s_arburst[1];    assign s1_if.arvalid = s_arvalid[1];
    assign s_arready[1]  = s1_if.arready;
    assign s_rid[1]      = s1_if.rid;       assign s_rdata[1]    = s1_if.rdata;
    assign s_rresp[1]    = s1_if.rresp;     assign s_rlast[1]    = s1_if.rlast;
    assign s_rvalid[1]   = s1_if.rvalid;    assign s1_if.rready  = s_rready[1];

    // ---------------------------------------------------------------- reset
    initial begin
        arst_n = 1'b0;
        repeat (5) @(posedge aclk);
        arst_n <= 1'b1;
    end

    // ---------------------------------------------------------------- test
    initial begin
        axi_base_test t;
        string        testname;
        if ($test$plusargs("DUMP")) begin
            $dumpfile("dump.vcd");
            $dumpvars(0, tb_top);
        end
        if (!$value$plusargs("TESTNAME=%s", testname)) testname = "axi_basic_rw_test";
        t = axi_create_test(testname);
        if (t == null) begin
            $display("ERROR: unknown test name '%s'  (see tb/axi_tests.sv)", testname);
            $finish;
        end
        t.env = new(m0_if, m1_if, s0_if, s1_if);
        t.run();
        $finish;
    end

    // watchdog: a hang shows up as a FAILED test instead of an endless run
    initial begin
        #50_000_000;
        $display("ERROR: TIMEOUT - the test did not finish (DUT or testbench is stuck)");
        $display(" TEST : FAILED");
        $finish;
    end
endmodule
