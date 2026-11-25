// axi_arbitration_test.sv  (included by tb/axi_test_list.sv)
`ifndef AXI_ARBITRATION_TEST_SV
`define AXI_ARBITRATION_TEST_SV
// ----------------------------------------------------------------------------
// TC-07 arbitration: both masters want the same slave all the time
// ----------------------------------------------------------------------------
class axi_arbitration_test extends axi_base_test;
    function new(string name); super.new(name); endfunction

    function int max_run(bit q [$]);
        int best, cur;
        best = 0;  cur = 0;
        for (int i = 0; i < q.size(); i++) begin
            if (i > 0 && q[i] == q[i-1]) cur++; else cur = 1;
            if (cur > best) best = cur;
        end
        return best;
    endfunction

    function int count_of(bit q [$], bit v);
        int n;
        n = 0;
        for (int i = 0; i < q.size(); i++) if (q[i] == v) n++;
        return n;
    endfunction

    virtual task main();
        axi_txn t;
        step("M0 and M1 each send 16 single-beat writes to S0, no gaps");
        for (int i = 0; i < 16; i++) begin
            t = env.gen[0].write(0, 4'h0, 8'd0);
            t = env.gen[1].write(0, 4'h0, 8'd0);
        end
        env.wait_idle();
        check(count_of(env.s_mon[0].aw_order, 0) == 16 && count_of(env.s_mon[0].aw_order, 1) == 16,
              $sformatf("AWs granted at S0: M0 %0d, M1 %0d (expected 16, 16)",
                        count_of(env.s_mon[0].aw_order, 0), count_of(env.s_mon[0].aw_order, 1)));
        check(max_run(env.s_mon[0].aw_order) <= 2,
              $sformatf("longest run of AW grants to one master = %0d (expected <= 2: round-robin)", max_run(env.s_mon[0].aw_order)));

        step("M0 and M1 each send 16 single-beat reads to S1, no gaps");
        for (int i = 0; i < 16; i++) begin
            t = env.gen[0].read(1, 4'h1, 8'd0);
            t = env.gen[1].read(1, 4'h1, 8'd0);
        end
        env.wait_idle();
        check(count_of(env.s_mon[1].ar_order, 0) == 16 && count_of(env.s_mon[1].ar_order, 1) == 16,
              $sformatf("ARs granted at S1: M0 %0d, M1 %0d (expected 16, 16)",
                        count_of(env.s_mon[1].ar_order, 0), count_of(env.s_mon[1].ar_order, 1)));
        check(max_run(env.s_mon[1].ar_order) <= 2,
              $sformatf("longest run of AR grants to one master = %0d (expected <= 2: round-robin)", max_run(env.s_mon[1].ar_order)));

        step("grant lock: S0 stalled, M0 asks alone and gets the grant, then M1 asks too");
        env.s_cfg[0].awready_pct = 0;
        env.clk(3);
        t = env.gen[0].write(0, 4'h4, 8'd0);
        env.clk(6);
        check(env.s_vif[0].awvalid === 1'b1 && env.s_vif[0].awid === 5'h04,
              $sformatf("S0 sees AWVALID = %b, AWID = 0x%02h (expected 1, 0x04: M0 holds the grant)",
                        env.s_vif[0].awvalid, env.s_vif[0].awid));
        t = env.gen[1].write(0, 4'h8, 8'd0);
        env.clk(10);
        check(env.s_vif[0].awvalid === 1'b1 && env.s_vif[0].awid === 5'h04,
              $sformatf("after M1 asked: S0 still sees AWID = 0x%02h (expected 0x04: grant not taken away before the handshake)",
                        env.s_vif[0].awid));
        env.s_cfg[0].awready_pct = 100;
        env.wait_idle();
        check(env.s_mon[0].aw_order[env.s_mon[0].aw_order.size()-2] == 0 &&
              env.s_mon[0].aw_order[env.s_mon[0].aw_order.size()-1] == 1,
              $sformatf("S0 accepted M%0d then M%0d (expected M0 then M1)",
                        env.s_mon[0].aw_order[env.s_mon[0].aw_order.size()-2],
                        env.s_mon[0].aw_order[env.s_mon[0].aw_order.size()-1]));

        step("slow slave (AWREADY 30 %): the grant must stay stable until the handshake");
        env.s_cfg[0].awready_pct = 30;
        for (int i = 0; i < 8; i++) begin
            t = env.gen[0].write(0, 4'h0, 8'd1);
            t = env.gen[1].write(0, 4'h4, 8'd1);
        end
        readback_all();
        prove("with both masters requesting one slave, grants alternate (round-robin) and nobody starves");
        prove("a grant is held until the slave accepts it, even when the other master starts asking");
        prove("AWVALID / ARVALID and the payload stay stable towards a slow slave (no [PROTO] error)");
    endtask
endclass
`endif
