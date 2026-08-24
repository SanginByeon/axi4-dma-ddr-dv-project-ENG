// ============================================================================
// dma_s1_seq.sv - DMA Scenario 1 Sequence
//
// - Performs a 256-byte basic copy using 4-byte-aligned addresses.
// - Generates a transaction for checking normal transfer flow and completion indication.
// ============================================================================

import utility_pkg::*;

class dma_s1_seq extends dma_base_seq;
    `uvm_object_utils(dma_s1_seq)

    function new(input string name = "dma_s1_seq");
        super.new(name);
    endfunction

    // [body]: generates a 256-byte basic-copy transaction and initializes source memory
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t");

        start_item(t);

        if (!t.randomize() with {
            src_addr == 32'h0000_0000; // SRC_ADDR=0x0000
            dst_addr == 32'h0000_0400; // DST_ADDR=0x0400 (1 KB offset)
            size     == 256;           // SIZE=0x100(256B)

            // CTRL settings
            enable == 1'b1;
            start  == 1'b1;
            irq    == 1'b1;
        }) begin
            `uvm_fatal("S1_SEQ", "Failed to randomize dma_tx in dma_s1_seq")
        end

        // Set scenario name
        t.scenario_name = "256B Basic copy (S1)";

        // Initialize source memory with the 32'hCAFE_0000-based pattern
        preload_src_mem(t.src_addr, t.data_payload);

        finish_item(t);

        `uvm_info(
            "S1_SEQ",
            $sformatf("Generated S1 Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass
