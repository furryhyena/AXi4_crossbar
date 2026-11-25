// axi_decerr_test.sv  (included by tb/axi_test_list.sv)
`ifndef AXI_DECERR_TEST_SV
`define AXI_DECERR_TEST_SV
// ----------------------------------------------------------------------------
// TC-02 DECERR for unmapped addresses
// ----------------------------------------------------------------------------
class axi_decerr_test extends axi_base_test;
    function new(string name); super.new(name); endfunction
    virtual task main();
        axi_txn t;
        int     seen;
        step("writes and reads of 1, 4 and 16 beats to unmapped addresses, both masters");
        for (int m = 0; m < 2; m++) begin
            t = env.gen[m].write(2, 4'h2, 8'd0);
            t = env.gen[m].write(2, 4'h2, 8'd3);
            t = env.gen[m].write(2, 4'h6, 8'd15);
            t = env.gen[m].read (2, 4'h2, 8'd0);
            t = env.gen[m].read (2, 4'h2, 8'd3);
            t = env.gen[m].read (2, 4'h6, 8'd15);
        end
        env.wait_idle();
        seen = env.s_mon[0].n_aw + env.s_mon[0].n_ar + env.s_mon[0].n_w +
               env.s_mon[1].n_aw + env.s_mon[1].n_ar + env.s_mon[1].n_w;
        check(env.sb.n_decerr == 12, $sformatf("DECERR responses at the masters = %0d (expected 12)", env.sb.n_decerr));
        check(seen == 0, $sformatf("AW + AR + W handshakes on S0 and S1 = %0d (expected 0)", seen));
        step("normal traffic still works after the DECERR bursts");
        t = env.gen[0].write(0, 4'h0, 8'd3);
        t = env.gen[1].write(1, 4'h1, 8'd3);
        readback_all();
        prove("an unmapped write gets BRESP = DECERR, an unmapped read gets ARLEN+1 beats of DECERR with RLAST");
        prove("unmapped requests and their data never appear on S0 or S1");
    endtask
endclass
`endif
