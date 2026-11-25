// =============================================================================
// axi_agent_cfg.sv - knobs of one master agent or one slave agent.
//   A test changes these (also while traffic is running) to create gaps,
//   backpressure, stalls, slow responses and SLVERR.
// =============================================================================
class axi_agent_cfg;
    // ---------------- master side
    int  aw_gap_max  = 0;      // 0..n idle clocks before every AW
    int  w_gap_max   = 0;      // 0..n idle clocks before every W beat
    int  ar_gap_max  = 0;      // 0..n idle clocks before every AR
    int  bready_pct  = 100;    // % of clocks with BREADY = 1
    int  rready_pct  = 100;    // % of clocks with RREADY = 1
    bit  w_hold      = 0;      // 1 = master sends no W data (AW still goes out)

    // ---------------- slave side
    int  awready_pct    = 100; // % of clocks with AWREADY = 1 (0 = stall)
    int  wready_pct     = 100;
    int  arready_pct    = 100;
    int  rvalid_gap_max = 0;   // 0..n idle clocks before every R beat
    int  resp_delay_max = 0;   // 0..n clocks before B / before the first R beat
    bit          slverr_en = 0;        // SLVERR for addr[27:0] in [slverr_lo, slverr_hi]
    bit [27:0]   slverr_lo = '0;
    bit [27:0]   slverr_hi = '0;

    // pct = % of time READY is high, gap = max idle clocks in front of VALID
    function void set_backpressure(int pct, int gap);
        aw_gap_max = gap;  w_gap_max = gap;  ar_gap_max = gap;
        bready_pct = pct;  rready_pct = pct;
        awready_pct = pct; wready_pct = pct; arready_pct = pct;
        rvalid_gap_max = gap;
    endfunction

    function bit in_slverr(bit [31:0] addr);
        return slverr_en && (addr[27:0] >= slverr_lo) && (addr[27:0] <= slverr_hi);
    endfunction
endclass
