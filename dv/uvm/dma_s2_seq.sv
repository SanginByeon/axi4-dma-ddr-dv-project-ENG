// ============================================================================
// dma_s2_seq.sv - DMA Scenario 2 Sequence
//
// - Performs a 1,024-byte copy at 4-byte-aligned addresses with 10% backpressure.
// - Generates a transaction for checking multi-burst W-channel handshake behavior.
// ============================================================================

import utility_pkg::*;

class dma_s2_seq extends dma_base_seq;
    `uvm_object_utils(dma_s2_seq)

    function new(input string name = "dma_s2_seq");
        super.new(name);
    endfunction

    // [body]: generates a 1,024-byte multi-burst transaction with 10% backpressure
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t");

        start_item(t);

        if (!t.randomize() with {
            src_addr == 32'h0000_0100; // SRC_ADDR=0x0100
            dst_addr == 32'h0000_0800; // DST_ADDR=0x0800
            size     == 1024;          // SIZE=0x400(1024B)

            // CTRL settings
            enable == 1'b1;
            start  == 1'b1;
            irq    == 1'b1;

            // DDR memory-model verification controls
            backpressure_prob == 10;
            error_inject      == 1'b0;
        }) begin
            `uvm_fatal("S2_SEQ", "Failed to randomize dma_tx in dma_s2_seq")
        end

        // Set scenario name
        t.scenario_name = "1024B Transfer with 10% Backpressure (S2)";

        // Initialize source memory with the 32'hCAFE_0000-based pattern
        preload_src_mem(t.src_addr, t.data_payload);

        finish_item(t);

        `uvm_info(
            "S2_SEQ",
            $sformatf("Generated S2 Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass
