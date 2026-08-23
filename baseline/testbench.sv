/*******************************************************************************
 * File        : testbench.sv
 * Source      : Fast Campus course
 * Course      : SamCoach's Semiconductor Practice Roadmap: Design · Verification · Layout · AI Semiconductor
 * URL    : https://fastcampus.co.kr/data_online_samcoach2
 ******************************************************************************/



`timescale 1ns/1ps
/*======================================================================================================================
[Top-Level System Diagram]
	+-------------------------------- tb --------------------------------+
	| 1) Generate clock/reset
	| 2) Control DMA registers with MMIO tasks (write/read)
	| 3) Run three scenarios → check completion (interrupt/polling) 				  |
	| 4) Integrity check / performance / coverage report						    |
	| 5) Runtime monitoring (state/register/AXI) 								   	|
	|
    |
	| 		+----------------+ 		  AXI4		  +-----------------+
  	| 		| dma_controller | (master) <-------> | ddr_controller 	|
	| 		+----------------+ 					  +-----------------+
	| 				^ 	MMIO(reg_addr/wdata/write/rdata/ack)
	| 				|
	| 			 (tasks)
	+---------------------------------------------------------------------
	+
    
[Key Data/Control Flow Summary]
	tb →(MMIO)→ dma_controller (configure SRC/DST/SIZE/CTRL)
	dma_controller →(AXI read/write bursts)→ ddr_controller
	dma_controller →(interrupt)→ tb (or tb polls STATUS)
	tb →(integrity/performance/coverage/log output)
    
[MMIO Write/Read Timing (Conceptual)]
	Write: (posedge clk) addr,wdata,write=1 → (next posedge) write=0 → wait for ack=1 → complete
	Read : (posedge clk) addr,write=0 → (two additional stabilization clocks) → sample rdata
    
[AXI Address-Channel Handshake (Conceptual)]
	Write: latch address/len at awvalid & awready → transfer beats through wvalid/wready → bvalid/bready response
	Read : latch address/len at arvalid & arready → receive data through rvalid/rready
    
[Intended State Transitions]
	IDLE(0)→SETUP(1)→READ_ADDR(2)→READ_DATA(3)→WRITE_ADDR(4)→WRITE_DATA(5)→WRITE_RESP(6)→
    (repeat NEXT_BURST(7)→SETUP(1) for multi-burst)→COMPLETE(8) or ERROR(9)
    
[Coverage Design Intent]
	- Transfer size (cp_size): exercise tiny/small/medium/large ranges
	- Alignment (cp_src/dst_alignment): classify 4B-aligned/unaligned from the low two bits
	- Burst length (cp_burst_len): observe single through medium lengths
	- States/transitions (cp_dma_state, cp_state_transitions): check normal flow and multi-burst loop
	- Cross (cx_size_alignment): prevent "large & unaligned" as an illegal design-constraint violation
    
[Scenario Execution Order (Timeline)]
	t=0ns : start clk toggling, resetn=0
	t=20ns : resetn=1 → five stabilization clocks
	S1(256B) → S2(1024B) → S3(16B,64B) → integrity → performance → coverage → finish
    
[Learning Observation Points]
	□ Provide both interrupt and polling paths (recover through the other if one fails)
	□ Visually verify state/register changes and AXI burst information through runtime logs
	□ Identify test gaps (unhit areas) from coverage metrics and establish evidence for new scenarios
======================================================================================================================*/

// ============================================================
// Coverage Model: sample on each rising clock edge to capture distributions/transitions/crosses
// ============================================================
covergroup cg_dma_coverage @(posedge tb.clk); 	// Sampling point: rising edge of tb.clk
	option.per_instance = 1; 					// Accumulate independently per instance
	option.name = "DMA_System_Coverage"; 		// Name used to identify the report
  
	// [Transfer-size distribution] : Divide into meaningful ranges including corners
	cp_size: coverpoint tb.dma_ctrl.size_reg iff (tb.resetn && tb.dma_ctrl.size_reg != 0) { // Valid sample only after reset release and when SIZE≠0
    	bins sz_tiny = {[1:16]}; 		// Very small transfer (boundary check)
    	bins sz_small = {[17:256]}; 	// Small
    	bins sz_medium = {[257:4096]}; 	// Medium
    	bins sz_large = {[4097:65536]}; // Large (strong multi-burst/alignment impact)
	}
  
	// [State distribution] : Cast design dbg_state to an integer and group into ranges
	cp_dma_state: coverpoint int'(tb.dma_ctrl.dbg_state) {
		bins idle = {0};
		bins setup = {1};
      	bins read_phases = {[2:3]}; // READ_ADDR/READ_DATA phase
      	bins write_phases= {[4:6]}; // WRITE_ADDR/WRITE_DATA/WRITE_RESP phase
		bins next_burst = {7};
		bins complete = {8};
		bins error = {9};
	}
  
	// [Alignment] : Determine 4B alignment from the low two address bits
  	cp_src_alignment: coverpoint tb.dma_ctrl.src_reg[1:0] iff(tb.resetn) {
      	bins aligned = {2'b00}; 		  // 4B aligned
        bins unaligned = {[2'b01:2'b11]}; // Unaligned (check aligner/mask logic)
	}
  	cp_dst_alignment: coverpoint tb.dma_ctrl.dst_reg[1:0] iff(tb.resetn) {
		bins aligned = {2'b00};
		bins unaligned = {[2'b01:2'b11]};
	}

  	// [Burst-length distribution] : Use observation signal dbg_burst_len(AXI len=0 → 1 beat)
	cp_burst_len: coverpoint tb.dma_ctrl.dbg_burst_len iff(tb.resetn) {
      	bins single = {0}; 	  // 1 beat
      	bins short = {[1:3]}; // 2~4 beats
        bins med = {[4:15]};  // Encoded lengths 4–15 represent bursts of 5–16 beats
	}
  
	// [State-transition sequences] : Normal flow and multi-burst re-entry loop
  	cp_state_transitions: coverpoint int'(tb.dma_ctrl.dbg_state) iff(tb.resetn) {
      	bins normal_flow = (0 => 1 => 2 => 3 => 4 => 5 => 6 => 8); // IDLE→...→COMPLETE
      	bins multi_burst = (6 => 7 => 1); 						   // RESP→NEXT_BURST→SETUP
	}

  	// [Cross] : Mark large & unaligned as illegal (design-constraint violation/test prohibited)
	cx_size_alignment: cross cp_size, cp_src_alignment {
		illegal_bins large_unaligned = binsof(cp_size.sz_large) && binsof(cp_src_alignment.unaligned);
	}
endgroup

// ============================================================
// Testbench Top Module: environment construction, scenario driving, reporting/monitoring
// ============================================================
module tb;
  
	logic clk, resetn; // Testbench clock and active-low reset

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

  	// [MMIO signals] : The tb accesses DMA registers like software
	logic [7:0] dma_reg_addr; 	// Target register address
	logic [31:0] dma_reg_wdata; // Write data
	logic [31:0] dma_reg_rdata; // Read data (provided by the design)
	logic dma_reg_write; 		// Write when 1, read when 0
	logic dma_reg_ack; 			// Access-completion response (similar to ready)

  	// [Interrupts] : Completion/error notification
	logic dma_done_int;
	logic dma_error_int;

  	// [Debug] : Internal observation (state/burst/buffer)
	logic [3:0] dbg_state;
	logic [7:0] dbg_burst_len;
	logic [4:0] dbg_buf_count;

  	// [AXI connectivity] : Shared bus-interface instance (clock/reset connected)
	axi4_if memory_axi(.aclk(clk), .aresetn(resetn));

  	// [DDR controller] : Operates as an AXI slave (memory-model replacement)
	ddr_controller ddr_ctrl (
		.axi(memory_axi.slave)
	);

  	// [DMA controller] : Accesses memory as an AXI master
	dma_controller dma_ctrl (
		.clk (clk),
		.resetn (resetn),
      
		.reg_addr (dma_reg_addr),
		.reg_wdata (dma_reg_wdata),
		.reg_write (dma_reg_write),
		.reg_rdata (dma_reg_rdata),
		.reg_ack (dma_reg_ack),
      
		.m (memory_axi.master),
      
		.dma_done_int (dma_done_int),
		.dma_error_int (dma_error_int),
      
		.dbg_state (dbg_state),
		.dbg_burst_len (dbg_burst_len),
		.dbg_buf_count (dbg_buf_count)
	);
  
	// [Coverage instance] : Start sampling each clock immediately after creation
	cg_dma_coverage cov_inst = new();
  
	// [Main sequence] : Waveform dump → stabilization → three scenarios → verification/report → finish
	initial begin
      	$dumpfile("dma_ddr_system.vcd"); // Waveform file name
      	$dumpvars(0, tb); 				 // Dump the complete tb hierarchy
		dma_reg_write <= 0;				 // Initialize default
      	wait(resetn);					 // Wait for reset release
		repeat(5) @(posedge clk);		 // Five clocks for stabilization
      
		$display("\n============================================================");
		$display(" DMA-DDR Memory System Comprehensive Test Started");
		$display("============================================================");
		$display("Start time: %0t ns", $time);
      
		// [Scenario] : Exercise diverse size/alignment/burst/transition conditions
      	test_scenario_1_basic_copy();		  // 256B basic copy (aligned/normal flow)
      	test_scenario_2_large_transfer();	  // 1024B large transfer (multi-burst possible)
		test_scenario_3_burst_optimization(); // 16B/64B (short-transfer behavior)

		// [Verification/report] : Data integrity → performance → coverage
		verify_data_integrity();
		analyze_performance();
		generate_coverage_report();
      
		$display("\n============================================================");
		$display(" Test Completed Successfully");
		$display("============================================================");
		#100 $finish; // Finish after allowing log completion
	end
  
	// -------------------------
	// Utility tasks : Reusable MMIO/wait/polling helpers
	// -------------------------
	// [MMIO write] : Align to posedge → hold one clock → wait for ack → log
	task write_dma_reg(input [7:0] addr, input [31:0] data);
		@(posedge clk);
		dma_reg_addr <= addr;  // Present address
      	dma_reg_wdata <= data; // Present data
      
      	dma_reg_write <= 1;    // Enable write
      	@(posedge clk); 	   // Hold for one clock (slave-latching margin)
      	dma_reg_write <= 0;	   // Disable write
      	wait(dma_reg_ack);	   // Wait for completion response from the design
        $display("[%6.1f ns] REG[0x%02X] <- 0x%08X", real'($time)/1000.0, addr, data); // Trace log
	endtask

	// [MMIO read] : Present address → stabilize for two clocks → sample rdata → log
	task read_dma_reg(input [7:0] addr, output [31:0] data);
		@(posedge clk);
		dma_reg_addr <= addr; // Present address
      	dma_reg_write <= 0;	  // Read mode
      	@(posedge clk);		  // One-clock margin (pipeline/combinational path)
        @(posedge clk);      // Wait one additional MMIO clock before sampling read data
		data = dma_reg_rdata; // Capture read data
      	$display("[%6.1f ns] REG[0x%02X] -> 0x%08X", real'($time)/1000.0, addr, data); // Trace log
	endtask
  
	// [DMA termination wait] : Capture the first completion/error/timeout event by edge
	task wait_dma_completion(input int timeout_cycles = 1000);
      	$display("[%6.1f ns] Waiting for DMA completion...", real'($time)/1000.0);
		fork
			begin
				@(posedge dma_done_int); // Completion-interrupt rising edge
          		$display("[%6.1f ns] DMA completion interrupt received!", real'($time)/1000.0);
			end
			begin
				@(posedge dma_error_int); // Error-interrupt rising edge
          		$display("[%6.1f ns] DMA error interrupt occurred!", real'($time)/1000.0);
			end
			begin
          		repeat(timeout_cycles) @(posedge clk); // Timeout counter
          		$display("[%6.1f ns] DMA timeout after %0d cycles", real'($time)/1000.0, timeout_cycles);
			end
		join_any 	  // Join after the first completion

		disable fork; // Terminate remaining threads to prevent resource leakage
	endtask
          
	// [STATUS polling] : Auxiliary completion check when an interrupt is absent or missed
	task wait_done_via_status(input int max_tries = 20);
		int i;
		logic [31:0] s;
		for (i = 0; i < max_tries; i++) begin
          	read_dma_reg(8'h04, s); // STATUS(assumed address 0x04)
          	if (s[1]) return;	    // Return immediately when done=1
          	@(posedge clk);		    // Wait one clock before the next poll
		end
		$display("STATUS polling timeout (done=0)"); // Polling-timeout notification
	endtask
          
	// -------------------------
	// Test scenarios: standard configure → start → completion-check pattern
	// -------------------------
          
	// [S1: 256B basic copy] : Check aligned addresses, normal flow, and completion signal
	task test_scenario_1_basic_copy();
		logic [31:0] status;
		$display("\n--- Scenario 1: Basic Memory Copy (256 bytes) ---");
      	write_dma_reg(8'h08, 32'h00000000); // SRC_ADDR=0x0000
		write_dma_reg(8'h0C, 32'h00000400); // DST_ADDR=0x0400(1 KB offset)
      	write_dma_reg(8'h10, 32'h00000100); // SIZE=0x100(256B)
      	write_dma_reg(8'h00, 32'h00000007); // CTRL: enable/start/irq(assumed)
      	wait_dma_completion(500);		    // Capture interrupt/error/timeout
      
      	wait_done_via_status();							   // Auxiliary check (STATUS polling)
      	read_dma_reg(8'h04, status); 					   // Read STATUS
      	if (status[1]) $display("Basic copy test passed"); // Pass when done=1
      	else $display("Basic copy test failed");		   // Fail otherwise

      	read_dma_reg(8'h14, status); 				 // BYTES_TRANSFERRED(assumed: 0x14)
		$display(" Bytes transferred: %0d", status); // Log actual transferred amount
	endtask
          
	// [S2: 1024B large transfer] : Observe burst/multi-burst path and response sequence
	task test_scenario_2_large_transfer();
		$display("\n--- Scenario 2: Large Transfer (1024 bytes) ---");
      	write_dma_reg(8'h08, 32'h00000100);   // SRC_ADDR=0x0100
      	write_dma_reg(8'h0C, 32'h00000800);   // DST_ADDR=0x0800
      	write_dma_reg(8'h10, 32'h00000400);   // SIZE=0x400(1024B)
      	write_dma_reg(8'h00, 32'h00000007);   // Start CTRL
      	wait_dma_completion(800);		      // Timeout margin
		$display("Large transfer completed"); // Completion log
	endtask
          
	// [S3: 16B/64B] : Observe len/handshake and overhead/optimization on small transfers
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
	// Data-integrity verification : Simple sample comparison (extensible)
	// -------------------------
	task automatic verify_data_integrity();
		automatic int error_count = 0; // Accumulated errors
      	logic [31:0] src_data, dst_data;
      
		$display("\n--- Data Integrity Verification ---");
		for (int i = 0; i < 8; i++) begin 		// For example: verify only eight sampled words
          	src_data = ddr_ctrl.mem[i]; 		// Source word i
          	dst_data = ddr_ctrl.mem[256 + i]; 	// Destination word (0x400=1024B → word offset 256)
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
	// Performance analysis : Compute the legacy estimate for the fixed 1,360-byte baseline workload
	// -------------------------
	task analyze_performance();
		real total_time_ns, throughput_mbps;
		int total_cycles;

		$display("\n--- Performance Analysis ---");
      	total_time_ns = real'($time); 						// Elapsed time to this point (ns)
      	total_cycles = int'(total_time_ns / 10.0); 			// 100 MHz → 10 ns/cycle
		throughput_mbps =
      		(256.0 + 1024.0 + 16.0 + 64.0) * 8.0 / 			// Total bits
            total_time_ns * 1000.0; // Convert bits/ns to megabits per second

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
	// Coverage report : Print per-item/overall summary
	// -------------------------
	task generate_coverage_report();
		real total_coverage;
		real size_cov, state_cov, align_cov, cross_cov;
      
		$display("\n--- Coverage Analysis Report ---");
      	total_coverage = cov_inst.get_coverage(); 				// Overall %
      	size_cov = cov_inst.cp_size.get_coverage(); 			// Size-distribution %
      	state_cov = cov_inst.cp_dma_state.get_coverage(); 		// State distribution %
      	align_cov = (cov_inst.cp_src_alignment.get_coverage() + cov_inst.cp_dst_alignment.get_coverage()) / 2.0; // Average-alignment %
      	cross_cov = cov_inst.cx_size_alignment.get_coverage(); 	// Cross %

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
	// Runtime monitoring : State/register/AXI activity logs
	// -------------------------
	logic [3:0] prev_state = 4'hF; // Previous state (initially unknown)
          
	// [State change] : Log a readable string whenever dbg_state changes
	always @(posedge clk) begin
		if (dbg_state != prev_state && resetn) begin
          	$display("[%6.1f ns] DMA State: %s", real'($time)/1000.0, get_dma_state_name(dbg_state));
			prev_state <= dbg_state;
		end
	end
          
	// [start_active change] : Monitor start-condition toggles for flow debugging
	logic prev_start_active = 1'b0;
	always @(posedge clk) begin
		if (dma_ctrl.start_active != prev_start_active && resetn) begin
          	$display("[%6.1f ns] start_active changed: %0b -> %0b", real'($time)/1000.0, prev_start_active, dma_ctrl.start_active);
			prev_start_active <= dma_ctrl.start_active;
		end
	end

	// [Control-register change] : Cast for bitwise comparison and summarize key fields
	logic [31:0] prev_ctrl = 32'h0;
	always @(posedge clk) begin
		if (logic'(dma_ctrl.ctrl) != prev_ctrl && resetn) begin
          	$display("[%6.1f ns] Control register changed: enable=%0b, start=%0b", real'($time)/1000.0, dma_ctrl.ctrl.enable, dma_ctrl.ctrl.start);
			prev_ctrl <= logic'(dma_ctrl.ctrl);
		end
	end
          
	// [AXI address channels] : Record address/beat count on AW/AR handshakes
	always @(posedge clk) begin
		if (memory_axi.awvalid && memory_axi.awready) begin
          	$display("[%6.1f ns] AXI Write: 0x%08X, %0d beats", real'($time)/1000.0, memory_axi.awaddr, memory_axi.awlen + 1);
		end
		if (memory_axi.arvalid && memory_axi.arready) begin
          	$display("[%6.1f ns] AXI Read: 0x%08X, %0d beats", real'($time)/1000.0, memory_axi.araddr, memory_axi.arlen + 1);
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
