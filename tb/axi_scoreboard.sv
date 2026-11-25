// =============================================================================
// axi_scoreboard.sv - compares what the masters saw with what the slaves saw.
//
// For every transaction that completes on a MASTER port:
//   [ROUTE]  the same request (ADDR, LEN, SIZE, BURST) reached the slave
//            selected by the address map, exactly once
//   [ID]     slave-side ID = {master index, master ID}; the master got its
//            own 4-bit ID back
//   [WDATA]  write data and strobes reached the slave unchanged
//   [RDATA]  read data returned to the master = data the slave sent
//   [RESP]   BRESP / RRESP at the master = response the slave gave
//   [DECERR] unmapped address: DECERR, len+1 read beats, never seen by a slave
//   [REF]    (when ref_check = 1) read data = reference memory, which is
//            updated from the writes the slaves really received
// At the end:
//   [GHOST]  nothing is left on a slave port that no master asked for
// =============================================================================
class axi_scoreboard;
    mailbox #(axi_txn)  m_mbx;            // from the master-port monitors
    mailbox #(axi_txn)  s_mbx;            // from the slave-port monitors
    axi_coverage        cov;

    axi_txn    sq_wr [2][$];              // slave-side writes not matched yet
    axi_txn    sq_rd [2][$];              // slave-side reads  not matched yet
    bit [7:0]  ref_mem0 [bit [27:0]];     // reference memory of S0
    bit [7:0]  ref_mem1 [bit [27:0]];     // reference memory of S1

    bit  ref_check = 0;                   // tests switch it on for read-back phases
    bit  quiet     = 0;                   // +SB_QUIET : no line per transaction

    int  checks, errors;
    int  n_done;                          // transactions completed on master ports
    int  n_master_done [2];
    int  n_slave_seen  [2];
    int  n_okay, n_slverr, n_decerr;
    int  n_route, n_id, n_wdata, n_rdata, n_resp, n_ref, n_dec;

    function new(mailbox #(axi_txn) m_mbx, mailbox #(axi_txn) s_mbx);
        this.m_mbx = m_mbx;  this.s_mbx = s_mbx;
        cov   = new();
        quiet = $test$plusargs("SB_QUIET");
    endfunction

    task run();
        fork
            forever begin axi_txn t;  s_mbx.get(t);  on_slave(t);  end
            forever begin axi_txn t;  m_mbx.get(t);  on_master(t); end
        join_none
    endtask

    function void fail(string msg);
        errors++;
        $display("[%0t] [SB] ERROR: %s", $time, msg);
    endfunction

    function bit [7:0] ref_rd(int s, bit [27:0] a);
        if (s == 0) return ref_mem0.exists(a) ? ref_mem0[a] : 8'h00;
        return ref_mem1.exists(a) ? ref_mem1[a] : 8'h00;
    endfunction

    function bit same_data(axi_txn a, axi_txn b);
        if (a.data.size() != b.data.size()) return 0;
        for (int i = 0; i < a.data.size(); i++)
            if (a.data[i] != b.data[i]) return 0;
        return 1;
    endfunction

    function bit same_strb(axi_txn a, axi_txn b);
        if (a.strb.size() != b.strb.size()) return 0;
        for (int i = 0; i < a.strb.size(); i++)
            if (a.strb[i] != b.strb[i]) return 0;
        return 1;
    endfunction

    // ------------------------------------------------------------ slave side
    function void on_slave(axi_txn t);
        bit [27:0] a;
        n_slave_seen[t.port]++;
        if (t.is_write) begin
            sq_wr[t.port].push_back(t);
            if (t.resp == RESP_OKAY) begin          // mirror what the slave memory did
                a = {t.addr[27:3], 3'b000};
                for (int i = 0; i < t.data.size(); i++) begin
                    for (int b = 0; b < 8; b++)
                        if (t.strb[i][b]) begin
                            if (t.port == 0) ref_mem0[a + b] = t.data[i][8*b +: 8];
                            else             ref_mem1[a + b] = t.data[i][8*b +: 8];
                        end
                    a = a + 8;
                end
            end
        end else sq_rd[t.port].push_back(t);
    endfunction

    // ------------------------------------------------------------ master side
    function void on_master(axi_txn t);
        int        tgt, found;
        bit [4:0]  exp_sid;
        axi_txn    s;
        string     hdr, res;
        bit        ok, route_ok, data_ok, resp_ok, ref_ok;
        bit [27:0] a;
        bit [63:0] exp;

        n_done++;
        n_master_done[t.master]++;
        cov.sample_txn(t);
        case (t.resp)
            RESP_OKAY:   n_okay++;
            RESP_SLVERR: n_slverr++;
            default:     n_decerr++;
        endcase

        tgt     = t.target();
        exp_sid = {t.master[0], t.id[3:0]};
        hdr     = $sformatf("%s M%0d id=0x%0h addr=0x%08h beats=%0d", t.kind(), t.master, t.id[3:0],
                            t.addr, int'(t.len) + 1);

        // ---------------- unmapped address: answered inside the crossbar
        if (tgt == 2) begin
            ok = (t.resp == RESP_DECERR);
            if (!t.is_write) begin
                if (t.data.size() != int'(t.len) + 1) ok = 0;
                for (int i = 0; i < t.data.size(); i++) if (t.data[i] != 64'h0) ok = 0;
            end
            checks++;  n_dec++;
            if (!quiet || !ok)
                $display("[%0t] [SB] %s -> unmapped | resp=%s (expected DECERR)%s : %s", $time, hdr,
                         resp_name(t.resp), t.is_write ? "" : $sformatf(", %0d zero beats", t.data.size()),
                         ok ? "PASS" : "FAIL");
            if (!ok) fail({"[DECERR] wrong answer for unmapped address: ", hdr});
            return;
        end

        // ---------------- find the same request on the slave port
        found = -1;
        if (t.is_write) begin
            for (int i = 0; i < sq_wr[tgt].size(); i++)
                if (found < 0 && sq_wr[tgt][i].id == exp_sid) found = i;
        end else begin
            for (int i = 0; i < sq_rd[tgt].size(); i++)
                if (found < 0 && sq_rd[tgt][i].id == exp_sid) found = i;
        end
        checks++;  n_route++;
        if (found < 0) begin
            fail($sformatf("[ROUTE] %s : S%0d never completed a %s with slave-side ID 0x%02h",
                           hdr, tgt, t.kind(), exp_sid));
            return;
        end
        if (t.is_write) begin s = sq_wr[tgt][found];  sq_wr[tgt].delete(found); end
        else            begin s = sq_rd[tgt][found];  sq_rd[tgt].delete(found); end

        route_ok = (s.addr == t.addr) && (s.len == t.len) && (s.size == t.size) && (s.burst == t.burst);
        if (!route_ok) fail($sformatf("[ROUTE] %s : slave saw addr=0x%08h len=%0d size=%0d burst=%0d",
                                      hdr, s.addr, s.len, s.size, s.burst));
        checks++;  n_id++;          // found by ID => slave-side ID is {master, id}

        data_ok = same_data(s, t);
        if (t.is_write) data_ok = data_ok && same_strb(s, t);
        checks++;
        if (t.is_write) n_wdata++; else n_rdata++;
        if (!data_ok) fail($sformatf("[%s] %s : data at the master and at S%0d differ",
                                     t.is_write ? "WDATA" : "RDATA", hdr, tgt));

        resp_ok = (s.resp == t.resp);
        checks++;  n_resp++;
        if (!resp_ok) fail($sformatf("[RESP] %s : master got %s, S%0d sent %s", hdr,
                                     resp_name(t.resp), tgt, resp_name(s.resp)));

        // ---------------- reference memory (read-back phases only)
        ref_ok = 1;
        res    = "";
        if (!t.is_write && ref_check && t.resp == RESP_OKAY) begin
            a = {t.addr[27:3], 3'b000};
            for (int i = 0; i < t.data.size(); i++) begin
                for (int b = 0; b < 8; b++) exp[8*b +: 8] = ref_rd(tgt, a + b);
                if (t.data[i] != exp) begin
                    ref_ok = 0;
                    fail($sformatf("[REF] %s beat %0d : got 0x%016h, reference memory has 0x%016h",
                                   hdr, i, t.data[i], exp));
                end
                a = a + 8;
            end
            checks++;  n_ref++;
            res = ref_ok ? ", ref-mem OK" : ", ref-mem MISMATCH";
        end

        if (!quiet)
            $display("[%0t] [SB] %s -> S%0d sid=0x%02h addr=0x%08h | route %s, %s %0d beats %s (first 0x%016h), resp %s/%s%s : %s",
                     $time, hdr, tgt, s.id, s.addr, route_ok ? "OK" : "BAD",
                     t.is_write ? "wdata" : "rdata", t.data.size(), data_ok ? "OK" : "BAD",
                     (t.data.size() > 0) ? t.data[0] : 64'h0,
                     resp_name(t.resp), resp_name(s.resp), res,
                     (route_ok && data_ok && resp_ok && ref_ok) ? "PASS" : "FAIL");
    endfunction

    // ------------------------------------------------------------ end of test
    function void final_report();
        for (int s = 0; s < 2; s++) begin
            checks++;
            if (sq_wr[s].size() + sq_rd[s].size() != 0) begin
                fail($sformatf("[GHOST] S%0d completed %0d writes and %0d reads that no master received a response for",
                               s, sq_wr[s].size(), sq_rd[s].size()));
            end
        end
        $display(" ---------------- scoreboard summary ----------------");
        $display(" transactions completed : %0d  (M0 %0d, M1 %0d)", n_done, n_master_done[0], n_master_done[1]);
        $display(" seen by slaves         : S0 %0d, S1 %0d   answered by crossbar (DECERR) %0d",
                 n_slave_seen[0], n_slave_seen[1], n_dec);
        $display(" responses at masters   : OKAY %0d, SLVERR %0d, DECERR %0d", n_okay, n_slverr, n_decerr);
        $display(" checks : ROUTE %0d  ID %0d  WDATA %0d  RDATA %0d  RESP %0d  DECERR %0d  REF %0d  GHOST 2",
                 n_route, n_id, n_wdata, n_rdata, n_resp, n_dec, n_ref);
        cov.report();
    endfunction
endclass
