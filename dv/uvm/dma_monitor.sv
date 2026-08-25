// ============================================================================
// dma_monitor.sv - DMA UVM Monitor
//
// - Collects transactions by observing MMIO writes and DDR-model backpressure/error settings.
// - Forwards the collected transaction to the Scoreboard on a DMA completion or error interrupt.
// ============================================================================

class dma_monitor extends uvm_monitor;
    `uvm_component_utils(dma_monitor)

    // [DMA register map]
    localparam logic [7:0] DMA_CTRL_REG     = 8'h00;
    localparam logic [7:0] DMA_SRC_ADDR_REG = 8'h08;
    localparam logic [7:0] DMA_DST_ADDR_REG = 8'h0C;
    localparam logic [7:0] DMA_SIZE_REG     = 8'h10;

    uvm_analysis_port #(dma_tx) send;

    virtual mmio_if.tb_mp mif;
    virtual axi4_if aif;
    virtual ddr_model_if dif;

    function new(input string name = "dma_monitor", uvm_component parent = null);
        super.new(name, parent);
        send = new("send", this);
    endfunction

    // [build_phase] : Prepare MMIO/AXI/DDR-model virtual interfaces
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db #(virtual mmio_if.tb_mp)::get(this, "", "mif", mif))
            `uvm_fatal("MON", "Unable to get mif from uvm_config_db");

        if (!uvm_config_db #(virtual axi4_if)::get(this, "", "aif", aif))
            `uvm_fatal("MON", "Unable to get aif from uvm_config_db");

        if (!uvm_config_db #(virtual ddr_model_if)::get(this, "", "dif", dif))
            `uvm_fatal("MON", "Unable to get dif from uvm_config_db");
    endfunction

    // [run_phase] : Reconstruct transactions by observing MMIO writes and completion/error interrupts
    virtual task run_phase(uvm_phase phase);
        dma_tx t;

        wait (aif.aresetn == 1'b1);      // Wait for reset deassertion
        repeat (2) @(posedge mif.clk);   // Stabilize immediately after reset deassertion

        t = dma_tx::type_id::create("t");

        forever begin
            @(posedge mif.clk);

            // Reconstruct transaction fields by observing MMIO-interface writes
            if (mif.dma_reg_write) begin
                case (mif.dma_reg_addr)
                    // Store each DMA configuration-register value in its transaction field
                    DMA_SRC_ADDR_REG: t.src_addr = mif.dma_reg_wdata;
                    DMA_DST_ADDR_REG: t.dst_addr = mif.dma_reg_wdata;
                    DMA_SIZE_REG: t.size = mif.dma_reg_wdata;
                    DMA_CTRL_REG: begin
                        // Reconstruct enable/start/irq settings from the low CTRL bits
                        t.enable = mif.dma_reg_wdata[0];
                        t.start  = mif.dma_reg_wdata[1];
                        t.irq    = mif.dma_reg_wdata[2];

                        // Capture verification conditions applied to the DDR memory model at DMA start
                        t.backpressure_prob = dif.backpressure_prob;
                        t.error_inject = dif.error_inject;

                        // When start is set, wait for DMA completion/error and forward the transaction
                        if (t.start) begin
                            @(posedge mif.dma_done_int or posedge mif.dma_error_int);
                            `uvm_info(
                                "MON",
                                $sformatf("Collected Transaction: %s", t.convert2string()),
                                UVM_MEDIUM
                            )
                            // Send the completed transaction to the Scoreboard through the analysis port
                            send.write(t);

                            // Create a new transaction object for the next DMA transfer
                            t = dma_tx::type_id::create("t");
                        end
                    end
                endcase
            end
        end
    endtask
endclass
