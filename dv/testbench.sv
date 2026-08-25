// ============================================================================
// testbench.sv - DMA-DDR UVM Testbench Top
//
// - Connects the DMA controller, DDR memory model, and AXI4/MMIO/DDR-model interfaces.
// - Passes virtual interfaces to the UVM environment and runs dma_test.
// - Runs baseline-transfer, W-channel backpressure, and BRESP error-injection scenarios.
// - Verifies complete transfer-region data integrity with a transaction-based Scoreboard.
// - Reports functional coverage and performance results in the UVM report phase.
// - Provides verbosity-controlled UVM logs for DMA states and AXI activity.
// ============================================================================

`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "mmio_if.sv"
`include "utility_pkg.sv"
import utility_pkg::*;

`include "coverage.sv"

`include "dma_tx.sv"
`include "dma_base_seq.sv"
`include "dma_s1_seq.sv"
`include "dma_s2_seq.sv"
`include "dma_s3_seq.sv"
`include "dma_driver.sv"
`include "dma_monitor.sv"
`include "dma_scoreboard.sv"
`include "dma_agent.sv"
`include "dma_env.sv"
`include "dma_test.sv"

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

    // [DDR memory-model control] : Pass backpressure and BRESP-error settings from the UVM environment
    ddr_model_if ddr_model_ctrl(.aclk(clk), .aresetn(resetn));

    // [DDR memory model] : Operates as an AXI slave
    ddr_memory_model ddr_model (
        .axi     (memory_axi.slave),
        .ddr_cfg (ddr_model_ctrl)
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

    // [UVM start]: passes the physical interfaces as virtual interfaces, then runs the test
    initial begin
        uvm_config_db #(virtual mmio_if.tb_mp)::set(
            null, "*", "mif", mmio.tb_mp
        );
        uvm_config_db #(virtual axi4_if)::set(
            null, "*", "aif", memory_axi
        );
        uvm_config_db #(virtual ddr_model_if)::set(
            null, "*", "dif", ddr_model_ctrl
        );

        run_test("dma_test");
    end

    // [Simulation observation] : Dump waveforms and print startup information
    initial begin
        $dumpfile("dma_ddr_system.vcd"); // Waveform file name
        $dumpvars(0, tb);                 // Dump the complete tb hierarchy
        wait(resetn);                     // Wait for reset release
        repeat(5) @(posedge clk);         // Five clocks for stabilization

        `uvm_info(
            "TB",
            "\n============================================================\n DMA-DDR UVM Verification Started\n============================================================",
            UVM_LOW
        )
    end

    // [Runtime monitoring] : State/register/AXI activity logs
    logic [3:0] prev_state = 4'hF;  // Previous state (initially unknown)

    // [State change] : Log a readable string whenever dbg_state changes
    always @(posedge clk) begin
        if (dbg_state != prev_state && resetn) begin
            `uvm_info(
                "TB",
                $sformatf("DMA State: %s", get_dma_state_name(dbg_state)),
                UVM_HIGH
            )
            prev_state <= dbg_state;
        end
    end

    // [start_active change] : Monitor start-condition toggles for flow debugging
    logic prev_start_active = 1'b0;
    always @(posedge clk) begin
        if (dma_ctrl.start_active != prev_start_active && resetn) begin
            `uvm_info(
                "TB",
                $sformatf(
                    "start_active changed: %0b -> %0b",
                    prev_start_active, dma_ctrl.start_active
                ),
                UVM_HIGH
            )
            prev_start_active <= dma_ctrl.start_active;
        end
    end

    // [Control-register change] : Compare by bit and summarize key fields
    logic [31:0] prev_ctrl = 32'h0;
    always @(posedge clk) begin
        if (logic'(dma_ctrl.ctrl) != prev_ctrl && resetn) begin
            `uvm_info(
                "TB",
                $sformatf(
                    "Control register changed: enable=%0b, start=%0b",
                    dma_ctrl.ctrl.enable, dma_ctrl.ctrl.start
                ),
                UVM_HIGH
            )
            prev_ctrl <= logic'(dma_ctrl.ctrl);
        end
    end

    // [AXI address channels] : Record address and beat count on AW/AR handshakes
    always @(posedge clk) begin
        if (memory_axi.awvalid && memory_axi.awready) begin
            `uvm_info(
                "TB",
                $sformatf(
                    "AXI Write: 0x%08X, %0d beats",
                    memory_axi.awaddr, memory_axi.awlen + 1
                ),
                UVM_HIGH
            )
        end

        if (memory_axi.arvalid && memory_axi.arready) begin
            `uvm_info(
                "TB",
                $sformatf(
                    "AXI Read: 0x%08X, %0d beats",
                    memory_axi.araddr, memory_axi.arlen + 1
                ),
                UVM_HIGH
            )
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
