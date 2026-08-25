// ============================================================================
// dma_s7_random_seq.sv - DMA Scenario 7 Constrained-Random Sequence
//
// - Generates normal transactions under 4-byte-alignment, 4 KB-range, and non-overlap constraints.
// - Randomizes transfer size, source/destination addresses, and backpressure probability subject to
//   the scenario constraints.
// - Adds checks of constraint-based random normal transfers and data integrity.
// ============================================================================

import utility_pkg::*;

class dma_s7_random_seq extends dma_base_seq;
    `uvm_object_utils(dma_s7_random_seq)

    localparam int unsigned RANDOM_TX_COUNT = 5;

    function new(input string name = "dma_s7_random_seq");
        super.new(name);
    endfunction

    // [body] : Repeatedly generate normal constrained-random transactions and initialize source memory
    virtual task body();
        dma_tx t;

        for (int unsigned i = 0; i < RANDOM_TX_COUNT; i++) begin
            t = dma_tx::type_id::create(
                $sformatf("t_s7_id%0d", i + 1)
            );

            start_item(t);

            if (!t.randomize() with {
                size inside {[4:256]};
                size[1:0] == 2'b00;

                src_addr[11:10] dist {
                    2'd0 := 1,
                    [2'd1:2'd2] :/ 2,
                    2'd3 := 1
                };
                dst_addr[11:10] dist {
                    2'd0 := 1,
                    [2'd1:2'd2] :/ 2,
                    2'd3 := 1
                };

                enable == 1'b1;
                start  == 1'b1;
                irq    == 1'b1;

                backpressure_prob inside {[1:99]};
                backpressure_prob dist {
                    [1:30]  :/ 3,
                    [31:70] :/ 3,
                    [71:99] :/ 3
                };
                error_inject == 1'b0;
            }) begin
                `uvm_fatal(
                    "S7_SEQ",
                    $sformatf("Failed to randomize S7 transaction ID %0d", i + 1)
                )
            end

            t.scenario_name = $sformatf(
                "[S7-%0d] Constrained-Random Normal Transfer",
                i + 1
            );

            // Initialize source memory with the 32'hCAFE_0000-based pattern
            preload_src_mem(t.src_addr, t.data_payload);

            finish_item(t);

            `uvm_info(
                "S7_SEQ",
                $sformatf("Generated S7 Transaction: %s", t.convert2string()),
                UVM_HIGH
            )
        end
    endtask
endclass
