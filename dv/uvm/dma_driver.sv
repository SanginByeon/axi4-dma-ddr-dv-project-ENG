// ============================================================================
// dma_driver.sv - DMA UVM Driver
//
// - Receives DMA transactions from the Sequence and writes their settings to MMIO registers.
// - Passes per-transaction backpressure and BRESP error-injection settings to the DDR memory model.
// - Waits for DMA completion or error, checks STATUS, and logs BYTES_DONE.
// - Calls MMIO tasks through utility_pkg.
// ============================================================================

import utility_pkg::*;

class dma_driver extends uvm_driver #(dma_tx);
    `uvm_component_utils(dma_driver)

    // [DMA register map]
    localparam logic [7:0] DMA_CTRL_REG       = 8'h00;
    localparam logic [7:0] DMA_STAT_REG       = 8'h04;
    localparam logic [7:0] DMA_SRC_ADDR_REG   = 8'h08;
    localparam logic [7:0] DMA_DST_ADDR_REG   = 8'h0C;
    localparam logic [7:0] DMA_SIZE_REG       = 8'h10;
    localparam logic [7:0] DMA_BYTES_DONE_REG = 8'h14;

    dma_tx req;
    virtual mmio_if.tb_mp mif;
    virtual axi4_if aif;
    virtual ddr_model_if dif;

    function new(input string name = "dma_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // [reset_phase] : Initialize MMIO outputs during reset
    virtual task reset_phase(uvm_phase phase);
        phase.raise_objection(this);

        wait (aif.aresetn == 1'b0); // Wait for reset assertion

        mif.dma_reg_write <= 1'b0;
        mif.dma_reg_addr  <= '0;
        mif.dma_reg_wdata <= '0;
        dif.backpressure_prob <= '0;
        dif.error_inject <= 1'b0;

        wait (aif.aresetn == 1'b1); // Wait for reset deassertion

        repeat (2) @(posedge mif.clk); // Stabilize immediately after reset deassertion

        `uvm_info("DRV", "Reset phase done", UVM_MEDIUM)
        phase.drop_objection(this);
    endtask

    // [build_phase] : Prepare transaction and virtual interfaces
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        req = dma_tx::type_id::create("req");

        if (!uvm_config_db #(virtual mmio_if.tb_mp)::get(this, "", "mif", mif))
            `uvm_fatal("DRV", "Unable to get mif from uvm_config_db");

        utility_pkg::mif = this.mif;

        if (!uvm_config_db #(virtual axi4_if)::get(this, "", "aif", aif))
            `uvm_fatal("DRV", "Unable to get aif from uvm_config_db");

        if (!uvm_config_db #(virtual ddr_model_if)::get(this, "", "dif", dif))
            `uvm_fatal("DRV", "Unable to get dif from uvm_config_db");
    endfunction

    // [run_phase] : Convert sequence items into MMIO stimulus and drive the DUT
    virtual task run_phase(uvm_phase phase);
        bit [31:0] ctrl_reg_value;
        bit [31:0] status;
        int timeout_cycles;
        int word_count;
        int stall_wait_budget;

        super.run_phase(phase);

        forever begin
            // Clear the combined CTRL value before receiving the next transaction
            ctrl_reg_value = 0;

            // Receive a transaction from the Sequencer and start MMIO stimulus
            seq_item_port.get_next_item(req);
            `uvm_info("DRV", $sformatf("Start %s", req.convert2string()), UVM_MEDIUM)

            // Apply DDR memory-model backpressure and BRESP-error settings before configuring the DMA
            dif.backpressure_prob <= req.backpressure_prob;
            dif.error_inject <= req.error_inject;

            // Configure source/destination addresses and transfer size before starting the DMA
            write_dma_reg(DMA_SRC_ADDR_REG, req.src_addr); // SRC_ADDR
            write_dma_reg(DMA_DST_ADDR_REG, req.dst_addr); // DST_ADDR
            write_dma_reg(DMA_SIZE_REG, req.size);         // SIZE

            // Combine transaction enable/start/irq values into the low CTRL bits
            if (req.enable)
                ctrl_reg_value |= (1 << 0); // Bit 0: enable
            if (req.start)
                ctrl_reg_value |= (1 << 1); // Bit 1: start
            if (req.irq)
                ctrl_reg_value |= (1 << 2); // Bit 2: irq_en

            // Write CTRL last to start the DMA with the configured addresses and size
            write_dma_reg(DMA_CTRL_REG, ctrl_reg_value); // CTRL: enable/start/irq

            // Wait for the interrupt first, then use STATUS polling as an auxiliary termination check
            // Allow normal stall latency based on transfer size and backpressure probability
            word_count = (req.size + 3) / 4;
            // Apply 4× margin to the average W-handshake wait of 100/(100-p)
            stall_wait_budget = 400 / (100 - req.backpressure_prob);
            timeout_cycles = 500 + (word_count * (8 + stall_wait_budget));
            wait_dma_completion(timeout_cycles); // Capture interrupt/error/timeout
            wait_done_via_status();               // Auxiliary check (STATUS polling)

            // Evaluate each transaction from the STATUS error/done bits
            read_dma_reg(DMA_STAT_REG, status); // Read STATUS

            if (status[2])
                `uvm_error("DRV", $sformatf("%s FAILED. DUT reported an error.", req.scenario_name))
            else if (status[1])
                `uvm_info("DRV", $sformatf("%s PASSED", req.scenario_name), UVM_MEDIUM)
            else
                `uvm_error("DRV", $sformatf("%s FAILED. Timeout occurred.", req.scenario_name))

            // Read and log the number of bytes received on the AXI read channel
            read_dma_reg(DMA_BYTES_DONE_REG, status); // BYTES_TRANSFERRED
            `uvm_info("DRV", $sformatf("Bytes transferred: %0d", status), UVM_HIGH)

            // Restore settings so backpressure/error injection does not leak into the next transaction
            dif.backpressure_prob <= '0;
            dif.error_inject <= 1'b0;

            // Complete the current transaction and allow the next item request
            seq_item_port.item_done();
        end
    endtask
endclass
