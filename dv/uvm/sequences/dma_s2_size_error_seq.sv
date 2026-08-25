// ============================================================================
// dma_s2_size_error_seq.sv - DMA Scenario 2 Size Error Sequence
//
// - Exercises the size-error path with 1-, 2-, 3-, and 15-byte transfer requests.
// - The DUT records error_code=0x2 in S_SETUP and raises the error interrupt in S_ERROR when
//   interrupts are enabled.
// - Preserves the existing Driver and Scoreboard negative-test reporting behavior.
// ============================================================================

import utility_pkg::*;

class dma_s2_size_error_seq extends dma_base_seq;
    `uvm_object_utils(dma_s2_size_error_seq)

    function new(input string name = "dma_s2_size_error_seq");
        super.new(name);
    endfunction

    // [body] : Generate a transaction and initialize source memory for each unsupported transfer size
    virtual task body();
        dma_tx t;

        int unsigned test_id[] = '{1, 2, 3, 4};
        int unsigned size_bytes[] = '{1, 2, 3, 15};
        bit [31:0] src_addr_list[] = '{
            32'h0000_0080, 32'h0000_0480,
            32'h0000_0C40, 32'h0000_0180
        };
        bit [31:0] dst_addr_list[] = '{
            32'h0000_0380, 32'h0000_0C80,
            32'h0000_0040, 32'h0000_0680
        };

        foreach (test_id[i]) begin
            int unsigned target_size = size_bytes[i];
            bit [31:0] target_src = src_addr_list[i];
            bit [31:0] target_dst = dst_addr_list[i];

            t = dma_tx::type_id::create(
                $sformatf("t_s2_id%0d", test_id[i])
            );

            start_item(t);

            if (!t.randomize() with {
                src_addr == local::target_src;
                dst_addr == local::target_dst;
                size     == local::target_size;

                enable == 1'b1;
                start  == 1'b1;
                irq    == 1'b1;

                backpressure_prob == 0;
                error_inject      == 1'b0;
            }) begin
                `uvm_fatal(
                    "S2_SEQ",
                    $sformatf("Failed to randomize S2 transaction ID %0d", test_id[i])
                )
            end

            t.scenario_name = $sformatf(
                "[S2-%0d] %0dB Size Error",
                test_id[i], target_size
            );

            // Initialize source memory with the 32'hCAFE_0000-based pattern
            preload_src_mem(t.src_addr, t.data_payload);

            finish_item(t);

            `uvm_info(
                "S2_SEQ",
                $sformatf("Generated S2 Transaction: %s", t.convert2string()),
                UVM_HIGH
            )
        end
    endtask
endclass
