// axi_same_id_test.sv  (included by tb/axi_test_list.sv)
`ifndef AXI_SAME_ID_TEST_SV
`define AXI_SAME_ID_TEST_SV
// ----------------------------------------------------------------------------
// TC-04 widened slave-side ID: both masters use the SAME ID at the same slave
// ----------------------------------------------------------------------------
class axi_same_id_test extends axi_base_test;
    function new(string name); super.new(name); endfunction
    virtual task configure();
        env.s_cfg[0].resp_delay_max = 6;       // keep several transactions outstanding
    endtask
    virtual task main();
        axi_txn t;
        step("M0 and M1 each send 4 writes to S0 with the same ID 0x4, at the same time");
        for (int i = 0; i < 4; i++) begin
            t = env.gen[0].write(0, 4'h4, 8'd3);
            t = env.gen[1].write(0, 4'h4, 8'd3);
        end
        env.wait_idle();
        check(env.s_mon[0].sid_seen[5'h04] && env.s_mon[0].sid_seen[5'h14],
              $sformatf("S0 saw AWID 0x04: %b, AWID 0x14: %b (expected 1, 1 = {master, id})",
                        env.s_mon[0].sid_seen[5'h04], env.s_mon[0].sid_seen[5'h14]));
        check(env.sb.n_master_done[0] == 4 && env.sb.n_master_done[1] == 4,
              $sformatf("B responses: M0 got %0d, M1 got %0d (expected 4, 4)", env.sb.n_master_done[0], env.sb.n_master_done[1]));
        readback_all();
        prove("two masters can use the same ID at the same slave together: the slave sees {master, id}");
        prove("every B / R went back to the master named by the top ID bit, with the top bit removed");
    endtask
endclass
`endif
