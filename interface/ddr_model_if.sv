// ============================================================================
// ddr_model_if.sv - DDR Memory Model Control Interface
//
// - Interface through which the UVM Driver configures DDR memory-model verification conditions.
// - Carries the AXI4 W-channel random-backpressure probability and BRESP error-injection setting.
// - Provides verification memory-model control signals rather than a DUT protocol interface.
// ============================================================================

interface ddr_model_if(input logic aclk, aresetn);

    // [Backpressure control] : Probability of deasserting WREADY (0–99%)
    logic [7:0] backpressure_prob;

    // [BRESP error injection] : Return SLVERR as the write response when set to 1
    logic error_inject;

endinterface
