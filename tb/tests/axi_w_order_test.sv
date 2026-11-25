// axi_w_order_test.sv  (included by tb/axi_test_list.sv)
`ifndef AXI_W_ORDER_TEST_SV
`define AXI_W_ORDER_TEST_SV
// ----------------------------------------------------------------------------
// TC-06 W ordering with the M fifo and the T fifo (AXI4 has no WID)
// ----------------------------------------------------------------------------
class axi_w_order_test extends axi_base_test;
    function new(string name); super.new(name); endfunction
    virtual task main();
        axi_txn t;
        step("M fifo: M0 sends AW to S0, then AW to S1, and holds back all W data");
        env.m_cfg[0].w_hold = 1;
        t = env.gen[0].write(0, 4'h0, 8'd3);
        t = env.gen[0].write(1, 4'h1, 8'd1);
        env.clk(10);
        check(env.s_mon[0].n_aw == 1 && env.s_mon[1].n_aw == 1,
              $sformatf("AW accepted: S0 %0d, S1 %0d (expected 1, 1: both AWs went out before any data)",
                        env.s_mon[0].n_aw, env.s_mon[1].n_aw));
        check(env.s_mon[0].n_w + env.s_mon[1].n_w == 0,
              $sformatf("W beats at S0 + S1 = %0d (expected 0)", env.s_mon[0].n_w + env.s_mon[1].n_w));
        env.m_cfg[0].w_hold = 0;
        env.wait_idle();
        check(env.s_mon[0].n_w == 4 && env.s_mon[1].n_w == 2,
              $sformatf("W beats: S0 %0d, S1 %0d (expected 4, 2: first burst to S0, second to S1)",
                        env.s_mon[0].n_w, env.s_mon[1].n_w));

        step("T fifo: S0 accepts AW of M1 first, then AW of M0. M0 sends its data first");
        env.m_cfg[0].w_hold = 1;
        env.m_cfg[1].w_hold = 1;
        t = env.gen[1].write(0, 4'h0, 8'd3);
        env.clk(5);
        t = env.gen[0].write(0, 4'h0, 8'd3);
        env.clk(5);
        env.m_cfg[0].w_hold = 0;
        env.clk(12);
        check(env.s_mon[0].n_w == 4,
              $sformatf("W beats at S0 = %0d (expected 4, unchanged: M0's data must wait for M1's data)", env.s_mon[0].n_w));
        env.m_cfg[1].w_hold = 0;
        env.wait_idle();
        check(env.s_mon[0].n_w == 12, $sformatf("W beats at S0 = %0d (expected 12)", env.s_mon[0].n_w));
        readback_all();
        prove("M fifo: a master can have AWs open at two slaves; each W burst goes to the slave of its own AW");
        prove("T fifo: a slave gets W bursts in the order it accepted the AWs, also when another master's data is ready first");
        prove("the scoreboard found every write burst on the right slave with the right data");
    endtask
endclass
`endif
