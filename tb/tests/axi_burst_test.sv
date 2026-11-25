// axi_burst_test.sv  (included by tb/axi_test_list.sv)
`ifndef AXI_BURST_TEST_SV
`define AXI_BURST_TEST_SV
// ----------------------------------------------------------------------------
// TC-03 bursts: 1 / 2 / 16 / 256 beats, full and random strobes
// ----------------------------------------------------------------------------
class axi_burst_test extends axi_base_test;
    function new(string name); super.new(name); endfunction
    virtual task main();
        axi_txn   t;
        bit [7:0] lens [4];
        lens[0] = 8'd0;  lens[1] = 8'd1;  lens[2] = 8'd15;  lens[3] = 8'd255;
        for (int pass = 0; pass < 2; pass++) begin
            step(pass ? "bursts of 1, 2, 16, 256 beats with RANDOM strobes" : "bursts of 1, 2, 16, 256 beats, all strobes on");
            env.gen[0].rand_strb = pass;
            env.gen[1].rand_strb = pass;
            for (int i = 0; i < 4; i++) begin
                t = env.gen[0].write(i % 2,       i % 2,       lens[i]);
                t = env.gen[1].write((i + 1) % 2, (i + 1) % 2, lens[i]);
            end
            env.wait_idle();
        end
        readback_all();
        check(env.m_mon[0].n_w == 2 * 275, $sformatf("W beats sent by M0 = %0d (expected 550 = 2 x (1+2+16+256))", env.m_mon[0].n_w));
        check(env.s_mon[0].n_w + env.s_mon[1].n_w == 4 * 275,
              $sformatf("W beats received by S0 + S1 = %0d (expected 1100)", env.s_mon[0].n_w + env.s_mon[1].n_w));
        prove("bursts of 1 to 256 beats pass through the 2-entry buffers without losing or reordering a beat");
        prove("write strobes reach the slave unchanged (byte-level reference memory matches on read-back)");
    endtask
endclass
`endif
