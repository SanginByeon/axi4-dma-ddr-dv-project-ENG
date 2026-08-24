// ============================================================================
// dma_agent.sv - DMA UVM Agent
//
// - Selects the Agent configuration from the inherited UVM active/passive setting.
// - Always creates the Monitor and creates/connects the Driver and Sequencer in active mode.
// ============================================================================

class dma_agent extends uvm_agent;
    `uvm_component_utils(dma_agent)

    dma_driver drv;
    dma_monitor mon;
    uvm_sequencer #(dma_tx) seqr;

    function new(input string name = "dma_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // [build_phase] : Always create the Monitor; create Driver/Sequencer in active mode
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        mon = dma_monitor::type_id::create("mon", this);

        // Create the Driver and Sequencer only in active mode
        if (get_is_active() == UVM_ACTIVE) begin
            drv = dma_driver::type_id::create("drv", this);
            seqr = uvm_sequencer #(dma_tx)::type_id::create("seqr", this);
        end
    endfunction

    // [connect_phase] : Connect Driver and Sequencer TLM ports in active mode
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
        end
    endfunction
endclass
