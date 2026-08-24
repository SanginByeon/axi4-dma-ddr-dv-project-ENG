// ============================================================================
// dma_base_seq.sv - DMA Base Sequence
//
// - Base sequence that generates and randomizes a DMA transaction.
// - Provides the common execution structure inherited by scenario sequences.
// ============================================================================

class dma_base_seq extends uvm_sequence #(dma_tx);
    `uvm_object_utils(dma_base_seq)

    function new(input string name = "dma_base_seq");
        super.new(name);
    endfunction

    // [body] : Generate one basic DMA transaction
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t");

        start_item(t);

        if (!t.randomize()) begin
            `uvm_fatal("BASE_SEQ", "Failed to randomize dma_tx in dma_base_seq")
        end

        finish_item(t);

        `uvm_info(
            "BASE_SEQ",
            $sformatf("Generated Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass
