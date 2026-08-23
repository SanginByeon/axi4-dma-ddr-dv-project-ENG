// ============================================================================
// coverage.sv - Functional Coverage Model
//
// - Separates the covergroup from the baseline testbench into a dedicated file.
// - Preserves the existing coverpoints, bins, crosses, and sampling conditions.
// - Confirms that coverage results match before and after the testbench split.
// ============================================================================

covergroup cg_dma_coverage @(posedge tb.clk); // Sampling point: rising edge of tb.clk
    option.per_instance = 1;                  // Collected independently per instance
    option.name = "DMA_System_Coverage";      // Name used to identify the report

    // [Transfer-size distribution]: meaningful ranges including corner cases
    cp_size: coverpoint tb.dma_ctrl.size_reg
        iff (tb.resetn && tb.dma_ctrl.size_reg != 0) {
        bins sz_tiny   = {[1:16]};       // Very small transfers (boundary check)
        bins sz_small  = {[17:256]};     // Small
        bins sz_medium = {[257:4096]};   // Medium
        bins sz_large  = {[4097:65536]}; // Large (strong multi-burst/alignment impact)
    }

    // [State distribution]: casts design dbg_state to an integer and groups it into ranges
    cp_dma_state: coverpoint int'(tb.dma_ctrl.dbg_state) {
        bins idle = {0};
        bins setup = {1};
        bins read_phases = {[2:3]};  // READ_ADDR/READ_DATA phases
        bins write_phases = {[4:6]}; // WRITE_ADDR/WRITE_DATA/WRITE_RESP phases
        bins next_burst = {7};
        bins complete = {8};
        bins error = {9};
    }

    // [Alignment]: determines 4-byte alignment from the two least-significant address bits
    cp_src_alignment: coverpoint tb.dma_ctrl.src_reg[1:0] iff (tb.resetn) {
        bins aligned = {2'b00};             // 4-byte aligned
        bins unaligned = {[2'b01:2'b11]};  // Unaligned (alignment/mask logic check)
    }

    cp_dst_alignment: coverpoint tb.dma_ctrl.dst_reg[1:0] iff (tb.resetn) {
        bins aligned = {2'b00};
        bins unaligned = {[2'b01:2'b11]};
    }

    // [Burst-length distribution]: uses observed dbg_burst_len (AXI len=0 -> 1 beat)
    cp_burst_len: coverpoint tb.dma_ctrl.dbg_burst_len iff (tb.resetn) {
        bins single = {0};   // 1 beat
        bins short = {[1:3]}; // 2~4 beats
        bins med = {[4:15]};  // 5-16 beats (example)
    }

    // [State-transition sequence]: normal flow and multi-burst re-entry loop
    cp_state_transitions: coverpoint int'(tb.dma_ctrl.dbg_state) iff (tb.resetn) {
        bins normal_flow = (0 => 1 => 2 => 3 => 4 => 5 => 6 => 8); // IDLE→...→COMPLETE
        bins multi_burst = (6 => 7 => 1);                          // RESP→NEXT_BURST→SETUP
    }

    // [Cross]: classifies large and unaligned transfers as illegal (design-constraint violation/test prohibited)
    cx_size_alignment: cross cp_size, cp_src_alignment {
        illegal_bins large_unaligned = binsof(cp_size.sz_large) && binsof(cp_src_alignment.unaligned);
    }
endgroup
