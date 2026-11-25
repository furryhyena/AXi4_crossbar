// axi_outstanding_test.sv  (included by tb/axi_test_list.sv)
`ifndef AXI_OUTSTANDING_TEST_SV
`define AXI_OUTSTANDING_TEST_SV
// ----------------------------------------------------------------------------
// TC-08 several outstanding transactions, slow slave, two slaves at once
// ----------------------------------------------------------------------------
class axi_outstanding_test extends axi_base_test;
    function new(string name); super.new(name); endfunction
    virtual task configure();
        env.s_cfg[0].resp_delay_max = 30;           // S0 answers slowly, S1 at once
    endtask
    virtual task main();
        axi_txn t;
        step("M0: 6 writes to S0 (ID 0) and 6 writes to S1 (ID 1), interleaved");
        for (int i = 0; i < 6; i++) begin
            t = env.gen[0].write(0, 4'h0, 8'd1);
            t = env.gen[0].write(1, 4'h1, 8'd1);
        end
        env.wait_idle();
        step("M0: reads of all 12 locations, S0 slow, S1 fast, all outstanding together");
        env.sb.ref_check = 1;
        env.gen[0].readback();
        env.wait_idle();
        check(env.m_mon[0].max_rd_out >= 4,
              $sformatf("peak outstanding reads of M0 = %0d (expected >= 4)", env.m_mon[0].max_rd_out));
        check(env.m_mon[0].max_wr_out >= 2,
              $sformatf("peak outstanding writes of M0 = %0d (expected >= 2)", env.m_mon[0].max_wr_out));
        check(env.sb.n_done == 24, $sformatf("transactions completed = %0d (expected 24)", env.sb.n_done));
        prove("one master can have several transactions outstanding at S0 and S1 at the same time");
        prove("responses with different IDs return in any order; each one carries the right data for its ID");
        prove("responses with the same ID (same slave) return in the order of the requests");
    endtask
endclass
`endif
