`timescale 1ns / 1ps
// =============================================================================
// axi_protocol_checker.sv - AXI4 protocol assertions (Protocol Assertion Plan
//                           A01..A17), one instance per port.
//
// tb_top creates one instance per port and connects the port's axi_if:
//     axi_protocol_checker #(.PORT("M0")) u_chk_m0 (.bus(m0_if));
// It only reads the signals, so the RTL and the class-based testbench
// do not change.
//
// Signals driven by the CROSSBAR (the real targets of these checks):
//     master ports M0/M1 : AWREADY, WREADY, ARREADY, B channel, R channel
//     slave  ports S0/S1 : AWVALID + payload, W channel, ARVALID + payload,
//                          BREADY, RREADY
// The same rules also catch a testbench master or slave that breaks AXI4.
//
// Every failure prints "[ASSERT] ERROR : <name> on <port> : <values>".
// The base test prints a table "checked / failed" for every assertion and
// port, and a failing assertion makes the test FAIL.
// =============================================================================
module axi_protocol_checker
    import axi_tb_pkg::*;
#(
    parameter string PORT = "port"      // name printed in messages and in the table
) (
    axi_if bus                          // the AXI port to watch (read only)
);
    // local names for the interface signals
    wire aclk = bus.aclk;
    wire arst_n = bus.arst_n;
    wire [4:0] awid = bus.awid;
    wire [31:0] awaddr = bus.awaddr;
    wire [7:0] awlen = bus.awlen;
    wire [2:0] awsize = bus.awsize;
    wire [1:0] awburst = bus.awburst;
    wire awvalid = bus.awvalid;
    wire awready = bus.awready;
    wire [63:0] wdata = bus.wdata;
    wire [7:0] wstrb = bus.wstrb;
    wire wlast = bus.wlast;
    wire wvalid = bus.wvalid;
    wire wready = bus.wready;
    wire [4:0] bid = bus.bid;
    wire [1:0] bresp = bus.bresp;
    wire bvalid = bus.bvalid;
    wire bready = bus.bready;
    wire [4:0] arid = bus.arid;
    wire [31:0] araddr = bus.araddr;
    wire [7:0] arlen = bus.arlen;
    wire [2:0] arsize = bus.arsize;
    wire [1:0] arburst = bus.arburst;
    wire arvalid = bus.arvalid;
    wire arready = bus.arready;
    wire [4:0] rid = bus.rid;
    wire [63:0] rdata = bus.rdata;
    wire [1:0] rresp = bus.rresp;
    wire rlast = bus.rlast;
    wire rvalid = bus.rvalid;
    wire rready = bus.rready;

    string P;
    initial begin
        P = PORT;
        axi_assert_stats::add_port(P);
        axi_assert_stats::add_name("A01 reset_valid_low");
        axi_assert_stats::add_name("A02 aw_valid_stable");
        axi_assert_stats::add_name("A03 aw_payload_stable");
        axi_assert_stats::add_name("A04 w_valid_stable");
        axi_assert_stats::add_name("A05 w_payload_stable");
        axi_assert_stats::add_name("A06 ar_valid_stable");
        axi_assert_stats::add_name("A07 ar_payload_stable");
        axi_assert_stats::add_name("A08 b_valid_stable");
        axi_assert_stats::add_name("A09 b_payload_stable");
        axi_assert_stats::add_name("A10 r_valid_stable");
        axi_assert_stats::add_name("A11 r_payload_stable");
        axi_assert_stats::add_name("A12 no_x_on_valid");
        axi_assert_stats::add_name("A13 no_x_on_payload");
        axi_assert_stats::add_name("A14 wlast_on_last_beat");
        axi_assert_stats::add_name("A15 b_after_wlast");
        axi_assert_stats::add_name("A16 r_after_ar");
        axi_assert_stats::add_name("A17 burst_legal");
    end

    // ------------------------------------------------------------ helpers
    wire aw_hs = (awvalid === 1'b1) && (awready === 1'b1);
    wire w_hs  = (wvalid  === 1'b1) && (wready  === 1'b1);
    wire b_hs  = (bvalid  === 1'b1) && (bready  === 1'b1);
    wire ar_hs = (arvalid === 1'b1) && (arready === 1'b1);
    wire r_hs  = (rvalid  === 1'b1) && (rready  === 1'b1);

    wire aw_wait = (awvalid === 1'b1) && (awready !== 1'b1);
    wire w_wait  = (wvalid  === 1'b1) && (wready  !== 1'b1);
    wire ar_wait = (arvalid === 1'b1) && (arready !== 1'b1);
    wire b_wait  = (bvalid  === 1'b1) && (bready  !== 1'b1);
    wire r_wait  = (rvalid  === 1'b1) && (rready  !== 1'b1);

    wire [4:0]  valids     = {awvalid, wvalid, arvalid, bvalid, rvalid};
    wire [9:0]  hs_signals = {awvalid, awready, wvalid, wready, arvalid, arready,
                              bvalid, bready, rvalid, rready};
    wire [47:0] aw_pl = {awid, awaddr, awlen, awsize, awburst};
    wire [72:0] w_pl  = {wdata, wstrb, wlast};
    wire [47:0] ar_pl = {arid, araddr, arlen, arsize, arburst};
    wire [6:0]  b_pl  = {bid, bresp};
    wire [71:0] r_pl  = {rid, rdata, rresp, rlast};


    // ------------------------------------------------------------ A01 reset
    // while reset is active every VALID must be 0
    a_reset_valid_low : assert property (@(posedge aclk) !arst_n |-> (valids === 5'b0))
        else axi_assert_stats::failed(P, "A01 reset_valid_low",
             $sformatf("in reset AWVALID=%b WVALID=%b ARVALID=%b BVALID=%b RVALID=%b (expected all 0)",
                       awvalid, wvalid, arvalid, bvalid, rvalid));

    // ------------------------------------------------------------ A02..A11 VALID and payload stable
    // VALID high and READY low  ->  next clock VALID still high and payload unchanged
    a_aw_valid_stable : assert property (@(posedge aclk) disable iff (!arst_n) aw_wait |=> (awvalid === 1'b1))
        else axi_assert_stats::failed(P, "A02 aw_valid_stable", "AWVALID dropped before AWREADY");
    a_aw_payload_stable : assert property (@(posedge aclk) disable iff (!arst_n) aw_wait |=> (aw_pl === $past(aw_pl)))
        else axi_assert_stats::failed(P, "A03 aw_payload_stable",
             $sformatf("AW changed while AWVALID=1, AWREADY=0; now ID %h ADDR %h LEN %0d",
                       awid, awaddr, awlen));

    a_w_valid_stable : assert property (@(posedge aclk) disable iff (!arst_n) w_wait |=> (wvalid === 1'b1))
        else axi_assert_stats::failed(P, "A04 w_valid_stable", "WVALID dropped before WREADY");
    a_w_payload_stable : assert property (@(posedge aclk) disable iff (!arst_n) w_wait |=> (w_pl === $past(w_pl)))
        else axi_assert_stats::failed(P, "A05 w_payload_stable",
             $sformatf("W changed while WVALID=1, WREADY=0; now DATA %h STRB %h LAST %b",
                       wdata, wstrb, wlast));

    a_ar_valid_stable : assert property (@(posedge aclk) disable iff (!arst_n) ar_wait |=> (arvalid === 1'b1))
        else axi_assert_stats::failed(P, "A06 ar_valid_stable", "ARVALID dropped before ARREADY");
    a_ar_payload_stable : assert property (@(posedge aclk) disable iff (!arst_n) ar_wait |=> (ar_pl === $past(ar_pl)))
        else axi_assert_stats::failed(P, "A07 ar_payload_stable",
             $sformatf("AR changed while ARVALID=1, ARREADY=0; now ID %h ADDR %h LEN %0d",
                       arid, araddr, arlen));

    a_b_valid_stable : assert property (@(posedge aclk) disable iff (!arst_n) b_wait |=> (bvalid === 1'b1))
        else axi_assert_stats::failed(P, "A08 b_valid_stable", "BVALID dropped before BREADY");
    a_b_payload_stable : assert property (@(posedge aclk) disable iff (!arst_n) b_wait |=> (b_pl === $past(b_pl)))
        else axi_assert_stats::failed(P, "A09 b_payload_stable",
             $sformatf("B changed while BVALID=1, BREADY=0; now BID %h BRESP %b", bid, bresp));

    a_r_valid_stable : assert property (@(posedge aclk) disable iff (!arst_n) r_wait |=> (rvalid === 1'b1))
        else axi_assert_stats::failed(P, "A10 r_valid_stable", "RVALID dropped before RREADY");
    a_r_payload_stable : assert property (@(posedge aclk) disable iff (!arst_n) r_wait |=> (r_pl === $past(r_pl)))
        else axi_assert_stats::failed(P, "A11 r_payload_stable",
             $sformatf("R changed while RVALID=1, RREADY=0; now RID %h RDATA %h RLAST %b",
                       rid, rdata, rlast));

    // ------------------------------------------------------------ A12, A13 no X / Z
    a_no_x_on_valid : assert property (@(posedge aclk) disable iff (!arst_n) !$isunknown(hs_signals))
        else axi_assert_stats::failed(P, "A12 no_x_on_valid",
             $sformatf("VALID/READY = %b (aw v,r  w v,r  ar v,r  b v,r  r v,r) has X or Z", hs_signals));

    a_no_x_on_payload : assert property (@(posedge aclk) disable iff (!arst_n)
            !((awvalid === 1'b1) && $isunknown(aw_pl)) && !((wvalid === 1'b1) && $isunknown(w_pl)) &&
            !((arvalid === 1'b1) && $isunknown(ar_pl)) && !((bvalid === 1'b1) && $isunknown(b_pl)) &&
            !((rvalid  === 1'b1) && $isunknown(r_pl)))
        else axi_assert_stats::failed(P, "A13 no_x_on_payload", "payload has X or Z while its VALID is 1");

    // ------------------------------------------------------------ A17 legal burst / size
    a_burst_legal : assert property (@(posedge aclk) disable iff (!arst_n)
            ((awvalid !== 1'b1) || (awburst != 2'b11 && awsize <= 3'd3)) &&
            ((arvalid !== 1'b1) || (arburst != 2'b11 && arsize <= 3'd3)))
        else axi_assert_stats::failed(P, "A17 burst_legal",
             $sformatf("AWBURST=%b AWSIZE=%0d ARBURST=%b ARSIZE=%0d (reserved burst 11 or size > 8 bytes)",
                       awburst, awsize, arburst, arsize));

    // ------------------------------------------------------------ A14, A15, A16 (counters)
    // A14: the beats of every W burst (counted up to WLAST) must equal AWLEN+1.
    //      AXI4 W bursts come in AW order, so the n-th W burst belongs to the
    //      n-th AW. Two queues are compared, so W may come before or after AW.
    // A15: number of B handshakes <= number of WLAST handshakes
    // A16: number of RLAST handshakes <= number of AR handshakes
    int unsigned aw_len_q [$];   // AWLEN+1 of every accepted AW, in order
    int unsigned w_beats_q [$];  // beats of every finished W burst, in order
    int unsigned beat_cnt;
    longint      n_wlast, n_b, n_ar, n_rlast;

    always @(posedge aclk or negedge arst_n) begin
        if (arst_n !== 1'b1) begin
            aw_len_q.delete();  w_beats_q.delete();
            beat_cnt = 0;  n_wlast = 0;  n_b = 0;  n_ar = 0;  n_rlast = 0;
            if (arst_n === 1'b0) axi_assert_stats::checked(P, "A01 reset_valid_low");
        end else begin
            // ---- "checked" counters for the concurrent assertions above
            if (aw_wait) begin axi_assert_stats::checked(P, "A02 aw_valid_stable");
                               axi_assert_stats::checked(P, "A03 aw_payload_stable"); end
            if (w_wait)  begin axi_assert_stats::checked(P, "A04 w_valid_stable");
                               axi_assert_stats::checked(P, "A05 w_payload_stable"); end
            if (ar_wait) begin axi_assert_stats::checked(P, "A06 ar_valid_stable");
                               axi_assert_stats::checked(P, "A07 ar_payload_stable"); end
            if (b_wait)  begin axi_assert_stats::checked(P, "A08 b_valid_stable");
                               axi_assert_stats::checked(P, "A09 b_payload_stable"); end
            if (r_wait)  begin axi_assert_stats::checked(P, "A10 r_valid_stable");
                               axi_assert_stats::checked(P, "A11 r_payload_stable"); end
            axi_assert_stats::checked(P, "A12 no_x_on_valid");
            if (valids !== 5'b0)                        axi_assert_stats::checked(P, "A13 no_x_on_payload");
            if (awvalid === 1'b1 || arvalid === 1'b1)  axi_assert_stats::checked(P, "A17 burst_legal");

            // ---- A14
            if (aw_hs) aw_len_q.push_back(int'(awlen) + 1);
            if (w_hs) begin
                beat_cnt++;
                if (wlast === 1'b1) begin
                    w_beats_q.push_back(beat_cnt);
                    beat_cnt = 0;
                end else if (beat_cnt >= 256) begin
                    axi_assert_stats::failed(P, "A14 wlast_on_last_beat",
                        "256 W beats without WLAST (longest AXI4 burst is 256 beats)");
                    beat_cnt = 0;
                end
            end
            while (aw_len_q.size() > 0 && w_beats_q.size() > 0) begin
                int unsigned exp_b, got_b;
                exp_b = aw_len_q.pop_front();
                got_b = w_beats_q.pop_front();
                axi_assert_stats::checked(P, "A14 wlast_on_last_beat");
                if (got_b != exp_b)
                    axi_assert_stats::failed(P, "A14 wlast_on_last_beat",
                        $sformatf("WLAST after %0d beats, AWLEN+1 = %0d", got_b, exp_b));
            end

            // ---- A15
            if (w_hs && wlast === 1'b1) n_wlast++;
            if (b_hs) begin
                n_b++;
                axi_assert_stats::checked(P, "A15 b_after_wlast");
                if (n_b > n_wlast)
                    axi_assert_stats::failed(P, "A15 b_after_wlast",
                        $sformatf("B handshakes = %0d but WLAST handshakes = %0d", n_b, n_wlast));
            end

            // ---- A16
            if (ar_hs) n_ar++;
            if (r_hs && rlast === 1'b1) begin
                n_rlast++;
                axi_assert_stats::checked(P, "A16 r_after_ar");
                if (n_rlast > n_ar)
                    axi_assert_stats::failed(P, "A16 r_after_ar",
                        $sformatf("RLAST handshakes = %0d but AR handshakes = %0d", n_rlast, n_ar));
            end
        end
    end
endmodule
