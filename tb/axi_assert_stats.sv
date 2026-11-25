// =============================================================================
// axi_assert_stats.sv - shared counters for the protocol assertions
//   axi_protocol_checker (one per port, bound into axi_if) reports here:
//     checked(port, name) : the assertion was really tested in this clock
//                           (its condition was active, not a vacuous pass)
//     failed (port, name) : the assertion failed
//   The base test prints the table at the end of every test and adds the
//   failures to the error count, so a failing assertion fails the test.
// =============================================================================
class axi_assert_stats;
    static string names [$];          // assertion names in plan order (A01..A17)
    static string ports [$];          // port names in the order they registered
    static int    n_chk  [string];    // key = "<port>.<name>"
    static int    n_fail [string];

    static function void add_name(string n);
        foreach (names[i]) if (names[i] == n) return;
        names.push_back(n);
    endfunction

    static function void add_port(string p);
        foreach (ports[i]) if (ports[i] == p) return;
        ports.push_back(p);
    endfunction

    static function void checked(string p, string n);
        string k = {p, ".", n};
        if (!n_chk.exists(k)) n_chk[k] = 0;
        n_chk[k]++;
    endfunction

    static function void failed(string p, string n, string msg);
        string k = {p, ".", n};
        if (!n_fail.exists(k)) n_fail[k] = 0;
        n_fail[k]++;
        $display("[%0t] [ASSERT] ERROR : %s on %s : %s", $time, n, p, msg);
    endfunction

    static function int errors();
        int e = 0;
        foreach (n_fail[k]) e += n_fail[k];
        return e;
    endfunction

    static function int get_chk(string k);
        return n_chk.exists(k) ? n_chk[k] : 0;
    endfunction

    static function int get_fail(string k);
        return n_fail.exists(k) ? n_fail[k] : 0;
    endfunction

    // one row per assertion, one "checked / failed" column per port
    static function void report();
        string line, k;
        $display(" ---------------- protocol assertions (this test) ----------------");
        $display(" each cell = times the rule was really tested / times it failed");
        line = $sformatf("   %-24s", "assertion");
        foreach (ports[i]) line = {line, $sformatf(" %14s", ports[i])};
        $display("%s", line);
        foreach (names[n]) begin
            line = $sformatf("   %-24s", names[n]);
            foreach (ports[p]) begin
                k = {ports[p], ".", names[n]};
                line = {line, $sformatf(" %8d / %-3d", get_chk(k), get_fail(k))};
            end
            $display("%s", line);
        end
        $display(" assertion failures : %0d", errors());
    endfunction
endclass
