// axi_buffer_test.sv  (included by tb/axi_test_list.sv)
`ifndef AXI_BUFFER_TEST_SV
`define AXI_BUFFER_TEST_SV
// ----------------------------------------------------------------------------
// TC-05 channel buffers: the crossbar holds requests, not the master
// ----------------------------------------------------------------------------
class axi_buffer_test extends axi_base_test;
    function new(string name); super.new(name); endfunction
    virtual task main();
        axi_txn t;
        int     nb0, nb1;
        step("S0 stalled (ARREADY = AWREADY = 0). M0 sends 3 reads to S0 (buffer depth = 2)");
        env.s_cfg[0].arready_pct = 0;
        env.s_cfg[0].awready_pct = 0;
        env.clk(3);
        t = env.gen[0].read(0, 4'h0, 8'd0);
        t = env.gen[0].read(0, 4'h4, 8'd0);
        t = env.gen[0].read(0, 4'h8, 8'd0);
        env.clk(10);
        check(env.m_mon[0].n_ar == 2, $sformatf("AR handshakes M0 -> crossbar = %0d (expected 2: taken into the AR buffer)", env.m_mon[0].n_ar));
        check(env.s_mon[0].n_ar == 0, $sformatf("AR handshakes crossbar -> S0 = %0d (expected 0: S0 is stalled)", env.s_mon[0].n_ar));
        check(env.s_vif[0].arvalid === 1'b1, $sformatf("crossbar ARVALID towards S0 = %b (expected 1, held)", env.s_vif[0].arvalid));
        check(env.m_vif[0].arready === 1'b0, $sformatf("M0 ARREADY = %b (expected 0: buffer full, 3rd read waits at M0)", env.m_vif[0].arready));
        check(env.m_vif[1].arready === 1'b1, $sformatf("M1 ARREADY = %b (expected 1: M1 is not affected)", env.m_vif[1].arready));

        step("while S0 is stalled, M1 writes and reads S1");
        t = env.gen[1].write(1, 4'h1, 8'd3);
        t = env.gen[1].read_at(t.addr, 4'h1, 8'd3);
        while (env.sb.n_master_done[1] < 2) env.clk(1);
        check(env.sb.n_master_done[1] == 2 && env.sb.n_master_done[0] == 0,
              $sformatf("completed: M1 %0d, M0 %0d (expected 2, 0)", env.sb.n_master_done[1], env.sb.n_master_done[0]));

        step("S0 released");
        env.s_cfg[0].arready_pct = 100;
        env.s_cfg[0].awready_pct = 100;
        env.wait_idle();
        check(env.s_mon[0].n_ar == 3, $sformatf("AR handshakes crossbar -> S0 = %0d (expected 3: nothing lost)", env.s_mon[0].n_ar));

        step("M0 does not take responses (RREADY = 0): the R buffer of S0 holds them");
        env.m_cfg[0].rready_pct = 0;
        env.clk(2);
        t = env.gen[0].read(0, 4'h0, 8'd0);
        t = env.gen[0].read(0, 4'h0, 8'd0);
        env.clk(12);
        check(env.s_mon[0].n_rlast == 5 && env.m_mon[0].n_rlast == 3,
              $sformatf("R bursts finished at S0 = %0d, at M0 = %0d (expected 5, 3: two wait in the R buffer)",
                        env.s_mon[0].n_rlast, env.m_mon[0].n_rlast));
        env.m_cfg[0].rready_pct = 100;
        env.wait_idle();

        step("M0 and M1 do not take B (BREADY = 0): M0 writes 3 times to S0, M1 writes 3 times to S1");
        nb0 = env.m_mon[0].n_b;                     // B handshakes so far
        nb1 = env.m_mon[1].n_b;
        env.m_cfg[0].bready_pct = 0;
        env.m_cfg[1].bready_pct = 0;
        env.clk(2);
        for (int i = 0; i < 3; i++) begin
            t = env.gen[0].write(0, 4'(4 * i),     8'd0);
            t = env.gen[1].write(1, 4'(4 * i + 1), 8'd0);
        end
        env.clk(25);
        for (int s = 0; s < 2; s++)
            check(env.s_vif[s].bvalid === 1'b1 && env.s_vif[s].bready === 1'b0,
                  $sformatf("S%0d: BVALID = %b, crossbar BREADY = %b (expected 1, 0: B buffer holds 2 responses and is full)",
                            s, env.s_vif[s].bvalid, env.s_vif[s].bready));
        check(env.m_mon[0].n_b == nb0 && env.m_mon[1].n_b == nb1,
              $sformatf("new B handshakes at the masters: M0 %0d, M1 %0d (expected 0, 0)",
                        env.m_mon[0].n_b - nb0, env.m_mon[1].n_b - nb1));
        env.m_cfg[0].bready_pct = 100;
        env.m_cfg[1].bready_pct = 100;
        env.wait_idle();
        check(env.m_mon[0].n_b == nb0 + 3 && env.m_mon[1].n_b == nb1 + 3,
              $sformatf("after BREADY = 1: new B handshakes M0 %0d, M1 %0d (expected 3, 3: nothing lost)",
                        env.m_mon[0].n_b - nb0, env.m_mon[1].n_b - nb1));
        prove("a request is accepted from the master although the slave is not ready: it waits in the crossbar buffer");
        prove("the master sees READY = 0 only when its 2-entry buffer is full");
        prove("a stalled slave does not disturb the other master on the other slave");
        prove("a slave response is accepted although the master is not ready: it waits in the B / R buffer");
        prove("when a B buffer is full the crossbar lowers BREADY to the slave, and no response is lost");
    endtask
endclass
`endif
