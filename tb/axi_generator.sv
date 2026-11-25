// =============================================================================
// axi_generator.sv - creates transactions for ONE master and puts them into
//                    the mailbox of that master's driver.
//
// ID rule (the crossbar is built with UNIQUE_IDS = 1, so the MASTER must make
// sure that transactions with the same ID that are outstanding together go to
// ONE slave):   ID[1:0] = target (0 = S0, 1 = S1, 2 = DECERR), ID[3:2] random.
//
// Address rule: master m only uses addresses with addr[16] = m, so the two
// masters never write the same memory word. A burst never crosses 4 KB.
// =============================================================================
class axi_generator;
    int                  master;
    mailbox #(axi_txn)   mbx;          // to the master driver
    int                  n_gen;        // transactions created so far
    axi_txn              written [$];  // writes to S0 / S1 (used by readback)

    // knobs for random()
    int  wr_pct    = 50;               // % writes
    int  w_s0      = 45;               // target weights (sum = 100)
    int  w_s1      = 45;
    int  w_decerr  = 10;
    int  len_max   = 7;                // AxLEN is 0..len_max
    bit  rand_strb = 0;                // 1 = random write strobes

    function new(int master, mailbox #(axi_txn) mbx);
        this.master = master;
        this.mbx    = mbx;
    endfunction

    function bit [31:0] rand_addr(int tgt, bit [7:0] len);
        bit [31:0]   base;
        bit [3:0]    nib;
        int unsigned nbytes, page, off;
        nbytes = (int'(len) + 1) * 8;
        page   = $urandom_range(0, 7);
        off    = $urandom_range(0, (4096 - nbytes) / 8) * 8;
        nib    = $urandom_range(2, 15);
        case (tgt)
            0:       base = 32'h0000_0000;
            1:       base = 32'h1000_0000;
            default: base = {nib, 28'h0};
        endcase
        return base + (master << 16) + (page << 12) + off;
    endfunction

    function bit [3:0] rand_id(int tgt);
        bit [1:0] hi;
        hi = $urandom_range(0, 3);
        return {hi, tgt[1:0]};
    endfunction

    function void send(axi_txn t);
        t.master = master;
        void'(mbx.try_put(t));         // mailbox is unbounded: always succeeds
        n_gen++;
        if (t.is_write && t.target() < 2) written.push_back(t);
    endfunction

    // ---------------- directed helpers
    function axi_txn write_at(bit [31:0] addr, bit [3:0] id, bit [7:0] len);
        axi_txn    t;
        bit [63:0] d;
        bit [7:0]  s;
        t = new();
        t.is_write = 1;  t.id = {1'b0, id};  t.addr = addr;  t.len = len;
        for (int i = 0; i <= len; i++) begin
            d = {$urandom(), $urandom()};
            s = rand_strb ? $urandom_range(0, 255) : 8'hFF;
            t.data.push_back(d);
            t.strb.push_back(s);
        end
        send(t);
        return t;
    endfunction

    function axi_txn read_at(bit [31:0] addr, bit [3:0] id, bit [7:0] len);
        axi_txn t;
        t = new();
        t.is_write = 0;  t.id = {1'b0, id};  t.addr = addr;  t.len = len;
        send(t);
        return t;
    endfunction

    // tgt: 0 = S0, 1 = S1, 2 = unmapped address (DECERR)
    function axi_txn write(int tgt, bit [3:0] id, bit [7:0] len);
        return write_at(rand_addr(tgt, len), id, len);
    endfunction

    function axi_txn read(int tgt, bit [3:0] id, bit [7:0] len);
        return read_at(rand_addr(tgt, len), id, len);
    endfunction

    // ---------------- random traffic
    function void random(int n);
        int        r, tgt;
        bit [7:0]  len;
        axi_txn    t;
        for (int i = 0; i < n; i++) begin
            r   = $urandom_range(0, 99);
            tgt = (r < w_s0) ? 0 : (r < w_s0 + w_s1) ? 1 : 2;
            len = $urandom_range(0, len_max);
            if ($urandom_range(0, 99) < wr_pct) t = write(tgt, rand_id(tgt), len);
            else                                t = read (tgt, rand_id(tgt), len);
        end
    endfunction

    // read every location written so far (same address, length and ID)
    function void readback();
        axi_txn t;
        for (int i = 0; i < written.size(); i++)
            t = read_at(written[i].addr, written[i].id[3:0], written[i].len);
    endfunction
endclass
