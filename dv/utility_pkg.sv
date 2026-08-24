// ============================================================================
// utility_pkg.sv - DMA Verification Utility Package
//
// - Provides MMIO register read/write, DMA-completion wait, and status-polling tasks.
// - Supports source-memory preload by UVM sequences and backdoor reads by the Scoreboard.
// - Checks the 4 KB memory range and treats backdoor-access failure as UVM fatal.
// - Preserves Step 1 MMIO access timing and controls progress logs through UVM verbosity.
// - Declares utility tasks/functions automatic for reentrancy.
// ============================================================================

package utility_pkg;

    `include "uvm_macros.svh"
    import uvm_pkg::*;

    // [Virtual interface] : Interface handle used by MMIO utility tasks
    virtual mmio_if.tb_mp mif;

    // [DDR backdoor] : Memory path and number of 32-bit words
    localparam string DDR_MEM_PATH = "tb.ddr_model.mem";
    localparam int unsigned DDR_WORD_COUNT = 1024;

    // [MMIO write] : Align to posedge → hold one clock → wait for ack → detailed log
    task automatic write_dma_reg(input [7:0] addr, input [31:0] data);
        @(posedge mif.clk);
        mif.dma_reg_addr  <= addr;  // Present address
        mif.dma_reg_wdata <= data;  // Present data

        mif.dma_reg_write <= 1'b1;  // Enable write
        @(posedge mif.clk);         // Hold for one clock (slave-latching margin)
        mif.dma_reg_write <= 1'b0;  // Disable write
        wait (mif.dma_reg_ack);     // Wait for completion response from the design
        `uvm_info(
            "MMIO",
            $sformatf("REG[0x%02X] <- 0x%08X", addr, data),
            UVM_HIGH
        )
    endtask

    // [MMIO read] : Present address → stabilize for two clocks → sample rdata → detailed log
    task automatic read_dma_reg(input [7:0] addr, output [31:0] data);
        @(posedge mif.clk);
        mif.dma_reg_addr  <= addr;  // Present address
        mif.dma_reg_write <= 1'b0;  // Read mode
        @(posedge mif.clk);        // One-clock margin (pipeline/combinational path)
        @(posedge mif.clk);        // Wait one additional MMIO clock before sampling read data
        data = mif.dma_reg_rdata;   // Capture read data
        `uvm_info(
            "MMIO",
            $sformatf("REG[0x%02X] -> 0x%08X", addr, data),
            UVM_HIGH
        )
    endtask

    // [DMA termination wait] : Capture the first completion/error/timeout event by edge
    task automatic wait_dma_completion(input int timeout_cycles = 1000);
        `uvm_info(
            "DMA_WAIT",
            "Waiting for DMA completion...",
            UVM_MEDIUM
        )
        fork
            begin
                @(posedge mif.dma_done_int);  // Completion-interrupt rising edge
                `uvm_info(
                    "DMA_WAIT",
                    "DMA completion interrupt received!",
                    UVM_MEDIUM
                )
            end
            begin
                @(posedge mif.dma_error_int);  // Error-interrupt rising edge
                `uvm_info(
                    "DMA_WAIT",
                    "DMA error interrupt occurred!",
                    UVM_MEDIUM
                )
            end
            begin
                repeat (timeout_cycles) @(posedge mif.clk); // Timeout counter
                `uvm_info(
                    "DMA_WAIT",
                    $sformatf("DMA timeout after %0d cycles", timeout_cycles),
                    UVM_MEDIUM
                )
            end
        join_any      // Join after the first completion

        disable fork;  // Terminate remaining threads to prevent resource leakage
    endtask

    // [STATUS polling]: secondary completion check when an interrupt is absent or missed
    task automatic wait_done_via_status(input int max_tries = 20);
        int i;
        logic [31:0] s;

        for (i = 0; i < max_tries; i++) begin
            read_dma_reg(8'h04, s);  // STATUS(0x04)
            if (s[1]) return;        // Return immediately when the done bit is 1
            @(posedge mif.clk);      // Wait one clock before the next poll
        end

        // Treat as an informational log because done=0 may be valid on the error-interrupt path
        `uvm_info("DMA_WAIT", "STATUS polling timeout (done=0)", UVM_MEDIUM)
    endtask

    // [Source-memory preload] : Inject data_payload in 32-bit words starting at src_addr
    task automatic preload_src_mem(input [31:0] src_addr, input byte data_payload[]);
        for (int i = 0; i < data_payload.size(); i += 4) begin
            bit [31:0] word = 0;
            int unsigned word_idx;  // Memory-model word index
            string path;

            if (i < data_payload.size())
                word[7:0] = data_payload[i];
            if (i + 1 < data_payload.size())
                word[15:8] = data_payload[i + 1];
            if (i + 2 < data_payload.size())
                word[23:16] = data_payload[i + 2];
            if (i + 3 < data_payload.size())
                word[31:24] = data_payload[i + 3];

            // Convert the byte address to a word index and check the memory range
            word_idx = (src_addr + i) >> 2;
            if (word_idx >= DDR_WORD_COUNT)
                `uvm_fatal("PRELOAD", $sformatf(
                    "Address out of DDR range: addr=0x%0h, idx=%0d",
                    src_addr + i, word_idx
                ))

            // Directly inject data into memory-model mem[word_idx]
            path = $sformatf("%s[%0d]", DDR_MEM_PATH, word_idx);
            if (!uvm_hdl_deposit(path, word))
                `uvm_fatal("PRELOAD", $sformatf(
                    "uvm_hdl_deposit failed: %s", path
                ))
        end
    endtask

    // [DDR memory read] : Backdoor-read the 32-bit word at the specified address
    function automatic void read_ddr_mem(input [31:0] addr, output [31:0] data);
        int unsigned word_idx;
        string path;

        // Convert the byte address to a word index and check the memory range
        word_idx = addr >> 2;
        if (word_idx >= DDR_WORD_COUNT)
            `uvm_fatal("SCB", $sformatf(
                "Address out of DDR range: addr=0x%0h, idx=%0d",
                addr, word_idx
            ))

        // Directly read data from memory-model mem[word_idx]
        path = $sformatf("%s[%0d]", DDR_MEM_PATH, word_idx);
        if (!uvm_hdl_read(path, data))
            `uvm_fatal("SCB", $sformatf(
                "uvm_hdl_read failed: %s", path
            ))
    endfunction

endpackage
