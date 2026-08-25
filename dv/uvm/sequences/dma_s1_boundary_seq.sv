// ============================================================================
// dma_s1_boundary_seq.sv - DMA Scenario 1 Boundary Sequence
//
// - Sequentially runs 11 normal-transfer boundary values without backpressure or error injection.
// - Checks 1-/4-/16-beat and multi-burst tail branches and complete data integrity.
// - Distributes source/destination start addresses across low/mid/high regions of the 4 KB memory.
// ============================================================================

import utility_pkg::*;

class dma_s1_boundary_seq extends dma_base_seq;
    `uvm_object_utils(dma_s1_boundary_seq)

    function new(input string name = "dma_s1_boundary_seq");
        super.new(name);
    endfunction

    // [body] : Generate a transaction and initialize source memory for each normal-transfer boundary
    virtual task body();
        dma_tx t;

        int unsigned test_id[] = '{
            1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
        };
        int unsigned size_bytes[] = '{
            4, 12, 16, 60, 64, 68, 80, 256, 1024, 1028, 2048
        };
        bit [31:0] src_addr_list[] = '{
            32'h0000_0000, 32'h0000_0400, 32'h0000_0C00,
            32'h0000_0100, 32'h0000_0500, 32'h0000_0C00,
            32'h0000_0200, 32'h0000_0600, 32'h0000_0000,
            32'h0000_0000, 32'h0000_0000
        };
        bit [31:0] dst_addr_list[] = '{
            32'h0000_0400, 32'h0000_0C00, 32'h0000_0000,
            32'h0000_0500, 32'h0000_0C00, 32'h0000_0000,
            32'h0000_0600, 32'h0000_0C00, 32'h0000_0800,
            32'h0000_0800, 32'h0000_0800
        };

        foreach (test_id[i]) begin
            int unsigned target_size = size_bytes[i];
            bit [31:0] target_src = src_addr_list[i];
            bit [31:0] target_dst = dst_addr_list[i];

            t = dma_tx::type_id::create(
                $sformatf("t_s1_id%0d", test_id[i])
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
                    "S1_SEQ",
                    $sformatf("Failed to randomize S1 transaction ID %0d", test_id[i])
                )
            end

            t.scenario_name = $sformatf(
                "[S1-%0d] %0dB Normal Boundary Transfer",
                test_id[i], target_size
            );

            // Initialize source memory with the 32'hCAFE_0000-based pattern
            preload_src_mem(t.src_addr, t.data_payload);

            finish_item(t);

            `uvm_info(
                "S1_SEQ",
                $sformatf("Generated S1 Transaction: %s", t.convert2string()),
                UVM_HIGH
            )
        end
    endtask
endclass
