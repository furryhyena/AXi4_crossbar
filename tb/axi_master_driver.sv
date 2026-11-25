// =============================================================================
// axi_master_driver.sv - drives one master port of the crossbar.
//   Five independent threads (AW, W, AR, BREADY, RREADY), so the channels are
//   independent like in a real master: W data may be sent before, with or
//   after its AW, and several transactions can be outstanding.
//   All pins are driven with non-blocking assignments at the clock edge.
// =============================================================================
class axi_master_driver;
    virtual axi_if       vif;
    axi_agent_cfg        cfg;
    int                  idx;
    mailbox #(axi_txn)   mbx;                      // from the generator
    mailbox #(axi_txn)   aw_mbx, w_mbx, ar_mbx;    // per-channel queues

    function new(virtual axi_if vif, axi_agent_cfg cfg, mailbox #(axi_txn) mbx, int idx);
        this.vif = vif;  this.cfg = cfg;  this.mbx = mbx;  this.idx = idx;
        aw_mbx = new();  w_mbx = new();  ar_mbx = new();
    endfunction

    task run();
        vif.awvalid <= 1'b0;  vif.awid <= '0;  vif.awaddr <= '0;  vif.awlen <= '0;
        vif.awsize  <= 3'd3;  vif.awburst <= 2'b01;
        vif.wvalid  <= 1'b0;  vif.wdata <= '0;  vif.wstrb <= '0;  vif.wlast <= 1'b0;
        vif.arvalid <= 1'b0;  vif.arid <= '0;  vif.araddr <= '0;  vif.arlen <= '0;
        vif.arsize  <= 3'd3;  vif.arburst <= 2'b01;
        vif.bready  <= 1'b0;  vif.rready <= 1'b0;
        fork
            dispatch();
            aw_ch();
            w_ch();
            ar_ch();
            ready_ch();
        join_none
    endtask

    // generator mailbox -> channel mailboxes
    task dispatch();
        axi_txn t;
        forever begin
            mbx.get(t);
            if (t.is_write) begin aw_mbx.put(t);  w_mbx.put(t); end
            else            ar_mbx.put(t);
        end
    endtask

    task aw_ch();
        axi_txn t;
        forever begin
            aw_mbx.get(t);
            repeat ($urandom_range(0, cfg.aw_gap_max)) @(posedge vif.aclk);
            vif.awvalid <= 1'b1;
            vif.awid    <= t.id;     vif.awaddr  <= t.addr;  vif.awlen <= t.len;
            vif.awsize  <= t.size;   vif.awburst <= t.burst;
            do @(posedge vif.aclk); while (vif.awready !== 1'b1);
            vif.awvalid <= 1'b0;
        end
    endtask

    task w_ch();
        axi_txn t;
        forever begin
            w_mbx.get(t);
            while (cfg.w_hold) @(posedge vif.aclk);
            for (int i = 0; i <= t.len; i++) begin
                repeat ($urandom_range(0, cfg.w_gap_max)) @(posedge vif.aclk);
                vif.wvalid <= 1'b1;
                vif.wdata  <= t.data[i];
                vif.wstrb  <= t.strb[i];
                vif.wlast  <= (i == t.len);
                do @(posedge vif.aclk); while (vif.wready !== 1'b1);
                vif.wvalid <= 1'b0;
                vif.wlast  <= 1'b0;
            end
        end
    endtask

    task ar_ch();
        axi_txn t;
        forever begin
            ar_mbx.get(t);
            repeat ($urandom_range(0, cfg.ar_gap_max)) @(posedge vif.aclk);
            vif.arvalid <= 1'b1;
            vif.arid    <= t.id;     vif.araddr  <= t.addr;  vif.arlen <= t.len;
            vif.arsize  <= t.size;   vif.arburst <= t.burst;
            do @(posedge vif.aclk); while (vif.arready !== 1'b1);
            vif.arvalid <= 1'b0;
        end
    endtask

    // BREADY / RREADY backpressure
    task ready_ch();
        forever begin
            @(posedge vif.aclk);
            vif.bready <= ($urandom_range(0, 99) < cfg.bready_pct);
            vif.rready <= ($urandom_range(0, 99) < cfg.rready_pct);
        end
    endtask
endclass
