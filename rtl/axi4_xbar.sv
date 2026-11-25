`timescale 1ns / 1ps

// =============================================================================
// axi4_xbar.sv  -  AXI4 2 masters x 2 slaves crossbar
//
// Architecture summary
//   * Targets: T0 = S0, T1 = S1, T2 = internal DECERR responder.
//     Address map: 0x0xxx_xxxx -> S0, 0x1xxx_xxxx -> S1, anything else -> T2.
//
//   * BUFFERS (the crossbar does the waiting, not the master / slave)
//       master side : one FIFO per request channel  (AW, W, AR)  per master
//       slave side  : one FIFO per response channel (B, R)       per slave
//     A master request is accepted into its FIFO as soon as there is space
//     (xREADY = !full). Decode, request gate and arbitration work on the FIFO
//     OUTPUT, so a request that cannot be forwarded yet waits INSIDE the
//     crossbar. In the same way a slave response is taken into the B / R FIFO
//     even if the destination master is not ready.
//     xREADY goes low only when a FIFO is full (normal AXI backpressure).
//
//   * WIDENED SLAVE-SIDE ID
//       slave ID = {master index, master ID}      (SID_WIDTH = ID_WIDTH + 1)
//     Two masters can use the same ID at the same slave at the same time:
//     the slave sees two different IDs. The B / R demux routes a response
//     with the top bit of BID / RID; the bit is removed before the response
//     is given to the master.
//
//   * ID RULE: the crossbar does not check IDs. The master must make sure
//     that its transactions with the same ID that are outstanding at the
//     same time go to ONE slave, so same-ID responses return in order.
//
//   * ARBITRATION: one round-robin arbiter (xbar_arb) per target and request
//     channel. The grant is locked until the target accepts, so the target
//     sees stable VALID / payload.
//
//   * W routing (AXI4 has no WID, W follows AW order):
//       - per master W-order FIFO (u_wsel) : target of every forwarded AW,
//         in AW order (which slave the next W burst of this master is for)
//       - per target W-order FIFO (u_tq)   : master of every accepted AW,
//         in AW order (which master the next W burst of this slave is from)
//       Both FIFOs are written at the same AW handshake. The W mux of target
//       t connects master m only when head(T fifo t) == m (sel) and
//       head(M fifo m) == t (en). Both FIFOs pop on the WLAST handshake.
//       Because both FIFOs see every AW in the same order, no W deadlock
//       is possible.
//
//   * B / R: per master a round-robin response selector (xbar_rsp_sel)
//     picks one target that has a response for it; locked while
//     VALID && !READY.
//
//   * AW / AR payload muxes are AND-OR muxes on the one-hot grant, so a
//     target that is not granted sees an all-zero payload.
//
// Note: W data is presented to a slave only after that slave has accepted
// the matching AW.
// =============================================================================

// -----------------------------------------------------------------------------
// Small synchronous FIFO (push / pop). Used as channel buffer and order FIFO.
//   stream use:  in_ready = !full,  push = in_valid && !full
//                out_valid = !empty, pop = out_valid && out_ready
// -----------------------------------------------------------------------------
module xbar_fifo #(
    parameter int WIDTH = 2,
    parameter int DEPTH = 8          // power of 2
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             push,
    input  logic [WIDTH-1:0] din,
    input  logic             pop,
    output logic [WIDTH-1:0] dout,
    output logic             empty,
    output logic             full
);
    localparam int PW = $clog2(DEPTH);

    logic [WIDTH-1:0] mem [DEPTH];
    logic [PW:0]      wptr, rptr;

    assign empty = (wptr == rptr);
    assign full  = (wptr[PW] != rptr[PW]) && (wptr[PW-1:0] == rptr[PW-1:0]);
    assign dout  = empty ? '0 : mem[rptr[PW-1:0]];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= '0;
            rptr <= '0;
        end else begin
            if (push && !full) begin
                mem[wptr[PW-1:0]] <= din;
                wptr              <= wptr + 1'b1;
            end
            if (pop && !empty) rptr <= rptr + 1'b1;
        end
    end
endmodule

// -----------------------------------------------------------------------------
// Round-robin arbiter for one target, two masters, with grant lock.
//   gnt is one-hot (or zero). Once a grant is given and the target is not
//   ready, the same grant is held until the handshake.
// -----------------------------------------------------------------------------
module xbar_arb (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [1:0] req,
    input  logic       ready,     // target READY
    output logic [1:0] gnt
);
    logic last;                   // last granted master
    logic lock, lock_m;

    always_comb begin
        if (lock)      gnt = lock_m ? 2'b10 : 2'b01;   // hold until handshake
        else if (&req) gnt = last   ? 2'b01 : 2'b10;   // round-robin
        else           gnt = req;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last   <= 1'b0;
            lock   <= 1'b0;
            lock_m <= 1'b0;
        end else begin
            lock <= (|gnt) && !ready;
            if ((|gnt) && !ready) lock_m <= gnt[1];
            if ((|gnt) &&  ready) last   <= gnt[1];
        end
    end
endmodule

// -----------------------------------------------------------------------------
// Response selector (one per master, for B and for R)
//   Picks one of the targets that currently present a response for this
//   master, round-robin. The selection is locked while VALID && !READY so the
//   master sees a stable VALID and payload (AXI rule).
// -----------------------------------------------------------------------------
module xbar_rsp_sel #(
    parameter int NT = 3
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic [NT-1:0] cand,    // target t has a response for this master
    input  logic          ready,   // master READY
    output logic          valid,   // a response is selected
    output logic [1:0]    sel      // selected target
);
    logic       lock;
    logic [1:0] lsel, last;

    int idx;

    always_comb begin
        valid = 1'b0;
        sel   = '0;
        idx   = 0;
        if (lock) begin
            valid = 1'b1;
            sel   = lsel;
        end else begin
            for (int k = 1; k <= NT; k++) begin
                idx = int'(last) + k;
                if (idx >= NT) idx = idx - NT;
                if (!valid && cand[idx]) begin
                    valid = 1'b1;
                    sel   = 2'(idx);
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lock <= 1'b0;
            lsel <= '0;
            last <= 2'(NT - 1);
        end else begin
            lock <= valid && !ready;
            if (valid && !ready) lsel <= sel;
            if (valid && ready)  last <= sel;
        end
    end
endmodule

// -----------------------------------------------------------------------------
// Top level
// -----------------------------------------------------------------------------
module axi4_xbar #(
    parameter  int NUM_MASTERS = 2,
    parameter  int NUM_SLAVES  = 2,
    parameter  int DATA_WIDTH  = 64,
    parameter  int ADDR_WIDTH  = 32,
    parameter  int ID_WIDTH    = 4,
    parameter  int BUF_DEPTH   = 2,                        // channel FIFO depth (power of 2)
    localparam int SID_WIDTH   = ID_WIDTH + $clog2(NUM_MASTERS)   // slave-side ID width
) (
    input  logic                                    aclk,
    input  logic                                    arst_n,

    // Master interfaces (ID_WIDTH bits of ID)
    input  logic [NUM_MASTERS-1:0][ID_WIDTH-1:0]    m_awid,
    input  logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0]  m_awaddr,
    input  logic [NUM_MASTERS-1:0][7:0]             m_awlen,
    input  logic [NUM_MASTERS-1:0][2:0]             m_awsize,
    input  logic [NUM_MASTERS-1:0][1:0]             m_awburst,
    input  logic [NUM_MASTERS-1:0]                  m_awvalid,
    output logic [NUM_MASTERS-1:0]                  m_awready,

    input  logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0]  m_wdata,
    input  logic [NUM_MASTERS-1:0][DATA_WIDTH/8-1:0]m_wstrb,
    input  logic [NUM_MASTERS-1:0]                  m_wlast,
    input  logic [NUM_MASTERS-1:0]                  m_wvalid,
    output logic [NUM_MASTERS-1:0]                  m_wready,

    output logic [NUM_MASTERS-1:0][ID_WIDTH-1:0]    m_bid,
    output logic [NUM_MASTERS-1:0][1:0]             m_bresp,
    output logic [NUM_MASTERS-1:0]                  m_bvalid,
    input  logic [NUM_MASTERS-1:0]                  m_bready,

    input  logic [NUM_MASTERS-1:0][ID_WIDTH-1:0]    m_arid,
    input  logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0]  m_araddr,
    input  logic [NUM_MASTERS-1:0][7:0]             m_arlen,
    input  logic [NUM_MASTERS-1:0][2:0]             m_arsize,
    input  logic [NUM_MASTERS-1:0][1:0]             m_arburst,
    input  logic [NUM_MASTERS-1:0]                  m_arvalid,
    output logic [NUM_MASTERS-1:0]                  m_arready,

    output logic [NUM_MASTERS-1:0][ID_WIDTH-1:0]    m_rid,
    output logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0]  m_rdata,
    output logic [NUM_MASTERS-1:0][1:0]             m_rresp,
    output logic [NUM_MASTERS-1:0]                  m_rlast,
    output logic [NUM_MASTERS-1:0]                  m_rvalid,
    input  logic [NUM_MASTERS-1:0]                  m_rready,

    // Slave interfaces (SID_WIDTH bits of ID = {master index, master ID})
    output logic [NUM_SLAVES-1:0][SID_WIDTH-1:0]    s_awid,
    output logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]   s_awaddr,
    output logic [NUM_SLAVES-1:0][7:0]              s_awlen,
    output logic [NUM_SLAVES-1:0][2:0]              s_awsize,
    output logic [NUM_SLAVES-1:0][1:0]              s_awburst,
    output logic [NUM_SLAVES-1:0]                   s_awvalid,
    input  logic [NUM_SLAVES-1:0]                   s_awready,

    output logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]   s_wdata,
    output logic [NUM_SLAVES-1:0][DATA_WIDTH/8-1:0] s_wstrb,
    output logic [NUM_SLAVES-1:0]                   s_wlast,
    output logic [NUM_SLAVES-1:0]                   s_wvalid,
    input  logic [NUM_SLAVES-1:0]                   s_wready,

    input  logic [NUM_SLAVES-1:0][SID_WIDTH-1:0]    s_bid,
    input  logic [NUM_SLAVES-1:0][1:0]              s_bresp,
    input  logic [NUM_SLAVES-1:0]                   s_bvalid,
    output logic [NUM_SLAVES-1:0]                   s_bready,

    output logic [NUM_SLAVES-1:0][SID_WIDTH-1:0]    s_arid,
    output logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]   s_araddr,
    output logic [NUM_SLAVES-1:0][7:0]              s_arlen,
    output logic [NUM_SLAVES-1:0][2:0]              s_arsize,
    output logic [NUM_SLAVES-1:0][1:0]              s_arburst,
    output logic [NUM_SLAVES-1:0]                   s_arvalid,
    input  logic [NUM_SLAVES-1:0]                   s_arready,

    input  logic [NUM_SLAVES-1:0][SID_WIDTH-1:0]    s_rid,
    input  logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]   s_rdata,
    input  logic [NUM_SLAVES-1:0][1:0]              s_rresp,
    input  logic [NUM_SLAVES-1:0]                   s_rlast,
    input  logic [NUM_SLAVES-1:0]                   s_rvalid,
    output logic [NUM_SLAVES-1:0]                   s_rready
);

    // This implementation is the fixed 2x2 configuration of the training project.
    if (NUM_MASTERS != 2 || NUM_SLAVES != 2) begin : g_cfg_check
        $error("axi4_xbar: only NUM_MASTERS=2, NUM_SLAVES=2 is supported");
    end

    localparam int         NT     = NUM_SLAVES + 1;   // T0, T1, T2 (DECERR)
    localparam int         STRB_W = DATA_WIDTH / 8;
    localparam logic [1:0] DECERR = 2'b11;

    localparam int AX_W = ID_WIDTH + ADDR_WIDTH + 8 + 3 + 2;   // AW / AR FIFO word
    localparam int W_W  = DATA_WIDTH + STRB_W + 1;             // W  FIFO word
    localparam int B_W  = SID_WIDTH + 2;                       // B  FIFO word
    localparam int R_W  = SID_WIDTH + DATA_WIDTH + 2 + 1;      // R  FIFO word

    // -------------------------------------------------------------------------
    // 1. Master-side request buffers (AW, W, AR)
    //    master -> [FIFO] -> awq_* / wq_* / arq_*  (used by the routing logic)
    // -------------------------------------------------------------------------
    logic [1:0]                  awq_valid, awq_ready, awq_empty, awq_full;
    logic [1:0][ID_WIDTH-1:0]    awq_id;
    logic [1:0][ADDR_WIDTH-1:0]  awq_addr;
    logic [1:0][7:0]             awq_len;
    logic [1:0][2:0]             awq_size;
    logic [1:0][1:0]             awq_burst;

    logic [1:0]                  wq_valid, wq_ready, wq_empty, wq_full, wq_last;
    logic [1:0][DATA_WIDTH-1:0]  wq_data;
    logic [1:0][STRB_W-1:0]      wq_strb;

    logic [1:0]                  arq_valid, arq_ready, arq_empty, arq_full;
    logic [1:0][ID_WIDTH-1:0]    arq_id;
    logic [1:0][ADDR_WIDTH-1:0]  arq_addr;
    logic [1:0][7:0]             arq_len;
    logic [1:0][2:0]             arq_size;
    logic [1:0][1:0]             arq_burst;

    for (genvar m = 0; m < 2; m++) begin : g_mbuf
        // AW buffer
        xbar_fifo #(.WIDTH(AX_W), .DEPTH(BUF_DEPTH)) u_aw_buf (
            .clk(aclk), .rst_n(arst_n),
            .push(m_awvalid[m] && !awq_full[m]),
            .din({m_awid[m], m_awaddr[m], m_awlen[m], m_awsize[m], m_awburst[m]}),
            .pop(awq_valid[m] && awq_ready[m]),
            .dout({awq_id[m], awq_addr[m], awq_len[m], awq_size[m], awq_burst[m]}),
            .empty(awq_empty[m]), .full(awq_full[m])
        );
        assign m_awready[m] = !awq_full[m];
        assign awq_valid[m] = !awq_empty[m];

        // W buffer
        xbar_fifo #(.WIDTH(W_W), .DEPTH(BUF_DEPTH)) u_w_buf (
            .clk(aclk), .rst_n(arst_n),
            .push(m_wvalid[m] && !wq_full[m]),
            .din({m_wdata[m], m_wstrb[m], m_wlast[m]}),
            .pop(wq_valid[m] && wq_ready[m]),
            .dout({wq_data[m], wq_strb[m], wq_last[m]}),
            .empty(wq_empty[m]), .full(wq_full[m])
        );
        assign m_wready[m] = !wq_full[m];
        assign wq_valid[m] = !wq_empty[m];

        // AR buffer
        xbar_fifo #(.WIDTH(AX_W), .DEPTH(BUF_DEPTH)) u_ar_buf (
            .clk(aclk), .rst_n(arst_n),
            .push(m_arvalid[m] && !arq_full[m]),
            .din({m_arid[m], m_araddr[m], m_arlen[m], m_arsize[m], m_arburst[m]}),
            .pop(arq_valid[m] && arq_ready[m]),
            .dout({arq_id[m], arq_addr[m], arq_len[m], arq_size[m], arq_burst[m]}),
            .empty(arq_empty[m]), .full(arq_full[m])
        );
        assign m_arready[m] = !arq_full[m];
        assign arq_valid[m] = !arq_empty[m];
    end

    // -------------------------------------------------------------------------
    // 2. Target bus: t_*[0], t_*[1] = physical slaves, t_*[2] = DECERR responder
    //    Request channels go straight to the slave ports.
    //    Response channels (tb_* / tr_*) come from the slave-side B / R buffers.
    // -------------------------------------------------------------------------
    logic [NT-1:0][SID_WIDTH-1:0]    t_awid, t_arid;
    logic [NT-1:0][ADDR_WIDTH-1:0]   t_awaddr, t_araddr;
    logic [NT-1:0][7:0]              t_awlen, t_arlen;
    logic [NT-1:0][2:0]              t_awsize, t_arsize;
    logic [NT-1:0][1:0]              t_awburst, t_arburst;
    logic [NT-1:0]                   t_awvalid, t_awready, t_arvalid, t_arready;
    logic [NT-1:0]                   t_wlast, t_wvalid, t_wready;
    logic [NT-1:0][DATA_WIDTH-1:0]   t_wdata;
    logic [NT-1:0][STRB_W-1:0]       t_wstrb;

    logic [NT-1:0]                   tb_valid, tb_ready;      // B at buffer output
    logic [NT-1:0][SID_WIDTH-1:0]    tb_id;
    logic [NT-1:0][1:0]              tb_resp;

    logic [NT-1:0]                   tr_valid, tr_ready, tr_last;   // R at buffer output
    logic [NT-1:0][SID_WIDTH-1:0]    tr_id;
    logic [NT-1:0][DATA_WIDTH-1:0]   tr_data;
    logic [NT-1:0][1:0]              tr_resp;

    logic [1:0]                      sb_empty, sb_full, sr_empty, sr_full;

    for (genvar s = 0; s < NUM_SLAVES; s++) begin : g_slave_map
        assign s_awid[s]    = t_awid[s];
        assign s_awaddr[s]  = t_awaddr[s];
        assign s_awlen[s]   = t_awlen[s];
        assign s_awsize[s]  = t_awsize[s];
        assign s_awburst[s] = t_awburst[s];
        assign s_awvalid[s] = t_awvalid[s];
        assign t_awready[s] = s_awready[s];

        assign s_wdata[s]   = t_wdata[s];
        assign s_wstrb[s]   = t_wstrb[s];
        assign s_wlast[s]   = t_wlast[s];
        assign s_wvalid[s]  = t_wvalid[s];
        assign t_wready[s]  = s_wready[s];

        assign s_arid[s]    = t_arid[s];
        assign s_araddr[s]  = t_araddr[s];
        assign s_arlen[s]   = t_arlen[s];
        assign s_arsize[s]  = t_arsize[s];
        assign s_arburst[s] = t_arburst[s];
        assign s_arvalid[s] = t_arvalid[s];
        assign t_arready[s] = s_arready[s];

        // B buffer: slave -> [FIFO] -> tb_*
        xbar_fifo #(.WIDTH(B_W), .DEPTH(BUF_DEPTH)) u_b_buf (
            .clk(aclk), .rst_n(arst_n),
            .push(s_bvalid[s] && !sb_full[s]),
            .din({s_bid[s], s_bresp[s]}),
            .pop(tb_valid[s] && tb_ready[s]),
            .dout({tb_id[s], tb_resp[s]}),
            .empty(sb_empty[s]), .full(sb_full[s])
        );
        assign s_bready[s] = !sb_full[s];
        assign tb_valid[s] = !sb_empty[s];

        // R buffer: slave -> [FIFO] -> tr_*
        xbar_fifo #(.WIDTH(R_W), .DEPTH(BUF_DEPTH)) u_r_buf (
            .clk(aclk), .rst_n(arst_n),
            .push(s_rvalid[s] && !sr_full[s]),
            .din({s_rid[s], s_rdata[s], s_rresp[s], s_rlast[s]}),
            .pop(tr_valid[s] && tr_ready[s]),
            .dout({tr_id[s], tr_data[s], tr_resp[s], tr_last[s]}),
            .empty(sr_empty[s]), .full(sr_full[s])
        );
        assign s_rready[s] = !sr_full[s];
        assign tr_valid[s] = !sr_empty[s];
    end

    // -------------------------------------------------------------------------
    // 3. Address decode  (S0: 0x0xxx_xxxx, S1: 0x1xxx_xxxx, otherwise DECERR)
    //    Decoding is done on the address at the FIFO output.
    // -------------------------------------------------------------------------
    function automatic logic [1:0] decode_addr(input logic [ADDR_WIDTH-1:0] addr);
        case (addr[31:28])
            4'h0:    return 2'd0;
            4'h1:    return 2'd1;
            default: return 2'd2;
        endcase
    endfunction

    logic [1:0][1:0] aw_tgt, ar_tgt;
    for (genvar m = 0; m < 2; m++) begin : g_decode
        assign aw_tgt[m] = decode_addr(awq_addr[m]);
        assign ar_tgt[m] = decode_addr(arq_addr[m]);
    end

    // -------------------------------------------------------------------------
    // 4. Write subsystem  (AW -> W -> B)
    // -------------------------------------------------------------------------
    logic [1:0]         aw_issue;                // AW forwarded to its target
    logic [NT-1:0][1:0] aw_req, aw_gnt;

    // W-order FIFOs
    logic [1:0][1:0]    wsel_head;               // per master: target of oldest AW still owing W
    logic [1:0]         wsel_empty, wsel_full;
    logic [NT-1:0]      tq_head;                 // per target: master of oldest AW still owing W
    logic [NT-1:0]      tq_empty, tq_full;

    // Request gate: request of master m for target t (taken from the AW FIFO
    // output). It goes to the arbiter only if both W-order FIFOs have space.
    always_comb begin
        for (int t = 0; t < NT; t++)
            for (int m = 0; m < 2; m++)
                aw_req[t][m] = awq_valid[m] && (aw_tgt[m] == 2'(t)) &&
                               !wsel_full[m] && !tq_full[t];
    end

    for (genvar t = 0; t < NT; t++) begin : g_aw_arb
        xbar_arb u_aw_arb (
            .clk(aclk), .rst_n(arst_n),
            .req(aw_req[t]), .ready(t_awready[t]), .gnt(aw_gnt[t])
        );
    end

    // AW mux: AND-OR mux on the one-hot grant.
    // Slave-side ID = {master index, master ID}.
    always_comb begin
        for (int t = 0; t < NT; t++) begin
            t_awvalid[t] = |aw_gnt[t];
            t_awid[t]    = ({SID_WIDTH{aw_gnt[t][0]}}  & {1'b0, awq_id[0]})
                         | ({SID_WIDTH{aw_gnt[t][1]}}  & {1'b1, awq_id[1]});
            t_awaddr[t]  = ({ADDR_WIDTH{aw_gnt[t][0]}} & awq_addr[0])
                         | ({ADDR_WIDTH{aw_gnt[t][1]}} & awq_addr[1]);
            t_awlen[t]   = ({8{aw_gnt[t][0]}}          & awq_len[0])
                         | ({8{aw_gnt[t][1]}}          & awq_len[1]);
            t_awsize[t]  = ({3{aw_gnt[t][0]}}          & awq_size[0])
                         | ({3{aw_gnt[t][1]}}          & awq_size[1]);
            t_awburst[t] = ({2{aw_gnt[t][0]}}          & awq_burst[0])
                         | ({2{aw_gnt[t][1]}}          & awq_burst[1]);
        end
    end

    // AW FIFO pop: the granted target accepted the request
    always_comb begin
        awq_ready = '0;
        for (int t = 0; t < NT; t++)
            for (int m = 0; m < 2; m++)
                if (aw_gnt[t][m] && t_awready[t]) awq_ready[m] = 1'b1;
    end
    assign aw_issue = awq_valid & awq_ready;

    // Handshake events that update the W-order tracking
    logic [1:0]    wq_last_hs;
    logic [NT-1:0] t_aw_hs, t_wlast_hs;

    always_comb begin
        for (int m = 0; m < 2; m++)
            wq_last_hs[m] = wq_valid[m] && wq_ready[m] && wq_last[m];
        for (int t = 0; t < NT; t++) begin
            t_aw_hs[t]    = t_awvalid[t] && t_awready[t];
            t_wlast_hs[t] = t_wvalid[t]  && t_wready[t] && t_wlast[t];
        end
    end

    // Per-master W-order FIFO ("M fifo"): target of every forwarded AW, in order
    for (genvar m = 0; m < 2; m++) begin : g_wsel
        xbar_fifo #(.WIDTH(2), .DEPTH(8)) u_wsel (
            .clk(aclk), .rst_n(arst_n),
            .push(aw_issue[m]),    .din(aw_tgt[m]),
            .pop(wq_last_hs[m]),   .dout(wsel_head[m]),
            .empty(wsel_empty[m]), .full(wsel_full[m])
        );
    end

    for (genvar t = 0; t < NT; t++) begin : g_tq
        xbar_fifo #(.WIDTH(1), .DEPTH(8)) u_tq (
            .clk(aclk), .rst_n(arst_n),
            .push(t_aw_hs[t]),    .din(aw_gnt[t][1]),
            .pop(t_wlast_hs[t]),  .dout(tq_head[t]),
            .empty(tq_empty[t]),  .full(tq_full[t])
        );
    end

    // W router: a beat moves from the W buffer of master o to target t only when
    //   head(T fifo t) == o  and  head(M fifo o) == t
    logic [NT-1:0][1:0] w_path;      // w_path[t][m] : W of master m is connected to target t

    always_comb begin
        for (int t = 0; t < NT; t++)
            for (int m = 0; m < 2; m++)
                w_path[t][m] = !tq_empty[t] && (tq_head[t] == 1'(m)) &&
                               !wsel_empty[m] && (wsel_head[m] == 2'(t));
    end

    always_comb begin
        for (int t = 0; t < NT; t++) begin
            t_wvalid[t] = (w_path[t][0] & wq_valid[0]) | (w_path[t][1] & wq_valid[1]);
            t_wlast[t]  = (w_path[t][0] & wq_last[0])  | (w_path[t][1] & wq_last[1]);
            t_wdata[t]  = ({DATA_WIDTH{w_path[t][0]}} & wq_data[0])
                        | ({DATA_WIDTH{w_path[t][1]}} & wq_data[1]);
            t_wstrb[t]  = ({STRB_W{w_path[t][0]}}     & wq_strb[0])
                        | ({STRB_W{w_path[t][1]}}     & wq_strb[1]);
        end
        for (int m = 0; m < 2; m++) begin
            wq_ready[m] = 1'b0;
            for (int t = 0; t < NT; t++)
                if (w_path[t][m] && t_wready[t]) wq_ready[m] = 1'b1;
        end
    end

    // B router: destination master = top bit of the slave-side BID
    logic [1:0][NT-1:0] b_cand;
    logic [1:0]         b_val;
    logic [1:0][1:0]    b_sel;

    always_comb begin
        for (int m = 0; m < 2; m++)
            for (int t = 0; t < NT; t++)
                b_cand[m][t] = tb_valid[t] && (tb_id[t][SID_WIDTH-1] == 1'(m));
    end

    for (genvar m = 0; m < 2; m++) begin : g_bsel
        xbar_rsp_sel #(.NT(NT)) u_bsel (
            .clk(aclk), .rst_n(arst_n),
            .cand(b_cand[m]), .ready(m_bready[m]),
            .valid(b_val[m]), .sel(b_sel[m])
        );
    end

    always_comb begin
        m_bvalid = '0;
        m_bid    = '0;
        m_bresp  = '0;
        for (int m = 0; m < 2; m++) begin
            if (b_val[m]) begin
                m_bvalid[m] = 1'b1;
                m_bid[m]    = tb_id[b_sel[m]][ID_WIDTH-1:0];   // master bit removed
                m_bresp[m]  = tb_resp[b_sel[m]];
            end
        end
    end

    // B READY back to the response source: the selected master is ready
    always_comb begin
        for (int t = 0; t < NT; t++) begin
            tb_ready[t] = 1'b0;
            for (int m = 0; m < 2; m++)
                if (b_val[m] && (b_sel[m] == 2'(t)) && m_bready[m]) tb_ready[t] = 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // 5. Read subsystem  (AR -> R)
    // -------------------------------------------------------------------------
    logic [NT-1:0][1:0] ar_req, ar_gnt;

    // Request gate: request of master m for target t (taken from the AR FIFO output)
    always_comb begin
        for (int t = 0; t < NT; t++)
            for (int m = 0; m < 2; m++)
                ar_req[t][m] = arq_valid[m] && (ar_tgt[m] == 2'(t));
    end

    for (genvar t = 0; t < NT; t++) begin : g_ar_arb
        xbar_arb u_ar_arb (
            .clk(aclk), .rst_n(arst_n),
            .req(ar_req[t]), .ready(t_arready[t]), .gnt(ar_gnt[t])
        );
    end

    // AR mux: same AND-OR gating as the AW mux.
    always_comb begin
        for (int t = 0; t < NT; t++) begin
            t_arvalid[t] = |ar_gnt[t];
            t_arid[t]    = ({SID_WIDTH{ar_gnt[t][0]}}  & {1'b0, arq_id[0]})
                         | ({SID_WIDTH{ar_gnt[t][1]}}  & {1'b1, arq_id[1]});
            t_araddr[t]  = ({ADDR_WIDTH{ar_gnt[t][0]}} & arq_addr[0])
                         | ({ADDR_WIDTH{ar_gnt[t][1]}} & arq_addr[1]);
            t_arlen[t]   = ({8{ar_gnt[t][0]}}          & arq_len[0])
                         | ({8{ar_gnt[t][1]}}          & arq_len[1]);
            t_arsize[t]  = ({3{ar_gnt[t][0]}}          & arq_size[0])
                         | ({3{ar_gnt[t][1]}}          & arq_size[1]);
            t_arburst[t] = ({2{ar_gnt[t][0]}}          & arq_burst[0])
                         | ({2{ar_gnt[t][1]}}          & arq_burst[1]);
        end
    end

    always_comb begin
        arq_ready = '0;
        for (int t = 0; t < NT; t++)
            for (int m = 0; m < 2; m++)
                if (ar_gnt[t][m] && t_arready[t]) arq_ready[m] = 1'b1;
    end

    // R router: destination master = top bit of the slave-side RID
    logic [1:0][NT-1:0] r_cand;
    logic [1:0]         r_val;
    logic [1:0][1:0]    r_sel;

    always_comb begin
        for (int m = 0; m < 2; m++)
            for (int t = 0; t < NT; t++)
                r_cand[m][t] = tr_valid[t] && (tr_id[t][SID_WIDTH-1] == 1'(m));
    end

    for (genvar m = 0; m < 2; m++) begin : g_rsel
        xbar_rsp_sel #(.NT(NT)) u_rsel (
            .clk(aclk), .rst_n(arst_n),
            .cand(r_cand[m]), .ready(m_rready[m]),
            .valid(r_val[m]), .sel(r_sel[m])
        );
    end

    always_comb begin
        m_rvalid = '0;
        m_rid    = '0;
        m_rdata  = '0;
        m_rresp  = '0;
        m_rlast  = '0;
        for (int m = 0; m < 2; m++) begin
            if (r_val[m]) begin
                m_rvalid[m] = 1'b1;
                m_rid[m]    = tr_id[r_sel[m]][ID_WIDTH-1:0];   // master bit removed
                m_rdata[m]  = tr_data[r_sel[m]];
                m_rresp[m]  = tr_resp[r_sel[m]];
                m_rlast[m]  = tr_last[r_sel[m]];
            end
        end
    end

    // R READY back to the response source: the selected master is ready
    always_comb begin
        for (int t = 0; t < NT; t++) begin
            tr_ready[t] = 1'b0;
            for (int m = 0; m < 2; m++)
                if (r_val[m] && (r_sel[m] == 2'(t)) && m_rready[m]) tr_ready[t] = 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // 6. DECERR responder (target T2)
    //    Write: AW id queue + count of finished W bursts -> one B per burst
    //    Read : {id,len} queue + beat counter            -> len+1 R beats
    //    W data reaches T2 only after its AW was accepted (W-order FIFOs).
    // -------------------------------------------------------------------------
    logic       err_id_full, err_b_hs;
    logic [3:0] err_wdone;

    assign err_b_hs     = tb_valid[2] && tb_ready[2];
    assign t_awready[2] = !err_id_full;
    assign t_wready[2]  = 1'b1;
    assign tb_valid[2]  = (err_wdone != 4'd0);
    assign tb_resp[2]   = DECERR;

    xbar_fifo #(.WIDTH(SID_WIDTH), .DEPTH(8)) u_err_id_fifo (
        .clk(aclk), .rst_n(arst_n),
        .push(t_awvalid[2] && t_awready[2]), .din(t_awid[2]),
        .pop(err_b_hs),                      .dout(tb_id[2]),
        .empty(),                            .full(err_id_full)
    );

    always_ff @(posedge aclk or negedge arst_n) begin
        if (!arst_n) err_wdone <= 4'd0;
        else begin
            case ({(t_wvalid[2] && t_wlast[2]), err_b_hs})
                2'b10:   err_wdone <= err_wdone + 4'd1;
                2'b01:   err_wdone <= err_wdone - 4'd1;
                default: ;
            endcase
        end
    end

    logic                   err_ar_empty, err_ar_full;
    logic [SID_WIDTH+8-1:0] err_ar_q;
    logic [7:0]             err_beat;

    assign t_arready[2] = !err_ar_full;
    assign tr_valid[2]  = !err_ar_empty;
    assign tr_id[2]     = err_ar_q[SID_WIDTH+8-1:8];
    assign tr_data[2]   = '0;
    assign tr_resp[2]   = DECERR;
    assign tr_last[2]   = !err_ar_empty && (err_beat == err_ar_q[7:0]);

    xbar_fifo #(.WIDTH(SID_WIDTH+8), .DEPTH(8)) u_err_ar_fifo (
        .clk(aclk), .rst_n(arst_n),
        .push(t_arvalid[2] && t_arready[2]),
        .din({t_arid[2], t_arlen[2]}),
        .pop(tr_valid[2] && tr_ready[2] && tr_last[2]),
        .dout(err_ar_q),
        .empty(err_ar_empty), .full(err_ar_full)
    );

    always_ff @(posedge aclk or negedge arst_n) begin
        if (!arst_n)                           err_beat <= 8'd0;
        else if (tr_valid[2] && tr_ready[2])   err_beat <= tr_last[2] ? 8'd0 : err_beat + 8'd1;
    end

endmodule
