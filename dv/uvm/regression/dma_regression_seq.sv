// ============================================================================
// dma_regression_seq.sv - DMA Multi-Seed Backpressure Regression Sequence
//
// - Combines six transfer sizes and six backpressure probabilities for one seed.
// - Generates 36 normal DMA transfers to repeatedly check stability under random stall timing.
// - Initializes source memory with a verification data pattern before each transaction.
// - Omits BRESP error injection because Step 4 exercised the planned directed scenarios and met the
//   corresponding functional coverage targets.
// ============================================================================

import utility_pkg::*;

class dma_regression_seq extends dma_base_seq;
    `uvm_object_utils(dma_regression_seq)

    // Simulator seed provided by the Test and recorded in the scenario name
    int unsigned simulation_seed;

    function new(input string name = "dma_regression_seq");
        super.new(name);
    endfunction

    // [body] : Generate the 6×6 matrix of backpressure probabilities and transfer sizes
    virtual task body();
        dma_tx t;

        int unsigned size_bytes[] = '{4, 16, 64, 80, 512, 1028};
        int unsigned backpressure_probs[] = '{0, 10, 30, 50, 70, 90};

        foreach (backpressure_probs[p]) begin
            foreach (size_bytes[s]) begin
                int unsigned test_id = (p * size_bytes.size()) + s + 1;
                int unsigned target_size = size_bytes[s];
                int unsigned target_prob = backpressure_probs[p];

                t = dma_tx::type_id::create(
                    $sformatf("t_regr_id%0d", test_id)
                );

                start_item(t);

                if (!t.randomize() with {
                    src_addr == 32'h0000_0000;
                    dst_addr == 32'h0000_0800;
                    size     == local::target_size;

                    enable == 1'b1;
                    start  == 1'b1;
                    irq    == 1'b1;

                    backpressure_prob == local::target_prob;
                    error_inject      == 1'b0;
                }) begin
                    `uvm_fatal(
                        "REGR_SEQ",
                        $sformatf(
                            "Failed to randomize regression transaction ID %0d",
                            test_id
                        )
                    )
                end

                t.scenario_name = $sformatf(
                    "[REGR-SEED%0d-P%0d-S%0d] Backpressure Regression",
                    simulation_seed, target_prob, target_size
                );

                // Initialize source memory with the data pattern before each transaction
                preload_src_mem(t.src_addr, t.data_payload);

                finish_item(t);

                `uvm_info(
                    "REGR_SEQ",
                    $sformatf("Generated Regression Transaction: %s", t.convert2string()),
                    UVM_HIGH
                )
            end
        end
    endtask
endclass
