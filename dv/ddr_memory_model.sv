// ============================================================================
// ddr_memory_model.sv - AXI4 Slave DDR Memory Model
//
// - Verification memory model that responds to DMA-controller AXI4 read/write requests.
// - Provides 1,024 x 32-bit memory and fixed read latency.
// - Removes the previous memory-pattern initialization for UVM; sequences preload source data.
// - Generates random AXI4 W-channel backpressure according to the configured probability.
// - Returns SLVERR through BRESP after a write burst according to configuration.
// - Does not model actual DDR-controller or PHY behavior.
// - Renames the baseline ddr_controller for its role and separates it into its own file.
// ============================================================================

module ddr_memory_model (
	axi4_if.slave axi, 	// AXI4 Slave interface
	ddr_model_if ddr_cfg	// DDR memory-model verification-condition control
);
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

	logic force_stall; 						// Deassert WREADY when 1
	logic [7:0] active_backpressure_prob; 	// Backpressure probability for the current write burst
	logic active_error_inject; 				// BRESP error-injection setting for the current write burst
  
	logic r_valid_now; 						// Whether to generate rvalid this cycle
	logic r_fire; 							// rvalid & rready handshake
  
	assign axi.rresp = 2'b00; 				// Read response is always OKAY
	assign axi.bresp = bresp_reg; 			// Connect write-response code
	assign axi.bid = bid_reg; 				// Connect write-response ID
  
	assign axi.arready = (!rd_active); 					// Accept AR while read-idle
	assign axi.awready = (!wr_active) && !bvalid_reg; 	// Accept AW while write-idle with no response pending
	assign axi.wready = wr_active && !force_stall; 		// Accept W data only when no random stall is active

	// [W-channel backpressure] : Latch probability at AW and decide random stall each write-burst cycle
	always_ff @(posedge axi.aclk or negedge axi.aresetn) begin
		if (!axi.aresetn) begin
			force_stall <= 1'b0;
			active_backpressure_prob <= '0;
			active_error_inject <= 1'b0;
		end else if (axi.awvalid && axi.awready) begin
			// Apply the same backpressure and BRESP settings throughout this write burst
			active_backpressure_prob <= ddr_cfg.backpressure_prob;
			active_error_inject <= ddr_cfg.error_inject;

			// Decide whether to stall the first W beat
			if (ddr_cfg.backpressure_prob == 0)
				force_stall <= 1'b0;
			else
				force_stall <=
					($urandom_range(0, 99) < ddr_cfg.backpressure_prob);
		end else if (wr_active) begin
			// Independently decide whether to stall on every cycle of the write burst
			if (active_backpressure_prob == 0)
				force_stall <= 1'b0;
			else
				force_stall <=
					($urandom_range(0, 99) < active_backpressure_prob);
		end else begin
			force_stall <= 1'b0;

			// Clear the previous write burst's error-injection setting before the next burst
			if (bvalid_reg && axi.bready)
				active_error_inject <= 1'b0;
		end
	end

	always_ff @(posedge axi.aclk or negedge axi.aresetn) begin // Clock/reset
      	if (!axi.aresetn) begin 				// Asynchronous reset
			rd_active <= 1'b0; rd_addr <= '0; rd_len <= '0; rd_cnt <= '0; rd_lat <= '0; rd_id_reg <= '0; // Initialize RD
			wr_active <= 1'b0; wr_addr <= '0; wr_len <= '0; wr_cnt <= '0; wr_id_reg <= '0; 				 // Initialize WR
			axi.rvalid <= 1'b0; axi.rlast <= 1'b0; axi.rid <= '0; axi.rdata <= '0; 						 // Initialize R channel
			bvalid_reg <= 1'b0; bresp_reg <= 2'b00; bid_reg <= '0; 										 // Initialize B channel
		end else begin
          	if (axi.arvalid && axi.arready) begin // Accept AR
              	rd_active <= 1'b1; 		// Start read
              	rd_addr <= axi.araddr; 	// Latch start address
              
              	rd_len <= axi.arlen; 	// Latch length minus 1
              	rd_cnt <= '0; 			// Initialize counter
              
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
              	wr_cnt <= '0;				 	  // Initialize counter
              
              	wr_id_reg <= axi.awid;			  // Latch ID
			end
          
          	if (wr_active && axi.wvalid && axi.wready) begin // Receive W data
              	mem[wr_addr[11:2]] <= axi.wdata;			 // Write memory
              	wr_addr <= wr_addr + 4;						 // Next word address
            	if (axi.wlast || (wr_cnt==wr_len)) begin	 // Detect final beat
					wr_active <= 1'b0;						 // End write
					bvalid_reg <= 1'b1;						 // Prepare BRESP

					// Select write response from the setting latched at the AW handshake
					if (active_error_inject)
						bresp_reg <= 2'b10;					 // SLVERR
					else
						bresp_reg <= 2'b00;					 // OKAY

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
