// axi_basic_rw_test.sv  (included by tb/axi_test_list.sv)
`ifndef AXI_BASIC_RW_TEST_SV
`define AXI_BASIC_RW_TEST_SV
// ----------------------------------------------------------------------------
// TC-01 basic read / write on all four paths
// ----------------------------------------------------------------------------
class axi_basic_rw_test extends axi_base_test;
    function new(string name); super.new(name); endfunction
    virtual task main();
        axi_txn t;
        for (int m = 0; m < 2; m++)
            for (int s = 0; s < 2; s++) begin
                step($sformatf("M%0d -> S%0d : 1-beat write, 4-beat write", m, s));
                t = env.gen[m].write(s, s, 8'd0);
                t = env.gen[m].write(s, s, 8'd3);
                env.wait_idle();
            end
        readback_all();
        check(env.sb.n_done == 16, $sformatf("transactions completed = %0d (expected 16: 8 writes + 8 reads)", env.sb.n_done));
        check(env.sb.n_okay == 16, $sformatf("OKAY responses = %0d (expected 16)", env.sb.n_okay));
        prove("M0->S0, M0->S1, M1->S0, M1->S1 : write reaches the right slave and reads back the same data");
        prove("BID / RID returned to the master equal the AWID / ARID it sent");
    endtask
endclass
`endif
