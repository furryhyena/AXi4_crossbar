// =============================================================================
// axi_coverage.sv - all functional coverage of the testbench
//
//   axi_coverage   (one object, in the scoreboard)
//     cg           : every transaction completed at a master port:
//                    read/write x master x target, burst length, response
//
//   axi_mport_cov  (one per master port, sampled every clock by the monitor)
//     cg_mport_hs     : AW / W / AR buffer full (crossbar READY low while VALID),
//                       master not ready for B / R (crossbar must hold the response)
//     cg_mport_out    : outstanding writes / reads of this master,
//                       W bursts open to 1 or 2 targets at once (M W-order FIFO)
//     cg_mport_order  : B / R completed in order or out of order (different IDs)
//
//   axi_sport_cov  (one per slave port, sampled every clock by the monitor)
//     cg_sport_hs     : slave not ready for AW / W / AR (requests wait in the
//                       crossbar), B / R buffer full (crossbar BREADY / RREADY low)
//     cg_sport_wpend  : accepted AWs still waiting for W data from M0 only,
//                       M1 only, or BOTH masters (T W-order FIFO holds 2 masters)
//     cg_sport_grant  : grant sequence at this slave (M0->M0, M0->M1, M1->M0,
//                       M1->M1) for AW and AR = round-robin arbitration
//
//   The per-port bins are also counted in a plain table (axi_bin_tracker),
//   printed at the end of each test, so the hits are visible in the log.
//   +define+AXI_NO_COV leaves the covergroups out (the table stays).
// =============================================================================

// ---------------------------------------------------------------- transactions
class axi_coverage;
`ifndef AXI_NO_COV
    covergroup cg with function sample(bit is_write, int master, int target,
                                       bit [7:0] len, bit [1:0] resp);
        cp_kind   : coverpoint is_write { bins read = {0};  bins write = {1}; }
        cp_master : coverpoint master   { bins m0 = {0};    bins m1 = {1}; }
        cp_target : coverpoint target   { bins s0 = {0};    bins s1 = {1};  bins decerr = {2}; }
        cp_len    : coverpoint len      { bins single = {0};       bins short_b = {[1:3]};
                                          bins mid_b  = {[4:15]};  bins long_b  = {[16:255]}; }
        cp_resp   : coverpoint resp     { bins okay = {0};  bins slverr = {2};  bins decerr = {3}; }
        x_path    : cross cp_kind, cp_master, cp_target;
    endgroup
`endif

    function new();
`ifndef AXI_NO_COV
        cg = new();
`endif
    endfunction

    function void sample_txn(axi_txn t);
`ifndef AXI_NO_COV
        cg.sample(t.is_write, t.master, t.target(), t.len, t.resp);
`endif
    endfunction

    function void report();
`ifndef AXI_NO_COV
        $display(" functional coverage (this run) : %0.1f %%", cg.get_inst_coverage());
`else
        $display(" functional coverage            : switched off (AXI_NO_COV)");
`endif
    endfunction
endclass

// ---------------------------------------------------------------- bin table
class axi_bin_tracker;
    string  title;
    string  names [$];
    int     hits  [string];

    function new(string title);
        this.title = title;
    endfunction

    function void add(string n);
        names.push_back(n);
        hits[n] = 0;
    endfunction

    function void hit(string n);
        if (!hits.exists(n)) $display("[COV] ERROR: unknown bin %s in %s", n, title);
        else                 hits[n]++;
    endfunction

    function int n_bins();
        return names.size();
    endfunction

    function int n_hit();
        int n;
        n = 0;
        foreach (names[i]) if (hits[names[i]] > 0) n++;
        return n;
    endfunction

    function void report();
        $display(" %s : %0d of %0d bins hit", title, n_hit(), n_bins());
        foreach (names[i])
            $display("     %-44s %8d%s", names[i], hits[names[i]], (hits[names[i]] == 0) ? "   <-- not hit in this test" : "");
    endfunction
endclass

// state of one channel in one clock: 0 = idle, 1 = VALID waiting for READY, 2 = handshake
function automatic int axi_ch_state(logic valid, logic ready);
    if (valid !== 1'b1) return 0;
    return (ready === 1'b1) ? 2 : 1;
endfunction

// ---------------------------------------------------------------- master port
class axi_mport_cov;
    axi_bin_tracker tr;

`ifndef AXI_NO_COV
    covergroup cg_mport_hs with function sample(int aw, int w, int ar, int b, int r);
        option.per_instance = 1;
        cp_aw : coverpoint aw { bins accepted = {2};  bins buffer_full = {1}; }
        cp_w  : coverpoint w  { bins accepted = {2};  bins buffer_full = {1}; }
        cp_ar : coverpoint ar { bins accepted = {2};  bins buffer_full = {1}; }
        cp_b  : coverpoint b  { bins taken    = {2};  bins master_not_ready = {1}; }
        cp_r  : coverpoint r  { bins taken    = {2};  bins master_not_ready = {1}; }
    endgroup

    covergroup cg_mport_out with function sample(int wr, int rd, int tg);
        option.per_instance = 1;
        cp_wr_outstanding : coverpoint wr { bins one = {1};  bins two_three = {[2:3]};  bins four_plus = {[4:$]}; }
        cp_rd_outstanding : coverpoint rd { bins one = {1};  bins two_three = {[2:3]};  bins four_plus = {[4:$]}; }
        cp_w_open_targets : coverpoint tg { bins one_target = {1};  bins two_targets = {[2:3]}; }
    endgroup

    covergroup cg_mport_order with function sample(bit is_b, bit ooo);
        option.per_instance = 1;
        cp_resp  : coverpoint is_b { bins r = {0};  bins b = {1}; }
        cp_order : coverpoint ooo  { bins in_order = {0};  bins out_of_order = {1}; }
        x_order  : cross cp_resp, cp_order;
    endgroup
`endif

    function new(string name);
        string c [5];
        tr = new({name, " state coverage"});
        c[0] = "aw";  c[1] = "w";  c[2] = "ar";
        for (int i = 0; i < 3; i++) begin tr.add({"hs.", c[i], ".accepted"});  tr.add({"hs.", c[i], ".buffer_full"}); end
        tr.add("hs.b.taken");  tr.add("hs.b.master_not_ready");
        tr.add("hs.r.taken");  tr.add("hs.r.master_not_ready");
        tr.add("out.wr.one");  tr.add("out.wr.two_three");  tr.add("out.wr.four_plus");
        tr.add("out.rd.one");  tr.add("out.rd.two_three");  tr.add("out.rd.four_plus");
        tr.add("out.w_open_targets.one");  tr.add("out.w_open_targets.two");
        tr.add("order.b.in_order");  tr.add("order.b.out_of_order");
        tr.add("order.r.in_order");  tr.add("order.r.out_of_order");
`ifndef AXI_NO_COV
        cg_mport_hs    = new();
        cg_mport_out   = new();
        cg_mport_order = new();
        cg_mport_hs.set_inst_name({name, "_hs"});
        cg_mport_out.set_inst_name({name, "_out"});
        cg_mport_order.set_inst_name({name, "_order"});
`endif
    endfunction

    function void hs_bin(string ch, int st, string ok_name, string wait_name);
        if (st == 2) tr.hit({"hs.", ch, ".", ok_name});
        if (st == 1) tr.hit({"hs.", ch, ".", wait_name});
    endfunction

    function void out_bin(string ch, int n);
        if (n == 1)               tr.hit({"out.", ch, ".one"});
        if (n == 2 || n == 3)     tr.hit({"out.", ch, ".two_three"});
        if (n >= 4)               tr.hit({"out.", ch, ".four_plus"});
    endfunction

    function void sample_cycle(int aw, int w, int ar, int b, int r, int wr, int rd, int tg);
`ifndef AXI_NO_COV
        cg_mport_hs.sample(aw, w, ar, b, r);
        cg_mport_out.sample(wr, rd, tg);
`endif
        hs_bin("aw", aw, "accepted", "buffer_full");
        hs_bin("w",  w,  "accepted", "buffer_full");
        hs_bin("ar", ar, "accepted", "buffer_full");
        hs_bin("b",  b,  "taken",    "master_not_ready");
        hs_bin("r",  r,  "taken",    "master_not_ready");
        out_bin("wr", wr);
        out_bin("rd", rd);
        if (tg == 1) tr.hit("out.w_open_targets.one");
        if (tg >= 2) tr.hit("out.w_open_targets.two");
    endfunction

    function void sample_order(bit is_b, bit ooo);
`ifndef AXI_NO_COV
        cg_mport_order.sample(is_b, ooo);
`endif
        tr.hit({"order.", is_b ? "b" : "r", ".", ooo ? "out_of_order" : "in_order"});
    endfunction
endclass

// ---------------------------------------------------------------- slave port
class axi_sport_cov;
    axi_bin_tracker tr;

`ifndef AXI_NO_COV
    covergroup cg_sport_hs with function sample(int aw, int w, int ar, int b, int r);
        option.per_instance = 1;
        cp_aw : coverpoint aw { bins accepted = {2};  bins slave_not_ready = {1}; }
        cp_w  : coverpoint w  { bins accepted = {2};  bins slave_not_ready = {1}; }
        cp_ar : coverpoint ar { bins accepted = {2};  bins slave_not_ready = {1}; }
        cp_b  : coverpoint b  { bins taken    = {2};  bins buffer_full = {1}; }
        cp_r  : coverpoint r  { bins taken    = {2};  bins buffer_full = {1}; }
    endgroup

    covergroup cg_sport_wpend with function sample(int pm);
        option.per_instance = 1;
        cp_w_waiting_from : coverpoint pm { bins m0_only = {1};  bins m1_only = {2};  bins both_masters = {3}; }
    endgroup

    covergroup cg_sport_grant with function sample(bit is_aw, int prev, int cur);
        option.per_instance = 1;
        cp_channel : coverpoint is_aw { bins ar = {0};  bins aw = {1}; }
        cp_prev    : coverpoint prev  { bins m0 = {0};  bins m1 = {1}; }
        cp_cur     : coverpoint cur   { bins m0 = {0};  bins m1 = {1}; }
        x_grant    : cross cp_channel, cp_prev, cp_cur;
    endgroup
`endif

    function new(string name);
        string c [3];
        tr = new({name, " state coverage"});
        c[0] = "aw";  c[1] = "w";  c[2] = "ar";
        for (int i = 0; i < 3; i++) begin tr.add({"hs.", c[i], ".accepted"});  tr.add({"hs.", c[i], ".slave_not_ready"}); end
        tr.add("hs.b.taken");  tr.add("hs.b.buffer_full");
        tr.add("hs.r.taken");  tr.add("hs.r.buffer_full");
        tr.add("wpend.m0_only");  tr.add("wpend.m1_only");  tr.add("wpend.both_masters");
        foreach (c[i]) if (i != 1)
            for (int p = 0; p < 2; p++)
                for (int q = 0; q < 2; q++)
                    tr.add($sformatf("grant.%s.m%0d_then_m%0d", c[i], p, q));
`ifndef AXI_NO_COV
        cg_sport_hs    = new();
        cg_sport_wpend = new();
        cg_sport_grant = new();
        cg_sport_hs.set_inst_name({name, "_hs"});
        cg_sport_wpend.set_inst_name({name, "_wpend"});
        cg_sport_grant.set_inst_name({name, "_grant"});
`endif
    endfunction

    function void hs_bin(string ch, int st, string ok_name, string wait_name);
        if (st == 2) tr.hit({"hs.", ch, ".", ok_name});
        if (st == 1) tr.hit({"hs.", ch, ".", wait_name});
    endfunction

    // pm: bit 0 = an AW of M0 waits for W data, bit 1 = an AW of M1 waits
    function void sample_cycle(int aw, int w, int ar, int b, int r, int pm);
`ifndef AXI_NO_COV
        cg_sport_hs.sample(aw, w, ar, b, r);
        cg_sport_wpend.sample(pm);
`endif
        hs_bin("aw", aw, "accepted", "slave_not_ready");
        hs_bin("w",  w,  "accepted", "slave_not_ready");
        hs_bin("ar", ar, "accepted", "slave_not_ready");
        hs_bin("b",  b,  "taken",    "buffer_full");
        hs_bin("r",  r,  "taken",    "buffer_full");
        if (pm == 1) tr.hit("wpend.m0_only");
        if (pm == 2) tr.hit("wpend.m1_only");
        if (pm == 3) tr.hit("wpend.both_masters");
    endfunction

    function void sample_grant(bit is_aw, int prev, int cur);
`ifndef AXI_NO_COV
        cg_sport_grant.sample(is_aw, prev, cur);
`endif
        tr.hit($sformatf("grant.%s.m%0d_then_m%0d", is_aw ? "aw" : "ar", prev, cur));
    endfunction
endclass
