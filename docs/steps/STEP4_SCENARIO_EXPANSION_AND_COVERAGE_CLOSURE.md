# Step 4 — Comprehensive Verification Through Test-Scenario Expansion and Coverage Closure

## Overview

Expand the Step 3 verification environment with normal boundary values, size errors, backpressure,
SLVERR, error recovery, and constrained-random conditions. Execute 37 transactions across seven
sequences and verify data integrity, error handling and recovery, and AXI4 W-channel protocol
compliance.

To measure execution of the verification plan, separate coverage into three covergroups for
transactions, the DMA FSM, and AXI events. Analyze functional verification and coverage results from
the expanded scenarios together to confirm that each verification item is satisfied.

During coverage closure, an uncovered bin in `cp_wlast_awlen` led me to a WLAST timing bug. I
corrected the DUT's WLAST calculation and reran the tests. After adding AXI4 W-channel assertions and
final pass criteria, all coverpoints and crosses reached 100%, assertion violations remained zero,
and the complete test passed.

## Objective

Expand test scenarios across diverse normal, error, and backpressure conditions to verify data
integrity, error handling and recovery, and the AXI4 W-channel protocol; measure the results with
functional coverage; analyze and address uncovered items; and complete coverage closure.

## File Organization

| File | Role |
|---|---|
| `design.sv` | Compile entry that includes AXI4/DDR-model interfaces, DMA controller, and DDR memory model |
| `axi4_if.sv` | Define AXI4 channel signals and master/slave modports |
| `ddr_model_if.sv` | Deliver backpressure probability and BRESP error-injection settings to the DDR memory model |
| `dma_controller.sv` | DUT that performs AXI4-based memory copies |
| `ddr_memory_model.sv` | Respond to AXI4 requests and generate W-channel backpressure and BRESP SLVERR |
| `mmio_if.sv` | Group MMIO register-access and interrupt signals and define TB/DUT modports |
| `coverage.sv` | Define Transaction, DMA FSM, and AXI-event functional coverage models |
| `axi_checker.sv` | Define assertions for AXI4 W-payload stability, WVALID persistence, and WLAST timing |
| `testbench.sv` | Connect DUT, verification environment, and checker; pass virtual interfaces; and run the UVM test |
| `utility_pkg.sv` | Provide MMIO access, normal/error termination wait, source preload, and DDR backdoor read |
| `dma_tx.sv` | Define DMA, backpressure/error-injection, and constrained-random conditions |
| `dma_base_seq.sv` | Base sequence for DMA transaction generation and randomization |
| `dma_s1_boundary_seq.sv` | Normal transfer-size and burst/tail-boundary sequence |
| `dma_s2_size_error_seq.sv` | Size-error sequence for sizes below 4 bytes or not divisible by 4 |
| `dma_s3_backpressure_seq.sv` | Sequence combining burst lengths and backpressure intensities |
| `dma_s4_slverr_seq.sv` | Standalone BRESP SLVERR-injection sequence |
| `dma_s5_backpressure_slverr_seq.sv` | Combined backpressure and BRESP SLVERR sequence |
| `dma_s6_error_recovery_seq.sv` | Normal-transfer recovery after a size error or SLVERR |
| `dma_s7_random_seq.sv` | Five constrained-random normal-transfer transactions |
| `dma_driver.sv` | Configure DDR-model conditions, drive MMIO stimulus, and check DMA results |
| `dma_monitor.sv` | Observe MMIO writes, DDR-model conditions, and completion/error interrupts |
| `dma_scoreboard.sv` | Compare source/destination data and check expected transaction counts |
| `dma_agent.sv` | Configure an active Sequencer/Driver and Monitor |
| `dma_env.sv` | Create the Agent and Scoreboard and connect the analysis port |
| `dma_test.sv` | Run seven sequences and report checker, coverage, and final results |

## Main Changes

- Separate the Verification Plan, Coverage Plan, Test Plan, and Assertion Set to establish
  traceability between verification objectives and implementation items
- Expand normal boundaries, size errors, backpressure, SLVERR, error recovery, and constrained-random
  conditions into seven sequences and 37 transactions
- Preserve the existing UVM component structure while checking expected scenario behavior through
  Scoreboard source/destination comparison, Driver termination-state checking, and subsequent
  transaction execution after errors
- Rebuild the previous single covergroup, which sampled every cycle uniformly, as three covergroups
  based on transactions, the DMA FSM, and AXI events
- Define 19 coverpoints and five crosses that measure DUT size branches, burst/tail handling, memory
  regions, backpressure intensity, error codes, and actual AXI handshakes
- Add the A-01–A-03 assertion checker for W-payload stability and WVALID persistence during AXI4
  W-channel stalls and WLAST timing on the final beat
- Compare the expected 20 UVM errors from negative tests with the actual count and combine transaction
  count, checker violations, and coverage closure into the final PASS/FAIL decision
- Extend the coverage report to print every coverpoint and cross with its ID
- Set UVM verbosity to `UVM_MEDIUM` and disable internal DUT progress logs by default to control output volume

Detailed plans are defined in the following documents.

- Verification plan: [`VERIFICATION_PLAN.md`](../VERIFICATION_PLAN.md)
- Coverage plan: [`COVERAGE_PLAN.md`](../COVERAGE_PLAN.md)
- Test plan: [`TEST_PLAN.md`](../TEST_PLAN.md)
- Assertion items: [`ASSERTION_SET.md`](../ASSERTION_SET.md)

## DUT Debugging

### AXI4 W-Channel WLAST Timing

In the first run, transaction coverage and DMA-FSM coverage reached 100%, but `cp_wlast_awlen` remained
at 33.33%, leaving AXI-event coverage at 92.59%. Because `cp_awlen` measured all 1-, 4-, and 16-beat
bursts, the gap indicated a WLAST behavior issue rather than a missing scenario, so the four-beat
write-burst waveform was analyzed.

The DUT calculated WLAST from the current beat number while outputting the next `WDATA`, causing WLAST
to assert after the final data handshake. The calculation was changed to use the next beat number,
`w_beats_sent + 1`.

- Detailed analysis: [`AXI4_WLAST_TIMING_DEBUGGING.md`](../debug/AXI4_WLAST_TIMING_DEBUGGING.md)
- Coverage-gap reproduction log:
  [`step4_wlast_coverage_gap.log`](../../runs/debug/step4_wlast_coverage_gap.log)

## Test Scenarios

| No. | Transactions | Scenario | Verification |
|---:|---:|---|---|
| S1 | 11 | Normal-transfer boundaries | Size, burst, and tail-boundary handling |
| S2 | 4 | Size error | `error_code=0x2` for sizes below 4 bytes or not divisible by 4 |
| S3 | 9 | W-channel backpressure | Combinations of 1-, 4-, and 16-beat bursts with 10%, 50%, and 90% backpressure |
| S4 | 1 | BRESP SLVERR | `error_code=0x3` path without backpressure |
| S5 | 3 | Backpressure + SLVERR | BRESP error handling at each backpressure level |
| S6 | 4 | Error recovery | Normal recovery immediately after a size error or SLVERR |
| S7 | 5 | Constrained random | Additional constraint-based normal transfers and data matches |
| **Total** | **37** |  |  |

The S1–S6 directed tests cover the main boundary values and coverage combinations. The five S7
transactions supplement them by checking random normal-transfer generation and data integrity under
the constraints; they are not the primary means of statistical random regression or coverage closure.

Addresses, sizes, backpressure settings, and expected results for every transaction are defined in
[`TEST_PLAN.md`](../TEST_PLAN.md).

## VCS Configuration

Use the same VCS, UVM, and compile options as Steps 2 and 3.

- Simulator: Synopsys VCS 2025.06
- UVM version: UVM 1.2
- Compile options:

  ```text
  -timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog -debug_access+all
  ```

- Run options: none

## VCS Verification Results

| Item | Step 3 | Step 4 |
|---|---:|---:|
| Executed scenarios | 4 transactions | 7 sequences, 37 transactions |
| Normal / Size error / SLVERR | 3 / 0 / 1 | 27 / 5 / 5 |
| Transaction count | 4 expected / 4 checked | 37 expected / 37 checked |
| Data comparison | All 340 words matched | 32 normal/SLVERR transactions PASS; 5 expected size-error mismatches |
| UVM Warning/Error/Fatal | 0 / 1 / 0 | 0 / 20 / 0 |
| Expected/actual UVM errors | Not applied | 20 / 20 |
| AXI4 W assertions | Not applied | 0 A-01–A-03 violations |
| Execution time | 11005ns | 56315ns |
| Transaction coverage | Not applied | 100.00% |
| DMA-FSM coverage | Not applied | 100.00% |
| AXI-event coverage | Not applied | 100.00% |
| Overall functional coverage | 66.84% | 100.00% |
| Final result | PASS | PASS |

- Step 3 log: [`step3_simulation.log`](../../runs/step3_simulation.log)
- Step 4 log: [`step4_simulation.log`](../../runs/step4_simulation.log)

The 20 Step 4 UVM errors are expected negative-test results: 15 Driver/Scoreboard reports from five
size-error transactions and five Driver reports from five SLVERR transactions. The final test passes
because expected and actual error counts match, warnings and fatals are zero, all 37 transactions are
checked, AXI4 W assertion violations are zero, and all three covergroups reach 100%.

The longer execution time results from expanding the scenario set from four to 37 transactions and is
not interpreted as a change in DUT performance.

The `Estimated throughput` in the simulation log is produced by the existing `analyze_performance()`
calculation, which uses the fixed 1,360B Step 2/3 transfer total (`256+1024+16+64`). Because Step 4
uses a different 37-transaction transfer composition, the printed throughput does not represent the
actual Step 4 throughput. Accurate measurement would require accumulating the actual transferred
bytes and active DUT interval for each transaction, but throughput and performance evaluation are
outside this project's functional and protocol verification scope. The existing calculation is
therefore left unchanged and excluded from verification results and performance comparisons.

The overall coverage values from Steps 3 and 4 use different coverage models and are not compared as
a simple numerical increase. Step 4 reaches closure when all targeted, reachable coverpoint and cross
bins in the new coverage model have been hit.
