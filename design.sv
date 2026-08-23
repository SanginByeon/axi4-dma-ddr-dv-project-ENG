// ============================================================================
// design.sv - Top-Level Source File for Design Compilation in EDA Playground
//
// - Serves as the top-level source file for design compilation in EDA Playground.
// - Includes the AXI4 interface, DMA controller, and DDR memory model in dependency order.
// - Manages only the design-source compilation order without implementing logic.
// ============================================================================

`timescale 1ns/1ps

`include "axi4_if.sv"
`include "dma_controller.sv"
`include "ddr_memory_model.sv"
