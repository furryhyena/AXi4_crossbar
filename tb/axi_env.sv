// =============================================================================
// axi_env.sv - builds and connects everything:
//
//   gen[m] --mailbox--> m_drv[m] ==> crossbar ==> s_drv[s] (memory model)
//                          |                         |
//                       m_mon[m] ---> scoreboard <--- s_mon[s]
// =============================================================================
class axi_env;
    virtual axi_if       m_vif [2];
    virtual axi_if       s_vif [2];

    axi_agent_cfg        m_cfg [2];
    axi_agent_cfg        s_cfg [2];
    axi_generator        gen   [2];
    axi_master_driver    m_drv [2];
    axi_slave_driver     s_drv [2];
    axi_monitor          m_mon [2];
    axi_monitor          s_mon [2];
    axi_scoreboard       sb;

    mailbox #(axi_txn)   g2d [2];
    mailbox #(axi_txn)   mm_mbx, sm_mbx;

    function new(virtual axi_if m0, virtual axi_if m1, virtual axi_if s0, virtual axi_if s1);
        m_vif[0] = m0;  m_vif[1] = m1;  s_vif[0] = s0;  s_vif[1] = s1;
        mm_mbx = new();
        sm_mbx = new();
        for (int i = 0; i < 2; i++) begin
            m_cfg[i] = new();
            s_cfg[i] = new();
            g2d[i]   = new();
            gen[i]   = new(i, g2d[i]);
            m_drv[i] = new(m_vif[i], m_cfg[i], g2d[i], i);
            s_drv[i] = new(s_vif[i], s_cfg[i], i);
            m_mon[i] = new(m_vif[i], 1'b0, i, mm_mbx);
            s_mon[i] = new(s_vif[i], 1'b1, i, sm_mbx);
        end
        sb = new(mm_mbx, sm_mbx);
    endfunction

    task start();
        m_drv[0].run();
        m_drv[1].run();
        s_drv[0].run();
        s_drv[1].run();
        sb.run();
        fork
            m_mon[0].run();
            m_mon[1].run();
            s_mon[0].run();
            s_mon[1].run();
        join_none
    endtask

    task clk(int n);
        repeat (n) @(posedge m_vif[0].aclk);
    endtask

    // wait until every generated transaction has completed on its master port
    task wait_idle();
        while (sb.n_done < gen[0].n_gen + gen[1].n_gen) @(posedge m_vif[0].aclk);
        clk(10);
    endtask

    function int total_errors();
        return sb.errors + m_mon[0].proto_errors + m_mon[1].proto_errors +
               s_mon[0].proto_errors + s_mon[1].proto_errors + s_drv[0].errors + s_drv[1].errors;
    endfunction
endclass
