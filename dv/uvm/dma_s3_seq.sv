// ============================================================================
// dma_s3_seq.sv - DMA Scenario 3 Sequences
//
// - Performs 16-byte and 64-byte small copies using 4-byte-aligned addresses.
// - Generates transactions for checking burst length and handshake behavior on small transfers.
// ============================================================================

import utility_pkg::*;

class dma_s3_1_seq extends dma_base_seq;
    `uvm_object_utils(dma_s3_1_seq)

    function new(input string name = "dma_s3_1_seq");
        super.new(name);
    endfunction

    // [body]: generates a 16-byte small-copy transaction and initializes source memory
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t");

        start_item(t);

        if (!t.randomize() with {
            src_addr == 32'h0000_0200; // SRC_ADDR=0x0200
            dst_addr == 32'h0000_0300; // DST_ADDR=0x0300
            size     == 16;            // SIZE=0x10(16B)

            // CTRL settings
            enable == 1'b1;
            start  == 1'b1;
            irq    == 1'b1;
        }) begin
            `uvm_fatal("S3_1_SEQ", "Failed to randomize dma_tx in dma_s3_1_seq")
        end

        // Set scenario name
        t.scenario_name = "16B Small transfer (S3_1)";

        // Initialize source memory with the 32'hCAFE_0000-based pattern
        preload_src_mem(t.src_addr, t.data_payload);

        finish_item(t);

        `uvm_info(
            "S3_1_SEQ",
            $sformatf("Generated S3_1 Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass

class dma_s3_2_seq extends dma_base_seq;
    `uvm_object_utils(dma_s3_2_seq)

    function new(input string name = "dma_s3_2_seq");
        super.new(name);
    endfunction

    // [body]: generates a 64-byte small-copy transaction and initializes source memory
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t");

        start_item(t);

        if (!t.randomize() with {
            src_addr == 32'h0000_0210; // SRC_ADDR=0x0210
            dst_addr == 32'h0000_0310; // DST_ADDR=0x0310
            size     == 64;            // SIZE=0x40(64B)

            // CTRL settings
            enable == 1'b1;
            start  == 1'b1;
            irq    == 1'b1;
        }) begin
            `uvm_fatal("S3_2_SEQ", "Failed to randomize dma_tx in dma_s3_2_seq")
        end

        // Set scenario name
        t.scenario_name = "64B Small transfer (S3_2)";

        // Initialize source memory with the 32'hCAFE_0000-based pattern
        preload_src_mem(t.src_addr, t.data_payload);

        finish_item(t);

        `uvm_info(
            "S3_2_SEQ",
            $sformatf("Generated S3_2 Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass
