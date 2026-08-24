// ============================================================================
// dma_env.sv - DMA UVM Environment
//
// - Top-level UVM environment that creates the DMA Agent and Scoreboard.
// - Connects the Monitor analysis port to the Scoreboard analysis export.
// ============================================================================

class dma_env extends uvm_env;
    `uvm_component_utils(dma_env)

    dma_scoreboard scb;
    dma_agent a;

    function new(input string name = "dma_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // [build_phase] : Create the Agent and Scoreboard
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        scb = dma_scoreboard::type_id::create("scb", this);
        a = dma_agent::type_id::create("a", this);
    endfunction

    // [connect_phase] : Connect the Monitor analysis port to the Scoreboard
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        a.mon.send.connect(scb.recv);
    endfunction
endclass
