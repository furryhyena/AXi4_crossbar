// =============================================================================
// axi_test_list.sv - one `include per test file in tb/tests/, plus the test
//                    factory that creates a test from its +TESTNAME.
// To add a test: put tb/tests/my_test.sv here and add one line to the factory.
// =============================================================================
`ifndef AXI_TEST_LIST_SV
`define AXI_TEST_LIST_SV
`include "tests/axi_basic_rw_test.sv"
`include "tests/axi_decerr_test.sv"
`include "tests/axi_burst_test.sv"
`include "tests/axi_same_id_test.sv"
`include "tests/axi_buffer_test.sv"
`include "tests/axi_w_order_test.sv"
`include "tests/axi_arbitration_test.sv"
`include "tests/axi_outstanding_test.sv"
`include "tests/axi_stress_test.sv"
`include "tests/axi_parallel_test.sv"

// ----------------------------------------------------------------------------
// test factory
// ----------------------------------------------------------------------------
function automatic axi_base_test axi_create_test(string n);
    axi_base_test t;
    t = null;
    if (n == "axi_basic_rw_test")     begin axi_basic_rw_test     x = new(n);  t = x; end
    if (n == "axi_decerr_test")       begin axi_decerr_test       x = new(n);  t = x; end
    if (n == "axi_burst_test")        begin axi_burst_test        x = new(n);  t = x; end
    if (n == "axi_same_id_test")      begin axi_same_id_test      x = new(n);  t = x; end
    if (n == "axi_buffer_test")       begin axi_buffer_test       x = new(n);  t = x; end
    if (n == "axi_w_order_test")      begin axi_w_order_test      x = new(n);  t = x; end
    if (n == "axi_arbitration_test")  begin axi_arbitration_test  x = new(n);  t = x; end
    if (n == "axi_outstanding_test")  begin axi_outstanding_test  x = new(n);  t = x; end
    if (n == "axi_stress_test")       begin axi_stress_test       x = new(n);  t = x; end
    if (n == "axi_parallel_test")     begin axi_parallel_test     x = new(n);  t = x; end
    return t;
endfunction
`endif
