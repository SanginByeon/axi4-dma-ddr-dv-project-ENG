// ============================================================================
// coverage.sv - DMA Functional Coverage Model
//
// - Separates DMA-transaction, FSM, and AXI4-event coverage into three covergroups.
// - Samples each transaction once at a completion/error interrupt and conditionally samples FSM/AXI events each clock.
// - Directly uses DUT/testbench observation signals without a separate coverage collector.
// ============================================================================

// [Transaction coverage] : Sample the transaction result once per completion or error interrupt
covergroup cg_dma_transaction
    @(posedge tb.mmio.dma_done_int or posedge tb.mmio.dma_error_int);
    option.per_instance = 1;
    option.name = "DMA_Transaction_Coverage";

    // [C-TX-01] : Create an independent bin for each transfer boundary value
    cp_size_boundary: coverpoint tb.dma_ctrl.size_reg {
        bins boundary[] = {
            1, 2, 3, 4, 12, 15, 16, 60, 64, 68, 80,
            256, 1024, 1028, 2048
        };
    }

    // [C-TX-02] : Transfer sizes from 4 to 2,048 bytes that are multiples of four
    cp_size_range: coverpoint tb.dma_ctrl.size_reg
        iff (
            (tb.dma_ctrl.size_reg >= 4) &&
            (tb.dma_ctrl.size_reg <= 2048) &&
            (tb.dma_ctrl.size_reg[1:0] == 2'b00)
        ) {
        bins size_tiny   = {[4:16]};
        bins size_small  = {[20:256]};
        bins size_medium = {[260:1024]};
        bins size_large  = {[1028:2048]};
    }

    // [C-TX-03] : Classify transfer sizes as normal, initial-error, or remaining-byte-error conditions
    cp_size_category: coverpoint (
        (tb.dma_ctrl.size_reg < 4) ? 2'd0 :
        ((tb.dma_ctrl.size_reg[1:0] != 2'b00) ? 2'd1 : 2'd2)
    ) {
        bins undersized   = {2'd0};
        bins residual     = {2'd1};
        bins word_aligned = {2'd2};
    }

    // [C-TX-04] : 4 KB memory region containing the source start address
    cp_src_region: coverpoint tb.dma_ctrl.src_reg[11:10] {
        bins low  = {2'd0};
        bins mid  = {[2'd1:2'd2]};
        bins high = {2'd3};
    }

    // [C-TX-05] : 4 KB memory region containing the destination start address
    cp_dst_region: coverpoint tb.dma_ctrl.dst_reg[11:10] {
        bins low  = {2'd0};
        bins mid  = {[2'd1:2'd2]};
        bins high = {2'd3};
    }

    // [C-TX-06] : W-channel backpressure intensity configured in the DDR memory model
    cp_backpressure_class: coverpoint tb.ddr_model_ctrl.backpressure_prob {
        bins bp_none   = {0};
        bins bp_low    = {[1:30]};
        bins bp_medium = {[31:70]};
        bins bp_high   = {[71:99]};
        illegal_bins out_of_range = default;
    }

    // [C-TX-07] : BRESP SLVERR-injection setting
    cp_error_inject: coverpoint tb.ddr_model_ctrl.error_inject {
        bins disabled = {1'b0};
        bins enabled  = {1'b1};
    }

    // [C-TX-08] : Actual termination error code reported by the DMA
    cp_error_code: coverpoint tb.dma_ctrl.stat.error_code {
        bins normal      = {4'h0};
        bins size_error  = {4'h2};
        bins bresp_error = {4'h3};
        illegal_bins unexpected = default;
    }

    // [X-TX-01] : Relate the transfer-size cause to the actual error code
    cx_size_result: cross cp_size_category, cp_error_code {
        bins aligned_to_normal =
            binsof(cp_size_category.word_aligned) &&
            binsof(cp_error_code.normal);
        bins undersized_to_size_error =
            binsof(cp_size_category.undersized) &&
            binsof(cp_error_code.size_error);
        bins residual_to_size_error =
            binsof(cp_size_category.residual) &&
            binsof(cp_error_code.size_error);

        ignore_bins other_results =
            (binsof(cp_size_category.word_aligned) &&
             !binsof(cp_error_code.normal)) ||
            (binsof(cp_size_category.undersized) &&
             !binsof(cp_error_code.size_error)) ||
            (binsof(cp_size_category.residual) &&
             !binsof(cp_error_code.size_error));
    }

    // [X-TX-02] : Relate the error-injection setting to the actual error code
    cx_inject_result: cross cp_error_inject, cp_error_code {
        bins no_inject_normal =
            binsof(cp_error_inject.disabled) &&
            binsof(cp_error_code.normal);
        bins no_inject_size_error =
            binsof(cp_error_inject.disabled) &&
            binsof(cp_error_code.size_error);
        bins inject_to_bresp_error =
            binsof(cp_error_inject.enabled) &&
            binsof(cp_error_code.bresp_error);

        ignore_bins other_results =
            (binsof(cp_error_inject.disabled) &&
             binsof(cp_error_code.bresp_error)) ||
            (binsof(cp_error_inject.enabled) &&
             !binsof(cp_error_code.bresp_error));
    }

    // [X-TX-03] : Standalone SLVERR and combined backpressure conditions
    cx_inject_backpressure: cross cp_error_inject, cp_backpressure_class;
endgroup

// [FSM coverage] : Sample DMA states, state transitions, and S_SETUP branches
covergroup cg_dma_fsm @(posedge tb.clk);
    option.per_instance = 1;
    option.name = "DMA_FSM_Coverage";

    // [C-FSM-01] : DMA FSM states
    cp_state: coverpoint tb.dbg_state iff (tb.resetn) {
        bins idle     = {4'h0};
        bins setup    = {4'h1};
        bins rd_addr  = {4'h2};
        bins rd_data  = {4'h3};
        bins wr_addr  = {4'h4};
        bins wr_data  = {4'h5};
        bins wr_resp  = {4'h6};
        bins next     = {4'h7};
        bins done     = {4'h8};
        bins error    = {4'h9};
        illegal_bins unexpected = default;
    }

    // [C-FSM-02] : Normal, multi-burst, error, and recovery state transitions
    cp_state_transition: coverpoint tb.dbg_state iff (tb.resetn) {
        bins idle_to_setup   = (4'h0 => 4'h1);
        bins setup_to_rd     = (4'h1 => 4'h2);
        bins rd_addr_to_data = (4'h2 => 4'h3);
        bins rd_to_wr_addr   = (4'h3 => 4'h4);
        bins wr_addr_to_data = (4'h4 => 4'h5);
        bins wr_data_to_resp = (4'h5 => 4'h6);
        bins resp_to_done    = (4'h6 => 4'h8);
        bins done_to_idle    = (4'h8 => 4'h0);
        bins resp_to_next    = (4'h6 => 4'h7);
        bins next_to_setup   = (4'h7 => 4'h1);
        bins setup_to_error  = (4'h1 => 4'h9);
        bins resp_to_error   = (4'h6 => 4'h9);
        bins error_to_idle   = (4'h9 => 4'h0);
        bins error_recovery  = (4'h9 => 4'h0 => 4'h1);
    }

    // [C-FSM-03] : Sample only the cycle in which S_SETUP selects the actual burst length
    cp_setup_case: coverpoint tb.dma_ctrl.bytes_left
        iff (
            tb.resetn &&
            (tb.dbg_state == 4'h1) &&
            !tb.dma_ctrl.setup_complete
        ) {
        bins invalid_size  = {[1:3]};
        bins one_beat      = {[4:15]};
        bins four_beats    = {[16:63]};
        bins sixteen_beats = {[64:$]};
    }

    // [C-FSM-04] : S_SETUP branch selected for the remainder after a full 64B burst
    cp_tail_setup_case: coverpoint tb.dma_ctrl.bytes_left
        iff (
            tb.resetn &&
            (tb.dbg_state == 4'h1) &&
            !tb.dma_ctrl.setup_complete &&
            (tb.dma_ctrl.size_reg > 64) &&
            (tb.dma_ctrl.size_reg[1:0] == 2'b00) &&
            (tb.dma_ctrl.bytes_left >= 4) &&
            (tb.dma_ctrl.bytes_left < 64)
        ) {
        bins one_beat_tail   = {[4:15]};
        bins four_beats_tail = {[16:63]};
    }
endgroup

// [AXI event coverage] : Sample actual AW/W/B-channel handshakes and stall events
covergroup cg_axi_event @(posedge tb.clk);
    option.per_instance = 1;
    option.name = "AXI_Event_Coverage";

    // [C-AXI-01] : Sample the actual burst length at an AW handshake
    cp_awlen: coverpoint tb.memory_axi.awlen
        iff (
            tb.resetn &&
            tb.memory_axi.awvalid &&
            tb.memory_axi.awready
        ) {
        bins one_beat      = {8'd0};
        bins four_beats    = {8'd3};
        bins sixteen_beats = {8'd15};
        illegal_bins unexpected = default;
    }

    // [C-AXI-02] : Backpressure setting latched for the write burst at the AW handshake
    cp_backpressure_cfg_at_aw: coverpoint tb.ddr_model_ctrl.backpressure_prob
        iff (
            tb.resetn &&
            tb.memory_axi.awvalid &&
            tb.memory_axi.awready
        ) {
        bins bp_none   = {0};
        bins bp_low    = {[1:30]};
        bins bp_medium = {[31:70]};
        bins bp_high   = {[71:99]};
        illegal_bins out_of_range = default;
    }

    // [C-AXI-03] : Whether a WVALID cycle handshakes or stalls
    cp_w_event: coverpoint tb.memory_axi.wready
        iff (tb.resetn && tb.memory_axi.wvalid) {
        bins stalled  = {1'b0};
        bins accepted = {1'b1};
    }

    // [C-AXI-04] : Burst length at which an actual W-channel stall occurs
    cp_stall_awlen: coverpoint tb.memory_axi.awlen
        iff (
            tb.resetn &&
            tb.memory_axi.wvalid &&
            !tb.memory_axi.wready
        ) {
        bins one_beat      = {8'd0};
        bins four_beats    = {8'd3};
        bins sixteen_beats = {8'd15};
        illegal_bins unexpected = default;
    }

    // [C-AXI-05] : Burst length at which a WLAST handshake occurs
    cp_wlast_awlen: coverpoint tb.memory_axi.awlen
        iff (
            tb.resetn &&
            tb.memory_axi.wvalid &&
            tb.memory_axi.wready &&
            tb.memory_axi.wlast
        ) {
        bins one_beat      = {8'd0};
        bins four_beats    = {8'd3};
        bins sixteen_beats = {8'd15};
        illegal_bins unexpected = default;
    }

    // [C-AXI-06] : Sample the actual response at a B-channel handshake
    cp_bresp: coverpoint tb.memory_axi.bresp
        iff (
            tb.resetn &&
            tb.memory_axi.bvalid &&
            tb.memory_axi.bready
        ) {
        bins okay   = {2'b00};
        bins slverr = {2'b10};
        ignore_bins unsupported = {2'b01, 2'b11};
    }

    // [C-AXI-07] : Sample the error-injection setting at a B-channel handshake
    cp_error_inject_at_b: coverpoint tb.ddr_model_ctrl.error_inject
        iff (
            tb.resetn &&
            tb.memory_axi.bvalid &&
            tb.memory_axi.bready
        ) {
        bins disabled = {1'b0};
        bins enabled  = {1'b1};
    }

    // [X-AXI-01] : Cross backpressure intensity with actual AWLEN
    cx_backpressure_awlen: cross cp_backpressure_cfg_at_aw, cp_awlen;

    // [X-AXI-02] : Relate the error-injection setting to the actual BRESP
    cx_bresp_error_inject: cross cp_bresp, cp_error_inject_at_b {
        bins normal_response =
            binsof(cp_bresp.okay) &&
            binsof(cp_error_inject_at_b.disabled);
        bins injected_slverr =
            binsof(cp_bresp.slverr) &&
            binsof(cp_error_inject_at_b.enabled);

        ignore_bins unexpected_pair =
            (binsof(cp_bresp.okay) &&
             binsof(cp_error_inject_at_b.enabled)) ||
            (binsof(cp_bresp.slverr) &&
             binsof(cp_error_inject_at_b.disabled));
    }
endgroup
