// ============================================================================
// mmio_if.sv - MMIO interface
//
// - SystemVerilog interface that groups MMIO register-access signals and
//   completion/error interrupts between the testbench and DMA controller.
// ============================================================================

interface mmio_if(input logic clk);

    // [MMIO signals] : The tb accesses DMA registers like software
    logic [7:0]  dma_reg_addr;   // Target register address
    logic [31:0] dma_reg_wdata;  // Write data
    logic [31:0] dma_reg_rdata;  // Read data (provided by the design)
    logic        dma_reg_write;  // Write when 1, read when 0
    logic        dma_reg_ack;    // Access-completion response (similar to ready)

    // [Interrupts] : Completion/error notification
    logic dma_done_int;
    logic dma_error_int;

    modport tb_mp (
        input clk, dma_reg_rdata, dma_reg_ack, dma_done_int, dma_error_int,
        output dma_reg_addr, dma_reg_wdata, dma_reg_write
    );

    modport dut_mp (
        output dma_reg_rdata, dma_reg_ack, dma_done_int, dma_error_int,
        input clk, dma_reg_addr, dma_reg_wdata, dma_reg_write
    );

endinterface
