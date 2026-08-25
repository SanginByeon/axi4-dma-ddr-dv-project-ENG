// ============================================================================
// dma_s4_slverr_seq.sv - DMA Scenario 4 SLVERR Sequence
//
// - Requests a 64-byte transfer with backpressure disabled and configures the memory model to return
//   SLVERR on the B channel.
// - The DUT records error_code=0x3 in S_WR_RESP and raises the enabled error interrupt in S_ERROR.
// - Provides a BRESP-error-path reference separate from combined backpressure scenarios.
// ============================================================================

import utility_pkg::*;

class dma_s4_slverr_seq extends dma_base_seq;
    `uvm_object_utils(dma_s4_slverr_seq)

    function new(input string name = "dma_s4_slverr_seq");
        super.new(name);
    endfunction

    // [body] : Generate a BRESP SLVERR transaction without backpressure
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t_s4_id1");

        start_item(t);

        if (!t.randomize() with {
            src_addr == 32'h0000_0200;
            dst_addr == 32'h0000_0A00;
            size     == 64;

            enable == 1'b1;
            start  == 1'b1;
            irq    == 1'b1;

            backpressure_prob == 0;
            error_inject      == 1'b1;
        }) begin
            `uvm_fatal("S4_SEQ", "Failed to randomize S4 transaction ID 1")
        end

        t.scenario_name = "[S4-1] 64B BRESP SLVERR Injection";

        // Initialize source memory with the 32'hCAFE_0000-based pattern
        preload_src_mem(t.src_addr, t.data_payload);

        finish_item(t);

        `uvm_info(
            "S4_SEQ",
            $sformatf("Generated S4 Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass
