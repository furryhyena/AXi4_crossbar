// axi_parallel_test.sv  (included by tb/axi_test_list.sv)
`ifndef AXI_PARALLEL_TEST_SV
`define AXI_PARALLEL_TEST_SV
// ----------------------------------------------------------------------------
// TC-10 parallel operation: two masters on two different slaves at the same time
//
// A crossbar has one arbiter and one mux per slave, so M0->S0 and M1->S1
// (or M0->S1 and M1->S0) must move data in the same clock cycles.
// If the crossbar let only one transaction through at a time (like a shared
// bus) the data would still be correct, so the other tests would still pass.
// This test measures it:
//   - overlap : clocks where S0 and S1 both have a W (or R) handshake
//   - time    : two transfers together must take about as long as one alone
// ----------------------------------------------------------------------------
class axi_parallel_test extends axi_base_test;
    localparam int LEN   = 63;      // AWLEN / ARLEN = 63 -> 64-beat bursts
    localparam int BEATS = LEN + 1;

    // counted every clock by count_overlap()
    int  w_overlap, r_overlap;      // clocks with a handshake on S0 and S1 together
    int  w_hs [2], r_hs [2];        // W / R beats seen at S0 and S1 during the window
    bit  counting;

    function new(string name); super.new(name); endfunction

    // runs for the whole test, counts only while counting = 1
    task count_overlap();
        bit w0, w1, r0, r1;
        forever begin
            @(posedge env.m_vif[0].aclk);
            if (counting) begin
                w0 = (env.s_vif[0].wvalid === 1'b1 && env.s_vif[0].wready === 1'b1);
                w1 = (env.s_vif[1].wvalid === 1'b1 && env.s_vif[1].wready === 1'b1);
                r0 = (env.s_vif[0].rvalid === 1'b1 && env.s_vif[0].rready === 1'b1);
                r1 = (env.s_vif[1].rvalid === 1'b1 && env.s_vif[1].rready === 1'b1);
                w_hs[0] += w0;  w_hs[1] += w1;
                r_hs[0] += r0;  r_hs[1] += r1;
                if (w0 && w1) w_overlap++;
                if (r0 && r1) r_overlap++;
            end
        end
    endtask

    function void clear_counts();
        w_overlap = 0;  r_overlap = 0;
        w_hs[0] = 0;  w_hs[1] = 0;  r_hs[0] = 0;  r_hs[1] = 0;
    endfunction

    // start the transactions, wait until all are done, return the clocks taken
    task automatic run_window(input int m [], input int s [], input bit is_write,
                              output int clocks);
        axi_txn t;
        int     target;
        clear_counts();
        target  = env.sb.n_done + m.size();
        clocks  = 0;
        counting = 1;
        foreach (m[i]) begin
            if (is_write) t = env.gen[m[i]].write(s[i], 4'(s[i]), 8'(LEN));
            else          t = env.gen[m[i]].read (s[i], 4'(s[i]), 8'(LEN));
        end
        while (env.sb.n_done < target) begin env.clk(1); clocks++; end
        counting = 0;
        env.clk(5);
    endtask

    virtual task main();
        int t_alone_w, t_par_w, t_cross_w, t_alone_r, t_par_r, t_cross_r;
        int lim;

        fork count_overlap(); join_none

        // ------------------------------------------------------------ writes
        step($sformatf("reference: M0 -> S0 one %0d-beat write ALONE", BEATS));
        run_window('{0}, '{0}, 1, t_alone_w);
        $display("[%0t] [INFO] alone write: %0d clocks, W beats S0 = %0d, S1 = %0d",
                 $time, t_alone_w, w_hs[0], w_hs[1]);
        check(w_hs[0] == BEATS && w_overlap == 0,
              $sformatf("W beats at S0 = %0d (expected %0d), overlap = %0d (expected 0: only one path is busy)",
                        w_hs[0], BEATS, w_overlap));

        lim = t_alone_w + t_alone_w / 2;           // together must stay below 1.5 x alone
        step($sformatf("straight paths together: M0 -> S0 and M1 -> S1, %0d-beat writes", BEATS));
        run_window('{0, 1}, '{0, 1}, 1, t_par_w);
        $display("[%0t] [INFO] parallel write: %0d clocks, W beats S0 = %0d, S1 = %0d, both in the same clock = %0d",
                 $time, t_par_w, w_hs[0], w_hs[1], w_overlap);
        check(w_hs[0] == BEATS && w_hs[1] == BEATS,
              $sformatf("W beats: S0 = %0d, S1 = %0d (expected %0d each)", w_hs[0], w_hs[1], BEATS));
        check(w_overlap >= BEATS * 3 / 4,
              $sformatf("clocks with a W beat on S0 AND S1 = %0d (expected >= %0d of %0d: data moves on both paths at once)",
                        w_overlap, BEATS * 3 / 4, BEATS));
        check(t_par_w < lim,
              $sformatf("time for two writes together = %0d clocks, one alone = %0d (expected < %0d; a shared bus would need about %0d)",
                        t_par_w, t_alone_w, lim, 2 * t_alone_w));

        step($sformatf("crossed paths together: M0 -> S1 and M1 -> S0, %0d-beat writes", BEATS));
        run_window('{0, 1}, '{1, 0}, 1, t_cross_w);
        $display("[%0t] [INFO] crossed write: %0d clocks, W beats S0 = %0d, S1 = %0d, both in the same clock = %0d",
                 $time, t_cross_w, w_hs[0], w_hs[1], w_overlap);
        check(w_hs[0] == BEATS && w_hs[1] == BEATS,
              $sformatf("W beats: S0 = %0d, S1 = %0d (expected %0d each)", w_hs[0], w_hs[1], BEATS));
        check(w_overlap >= BEATS * 3 / 4,
              $sformatf("clocks with a W beat on S0 AND S1 = %0d (expected >= %0d of %0d)",
                        w_overlap, BEATS * 3 / 4, BEATS));
        check(t_cross_w < lim,
              $sformatf("time for two crossed writes together = %0d clocks (expected < %0d)", t_cross_w, lim));

        // ------------------------------------------------------------ reads
        step($sformatf("reference: M0 -> S0 one %0d-beat read ALONE", BEATS));
        run_window('{0}, '{0}, 0, t_alone_r);
        $display("[%0t] [INFO] alone read: %0d clocks, R beats S0 = %0d, S1 = %0d",
                 $time, t_alone_r, r_hs[0], r_hs[1]);
        check(r_hs[0] == BEATS && r_overlap == 0,
              $sformatf("R beats at S0 = %0d (expected %0d), overlap = %0d (expected 0)", r_hs[0], BEATS, r_overlap));

        lim = t_alone_r + t_alone_r / 2;
        step($sformatf("straight paths together: M0 -> S0 and M1 -> S1, %0d-beat reads", BEATS));
        run_window('{0, 1}, '{0, 1}, 0, t_par_r);
        $display("[%0t] [INFO] parallel read: %0d clocks, R beats S0 = %0d, S1 = %0d, both in the same clock = %0d",
                 $time, t_par_r, r_hs[0], r_hs[1], r_overlap);
        check(r_hs[0] == BEATS && r_hs[1] == BEATS,
              $sformatf("R beats: S0 = %0d, S1 = %0d (expected %0d each)", r_hs[0], r_hs[1], BEATS));
        check(r_overlap >= BEATS * 3 / 4,
              $sformatf("clocks with an R beat on S0 AND S1 = %0d (expected >= %0d of %0d)",
                        r_overlap, BEATS * 3 / 4, BEATS));
        check(t_par_r < lim,
              $sformatf("time for two reads together = %0d clocks, one alone = %0d (expected < %0d)",
                        t_par_r, t_alone_r, lim));

        step($sformatf("crossed paths together: M0 -> S1 and M1 -> S0, %0d-beat reads", BEATS));
        run_window('{0, 1}, '{1, 0}, 0, t_cross_r);
        $display("[%0t] [INFO] crossed read: %0d clocks, R beats S0 = %0d, S1 = %0d, both in the same clock = %0d",
                 $time, t_cross_r, r_hs[0], r_hs[1], r_overlap);
        check(r_hs[0] == BEATS && r_hs[1] == BEATS,
              $sformatf("R beats: S0 = %0d, S1 = %0d (expected %0d each)", r_hs[0], r_hs[1], BEATS));
        check(r_overlap >= BEATS * 3 / 4,
              $sformatf("clocks with an R beat on S0 AND S1 = %0d (expected >= %0d of %0d)",
                        r_overlap, BEATS * 3 / 4, BEATS));
        check(t_cross_r < lim,
              $sformatf("time for two crossed reads together = %0d clocks (expected < %0d)", t_cross_r, lim));

        $display("\n[%0t] [INFO] summary (clocks): write alone %0d | straight %0d | crossed %0d", $time,
                 t_alone_w, t_par_w, t_cross_w);
        $display("[%0t] [INFO] summary (clocks): read  alone %0d | straight %0d | crossed %0d", $time,
                 t_alone_r, t_par_r, t_cross_r);

        readback_all();
        prove("M0->S0 and M1->S1 move W data in the same clock cycles (straight paths work in parallel)");
        prove("M0->S1 and M1->S0 move W data in the same clock cycles (crossed paths work in parallel)");
        prove("R data from S0 and S1 reaches the two masters in the same clock cycles");
        prove("two transfers on different slaves take about as long as one transfer alone (not one after another)");
    endtask
endclass
`endif
