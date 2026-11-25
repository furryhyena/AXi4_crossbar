// =============================================================================
// axi_txn.sv - one AXI transaction = one whole burst (write or read).
//   The generator creates it, the driver drives it, the monitors rebuild it
//   from the pins and the scoreboard compares the rebuilt copies.
// =============================================================================
class axi_txn;
    bit          is_write;       // 1 = write burst, 0 = read burst
    int          master;         // master that issued it (0 / 1)
    int          port;           // port index where a monitor saw it
    bit [4:0]    id;             // ID as seen on that port (master side: bit 4 = 0)
    bit [31:0]   addr;
    bit [7:0]    len;            // beats - 1
    bit [2:0]    size;           // always 3 (8 bytes per beat) in this testbench
    bit [1:0]    burst;          // always 1 (INCR) in this testbench
    bit [63:0]   data [$];       // write data, or read data collected by a monitor
    bit [7:0]    strb [$];       // write strobes (one per beat)
    bit [1:0]    resp;           // BRESP / RRESP
    time         t_req;          // time of the AW / AR handshake
    time         t_done;         // time of the B / last R handshake

    function new();
        size  = 3'd3;
        burst = 2'b01;
    endfunction

    // address map of the crossbar: 0 = S0, 1 = S1, 2 = DECERR
    function int target();
        case (addr[31:28])
            4'h0:    return 0;
            4'h1:    return 1;
            default: return 2;
        endcase
    endfunction

    function string kind();
        return is_write ? "WR" : "RD";
    endfunction
endclass
