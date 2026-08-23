// ============================================================================
// testbench.sv - DMA-DDR Directed Testbench Top
//
// - Connects the DMA controller, DDR memory model, and AXI4/MMIO interfaces.
// - Uses the separated utility package and functional coverage model.
// - Preserves the baseline directed-test scenarios and verification procedure.
// - Reports transfer results, data integrity, performance, and functional coverage results.
// ============================================================================

`timescale 1ns/1ps

`include "mmio_if.sv"
`include "utility_pkg.sv"
`include "coverage.sv"

import utility_pkg::*;


module tb;

    logic clk, resetn;  // Testbench clock and active-low reset

    // [Clock generation] : 100 MHz (10 ns period) → toggle every #5
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // [Reset sequence] : Hold reset low for 20 ns, then deassert it
    initial begin
        resetn = 0;
        #20 resetn = 1;
    end

    // [Debug] : Internal observation (state/burst/buffer)
    logic [3:0] dbg_state;
    logic [7:0] dbg_burst_len;
    logic [4:0] dbg_buf_count;

    // [AXI connectivity] : Shared bus-interface instance (clock/reset connected)
    axi4_if memory_axi(.aclk(clk), .aresetn(resetn));

    // [MMIO connectivity]
    mmio_if mmio(.clk(clk));

    // [mif binding]: binds the MMIO interface instance to utility_pkg::mif
    initial begin
        utility_pkg::mif = mmio.tb_mp;
    end

    // [DDR memory model] : Operates as an AXI slave
    ddr_memory_model ddr_model (
        .axi(memory_axi.slave)
    );

    // [DMA controller] : Accesses memory as an AXI master
    dma_controller dma_ctrl (
        .clk (clk),
        .resetn (resetn),

        .reg_addr (mmio.dma_reg_addr),
        .reg_wdata (mmio.dma_reg_wdata),
        .reg_write (mmio.dma_reg_write),
        .reg_rdata (mmio.dma_reg_rdata),
        .reg_ack (mmio.dma_reg_ack),

        .m (memory_axi.master),

        .dma_done_int (mmio.dma_done_int),
        .dma_error_int (mmio.dma_error_int),

        .dbg_state (dbg_state),
        .dbg_burst_len (dbg_burst_len),
        .dbg_buf_count (dbg_buf_count)
    );

    // [Coverage instance]: begins sampling on every clock immediately after creation
    cg_dma_coverage cov_inst = new();

    // [Main sequence]: waveform dump -> stabilization -> three scenarios -> checks/report -> finish
    initial begin
        $dumpfile("dma_ddr_system.vcd"); // Waveform file name
        $dumpvars(0, tb);                 // Dump the complete tb hierarchy
        mmio.dma_reg_write <= 0;  // Initialize default value
        wait(resetn);              // Wait for reset deassertion
        repeat(5) @(posedge clk);  // Five clocks for stabilization

        $display("\n============================================================");
        $display(" DMA-DDR Memory System Comprehensive Test Started");
        $display("============================================================");
        $display("Start time: %0t ns", $time);

        // [Scenarios]: exercise a range of sizes, alignments, bursts, and transitions
        test_scenario_1_basic_copy();          // 256-byte basic copy (aligned/normal flow)
        test_scenario_2_large_transfer();      // 1,024-byte large transfer (multi-burst capable)
        test_scenario_3_burst_optimization();  // 16-byte/64-byte transfers (short-transfer behavior)

        // [Checks/report]: data integrity -> performance -> coverage
        verify_data_integrity();
        analyze_performance();
        generate_coverage_report();

        $display("\n============================================================");
        $display(" Test Completed Successfully");
        $display("============================================================");
        #100 $finish;  // Finish after allowing time for log completion
    end

    // -------------------------
    // Test scenarios: standard configure -> start -> completion-check pattern
    // -------------------------

    // [S1: 256-byte basic copy]: check aligned addresses, normal flow, and completion indication
    task test_scenario_1_basic_copy();
        logic [31:0] status;

        $display("\n--- Scenario 1: Basic Memory Copy (256 bytes) ---");
        write_dma_reg(8'h08, 32'h00000000); // SRC_ADDR=0x0000
        write_dma_reg(8'h0C, 32'h00000400); // DST_ADDR=0x0400 (1 KB offset)
        write_dma_reg(8'h10, 32'h00000100); // SIZE=0x100(256B)
        write_dma_reg(8'h00, 32'h00000007); // CTRL: enable/start/irq (assumed)
        wait_dma_completion(500);           // Detect interrupt, error, or timeout

        wait_done_via_status();           // Secondary check (STATUS polling)
        read_dma_reg(8'h04, status);      // Read STATUS
        if (status[1])
            $display("Basic copy test passed"); // Pass when done=1
        else
            $display("Basic copy test failed"); // Fail otherwise

        read_dma_reg(8'h14, status);             // BYTES_TRANSFERRED (assumed address: 0x14)
        $display(" Bytes transferred: %0d", status); // Log actual transferred amount
    endtask

    // [S2: 1,024-byte large transfer]: observe burst/multi-burst paths and response sequence
    task test_scenario_2_large_transfer();
        $display("\n--- Scenario 2: Large Transfer (1024 bytes) ---");
        write_dma_reg(8'h08, 32'h00000100); // SRC_ADDR=0x0100
        write_dma_reg(8'h0C, 32'h00000800); // DST_ADDR=0x0800
        write_dma_reg(8'h10, 32'h00000400); // SIZE=0x400(1024B)
        write_dma_reg(8'h00, 32'h00000007); // Start through CTRL
        wait_dma_completion(800);           // Extended timeout margin
        $display("Large transfer completed"); // Completion log
    endtask

    // [S3: 16-byte/64-byte transfers]: observe length/handshake behavior and overhead/optimization for small transfers
    task test_scenario_3_burst_optimization();
        $display("\n--- Scenario 3: Burst Optimization for Various Sizes---");
        $display(" 3-1. Small transfer (16 bytes)");
        write_dma_reg(8'h08, 32'h00000200); // SRC_ADDR=0x0200
        write_dma_reg(8'h0C, 32'h00000300); // DST_ADDR=0x0300
        write_dma_reg(8'h10, 32'h00000010); // SIZE=16B
        write_dma_reg(8'h00, 32'h00000007); // Start
        wait_dma_completion(200);

        $display(" 3-2. Medium transfer (64 bytes)");
        write_dma_reg(8'h08, 32'h00000210); // SRC_ADDR=0x0210
        write_dma_reg(8'h0C, 32'h00000310); // DST_ADDR=0x0310
        write_dma_reg(8'h10, 32'h00000040); // SIZE=64B
        write_dma_reg(8'h00, 32'h00000007); // Start
        wait_dma_completion(300);

        $display("Burst optimization tests completed");
    endtask

    // -------------------------
    // Data-integrity check: simple sample comparison (extendable)
    // -------------------------
    task automatic verify_data_integrity();
        automatic int error_count = 0;  // Accumulated error count
        logic [31:0] src_data, dst_data;

        $display("\n--- Data Integrity Verification ---");
        for (int i = 0; i < 8; i++) begin // Example: check only an eight-word sample
            src_data = ddr_model.mem[i];       // Source word i
            dst_data = ddr_model.mem[256 + i]; // Destination word (0x400=1,024 bytes -> word offset 256)

            if (src_data == dst_data)
                $display(" [%2d] Match: 0x%08X", i, src_data);
            else begin
                $display(" [%2d] Mismatch: src=0x%08X, dst=0x%08X", i, src_data, dst_data);
                error_count++;
            end
        end

        if (error_count == 0)
            $display("All data transferred correctly!");
        else
            $display("Found %0d data mismatches", error_count);
    endtask

    // -------------------------
    // Performance analysis: computes the legacy estimate for the fixed 1,360-byte baseline workload
    // -------------------------
    task analyze_performance();
        real total_time_ns, throughput_mbps;
        int total_cycles;

        $display("\n--- Performance Analysis ---");
        total_time_ns = real'($time);             // Elapsed time to this point (ns)
        total_cycles = int'(total_time_ns / 10.0); // 100 MHz → 10 ns/cycle
        throughput_mbps =
            (256.0 + 1024.0 + 16.0 + 64.0) * 8.0 / // Total bits
            total_time_ns * 1000.0;                // Convert bits/ns to megabits per second

        $display(" Total execution time: %0.1f ns (%0d cycles)", total_time_ns, total_cycles);
        $display(" Estimated throughput: %0.2f Mbps", throughput_mbps);

        if (throughput_mbps > 100.0)
            $display(" Excellent performance");
        else if (throughput_mbps > 50.0)
            $display(" Good performance");
        else
            $display(" Performance improvement needed");
    endtask

    // -------------------------
    // Coverage report: prints per-item and overall summaries
    // -------------------------
    task generate_coverage_report();
        real total_coverage;
        real size_cov, state_cov, align_cov, cross_cov;

        $display("\n--- Coverage Analysis Report ---");
        total_coverage = cov_inst.get_coverage();           // Overall %
        size_cov = cov_inst.cp_size.get_coverage();         // Size-distribution %
        state_cov = cov_inst.cp_dma_state.get_coverage();   // State-distribution %
        align_cov = (cov_inst.cp_src_alignment.get_coverage()
                   + cov_inst.cp_dst_alignment.get_coverage()) / 2.0; // Alignment average %
        cross_cov = cov_inst.cx_size_alignment.get_coverage();        // Cross %

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
    endtask

    // -------------------------
    // Real-time monitoring: state/register/AXI activity log
    // -------------------------
    logic [3:0] prev_state = 4'hF;  // Previous state (initially unknown)

    // [State change] : Log a readable string whenever dbg_state changes
    always @(posedge clk) begin
        if (dbg_state != prev_state && resetn) begin
            $display("[%6.1f ns] DMA State: %s",
                     real'($time) / 1000.0, get_dma_state_name(dbg_state));
            prev_state <= dbg_state;
        end
    end

    // [start_active change] : Monitor start-condition toggles for flow debugging
    logic prev_start_active = 1'b0;
    always @(posedge clk) begin
        if (dma_ctrl.start_active != prev_start_active && resetn) begin
            $display("[%6.1f ns] start_active changed: %0b -> %0b",
                     real'($time) / 1000.0, prev_start_active, dma_ctrl.start_active);
            prev_start_active <= dma_ctrl.start_active;
        end
    end

    // [Control-register change]: casts for bit-level comparison and logs only key fields
    logic [31:0] prev_ctrl = 32'h0;
    always @(posedge clk) begin
        if (logic'(dma_ctrl.ctrl) != prev_ctrl && resetn) begin
            $display("[%6.1f ns] Control register changed: enable=%0b, start=%0b",
                     real'($time) / 1000.0, dma_ctrl.ctrl.enable, dma_ctrl.ctrl.start);
            prev_ctrl <= logic'(dma_ctrl.ctrl);
        end
    end

    // [AXI address channels] : Record address and beat count on AW/AR handshakes
    always @(posedge clk) begin
        if (memory_axi.awvalid && memory_axi.awready) begin
            $display("[%6.1f ns] AXI Write: 0x%08X, %0d beats",
                     real'($time) / 1000.0, memory_axi.awaddr, memory_axi.awlen + 1);
        end

        if (memory_axi.arvalid && memory_axi.arready) begin
            $display("[%6.1f ns] AXI Read: 0x%08X, %0d beats",
                     real'($time) / 1000.0, memory_axi.araddr, memory_axi.arlen + 1);
        end
    end

    // [State code → name] : Mapping for readable logs
    function string get_dma_state_name(input [3:0] s);
        case (s)
            4'h0: return "IDLE";
            4'h1: return "SETUP";
            4'h2: return "READ_ADDR";
            4'h3: return "READ_DATA";
            4'h4: return "WRITE_ADDR";
            4'h5: return "WRITE_DATA";
            4'h6: return "WRITE_RESP";
            4'h7: return "NEXT_BURST";
            4'h8: return "COMPLETE";
            4'h9: return "ERROR";
            default: return "UNKNOWN";
        endcase
    endfunction
endmodule
