/*******************************************************************************
 * File        : design.sv
 * Source      : Fast Campus course
 * Course      : SamCoach's Semiconductor Practice Roadmap: Design · Verification · Layout · AI Semiconductor
 * URL    : https://fastcampus.co.kr/data_online_samcoach2
 ******************************************************************************/



// ===============================================================
// design.sv — AMBA AXI4-based DMA controller + DDR memory model + AXI4 interface
//================================================================
//
// ==============================
// [Overview: blocks and data flow]
// ==============================
//
// CPU/Host (register writes)
// 		| reg_write/reg_addr/reg_wdata
// 		v
// +-------------------+      AXI4 Master 	   +---------------------+
// | DMA Controller    | ====================> | DDR Controller      |
// | (this module)     | <==================== | (AXI4 Slave + mem)  |
// +-------------------+                       +---------------------+
//          | 											  |
// 			| 				Internal simple 4 KB memory 	   |
// 			| 				mem[0:1023] 				  |
// 			| 											  |
// 			+--[FIFO 16x32]--(Temporary read-data storage)--> Write output
//
// - DMA: Repeats “read burst → enqueue into FIFO → write burst” to copy SIZE bytes.
// - DDR: Simple AXI slave; responds through R/W-channel handshakes and mem[] accesses.
//
// =====================================
// [Per-burst sequence: procedural summary]
// =====================================
// 1) SETUP: Select a burst of 1, 4, or 16 beats from bytes_left and store 0, 3, or 15 in burst_len_m1.
// 2) RD_ADDR: Issue the read burst at cur_src on AR.
// 3) RD_DATA: On r_fire for each beat, enqueue into FIFO and update cur_src+=4 and bytes_left/bytes_done.
// 4) WR_ADDR: Issue the write burst at cur_dst on AW.
// 5) WR_DATA: Dequeue and transmit FIFO data, update cur_dst+=4, then enter RESP after the final beat.
// 6) WR_RESP: Check BRESP. Remaining data → NEXT→SETUP, No remaining data → DONE.
//
// =====================================
// [FSM overview (states/transitions)]
// =====================================
// IDLE→SETUP→RD_ADDR→RD_DATA→WR_ADDR→WR_DATA→WR_RESP→(NEXT|DONE)
// Repeat NEXT→SETUP; enter ERROR on an error and IDLE after DONE.
//
// =====================================
// [Register summary and usage]
// =====================================
// 0x00 CTRL: [2]=irq_en, [1]=start (pulse), [0]=enable, [15:8]=channel_id
// 0x04 STAT: [0]=busy, [1]=done(sticky), [2]=error, [11:8]=error_code
// 0x08 SRC : Source start address
// 0x0C DST : Destination start address
// 0x10 SIZE: Total transfer bytes (assumed divisible by 4)
// 0x14 BYTES: Cumulative transferred bytes (bytes_done)
//
// Procedure: Configure SRC/DST/SIZE → set CTRL.enable=1 and CTRL.start=1 → check STAT.done/error.
//
// ---------------------------------------------------------------
`timescale 1ns/1ps // Simulation time unit/precision
// ---------------------------------------------------------------
// AXI4 interface (required signals only)
// ---------------------------------------------------------------
interface axi4_if #(
	parameter ADDR_WIDTH = 32, 	// Address width
	parameter DATA_WIDTH = 32, 	// Data width
	parameter ID_WIDTH = 4 		// ID width
)(input logic aclk, aresetn); 	// Common clock/reset
  
	// Write Address
	logic [ID_WIDTH-1:0] 	awid; 		// Write transaction ID
	logic [ADDR_WIDTH-1:0] 	awaddr; 	// Write start address
	logic [7:0] 			awlen; 		// Burst length minus 1
	logic [2:0] 			awsize;		// log2(bytes per beat)
	logic [1:0] 			awburst; 	// Burst type (INCR/...)
	logic 					awvalid; 	// Address valid
	logic 					awready; 	// Ready to accept the address
  
	// Write Data
  	logic [DATA_WIDTH-1:0] 	 wdata; 	// Write data
	logic [DATA_WIDTH/8-1:0] wstrb; 	// Byte-valid mask
	logic 					 wlast; 	// Final-beat indicator
	logic 					 wvalid; 	// Data valid
	logic 					 wready; 	// Ready to accept data
  
  	// Write Resp
  	logic [ID_WIDTH-1:0] bid; 	 // Response ID
 	logic [1:0] 		 bresp;  // Response code
  	logic 				 bvalid; // Response valid
	logic 				 bready; // Ready to accept the write response
  
	// Read Address
  	logic [ID_WIDTH-1:0] 	arid; 	 // Read transaction ID
  	logic [ADDR_WIDTH-1:0] 	araddr;  // Read start address
  	logic [7:0] 			arlen; 	 // Burst length minus 1
  	logic [2:0] 			arsize;  // log2(bytes per beat)
	logic [1:0] 			arburst; // Burst type
	logic 					arvalid; // Address valid
	logic 					arready; // Ready to accept the address

  	// Read Data
	logic [ID_WIDTH-1:0] 	rid; 	// Data ID
	logic [DATA_WIDTH-1:0] 	rdata; 	// Read data
	logic [1:0] 			rresp; 	// Read response
	logic 					rlast; 	// Final-beat indicator
	logic 					rvalid; // Data valid
	logic 					rready; // Ready to accept data
  
	// Master
	modport master (
		// write address
		output awid, awaddr, awlen, awsize, awburst, awvalid, // Driven by the master
		input awready, 										  // Slave ready to accept the address
		// write data
		output wdata, wstrb, wlast, wvalid, 				  // Master drives data
		input wready, 										  // Slave ready to accept data
		// write resp
		input bid, bresp, bvalid, 							  // Receive the slave response
		output bready, 										  // Ready to accept the response
		// read address
		output arid, araddr, arlen, arsize, arburst, arvalid, // Master drives the address
		input arready, 										  // Slave ready to accept the address
		// read data
		input rid, rdata, rresp, rlast, rvalid, 			  // Receive data
		output rready, 										  // Ready to accept data
		// common
		input aclk, aresetn 								  // Common clock/reset
	);
  
	// Slave
	modport slave (
	// write address
	input awid, awaddr, awlen, awsize, awburst, awvalid, // Receive address/attributes
	output awready, 									 // Ready to accept the address
	// write data
	input wdata, wstrb, wlast, wvalid, 					 // Receive data
	output wready, 										 // Ready to accept data
	// write resp
	output bid, bresp, bvalid,							 // Provide response
	input bready, 										 // Master ready to accept the response
	// read address
	input arid, araddr, arlen, arsize, arburst, arvalid, // Receive address/attributes
	output arready, 									 // Ready to accept the address
	// read data
	output rid, rdata, rresp, rlast, rvalid,			 // Provide data/response
	input rready,										 // Master ready to accept data
	// common
	input aclk, aresetn 								 // Common clock/reset
	);
endinterface

// ---------------------------------------------------------------
// DMA controller (AXI4 master)
// ---------------------------------------------------------------
module dma_controller (
  	input logic clk,	// Internal clock
  	input logic resetn, // Internal reset (active-low)
  
	// Register interface
	input logic [7:0] 	reg_addr, 		// Register address
	input logic [31:0] 	reg_wdata, 		// Write data
	input logic 		reg_write, 		// Write trigger
	output logic [31:0] reg_rdata, 		// Read data
	output logic 		reg_ack, 		// Access ACK
  
	// AXI4 Master
	axi4_if.master m, 					// AXI master port
  
	// Interrupts
	output logic dma_done_int, 			// Completion pulse (when irq_en)
    output logic dma_error_int,         // Asserted while servicing S_ERROR when irq_en
  
	// Debug
	output logic [3:0] dbg_state, 		// FSM-state observation
	output logic [7:0] dbg_burst_len,	// Configured burst length minus 1
	output logic [4:0] dbg_buf_count 	// Internal FIFO count
);
  
	typedef struct packed {		 // Control-register bit fields
		logic [15:0] rsvd1;		 // Reserved
      	logic [7:0]  channel_id; // Used as AXI ID
      	logic [4:0]  rsvd0; 	 // Reserved
		logic 		 irq_en;	 // Interrupt enable
		logic 		 start;		 // Start (pulse expected)
		logic 		 enable;	 // DMA enable
	} dma_ctrl_t;
  
	typedef struct packed {		 // Status-register bit fields
		logic [19:0] rsvd3;		 // Reserved
		logic [3:0]	 error_code; // Error code
		logic [4:0]	 rsvd2;		 // Reserved
		logic		 error;		 // Error flag
		logic		 done;		 // Completion (sticky)
		logic		 busy;		 // Busy
	} dma_status_t;
  
	dma_ctrl_t	 ctrl;			 // Latched CTRL
	dma_status_t stat;			 // Latched STAT
  
	logic [31:0] src_reg, dst_reg, size_reg, bytes_done; // Configuration/progress values
  
  	typedef enum logic [3:0] {	 // FSM-state encoding
      	S_IDLE = 4'h0,			 // Idle
      	S_SETUP = 4'h1,			 // Determine burst length
      	S_RD_ADDR = 4'h2,		 // Issue read address
      	S_RD_DATA = 4'h3,		 // Receive read data
      	S_WR_ADDR = 4'h4,		 // Issue write address
      	S_WR_DATA = 4'h5,		 // Transmit write data
      	S_WR_RESP = 4'h6,		 // Check BRESP
      	S_NEXT = 4'h7,			 // Prepare next burst
      	S_DONE = 4'h8,			 // Complete transfer
      	S_ERROR = 4'h9			 // Error handling
    } state_t;
  
	state_t cur, nxt;			 // Current/next state
  
	logic start_active;			 // Start-pulse latch
  	logic setup_complete;		 // One-shot SETUP flag
  
  	logic [31:0] cur_src, cur_dst; 	 // Source/destination of current burst
  	logic [31:0] bytes_left;		 // Remaining bytes
  	logic [7:0]  burst_len_m1;		 // Burst length minus 1
  	logic [7:0]  r_beats_rcvd;		 // Number of R beats received
  	logic [7:0]  w_beats_sent;		 // Number of W beats sent

	// Internal FIFO (depth 16)
	logic [31:0] fifo[0:15];			 // Data buffer
  	logic [3:0]  wr_ptr, rd_ptr;		 // FIFO pointers
  	logic [4:0]  count; 				 // Stored count (0–16)
	wire 		 buf_empty = (count==0); // Whether empty
	wire 		 buf_full = (count==16); // Whether full
  
	assign dbg_burst_len = burst_len_m1; // Debug output
  	assign dbg_buf_count = count;		 // Debug output

	wire r_fire = m.rvalid && m.rready;  // Read handshake
  	wire w_fire = m.wvalid && m.wready;  // Write handshake
  
	// Register write: simple MMIO protocol
	always_ff @(posedge clk or negedge resetn) begin
		if(!resetn) begin
			ctrl	 <= '0;				   // Initialize CTRL
			src_reg	 <= '0; dst_reg <= '0; // Initialize SRC/DST
			size_reg <= '0; 			   // Initialize SIZE
			reg_ack	 <= 1'b0;			   // ACK Low
		end else begin
			reg_ack <= 1'b0;			   // Default ACK low
          	if (reg_write) begin		   // On write access
              	reg_ack <= 1'b1;		   // Immediate ACK
              	unique case (reg_addr)	   // Decode address
					8'h00: begin
						ctrl <= dma_ctrl_t'(reg_wdata); // Update CTRL
                      	$display("[%0t] DMA: Control register set - enable=%0b, start=%0b", $time, reg_wdata[0], reg_wdata[1]); // Debug log
					end
					8'h08: begin
                      	src_reg <= reg_wdata;
                      	$display("[%0t] DMA: Source address set - 0x%08X", $time, reg_wdata);
                    end
                  	8'h0C: begin
                      	dst_reg <= reg_wdata; $display("[%0t] DMA: Destination address set - 0x%08X", $time, reg_wdata);
                    end
                  	8'h10: begin
                      	size_reg <= reg_wdata; $display("[%0t] DMA: Transfer size set - %0d bytes", $time, reg_wdata);
                    end
                  	default: $display("[%0t] DMA: Invalid register address access - 0x%02X", $time, reg_addr);
				endcase
			end
		end
	end
  
	// Register-read MUX
	always_comb begin
		unique case (reg_addr)
			8'h00: 	 reg_rdata = {ctrl}; 		// Read CTRL
			8'h04: 	 reg_rdata = {stat}; 		// Read STAT
			8'h08: 	 reg_rdata = src_reg; 		// Read SRC
			8'h0C: 	 reg_rdata = dst_reg; 		// Read DST
			8'h10: 	 reg_rdata = size_reg; 		// Read SIZE
			8'h14: 	 reg_rdata = bytes_done; 	// Progress bytes
			default: reg_rdata = 32'hDEAD_BEEF; // Guard value
		endcase
	end
  
	// Prefetch register for write-data alignment
	logic [31:0] wdata_hold; // Hold the next beat one cycle early

	// Main FSM
	always_ff @(posedge clk or negedge resetn) begin
		if(!resetn) begin
			cur <= S_IDLE; dbg_state <= S_IDLE; 			// Initial state
			start_active <= 1'b0; 							// Initialize start latch
			setup_complete <= 1'b0; 						// Initialize SETUP flag
			r_beats_rcvd <= '0; w_beats_sent <= '0; 		// Initialize counters
			wr_ptr <= '0; rd_ptr <= '0; count <= '0;		// Initialize FIFO
			cur_src <= '0; cur_dst <= '0; bytes_left <= '0; // Initialize addresses/remaining count
			burst_len_m1 <= '0; bytes_done <= '0; 			// Initialize length/completion
          
			// AXI defaults (4-byte beats, INCR bursts)
			m.awvalid <= 1'b0; m.awaddr <= '0; m.awlen <= '0; 				 // Initialize AW
			m.awsize <= 3'b010; m.awburst<=2'b01; m.awid <= 4'h0;			 // Configuration
			m.wvalid <= 1'b0; m.wdata <= '0; m.wstrb <= 4'hF; m.wlast<=1'b0; // Initialize W
			m.bready <= 1'b1;												 // Accept BRESP immediately
			m.arvalid <= 1'b0; m.araddr <= '0; m.arlen <= '0;				 // Initialize AR
			m.arsize<=3'b010; m.arburst<=2'b01; m.arid<=4'h0;				 // Configuration
			m.rready <= 1'b1;												 // Accept RDATA immediately
          
			stat <= '0;			   // Clear status
          	dma_done_int <= 1'b0;  // Interrupts Low
          	dma_error_int <= 1'b0; // Interrupts Low
          	wdata_hold <= '0; 	   // Initialize prefetch
		end else begin
			cur <= nxt; 		   // State transition
			dbg_state <= nxt; 	   // Debug output
			dma_done_int <= 1'b0;  // Pulse signal defaults low
          	dma_error_int <= 1'b0;
			
			m.awvalid <= 1'b0; 	   // Address valid is 1 only in its state
			m.arvalid <= 1'b0; 	   // Address valid is 1 only in its state
			// Control m.wvalid/m.wdata/m.wlast only in S_WR_DATA
			
          	if (reg_write && (reg_addr==8'h00) && reg_wdata[1]) begin // When writing CTRL.start=1
				start_active <= 1'b1;  	// Set start latch
				setup_complete <= 1'b0; // Prepare new transfer
				$display("[%0t] DMA: start_active set to 1", $time);
			end
          
			unique case (cur)
				S_IDLE: begin
					stat.busy <= 1'b0;						  // Mark idle
                  	if (start_active) begin					  // Detect start command
						cur_src <= src_reg;					  // Latch source
						cur_dst <= dst_reg;					  // Latch destination
						bytes_left <= size_reg;				  // Load the requested transfer size
						bytes_done <= 0;					  // Clear the byte counter
						r_beats_rcvd <= 0; w_beats_sent <= 0; // Reset counters
						wr_ptr <= 0; rd_ptr <= 0; count <= 0; // Reset FIFO
                      
						stat.busy <= 1'b1;		 // Start operation
                      	stat.done <= 1'b0;		 // Clear done
                      	stat.error <= 1'b0;		 // Clear error
                      	stat.error_code <= 4'h0; // Initialize error code
                      	$display("[%0t] DMA: NEW TRANSFER STARTED - 0x%08X -> 0x%08X (%0d bytes)", $time, src_reg, dst_reg, size_reg);
                    end
				end
              
				S_SETUP: begin
					start_active <= 1'b0;		// Consume start pulse
                  if (!setup_complete) begin 	// Run once only
                      	setup_complete <= 1'b1; // Prevent rerun
                    	$display("[%0t] DMA: SETUP EXECUTING - bytes_left=%0d, src=0x%08X, dst=0x%08X", $time, bytes_left, cur_src, cur_dst);
                    
                    	if (bytes_left == 0) begin 							// Disallow zero-byte transfer
							stat.error <= 1'b1; stat.error_code <= 4'h2; 	// Size error
                          	$display("[%0t] DMA: SETUP ERROR - bytes_left is ZERO", $time);
						end else if (bytes_left >= 64) begin
							burst_len_m1 <= 8'd15; 							// 16 beats (64B)
                          	$display("[%0t] DMA: SETUP SUCCESS - 16 beats (64 bytes) for %0d bytes_left", $time, bytes_left);
						end else if (bytes_left >= 16) begin
							burst_len_m1 <= 8'd3; 							// 4 beats (16B)
                          	$display("[%0t] DMA: SETUP SUCCESS - 4 beats (16 bytes) for %0d bytes_left", $time, bytes_left);
						end else if (bytes_left >= 4) begin
							burst_len_m1 <= 8'd0; 							// 1 beat (4B)
                          	$display("[%0t] DMA: SETUP SUCCESS - 1 beat (4 bytes) for %0d bytes_left", $time, bytes_left);
						end else begin 										// Less than 4 bytes is unsupported
							stat.error <= 1'b1; stat.error_code <= 4'h2;
                          	$display("[%0t] DMA: SETUP ERROR - bytes_left=%0d < 4", $time, bytes_left);
						end
						r_beats_rcvd <= 0; w_beats_sent <= 0; 				// Reset counters
					end
				end
              
				S_RD_ADDR: begin
					m.arvalid <= 1'b1; 				// AR valid
					m.araddr <= cur_src; 			// Start address
					m.arlen <= burst_len_m1; 		// Length minus 1
					m.arid <= ctrl.channel_id[3:0]; // Set ID
                  	$display("[%0t] DMA: READ ADDR - 0x%08X, %0d beats", $time, cur_src, burst_len_m1+1);
				end
             
				S_RD_DATA: begin
                  	if (r_fire) begin 						// On R-beat receipt
						fifo[wr_ptr] <= m.rdata; 			// Enqueue into FIFO
						wr_ptr <= wr_ptr + 1; 				// Increment WR pointer
						count <= count + 1; 				// Increment stored count
						r_beats_rcvd <= r_beats_rcvd + 1; 	// Receive count
						cur_src <= cur_src + 4; 			// Increment source address
						bytes_left <= bytes_left - 4; 		// Decrement remaining bytes
						bytes_done <= bytes_done + 4; 		// Increment progress bytes
						$display("[%0t] DMA: READ DATA - 0x%08X (beat %0d/%0d)", $time, m.rdata, r_beats_rcvd+1, burst_len_m1+1);
					end
				end
         
				S_WR_ADDR: begin
					m.awvalid <= 1'b1; 				// AW valid
					m.awaddr <= cur_dst; 			// Start address
					m.awlen <= burst_len_m1; 		// Length minus 1
					m.awid <= ctrl.channel_id[3:0]; // Set ID
                  	$display("[%0t] DMA: WRITE ADDR - 0x%08X, %0d beats", $time, cur_dst, burst_len_m1+1);
				end
         
				// Write data: first-cycle alignment + one-cycle lookahead prefetch
				S_WR_DATA: begin
                  	if (!m.wvalid && !buf_empty) begin 			   // Start transfer (idle → active)
                    	wdata_hold <= fifo[rd_ptr + 1]; 		   // Hold next data early
                    	m.wdata <= fifo[rd_ptr]; 				   // Output current data
						m.wvalid <= 1'b1;  						   // Assert valid
                      	m.wlast <= (w_beats_sent == burst_len_m1); // Whether final
					end
                  	else if (m.wvalid) begin 						// Transfer in progress
                      	m.wdata <= wdata_hold; 						// Output held data
                    	m.wlast <= (w_beats_sent == burst_len_m1); 	// Whether final
					end
					else begin
						m.wlast <= 1'b0; 							// last=0 while idle
                    end
                  
                  	if (w_fire) begin 						// W-beat transmission handshake
                      	rd_ptr <= rd_ptr + 1; 				// Increment RD pointer
                      	count <= count - 1; 				// Decrement stored count
                      	cur_dst <= cur_dst + 4; 			// Increment destination address
						w_beats_sent <= w_beats_sent + 1; 	// Increment transmit count
                      
                      	if (w_beats_sent != burst_len_m1) 	// Before the final beat
                        	wdata_hold <= fifo[rd_ptr + 2]; // Prefetch the data after next
                      
                      	if (w_beats_sent == burst_len_m1) 	// Immediately after final beat
							m.wvalid <= 1'b0; 				// Deassert wvalid (move to RESP)
						$display("[%0t] DMA: WRITE DATA - 0x%08X -> 0x%08X (beat %0d/%0d)", $time, m.wdata, cur_dst, w_beats_sent+1, burst_len_m1+1);
					end
                end

				S_WR_RESP: begin
					m.bready <= 1'b1; 					// Accept BRESP immediately
					if (m.bvalid && m.bready) begin 	// Receive response
						if (m.bresp != 2'b00) begin 	// Error response
							stat.error <= 1'b1; 		// Set error
							stat.error_code <= 4'h3; 	// Set code
                          	$display("[%0t] DMA: WRITE ERROR - BRESP=%b", $time, m.bresp);
						end else begin 					// OKAY response
                          	if (bytes_left == 0) begin 	// When no bytes remain
								stat.done <= 1'b1; 		// Completion (sticky)
								stat.busy <= 1'b0; 		// Deassert busy
							end
							$display("[%0t] DMA: WRITE COMPLETE - bytes_left=%0d", $time, bytes_left);
						end
					end
				end
              
				S_NEXT: begin
					r_beats_rcvd <= 0; 		// Reset counters
                  	w_beats_sent <= 0; 		// Reset counters
                  	setup_complete <= 1'b0; // Allow next SETUP
                  	$display("[%0t] DMA: NEXT BURST - %0d bytes remaining", $time, bytes_left);
				end
              
				S_DONE: begin
					stat.busy <= 1'b0; 			 // End operation
                  	stat.done <= 1'b1; 			 // Hold completion
                  	dma_done_int <= ctrl.irq_en; // Pulse when IRQ enabled
                  	$display("[%0t] DMA: TRANSFER COMPLETED - Total %0d bytes", $time, bytes_done);
				end

              	S_ERROR: begin
					stat.busy <= 1'b0; 				// Stop
					stat.error <= 1'b1; 			// Hold error
                    dma_error_int <= ctrl.irq_en; // Assert while S_ERROR is serviced and IRQ is enabled
                  	$display("[%0t] DMA: ERROR STATE - code=0x%0h", $time, stat.error_code);
				end
              
              	default: ; // Defensive default
			endcase
		end
	end
  
	// Next-state combinational logic
	always_comb begin
		nxt = cur; // Hold by default
		unique case (cur)
			S_IDLE: begin
            	$display("[%0t] DMA: IDLE check - start_active=%0b, size_reg=%0d", $time, start_active, size_reg);
              	if (start_active) begin 	// Start command
					if (size_reg==0) begin 	// Size 0 → error
                    	$display("[%0t] DMA: IDLE -> ERROR (size=0)", $time);
						nxt = S_ERROR;
					end else begin 			// Normal → SETUP
                    	$display("[%0t] DMA: IDLE -> SETUP (size=%0d)", $time, size_reg);
						nxt = S_SETUP;
					end
				end
			end
          
			S_SETUP: if (setup_complete) begin
              	if (stat.error)
                  	nxt = S_ERROR;
              	else
                  	nxt = S_RD_ADDR;
            end 					// Proceed to RD_ADDR after setup
          
			S_RD_ADDR: if (m.arvalid && m.arready)
              	nxt = S_RD_DATA; 	// AR handshake → RD_DATA
          
			S_RD_DATA: if (r_fire && (r_beats_rcvd==burst_len_m1))
              	nxt = S_WR_ADDR; 	// Final read beat → WR_ADDR
          
			S_WR_ADDR: if (m.awvalid && m.awready)
              	nxt = S_WR_DATA; 	// AW handshake → WR_DATA

          	S_WR_DATA: if (w_fire && (w_beats_sent == burst_len_m1))
              	nxt = S_WR_RESP; 	// Final write beat → RESP
          
			S_WR_RESP: if (m.bvalid && m.bready) begin
				if (stat.error)
                  	nxt = S_ERROR; 	// Error → ERROR
				else if (bytes_left>0)
                  	nxt = S_NEXT; 	// Remaining data → NEXT
				else
                  	nxt = S_DONE; 	// No remaining data → DONE
			end

          	S_NEXT: nxt = S_SETUP; 	// Repeat
          
			S_DONE: nxt = S_IDLE; 	// Idle after completion
          
          	S_ERROR: if (start_active) nxt = S_IDLE; // Allow retry
          
			default: nxt = S_IDLE; 	// Defensive
		endcase
	end
endmodule

// ---------------------------------------------------------------
// DDR controller (AXI4 slave)
// ---------------------------------------------------------------
module ddr_controller (axi4_if.slave axi); 	// Use interface as a slave
	logic [31:0] mem [0:1023]; 				// 4 KB memory model (word array)
  
	localparam int R_LAT = 3; 				// Initial read-latency cycles
	logic rd_active; 						// Read-active flag
	logic [31:0] rd_addr; 					// Current read address
	logic [7:0] rd_len; 					// Requested burst length minus 1
	logic [7:0] rd_cnt; 					// Number of beats sent
	logic [2:0] rd_lat; 					// Initial-latency counter
	logic [3:0] rd_id_reg; 					// Latched read ID
  
	logic wr_active; 						// Write-active flag
	logic [31:0] wr_addr; 					// Current write address
	logic [7:0] wr_len; 					// Requested burst length minus 1
	logic [7:0] wr_cnt; 					// Number of beats received
	logic [3:0] wr_id_reg; 					// Latched write ID
  
	logic bvalid_reg; 						// Internal BRESP valid
	logic [1:0] bresp_reg; 					// Internal BRESP code
	logic [3:0] bid_reg; 					// Internal BRESP ID
  
	logic r_valid_now; 						// Whether to generate rvalid this cycle
	logic r_fire; 							// rvalid & rready handshake
  
	assign axi.rresp = 2'b00; 				// Read response is always OKAY
	assign axi.bresp = bresp_reg; 			// Connect write-response code
	assign axi.bid = bid_reg; 				// Connect write-response ID
  
  	assign axi.arready = (!rd_active); 					// Accept AR while read-idle
	assign axi.awready = (!wr_active) && !bvalid_reg; 	// Accept AW while write-idle with no response pending
	assign axi.wready = wr_active; 						// Accept data only while write is active
  
	always_ff @(posedge axi.aclk or negedge axi.aresetn) begin // Clock/reset
      	if (!axi.aresetn) begin 				// Asynchronous reset
          	for (int i=0; i<64; i++) 
				mem[i] <= 32'hCAFE_0000 + i; 	// Initial pattern
			for (int j=64; j<1024; j++)
              	mem[j] <= 32'h0; 				// Remaining locations = 0
			rd_active <= 1'b0; rd_addr <= '0; rd_len <= '0; rd_cnt <= '0; rd_lat <= '0; rd_id_reg <= '0; // Initialize RD
			wr_active <= 1'b0; wr_addr <= '0; wr_len <= '0; wr_cnt <= '0; wr_id_reg <= '0; 				 // Initialize WR
			axi.rvalid <= 1'b0; axi.rlast <= 1'b0; axi.rid <= '0; axi.rdata <= '0; 						 // Initialize R channel
			bvalid_reg <= 1'b0; bresp_reg <= 2'b00; bid_reg <= '0; 										 // Initialize B channel
		end else begin
          	if (axi.arvalid && axi.arready) begin // Accept AR
              	rd_active <= 1'b1; 		// Start read
              	rd_addr <= axi.araddr; 	// Latch start address
              
              	rd_len <= axi.arlen; 	// Latch length minus 1
              	rd_cnt <= '0; 			// Initialize counters
              
              	rd_lat <= R_LAT[2:0]; 	// Set initial latency
              	rd_id_reg <= axi.arid; 	// Latch ID
			end
          
          	r_valid_now = rd_active && (rd_lat==0); // Generate rvalid after latency
			axi.rvalid <= r_valid_now; 				// Drive rvalid
			axi.rlast <= 1'b0; 						// Default last=0
			r_fire = r_valid_now && axi.rready; 	// Whether handshake occurs
          
          	if (rd_active) begin 					 // Read in progress
              	if (rd_lat != 0) begin 				 // Still in latency phase
                  	rd_lat <= rd_lat - 1; 			 // Count down latency
                end else begin 						 // Data-output phase
					axi.rid <= rd_id_reg; 			 // Output ID
                  	axi.rdata <= mem[rd_addr[11:2]]; // Read by word address
                  
                  	if (r_fire) begin 				 // When transfer occurs
						rd_addr <= rd_addr + 4;		 // Next word
                      	if (rd_cnt == rd_len) begin  // On final beat
							axi.rlast <= 1'b1; 		 // last=1
							rd_active <= 1'b0;		 // End read
						end
						rd_cnt <= rd_cnt + 1;		 // Increment sent count
					end
				end
			end
          
          	if (axi.awvalid && axi.awready) begin // Accept AW
              	wr_active <= 1'b1;				  // Start write
              	wr_addr <= axi.awaddr;			  // Latch start address
              
              	wr_len <= axi.awlen;			  // Latch length minus 1
              	wr_cnt <= '0;				 	  // Initialize counters
              
              	wr_id_reg <= axi.awid;			  // Latch ID
			end
          
          	if (wr_active && axi.wvalid && axi.wready) begin // Receive W data
              	mem[wr_addr[11:2]] <= axi.wdata;			 // Write memory
              	wr_addr <= wr_addr + 4;						 // Next word address
            	if (axi.wlast || (wr_cnt==wr_len)) begin	 // Detect final beat
					wr_active <= 1'b0;						 // End write
					bvalid_reg <= 1'b1;						 // Prepare BRESP
					bresp_reg <= 2'b00;						 // OKAY
					bid_reg <= wr_id_reg;					 // Response ID
				end
				wr_cnt <= wr_cnt + 1;						 // Increment received count
			end

          	if (bvalid_reg && axi.bready) begin				 // When BRESP is accepted
              	bvalid_reg <= 1'b0;							 // Complete response
			end
		end
	end
  
  	assign axi.bvalid = bvalid_reg;							 // Connect external BRESP valid
  
endmodule
