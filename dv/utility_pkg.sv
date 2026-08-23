// ============================================================================
// utility_pkg.sv - MMIO Utility Task Package
//
// - Provides MMIO register read/write, DMA-completion wait, and status-polling tasks.
// - Separates the utility tasks from the baseline testbench into a dedicated package.
// - Preserves existing task behavior and MMIO access timing.
// - Declares automatic tasks for safe reuse.
// ============================================================================

package utility_pkg;

    // Declare the virtual-interface handle
    virtual mmio_if.tb_mp mif;

    // [MMIO write]: align to posedge -> hold for one clock -> wait for ack -> log
    task automatic write_dma_reg(input [7:0] addr, input [31:0] data);
        @(posedge mif.clk);
        mif.dma_reg_addr <= addr;  // Drive address
        mif.dma_reg_wdata <= data; // Drive data

        mif.dma_reg_write <= 1;  // Assert write
        @(posedge mif.clk);      // Hold for one clock (slave-latching margin)
        mif.dma_reg_write <= 0;  // Deassert write
        wait(mif.dma_reg_ack);   // Wait for completion response from the design
        $display("[%6.1f ns] REG[0x%02X] <- 0x%08X", real'($time) / 1000.0, addr, data);
    endtask

    // [MMIO read]: drive address -> stabilize for two clocks -> sample rdata -> log
    task automatic read_dma_reg(input [7:0] addr, output [31:0] data);
        @(posedge mif.clk);
        mif.dma_reg_addr <= addr;  // Drive address
        mif.dma_reg_write <= 0;    // Read mode
        @(posedge mif.clk);        // One-clock margin (pipeline/combinational path)
        @(posedge mif.clk);        // Wait one additional MMIO clock before sampling read data
        data = mif.dma_reg_rdata;   // Capture read data
        $display("[%6.1f ns] REG[0x%02X] -> 0x%08X", real'($time) / 1000.0, addr, data);
    endtask

    // [DMA termination wait] : Capture the first completion/error/timeout event by edge
    task automatic wait_dma_completion(input int timeout_cycles = 1000);
        $display("[%6.1f ns] Waiting for DMA completion...", real'($time) / 1000.0);
        fork
            begin
                @(posedge mif.dma_done_int);  // Completion-interrupt rising edge
                $display("[%6.1f ns] DMA completion interrupt received!", real'($time) / 1000.0);
            end
            begin
                @(posedge mif.dma_error_int);  // Error-interrupt rising edge
                $display("[%6.1f ns] DMA error interrupt occurred!", real'($time) / 1000.0);
            end
            begin
                repeat(timeout_cycles) @(posedge mif.clk);  // Timeout counter
                $display("[%6.1f ns] DMA timeout after %0d cycles", real'($time) / 1000.0, timeout_cycles);
            end
        join_any      // Join after the first completion

        disable fork;  // Terminate remaining threads to prevent resource leakage
    endtask

    // [STATUS polling]: secondary completion check when an interrupt is absent or missed
    task automatic wait_done_via_status(input int max_tries = 20);
        int i;
        logic [31:0] s;

        for (i = 0; i < max_tries; i++) begin
            read_dma_reg(8'h04, s);  // STATUS (assumed address 0x04)
            if (s[1]) return;        // Return immediately when the done bit is 1
            @(posedge mif.clk);      // Wait one clock before the next poll
        end

        $display("STATUS polling timeout (done=0)");  // Polling-timeout notification
    endtask

endpackage
