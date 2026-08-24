// ============================================================================
// dma_test.sv - DMA UVM Test
//
// - Sequentially runs normal-transfer scenario sequences in the DMA UVM environment after reset deassertion.
// - Passes Agent mode and expected transaction count to the environment through config_db.
// - Sets verbosity for the complete UVM hierarchy in the end_of_elaboration phase.
// - Collects functional coverage and prints coverage and performance summaries in the report phase.
// ============================================================================

class dma_test extends uvm_test;
    `uvm_component_utils(dma_test)

    // Total transactions executed by this Test and expected to be checked by the Scoreboard
    localparam int EXPECTED_TX_COUNT = 4;

    dma_s1_seq s1;
    dma_s2_seq s2;
    dma_s3_1_seq s3_1;
    dma_s3_2_seq s3_2;

    dma_env e;
    virtual axi4_if aif;

    // [Coverage instance]: begins sampling on every clock immediately after creation
    cg_dma_coverage cov_inst = new();

    function new(input string name = "dma_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // [build_phase] : Create scenario Sequences and the UVM Environment
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        s1 = dma_s1_seq::type_id::create("s1");
        s2 = dma_s2_seq::type_id::create("s2");
        s3_1 = dma_s3_1_seq::type_id::create("s3_1");
        s3_2 = dma_s3_2_seq::type_id::create("s3_2");

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
        uvm_top.set_report_verbosity_level_hier(UVM_FULL);
    endfunction

    // [run_phase]: sequentially runs normal-transfer scenarios after reset deassertion
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        // Start scenarios after two stabilization clocks following reset release
        wait (aif.aresetn === 1'b1);
        repeat (2) @(posedge aif.aclk);

        s1.start(e.a.seqr);
        s2.start(e.a.seqr);
        s3_1.start(e.a.seqr);
        s3_2.start(e.a.seqr);

        phase.drop_objection(this);
    endtask

    // [report_phase] : Report performance and functional coverage results
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        analyze_performance();
        generate_coverage_report();
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

    // [Coverage report]: prints per-item and overall summaries
    function void generate_coverage_report();
        real total_coverage;
        real size_cov, state_cov, align_cov, cross_cov;

        $display("\n--- Coverage Analysis Report ---");
        total_coverage = cov_inst.get_coverage();         // Overall %
        size_cov = cov_inst.cp_size.get_coverage();       // Size-distribution %
        state_cov = cov_inst.cp_dma_state.get_coverage(); // State-distribution %
        align_cov = (
            cov_inst.cp_src_alignment.get_coverage() +
            cov_inst.cp_dst_alignment.get_coverage()
        ) / 2.0;                                          // Alignment average %
        cross_cov = cov_inst.cx_size_alignment.get_coverage(); // Cross %

        $display(" Overall Coverage: %6.2f%%", total_coverage);
        $display(" Transfer Size Pattern: %6.2f%%", size_cov);
        $display(" DMA State Transition: %6.2f%%", state_cov);
        $display(" Address Alignment: %6.2f%%", align_cov);
        $display(" Cross Scenario: %6.2f%%", cross_cov);

        if (total_coverage >= 90.0)
            $display(" Excellent Coverage - Very good test quality");
        else if (total_coverage >= 75.0)
            $display(" Good Coverage - Additional tests recommended");
        else
            $display(" Insufficient Coverage - More test scenarios needed");
    endfunction
endclass
