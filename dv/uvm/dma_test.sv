// ============================================================================
// dma_test.sv - DMA UVM Test
//
// - Sequentially runs normal-boundary, error, backpressure, and constrained-random scenarios after reset.
// - Passes Agent mode and expected transaction count to the environment through config_db.
// - Sets verbosity for the complete UVM hierarchy in the end_of_elaboration phase.
// - Combines expected negative-test errors, AXI checker, and functional coverage in the final decision.
// ============================================================================

class dma_test extends uvm_test;
    `uvm_component_utils(dma_test)

    // Total transactions executed by this Test and expected to be checked by the Scoreboard
    localparam int EXPECTED_TX_COUNT = 37;

    // Expected UVM errors: 5 size errors × 3 reports and 5 SLVERRs × 1 report
    localparam int EXPECTED_UVM_ERROR_COUNT = 20;

    dma_s1_boundary_seq s1_boundary;
    dma_s2_size_error_seq s2_size_error;
    dma_s3_backpressure_seq s3_backpressure;
    dma_s4_slverr_seq s4_slverr;
    dma_s5_backpressure_slverr_seq s5_backpressure_slverr;
    dma_s6_error_recovery_seq s6_error_recovery;
    dma_s7_random_seq s7_random;

    dma_env e;
    virtual axi4_if aif;

    // Transaction/FSM/AXI-event functional coverage instances
    cg_dma_transaction transaction_cov = new();
    cg_dma_fsm fsm_cov = new();
    cg_axi_event axi_cov = new();

    function new(input string name = "dma_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // [build_phase] : Create scenario Sequences and the UVM Environment
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        s1_boundary = dma_s1_boundary_seq::type_id::create("s1_boundary");
        s2_size_error = dma_s2_size_error_seq::type_id::create("s2_size_error");
        s3_backpressure = dma_s3_backpressure_seq::type_id::create("s3_backpressure");
        s4_slverr = dma_s4_slverr_seq::type_id::create("s4_slverr");
        s5_backpressure_slverr = dma_s5_backpressure_slverr_seq::type_id::create(
            "s5_backpressure_slverr"
        );
        s6_error_recovery = dma_s6_error_recovery_seq::type_id::create(
            "s6_error_recovery"
        );
        s7_random = dma_s7_random_seq::type_id::create("s7_random");

        // Configure the DMA Agent in active mode to generate stimulus
        uvm_config_db #(uvm_bitstream_t)::set(
            this, "e.a", "is_active", UVM_ACTIVE
        );

        // Pass the Test's total transaction count to the Scoreboard
        uvm_config_db #(int)::set(
            this, "e.scb", "expected_count", EXPECTED_TX_COUNT
        );

        e = dma_env::type_id::create("e", this);

        if (!uvm_config_db #(virtual axi4_if)::get(this, "", "aif", aif))
            `uvm_fatal("TEST", "Unable to access aif from uvm_config_db");
    endfunction

    // [end_of_elaboration_phase] : Set the log level for the complete UVM hierarchy
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.set_report_verbosity_level_hier(UVM_MEDIUM);
    endfunction

    // [run_phase] : Sequentially run the seven Step 4 verification scenarios after reset release
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        // Start scenarios after two stabilization clocks following reset release
        wait (aif.aresetn === 1'b1);
        repeat (2) @(posedge aif.aclk);

        s1_boundary.start(e.a.seqr);
        s2_size_error.start(e.a.seqr);
        s3_backpressure.start(e.a.seqr);
        s4_slverr.start(e.a.seqr);
        s5_backpressure_slverr.start(e.a.seqr);
        s6_error_recovery.start(e.a.seqr);
        s7_random.start(e.a.seqr);

        phase.drop_objection(this);
    endtask

    // [report_phase] : Report performance and functional coverage results
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        analyze_performance();
        generate_axi_checker_report();
        generate_coverage_report();
        generate_final_test_result();
    endfunction

    // [Final result] : Combine expected errors, transactions, checker, and coverage for PASS/FAIL
    function void generate_final_test_result();
        uvm_report_server report_server;
        int actual_error_count;
        int actual_warning_count;
        int actual_fatal_count;
        real transaction_coverage, fsm_coverage, axi_coverage;
        bit coverage_closed;

        report_server = uvm_report_server::get_server();
        actual_error_count = report_server.get_severity_count(UVM_ERROR);
        actual_warning_count = report_server.get_severity_count(UVM_WARNING);
        actual_fatal_count = report_server.get_severity_count(UVM_FATAL);

        transaction_coverage = transaction_cov.get_inst_coverage();
        fsm_coverage = fsm_cov.get_inst_coverage();
        axi_coverage = axi_cov.get_inst_coverage();
        coverage_closed =
            (transaction_coverage >= 99.99) &&
            (fsm_coverage >= 99.99) &&
            (axi_coverage >= 99.99);

        $display("\n============================================================");
        $display(" Final Test Result");
        $display("============================================================");
        $display(
            " Expected/Actual UVM errors: %0d / %0d",
            EXPECTED_UVM_ERROR_COUNT,
            actual_error_count
        );
        $display(" UVM warnings: %0d", actual_warning_count);
        $display(" UVM fatals: %0d", actual_fatal_count);
        $display(
            " Checked transactions: %0d / %0d",
            e.scb.checked_count,
            EXPECTED_TX_COUNT
        );
        $display(" AXI W violations: %0d", tb.axi_w_checker.vio_total);
        $display(" Functional coverage closed: %s", coverage_closed ? "YES" : "NO");

        if (
            (actual_error_count == EXPECTED_UVM_ERROR_COUNT) &&
            (actual_warning_count == 0) &&
            (actual_fatal_count == 0) &&
            (e.scb.checked_count == EXPECTED_TX_COUNT) &&
            (tb.axi_w_checker.vio_total == 0) &&
            coverage_closed
        )
            $display("\n FINAL TEST RESULT: PASSED");
        else
            $display("\n FINAL TEST RESULT: FAILED");
    endfunction

    // [AXI checker report] : Report per-assertion violation counts and final result
    function void generate_axi_checker_report();
        $display("\n--- AXI4 W Channel Checker Report ---");
        $display(
            " A-01 W payload stable on stall violations: %0d",
            tb.axi_w_checker.vio_w_payload_stable_on_stall
        );
        $display(
            " A-02 WVALID hold violations: %0d",
            tb.axi_w_checker.vio_wvalid_hold
        );
        $display(
            " A-03 WLAST timing violations: %0d",
            tb.axi_w_checker.vio_wlast_timing
        );
        $display(
            " Total AXI W violations: %0d",
            tb.axi_w_checker.vio_total
        );

        if (tb.axi_w_checker.vio_total == 0)
          $display("\n AXI4 W channel checker: PASSED");
        else
          $display("\n AXI4 W channel checker: FAILED");
    endfunction

    // [Performance analysis] : Compute the legacy estimate for the fixed 1,360-byte baseline workload
    function void analyze_performance();
        real total_time_ns, throughput_mbps;
        int total_cycles;

        $display("\n--- Performance Analysis ---");
        total_time_ns = real'($time);             // Elapsed time to this point (ns)
        total_cycles = int'(total_time_ns / 10.0); // 100 MHz → 10 ns/cycle
        throughput_mbps =
            (256.0 + 1024.0 + 16.0 + 64.0) * 8.0 / // Total bits
            total_time_ns * 1000.0;                 // Convert bits/ns to megabits per second

        $display(" Total execution time: %0.1f ns (%0d cycles)", total_time_ns, total_cycles);
        $display(" Estimated throughput: %0.2f Mbps", throughput_mbps);

        if (throughput_mbps > 100.0)
            $display(" Excellent performance");
        else if (throughput_mbps > 50.0)
            $display(" Good performance");
        else
            $display(" Performance improvement needed");
    endfunction

    // [Coverage-item report] : Print ID, name, and per-item coverage in a uniform format
    function void print_coverage_item(
        input string coverage_id,
        input string coverage_name,
        input real coverage_value
    );
        $display(
            " %-9s %-32s : %6.2f%%",
            coverage_id, coverage_name, coverage_value
        );
    endfunction

    // [Coverage report] : Print group summaries and every coverpoint/cross result
    function void generate_coverage_report();
        real total_coverage;
        real transaction_coverage, fsm_coverage, axi_coverage;

        $display("\n--- Coverage Analysis Report ---");
        transaction_coverage = transaction_cov.get_inst_coverage();
        fsm_coverage = fsm_cov.get_inst_coverage();
        axi_coverage = axi_cov.get_inst_coverage();
        total_coverage = (
            transaction_coverage + fsm_coverage + axi_coverage
        ) / 3.0;

        $display(" Overall Coverage: %6.2f%%", total_coverage);
        $display(" DMA Transaction Coverage: %6.2f%%", transaction_coverage);
        $display(" DMA FSM Coverage: %6.2f%%", fsm_coverage);
        $display(" AXI Event Coverage: %6.2f%%", axi_coverage);

        $display("\n [DMA Transaction Coverpoints]");
        print_coverage_item("C-TX-01", "cp_size_boundary",
            transaction_cov.cp_size_boundary.get_coverage());
        print_coverage_item("C-TX-02", "cp_size_range",
            transaction_cov.cp_size_range.get_coverage());
        print_coverage_item("C-TX-03", "cp_size_category",
            transaction_cov.cp_size_category.get_coverage());
        print_coverage_item("C-TX-04", "cp_src_region",
            transaction_cov.cp_src_region.get_coverage());
        print_coverage_item("C-TX-05", "cp_dst_region",
            transaction_cov.cp_dst_region.get_coverage());
        print_coverage_item("C-TX-06", "cp_backpressure_class",
            transaction_cov.cp_backpressure_class.get_coverage());
        print_coverage_item("C-TX-07", "cp_error_inject",
            transaction_cov.cp_error_inject.get_coverage());
        print_coverage_item("C-TX-08", "cp_error_code",
            transaction_cov.cp_error_code.get_coverage());

        $display("\n [DMA Transaction Crosses]");
        print_coverage_item("X-TX-01", "cx_size_result",
            transaction_cov.cx_size_result.get_coverage());
        print_coverage_item("X-TX-02", "cx_inject_result",
            transaction_cov.cx_inject_result.get_coverage());
        print_coverage_item("X-TX-03", "cx_inject_backpressure",
            transaction_cov.cx_inject_backpressure.get_coverage());

        $display("\n [DMA FSM Coverpoints]");
        print_coverage_item("C-FSM-01", "cp_state",
            fsm_cov.cp_state.get_coverage());
        print_coverage_item("C-FSM-02", "cp_state_transition",
            fsm_cov.cp_state_transition.get_coverage());
        print_coverage_item("C-FSM-03", "cp_setup_case",
            fsm_cov.cp_setup_case.get_coverage());
        print_coverage_item("C-FSM-04", "cp_tail_setup_case",
            fsm_cov.cp_tail_setup_case.get_coverage());

        $display("\n [AXI Event Coverpoints]");
        print_coverage_item("C-AXI-01", "cp_awlen",
            axi_cov.cp_awlen.get_coverage());
        print_coverage_item("C-AXI-02", "cp_backpressure_cfg_at_aw",
            axi_cov.cp_backpressure_cfg_at_aw.get_coverage());
        print_coverage_item("C-AXI-03", "cp_w_event",
            axi_cov.cp_w_event.get_coverage());
        print_coverage_item("C-AXI-04", "cp_stall_awlen",
            axi_cov.cp_stall_awlen.get_coverage());
        print_coverage_item("C-AXI-05", "cp_wlast_awlen",
            axi_cov.cp_wlast_awlen.get_coverage());
        print_coverage_item("C-AXI-06", "cp_bresp",
            axi_cov.cp_bresp.get_coverage());
        print_coverage_item("C-AXI-07", "cp_error_inject_at_b",
            axi_cov.cp_error_inject_at_b.get_coverage());

        $display("\n [AXI Event Crosses]");
        print_coverage_item("X-AXI-01", "cx_backpressure_awlen",
            axi_cov.cx_backpressure_awlen.get_coverage());
        print_coverage_item("X-AXI-02", "cx_bresp_error_inject",
            axi_cov.cx_bresp_error_inject.get_coverage());

        if (
            (transaction_coverage >= 99.99) &&
            (fsm_coverage >= 99.99) &&
            (axi_coverage >= 99.99)
        )
          $display("\n Coverage Closure Achieved");
        else
          $display("\n Coverage Closure Incomplete");
    endfunction
endclass
