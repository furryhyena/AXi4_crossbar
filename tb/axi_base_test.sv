// =============================================================================
// axi_base_test.sv - every test extends this class and overrides
//                      configure()  : set knobs before traffic starts
//                      main()       : send transactions, do extra checks
// run() = start env -> wait for reset -> check reset state -> main() ->
//         wait until everything completed -> report -> PASSED / FAILED
// =============================================================================
class axi_base_test;
    axi_env  env;
    string   name;
    string   proved [$];
    int      test_checks;

    function new(string name);
        this.name = name;
    endfunction

    virtual task configure();
    endtask

    virtual task main();
    endtask

    // test-level check: prints the compared values (put them in msg)
    function void check(bit cond, string msg);
        test_checks++;
        env.sb.checks++;
        if (cond) $display("[%0t] [CHECK] PASS : %s", $time, msg);
        else begin
            env.sb.errors++;
            $display("[%0t] [CHECK] FAIL : %s   <-- ERROR", $time, msg);
        end
    endfunction

    function void prove(string s);
        proved.push_back(s);
    endfunction

    function void step(string s);
        $display("\n[%0t] ---- %s", $time, s);
    endfunction

    task check_reset_state();
        step("state after reset");
        for (int i = 0; i < 2; i++) begin
            check(env.m_vif[i].bvalid === 1'b0 && env.m_vif[i].rvalid === 1'b0,
                  $sformatf("M%0d: BVALID = %b, RVALID = %b (expected 0, 0)", i,
                            env.m_vif[i].bvalid, env.m_vif[i].rvalid));
            check(env.m_vif[i].awready === 1'b1 && env.m_vif[i].wready === 1'b1 && env.m_vif[i].arready === 1'b1,
                  $sformatf("M%0d: AWREADY = %b, WREADY = %b, ARREADY = %b (expected 1: request buffers empty)", i,
                            env.m_vif[i].awready, env.m_vif[i].wready, env.m_vif[i].arready));
            check(env.s_vif[i].awvalid === 1'b0 && env.s_vif[i].wvalid === 1'b0 && env.s_vif[i].arvalid === 1'b0,
                  $sformatf("S%0d: AWVALID = %b, WVALID = %b, ARVALID = %b (expected 0)", i,
                            env.s_vif[i].awvalid, env.s_vif[i].wvalid, env.s_vif[i].arvalid));
            check(env.s_vif[i].bready === 1'b1 && env.s_vif[i].rready === 1'b1,
                  $sformatf("S%0d: BREADY = %b, RREADY = %b (expected 1: response buffers empty)", i,
                            env.s_vif[i].bready, env.s_vif[i].rready));
        end
    endtask

    // write phase done -> switch the reference-memory check on -> read everything back
    task readback_all();
        env.wait_idle();
        step("read-back of every written location (reference memory check ON)");
        env.sb.ref_check = 1;
        env.gen[0].readback();
        env.gen[1].readback();
        env.wait_idle();
    endtask

    task run();
        int errs;
        $display("\n============================================================");
        $display(" TEST %s : START", name);
        $display("============================================================");
        configure();
        env.start();
        wait (env.m_vif[0].arst_n === 1'b1);
        env.clk(3);
        check_reset_state();
        main();
        env.wait_idle();
        env.sb.final_report();
        $display(" ---------------- state coverage (this test) ----------------");
        for (int i = 0; i < 2; i++) env.m_mon[i].report_cov();
        for (int i = 0; i < 2; i++) env.s_mon[i].report_cov();
        axi_assert_stats::report();
        errs = env.total_errors() + axi_assert_stats::errors();
        $display(" ---------------- WHAT THIS TEST PROVED ----------------");
        if (errs == 0) for (int i = 0; i < proved.size(); i++) $display("  %0d. %s", i + 1, proved[i]);
        else           $display("  nothing - the test has errors, see the ERROR lines above");
        $display("============================================================");
        $display(" checks : %0d    errors : %0d", env.sb.checks, errs);
        $display(" TEST %s : %s", name, (errs == 0) ? "PASSED" : "FAILED");
        $display("============================================================\n");
    endtask
endclass
