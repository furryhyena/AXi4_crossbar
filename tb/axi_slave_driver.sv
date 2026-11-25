// =============================================================================
// axi_slave_driver.sv - slave model = byte memory + AXI responder.
//   * accepts AW / W / AR with random READY (cfg.*ready_pct)
//   * writes memory with strobes, answers B per burst
//   * answers reads from memory, len+1 beats, RLAST on the last beat
//   * responses are returned in the order the requests arrived
//   * SLVERR window: writes there are dropped, B / R carry SLVERR
//   IDs are 5 bits here ({master, id}) and are returned unchanged.
// =============================================================================
class axi_slave_driver;
    virtual axi_if       vif;
    axi_agent_cfg        cfg;
    int                  idx;
    int                  errors;

    bit [7:0]            mem [bit [27:0]];     // byte memory, key = addr[27:0]
    axi_txn              aw_q [$];             // accepted AWs waiting for W data
    axi_txn              b_q  [$];             // finished write bursts waiting for B
    axi_txn              ar_q [$];             // accepted ARs waiting for R data

    function new(virtual axi_if vif, axi_agent_cfg cfg, int idx);
        this.vif = vif;  this.cfg = cfg;  this.idx = idx;
    endfunction

    function bit [7:0] rd_byte(bit [31:0] a);
        if (mem.exists(a[27:0])) return mem[a[27:0]];
        return 8'h00;
    endfunction

    task run();
        vif.awready <= 1'b0;  vif.wready <= 1'b0;  vif.arready <= 1'b0;
        vif.bvalid  <= 1'b0;  vif.bid <= '0;  vif.bresp <= '0;
        vif.rvalid  <= 1'b0;  vif.rid <= '0;  vif.rdata <= '0;  vif.rresp <= '0;  vif.rlast <= 1'b0;
        fork
            aw_ch();
            w_ch();
            b_ch();
            ar_ch();
            r_ch();
        join_none
    endtask

    task aw_ch();
        axi_txn t;
        forever begin
            @(posedge vif.aclk);
            if (vif.awvalid === 1'b1 && vif.awready === 1'b1) begin
                t = new();
                t.is_write = 1;  t.id = vif.awid;  t.addr = vif.awaddr;  t.len = vif.awlen;
                aw_q.push_back(t);
            end
            vif.awready <= ($urandom_range(0, 99) < cfg.awready_pct);
        end
    endtask

    task w_ch();
        axi_txn    cur;
        bit [31:0] a;
        cur = null;
        forever begin
            @(posedge vif.aclk);
            if (vif.wvalid === 1'b1 && vif.wready === 1'b1) begin
                if (cur == null) begin
                    if (aw_q.size() == 0) begin
                        errors++;
                        $display("[%0t] [S%0d DRV] ERROR: W beat arrived before any AW", $time, idx);
                    end else begin
                        cur = aw_q.pop_front();
                        a   = {cur.addr[31:3], 3'b000};
                    end
                end
                if (cur != null) begin
                    if (!cfg.in_slverr(cur.addr))
                        for (int b = 0; b < 8; b++)
                            if (vif.wstrb[b]) mem[a[27:0] + b] = vif.wdata[8*b +: 8];
                    a = a + 8;
                    if (vif.wlast === 1'b1) begin
                        b_q.push_back(cur);
                        cur = null;
                    end
                end
            end
            vif.wready <= ($urandom_range(0, 99) < cfg.wready_pct);
        end
    endtask

    task b_ch();
        axi_txn t;
        forever begin
            @(posedge vif.aclk);
            if (b_q.size() > 0) begin
                t = b_q.pop_front();
                repeat ($urandom_range(0, cfg.resp_delay_max)) @(posedge vif.aclk);
                vif.bvalid <= 1'b1;
                vif.bid    <= t.id;
                vif.bresp  <= cfg.in_slverr(t.addr) ? RESP_SLVERR : RESP_OKAY;
                do @(posedge vif.aclk); while (vif.bready !== 1'b1);
                vif.bvalid <= 1'b0;
            end
        end
    endtask

    task ar_ch();
        axi_txn t;
        forever begin
            @(posedge vif.aclk);
            if (vif.arvalid === 1'b1 && vif.arready === 1'b1) begin
                t = new();
                t.is_write = 0;  t.id = vif.arid;  t.addr = vif.araddr;  t.len = vif.arlen;
                ar_q.push_back(t);
            end
            vif.arready <= ($urandom_range(0, 99) < cfg.arready_pct);
        end
    endtask

    task r_ch();
        axi_txn    t;
        bit [31:0] a;
        bit [63:0] d;
        forever begin
            @(posedge vif.aclk);
            if (ar_q.size() > 0) begin
                t = ar_q.pop_front();
                a = {t.addr[31:3], 3'b000};
                repeat ($urandom_range(0, cfg.resp_delay_max)) @(posedge vif.aclk);
                for (int i = 0; i <= t.len; i++) begin
                    repeat ($urandom_range(0, cfg.rvalid_gap_max)) @(posedge vif.aclk);
                    for (int b = 0; b < 8; b++) d[8*b +: 8] = rd_byte(a + b);
                    vif.rvalid <= 1'b1;
                    vif.rid    <= t.id;
                    vif.rdata  <= d;
                    vif.rresp  <= cfg.in_slverr(t.addr) ? RESP_SLVERR : RESP_OKAY;
                    vif.rlast  <= (i == t.len);
                    do @(posedge vif.aclk); while (vif.rready !== 1'b1);
                    vif.rvalid <= 1'b0;
                    vif.rlast  <= 1'b0;
                    a = a + 8;
                end
            end
        end
    endtask
endclass
