# Step 1 — Refactoring the Baseline Design and Testbench

## Overview

I split the baseline design and testbench into separate files and preserved the MMIO timing, directed
scenarios, and coverage model.

## Objective

Separate the integrated baseline design and verification code into role-specific files to clarify
component responsibilities and dependencies and establish the structural foundation for the Step 2
UVM migration while preserving the existing verification behavior.

## File Organization

| File | Role |
|---|---|
| `design.sv` | Top-level source file for design compilation that includes the AXI4 interface, DMA controller, and DDR memory model |
| `axi4_if.sv` | Define AXI4 channel signals and master/slave modports |
| `dma_controller.sv` | DUT that performs AXI4-based memory copies |
| `ddr_memory_model.sv` | Verification memory model that responds to DUT AXI4 requests |
| `mmio_if.sv` | Group MMIO register-access and interrupt signals and define TB/DUT modports |
| `utility_pkg.sv` | Provide reentrant MMIO read/write, DMA-completion wait, and status-polling tasks |
| `coverage.sv` | Measure transfer-size, FSM-state, address-alignment, burst-length, state-transition, and cross coverage |
| `testbench.sv` | Generate clock/reset, connect the verification environment, run directed scenarios, and report results |

## Main Changes

- Separate the AXI4 interface, DMA controller, and DDR memory model from the baseline `design.sv` into role-specific files
- Keep `design.sv`, the default Design file whose name cannot be changed in EDA Playground, as the
  top-level source file for design compilation and configure it to `include` the separated AXI4
  interface, DMA controller, and DDR memory model
- Rename the DDR memory-model module from `ddr_controller` to `ddr_memory_model` to reflect its actual role
- Separate the MMIO signals into an interface and define `tb_mp` and `dut_mp` modports
- Move MMIO read/write and DMA-completion-wait tasks into a package and declare them `automatic`
- Move the baseline covergroup into a separate file
- Simplify `testbench.sv` around verification-environment connectivity and scenario execution

## Test Scenarios

Run the baseline directed scenarios in the same order.

| No. | Scenario Name |
|---:|---|
| S1 | 256B basic copy |
| S2 | 1024B large transfer |
| S3 | 16B/64B transfers |

## VCS Verification Results

| Item | Baseline | Step 1 |
|---|---:|---:|
| Test result | PASS | PASS |
| Data comparison | 8 sampled words matched | 8 sampled words matched |
| Execution time | 10175ns | 10175ns |
| Estimated throughput | 1069.29Mbps | 1069.29Mbps |
| Transfer-size coverage | 75.00% | 75.00% |
| DMA-state coverage | 85.71% | 85.71% |
| Address-alignment coverage | 50.00% | 50.00% |
| Size/alignment cross | 42.86% | 42.86% |
| Overall functional coverage | 64.80% | 64.80% |

- Baseline log: [`baseline_simulation.log`](../../baseline/baseline_simulation.log)
- Step 1 log: [`step1_simulation.log`](../../runs/step1_simulation.log)

The baseline and refactored testbenches produced the same results for the directed tests, including
64.80% functional coverage and a simulated duration of 10,175 ns.
