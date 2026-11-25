// axi_stress_test.sv  (included by tb/axi_test_list.sv)
`ifndef AXI_STRESS_TEST_SV
`define AXI_STRESS_TEST_SV
// ----------------------------------------------------------------------------
// TC-09 stress: long random mix with backpressure, then read-back
//   +STRESS_N=<n> : transactions per master (default 200)
// ----------------------------------------------------------------------------
class axi_stress_test extends axi_base_test;
    function new(string name); super.new(name); endfunction
    virtual task configure();
        for (int i = 0; i < 2; i++) begin
            env.m_cfg[i].set_backpressure(70, 1);
            env.s_cfg[i].set_backpressure(70, 1);
            env.s_cfg[i].resp_delay_max = 4;
            env.gen[i].len_max   = 15;
            env.gen[i].rand_strb = 1;
        end
        env.s_cfg[0].slverr_en = 1;                 // S0: 0x0000_3000 .. 0x0000_33FF answers SLVERR
        env.s_cfg[0].slverr_lo = 28'h000_3000;
        env.s_cfg[0].slverr_hi = 28'h000_33FF;
    endtask
    virtual task main();
        int n;
        if (!$value$plusargs("STRESS_N=%d", n)) n = 200;
        step($sformatf("%0d random transactions per master, 70 %% READY on all channels, SLVERR window on S0", n));
        env.gen[0].random(n);
        env.gen[1].random(n);
        readback_all();
        check(env.sb.n_done == env.gen[0].n_gen + env.gen[1].n_gen,
              $sformatf("completed %0d of %0d transactions", env.sb.n_done, env.gen[0].n_gen + env.gen[1].n_gen));
        prove("a long random mix of reads, writes and DECERR accesses from both masters completes without any mismatch");
        prove("after the mix, every written location reads back the value of the reference memory");
        prove("SLVERR answers from S0 reach the right master unchanged, DECERR answers come from the crossbar");
    endtask
endclass
`endif
