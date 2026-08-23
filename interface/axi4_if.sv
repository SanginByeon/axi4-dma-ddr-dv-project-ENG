// ============================================================================
// axi4_if.sv - AXI4 Interface
//
// - Groups AXI4 signals between the DMA controller and DDR memory model.
// - Defines address/data/ID widths as parameters and provides required AXI4 channel signals.
// - Distinguishes component signal directions through master/slave modports.
// - Separates the baseline design.sv AXI4 interface into its own file without behavioral changes.
// ============================================================================

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
