// =============================================================================
// axi_monitor.sv - passive monitor, used on master ports AND slave ports.
//   * rebuilds whole transactions from the pins and sends every finished
//     transaction to the scoreboard
//   * counts handshakes (tests use the counters to see where a request is)
//   * [PROTO] checks: VALID must stay high and the payload must not change
//     until READY; burst length must match AxLEN; no unexpected response
// =============================================================================
class axi_monitor;
    virtual axi_if       vif;
    bit                  is_slave;       // 1 = sits on a slave port of the crossbar
    int                  idx;
    string               name;
    mailbox #(axi_txn)   mbx;            // finished transactions -> scoreboard

    // handshake counters
    int  n_aw, n_w, n_wlast, n_b, n_ar, n_r, n_rlast;
    int  max_wr_out, max_rd_out;         // peak number of outstanding transactions
    int  proto_errors;
    bit  aw_order [$];                   // slave side: master bit of every accepted AW
    bit  ar_order [$];
    bit  sid_seen [32];                  // IDs seen on AW / AR of this port

    // transaction assembly
    axi_txn  aw_pend   [$];              // AW seen, data not attached yet
    axi_txn  wb_done   [$];              // complete W bursts not attached yet
    axi_txn  wr_wait_b [$];              // AW + W complete, waiting for B
    axi_txn  rd_pend   [$];              // AR seen, R not complete
    axi_txn  cur_w;

    // state coverage (only one of the two is created)
    axi_mport_cov  mcov;
    axi_sport_cov  scov;

    // previous-cycle values for the stability checks (AW, W, B, AR, R)
    bit          pv [5], pr [5];
    bit [127:0]  pp [5];

    function new(virtual axi_if vif, bit is_slave, int idx, mailbox #(axi_txn) mbx);
        this.vif = vif;  this.is_slave = is_slave;  this.idx = idx;  this.mbx = mbx;
        name = $sformatf("%s%0d", is_slave ? "S" : "M", idx);
        if (is_slave) scov = new(name);
        else          mcov = new(name);
    endfunction

    function void report_cov();
        if (is_slave) scov.tr.report();
        else          mcov.tr.report();
    endfunction

    // per-clock state coverage, sampled after the transactions were updated
    function void sample_cov(int aw, int w, int ar, int b, int r);
        int pm, tg;
        bit tgt_seen [3];
        if (is_slave) begin
            pm = 0;
            foreach (aw_pend[i]) pm = pm | (1 << aw_pend[i].master);
            scov.sample_cycle(aw, w, ar, b, r, pm);
        end else begin
            tg = 0;
            foreach (aw_pend[i]) tgt_seen[aw_pend[i].target()] = 1'b1;
            foreach (tgt_seen[i]) if (tgt_seen[i]) tg++;
            mcov.sample_cycle(aw, w, ar, b, r, n_aw - n_b, n_ar - n_rlast, tg);
        end
    endfunction

    function void perr(string msg);
        proto_errors++;
        $display("[%0t] [PROTO %s] ERROR: %s", $time, name, msg);
    endfunction

    task run();
        forever begin
            @(posedge vif.aclk);
            if (vif.arst_n !== 1'b1) begin
                for (int i = 0; i < 5; i++) pv[i] = 1'b0;
            end else begin
                int aw, w, ar, b, r;
                aw = axi_ch_state(vif.awvalid, vif.awready);
                w  = axi_ch_state(vif.wvalid,  vif.wready);
                ar = axi_ch_state(vif.arvalid, vif.arready);
                b  = axi_ch_state(vif.bvalid,  vif.bready);
                r  = axi_ch_state(vif.rvalid,  vif.rready);
                stability();
                collect();
                sample_cov(aw, w, ar, b, r);
            end
        end
    endtask

    function void stability();
        bit          cv [5], cr [5];
        bit [127:0]  cp [5];
        string       ch [5];
        ch[0] = "AW";  ch[1] = "W";  ch[2] = "B";  ch[3] = "AR";  ch[4] = "R";
        cv[0] = vif.awvalid;  cr[0] = vif.awready;
        cp[0] = {vif.awid, vif.awaddr, vif.awlen, vif.awsize, vif.awburst};
        cv[1] = vif.wvalid;   cr[1] = vif.wready;
        cp[1] = {vif.wdata, vif.wstrb, vif.wlast};
        cv[2] = vif.bvalid;   cr[2] = vif.bready;
        cp[2] = {vif.bid, vif.bresp};
        cv[3] = vif.arvalid;  cr[3] = vif.arready;
        cp[3] = {vif.arid, vif.araddr, vif.arlen, vif.arsize, vif.arburst};
        cv[4] = vif.rvalid;   cr[4] = vif.rready;
        cp[4] = {vif.rid, vif.rdata, vif.rresp, vif.rlast};
        for (int i = 0; i < 5; i++) begin
            if (pv[i] && !pr[i]) begin
                if (!cv[i])               perr({ch[i], "VALID went low before READY"});
                else if (cp[i] != pp[i])  perr({ch[i], " payload changed while waiting for READY"});
            end
            pv[i] = cv[i];  pr[i] = cr[i];  pp[i] = cp[i];
        end
    endfunction

    task collect();
        axi_txn t, b;
        int     found;

        // ---------------- AW
        if (vif.awvalid === 1'b1 && vif.awready === 1'b1) begin
            t = new();
            t.is_write = 1;  t.port = idx;  t.id = vif.awid;
            t.master   = is_slave ? int'(vif.awid[4]) : idx;
            t.addr = vif.awaddr;  t.len = vif.awlen;  t.size = vif.awsize;  t.burst = vif.awburst;
            t.t_req = $time;
            aw_pend.push_back(t);
            if (is_slave && aw_order.size() > 0) scov.sample_grant(1'b1, int'(aw_order[$]), int'(vif.awid[4]));
            aw_order.push_back(vif.awid[4]);
            sid_seen[vif.awid] = 1'b1;
            n_aw++;
            if (n_aw - n_b > max_wr_out) max_wr_out = n_aw - n_b;
        end

        // ---------------- W
        if (vif.wvalid === 1'b1 && vif.wready === 1'b1) begin
            if (cur_w == null) cur_w = new();
            cur_w.data.push_back(vif.wdata);
            cur_w.strb.push_back(vif.wstrb);
            n_w++;
            if (vif.wlast === 1'b1) begin
                wb_done.push_back(cur_w);
                cur_w = null;
                n_wlast++;
            end
        end

        // attach W bursts to AWs: both are in AW order (AXI4 has no WID)
        while (aw_pend.size() > 0 && wb_done.size() > 0) begin
            t = aw_pend.pop_front();
            b = wb_done.pop_front();
            t.data = b.data;
            t.strb = b.strb;
            if (t.data.size() != int'(t.len) + 1)
                perr($sformatf("write burst has %0d beats, AWLEN+1 = %0d", t.data.size(), int'(t.len) + 1));
            wr_wait_b.push_back(t);
        end

        // ---------------- B
        if (vif.bvalid === 1'b1 && vif.bready === 1'b1) begin
            n_b++;
            found = -1;
            for (int i = 0; i < wr_wait_b.size(); i++)
                if (found < 0 && wr_wait_b[i].id == vif.bid) found = i;
            if (found < 0) perr($sformatf("B with BID 0x%0h but no finished write with this ID", vif.bid));
            else begin
                t = wr_wait_b[found];
                wr_wait_b.delete(found);
                if (!is_slave) mcov.sample_order(1'b1, found > 0);
                t.resp = vif.bresp;  t.t_done = $time;
                mbx.put(t);
            end
        end

        // ---------------- AR
        if (vif.arvalid === 1'b1 && vif.arready === 1'b1) begin
            t = new();
            t.is_write = 0;  t.port = idx;  t.id = vif.arid;
            t.master   = is_slave ? int'(vif.arid[4]) : idx;
            t.addr = vif.araddr;  t.len = vif.arlen;  t.size = vif.arsize;  t.burst = vif.arburst;
            t.t_req = $time;
            rd_pend.push_back(t);
            if (is_slave && ar_order.size() > 0) scov.sample_grant(1'b0, int'(ar_order[$]), int'(vif.arid[4]));
            ar_order.push_back(vif.arid[4]);
            sid_seen[vif.arid] = 1'b1;
            n_ar++;
            if (n_ar - n_rlast > max_rd_out) max_rd_out = n_ar - n_rlast;
        end

        // ---------------- R  (same ID -> oldest outstanding read with that ID)
        if (vif.rvalid === 1'b1 && vif.rready === 1'b1) begin
            n_r++;
            found = -1;
            for (int i = 0; i < rd_pend.size(); i++)
                if (found < 0 && rd_pend[i].id == vif.rid) found = i;
            if (found < 0) perr($sformatf("R with RID 0x%0h but no outstanding read with this ID", vif.rid));
            else begin
                t = rd_pend[found];
                t.data.push_back(vif.rdata);
                if (vif.rresp != RESP_OKAY) t.resp = vif.rresp;
                if ((vif.rlast === 1'b1) != (t.data.size() == int'(t.len) + 1))
                    perr($sformatf("RLAST = %b on beat %0d of a %0d-beat read", vif.rlast, t.data.size(), int'(t.len) + 1));
                if (vif.rlast === 1'b1) begin
                    rd_pend.delete(found);
                    if (!is_slave) mcov.sample_order(1'b0, found > 0);
                    n_rlast++;
                    t.t_done = $time;
                    mbx.put(t);
                end
            end
        end
    endtask
endclass
