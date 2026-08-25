# Step 3 — AXI4 W-Channel Backpressure and BRESP Error-Injection Environment

## Overview

Add AXI4 W-channel backpressure and BRESP error injection to the Step 2 UVM verification environment.
Configure the DDR memory model to probabilistically deassert `WREADY` or return `SLVERR` as the write
response according to the settings for each transaction.

Retain the existing normal transfer as the reference scenario while applying 10% and 90%
backpressure and BRESP error injection. Fix the DUT's W-payload, FIFO-prefetch, and BRESP-state-
transition bugs found under backpressure and error responses, and re-verify data integrity across the
complete transfer region and the error-handling path.

## Objective

Build a verification environment with controllable AXI4 slave response delays and error responses so
protocol-handling and error-state-transition issues that remain hidden under ideal response conditions
can be reproduced, analyzed, and fixed.

## File Organization

| File | Role |
|---|---|
| `design.sv` | Compile entry that includes the AXI4/DDR-model interfaces, DMA controller, and DDR memory model |
| `axi4_if.sv` | Define AXI4 channel signals and master/slave modports |
| `ddr_model_if.sv` | Deliver backpressure probability and BRESP error-injection settings to the DDR memory model |
| `dma_controller.sv` | DUT that performs AXI4-based memory copies |
| `ddr_memory_model.sv` | Respond to AXI4 requests and generate W-channel backpressure and BRESP SLVERR |
| `mmio_if.sv` | Group MMIO register-access and interrupt signals and define TB/DUT modports |
| `coverage.sv` | Measure transfer-size, FSM-state, address-alignment, burst-length, state-transition, and cross coverage |
| `testbench.sv` | Connect DUT/interfaces, provide virtual interfaces, and run the UVM test |
| `utility_pkg.sv` | Provide MMIO access, normal/error termination wait, source preload, and DDR backdoor read |
| `dma_tx.sv` | Sequence item defining DMA, backpressure, and error-injection settings |
| `dma_base_seq.sv` | Base sequence for DMA transaction generation and randomization |
| `dma_s1_seq.sv` | Reference 256B copy without backpressure or error injection |
| `dma_s2_seq.sv` | 1024B multi-burst sequence with 10% backpressure |
| `dma_s3_seq.sv` | Sequence with 90% backpressure and BRESP SLVERR injection |
| `dma_driver.sv` | Configure DDR-model conditions, drive MMIO stimulus, and check DMA results |
| `dma_monitor.sv` | Observe MMIO writes, DDR-model conditions, and completion/error interrupts |
| `dma_scoreboard.sv` | Compare source/destination data and check the expected transaction count |
| `dma_agent.sv` | Create the Monitor and add/connect the Sequencer and Driver in active mode |
| `dma_env.sv` | Create the Agent and Scoreboard and connect the analysis port |
| `dma_test.sv` | Run reference, backpressure, and error-injection sequences and report results |

## Main Changes

- Add `ddr_model_if` so the UVM Driver configures DDR memory-model `backpressure_prob` and
  `error_inject` conditions for each transaction
- Implement W-channel backpressure by latching verification conditions at the AW handshake and having
  the DDR memory model deassert `WREADY` at the configured probability during the write burst
- Implement error-response injection so the DDR memory model returns `BRESP=SLVERR` according to the
  latched `error_inject` value after the write burst completes
- Add a backpressure probability ranging from 0% to 99% and a separate one-bit BRESP error-injection
  flag to `dma_tx`; both default to zero
- Have the Driver calculate timeout margin from transfer size and backpressure probability, then restore DDR memory-model settings to defaults after each transaction
- Have the Monitor capture the backpressure and error-injection conditions applied when the DMA starts
- Change STATUS polling to treat either `done` or `error` as DMA termination
- Fix the W-payload update-condition and FIFO-prefetch-range bugs found under backpressure
- Fix the error-state-transition-condition bug exposed by BRESP SLVERR injection

## DUT Debugging

### AXI4 W-Channel Data Mismatch

While backpressure held `WREADY=0`, the DUT checked only `WVALID` and output the next `WDATA`, causing
a data mismatch. The DUT was changed to output the next W payload only on a completed handshake, and
unnecessary FIFO prefetch when no subsequent data exists was removed.

- Detailed analysis: [`AXI4_W_CHANNEL_DATA_MISMATCH_DEBUGGING.md`](../debug/AXI4_W_CHANNEL_DATA_MISMATCH_DEBUGGING.md)
- Reproduction log: [`step3_w_payload_failure.log`](../../runs/debug/step3_w_payload_failure.log)

### BRESP Error-State Transition

The DUT detected `BRESP=SLVERR` and set `stat.error`, but the next-state combinational logic referenced
the old `stat.error` value and transitioned to `S_DONE` rather than `S_ERROR`. The logic was changed to
determine the error state directly from `BRESP` at the current handshake.

- Detailed analysis: [`AXI4_BRESP_ERROR_PATH_DEBUGGING.md`](../debug/AXI4_BRESP_ERROR_PATH_DEBUGGING.md)
- Reproduction log: [`step3_bresp_error_path_failure.log`](../../runs/debug/step3_bresp_error_path_failure.log)

## Test Scenarios

| No. | Transfer Size | Backpressure | Error Injection | Verification |
|---:|---:|---:|---:|---|
| S1 | 256B | 0% | Disabled | Reproduce the Step 2 reference transfer |
| S2 | 1024B | 10% | Disabled | W-channel handshaking and data integrity in a multi-burst environment |
| S3-1 | 16B | 90% | Disabled | Small-burst handling under heavy backpressure |
| S3-2 | 64B | 0% | `BRESP=SLVERR` | Write-response error state and error interrupt |

## VCS Configuration

Use the same VCS, UVM, and compile options as Step 2.

- Simulator: Synopsys VCS 2025.06
- UVM version: UVM 1.2
- Compile options:

  ```text
  -timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog -debug_access+all
  ```

- Run options: none

## VCS Verification Results

| Item | Step 2 | Step 3 |
|---|---:|---:|
| Scenario result | 4 normal transfers PASS | 3 normal transfers PASS, 1 SLVERR path confirmed |
| Data comparison | All 340 words across 4 transfers matched | All 340 words across 4 transfers matched |
| Transaction count | 4 expected / 4 checked | 4 expected / 4 checked |
| UVM Warning/Error/Fatal | 0 / 0 / 0 | 0 / 1 / 0 |
| Execution time | 10415ns | 11005ns |
| Estimated throughput | 1044.65Mbps | 988.64Mbps |
| Transfer-size coverage | 75.00% | 75.00% |
| DMA-state coverage | 85.71% | 100.00% |
| Address-alignment coverage | 50.00% | 50.00% |
| Size/alignment cross | 42.86% | 42.86% |
| Overall functional coverage | 64.80% | 66.84% |

- Step 2 log: [`step2_simulation.log`](../../runs/step2_simulation.log)
- Step 3 log: [`step3_simulation.log`](../../runs/step3_simulation.log)

S1, S2, and S3-1 pass the Driver's normal-completion check and Scoreboard data comparison. The
intentionally injected SLVERR in S3-2 produces `S_WR_RESP → S_ERROR`, `error_code=0x3`, and an error
interrupt. Source and destination data match in every scenario, and DMA-state coverage increases to
100% by including entry into the error state.

The single error in the UVM summary is the Driver's report of the intentional `STATUS.error=1` in
S3-2. This step focuses on confirming operation of the error-response path; functional coverage of
error codes and scenario-specific expected-result evaluation are extended in the subsequent coverage
enhancement step.
