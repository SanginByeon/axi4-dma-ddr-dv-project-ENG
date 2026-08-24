// ============================================================================
// dma_scoreboard.sv - DMA UVM Scoreboard
//
// - Backdoor-reads source and destination memory from Monitor-provided DMA transactions
//   and checks complete transfer-region data integrity in 32-bit words.
// - Detects unknown data and reports a transaction-count mismatch when the number of observed
//   transfers differs from the expected count.
// ============================================================================

class dma_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(dma_scoreboard)

    uvm_analysis_imp #(dma_tx, dma_scoreboard) recv;

    // Number of Monitor transactions checked for data integrity
    int checked_count;

    // Expected number of transactions configured for generation by the Test
    int expected_count;

    function new(input string name = "dma_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // [build_phase] : Configure analysis implementation and transaction count
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        recv = new("recv", this);
        checked_count = 0;

        // Read the Test-provided transaction count for the final count comparison
        if (!uvm_config_db #(int)::get(this, "", "expected_count", expected_count))
            `uvm_fatal("SCB", "Unable to get expected_count from uvm_config_db")
    endfunction

    // [write] : Receive a Monitor transaction and check data integrity
    virtual function void write(input dma_tx t);
        checked_count++;

        `uvm_info(
            "SCB",
            $sformatf(
                "Received transaction #%0d from dma_monitor: %s",
                checked_count, t.convert2string()
            ),
            UVM_HIGH
        )

        check_dma_transfer(t);
    endfunction

    // [check_dma_transfer] : Compare source and destination data in words across the transfer region
    virtual function void check_dma_transfer(dma_tx t);
        int mismatch_count = 0;
        int unknown_count = 0;
        logic [31:0] src_data, dst_data;

        // Read source/destination data from addresses and size collected by the Monitor
        for (int i = 0; i < t.size; i += 4) begin
            read_ddr_mem(t.src_addr + i, src_data);
            read_ddr_mem(t.dst_addr + i, dst_data);

            // Treat data containing X/Z as a failure even if the values compare equal
            if ($isunknown(src_data) || $isunknown(dst_data)) begin
                `uvm_error(
                    "SCB",
                    $sformatf(
                        "[%0d] Unknown data detected: src=0x%h, dst=0x%h",
                        i, src_data, dst_data
                    )
                )
                unknown_count++;
            end else if (src_data == dst_data)
                `uvm_info(
                    "SCB",
                    $sformatf("[%0d] Match src=0x%h, dst=0x%h", i, src_data, dst_data),
                    UVM_FULL
                )
            else begin
                `uvm_error(
                    "SCB",
                    $sformatf("[%0d] Mismatch src=0x%h, dst=0x%h", i, src_data, dst_data)
                )
                mismatch_count++;
            end
        end

        if ((mismatch_count == 0) && (unknown_count == 0))
            `uvm_info("SCB", "Data Transfer Verification PASSED", UVM_MEDIUM)
        else
            `uvm_error(
                "SCB",
                $sformatf(
                    "Data Transfer Verification FAILED: mismatches=%0d, unknowns=%0d",
                    mismatch_count, unknown_count
                )
            )
    endfunction

    // [check_phase] : Report a mismatch when observed and expected transaction counts differ
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        if (checked_count != expected_count)
            `uvm_error(
                "SCB",
                $sformatf(
                    "Transaction count mismatch: expected=%0d, checked=%0d",
                    expected_count, checked_count
                )
            )
        else
            `uvm_info(
                "SCB",
                $sformatf("All expected transactions checked: %0d", checked_count),
                UVM_LOW
            )
    endfunction
endclass
