# DMA Test Plan

## 1. Overview

This document defines the stimulus values for the seven sequences and 37 total transactions executed in Step 4.
Verification objectives and result criteria are defined in [`VERIFICATION_PLAN.md`](./VERIFICATION_PLAN.md), coverage goals in
[`COVERAGE_PLAN.md`](./COVERAGE_PLAN.md), and assertion items in
[`ASSERTION_SET.md`](./ASSERTION_SET.md).

## 2. Common Configuration

- Every transaction uses `enable=1`, `start=1`, and `irq=1`.
- Source and destination addresses satisfy 4-byte alignment, the 4 KB memory range, and non-overlap conditions.
- Before each transaction, source memory is initialized with the `32'hCAFE_0000 + word index` pattern.
- `backpressure_prob` is the probability that the DDR memory model deasserts WREADY.
- When `error_inject=1`, the DDR memory model returns `BRESP=SLVERR` after the write burst completes.
- Size errors and SLVERR are intentional negative-test results and are included in the expected UVM error count.

## 3. Scenario Summary

| ID | Sequence | Transactions | Purpose | Expected UVM Errors |
|---|---|---:|---|---:|
| S1 | [`dma_s1_boundary_seq.sv`](../dv/uvm/sequences/dma_s1_boundary_seq.sv) | 11 | Check normal transfer sizes and burst/tail boundaries | 0 |
| S2 | [`dma_s2_size_error_seq.sv`](../dv/uvm/sequences/dma_s2_size_error_seq.sv) | 4 | Check sizes below 4 bytes and non-multiple-of-4 size errors | 12 |
| S3 | [`dma_s3_backpressure_seq.sv`](../dv/uvm/sequences/dma_s3_backpressure_seq.sv) | 9 | Check combinations of burst length and backpressure intensity | 0 |
| S4 | [`dma_s4_slverr_seq.sv`](../dv/uvm/sequences/dma_s4_slverr_seq.sv) | 1 | Check BRESP SLVERR without backpressure | 1 |
| S5 | [`dma_s5_backpressure_slverr_seq.sv`](../dv/uvm/sequences/dma_s5_backpressure_slverr_seq.sv) | 3 | Check combined backpressure and BRESP SLVERR | 3 |
| S6 | [`dma_s6_error_recovery_seq.sv`](../dv/uvm/sequences/dma_s6_error_recovery_seq.sv) | 4 | Check normal recovery after a size error or SLVERR | 4 |
| S7 | [`dma_s7_random_seq.sv`](../dv/uvm/sequences/dma_s7_random_seq.sv) | 5 | Additional constraint-based normal transfers | 0 |
| Total |  | **37** |  | **20** |

## 4. Directed Test Matrix

### 4.1 S1: Normal-Transfer Boundary Values

| Test ID | Size (B) | Source | Destination | Backpressure | Error Inject | Expected Result |
|---|---:|---:|---:|---:|---:|---|
| S1-1 | 4 | `0x0000` | `0x0400` | 0% | 0 | Normal completion, matching data |
| S1-2 | 12 | `0x0400` | `0x0C00` | 0% | 0 | Normal completion, repeated 1-beat bursts |
| S1-3 | 16 | `0x0C00` | `0x0000` | 0% | 0 | Normal completion, 4-beat burst |
| S1-4 | 60 | `0x0100` | `0x0500` | 0% | 0 | Normal completion with three 4-beat bursts followed by three 1-beat bursts |
| S1-5 | 64 | `0x0500` | `0x0C00` | 0% | 0 | Normal completion, 16-beat burst |
| S1-6 | 68 | `0x0C00` | `0x0000` | 0% | 0 | Normal completion, 16-beat burst and 1-beat tail |
| S1-7 | 80 | `0x0200` | `0x0600` | 0% | 0 | Normal completion, 16-beat and 4-beat bursts |
| S1-8 | 256 | `0x0600` | `0x0C00` | 0% | 0 | Normal completion, multi-burst |
| S1-9 | 1,024 | `0x0000` | `0x0800` | 0% | 0 | Normal completion, multi-burst |
| S1-10 | 1,028 | `0x0000` | `0x0800` | 0% | 0 | Normal completion, multi-burst and 1-beat tail |
| S1-11 | 2,048 | `0x0000` | `0x0800` | 0% | 0 | Normal completion, maximum non-overlapping transfer |

### 4.2 S2: Size error

| Test ID | Size (B) | Source | Destination | Backpressure | Error Inject | Expected Result |
|---|---:|---:|---:|---:|---:|---|
| S2-1 | 1 | `0x0080` | `0x0380` | 0% | 0 | `error_code=0x2`, error interrupt |
| S2-2 | 2 | `0x0480` | `0x0C80` | 0% | 0 | `error_code=0x2`, error interrupt |
| S2-3 | 3 | `0x0C40` | `0x0040` | 0% | 0 | `error_code=0x2`, error interrupt |
| S2-4 | 15 | `0x0180` | `0x0680` | 0% | 0 | Process 12B, then `error_code=0x2` on the remaining 3B |

### 4.3 S3: W channel backpressure

| Test ID | Size (B) | Source | Destination | Backpressure | Error Inject | Expected Result |
|---|---:|---:|---:|---:|---:|---|
| S3-1 | 4 | `0x0100` | `0x0500` | 10% | 0 | Normal completion, matching data |
| S3-2 | 16 | `0x0500` | `0x0C00` | 10% | 0 | Normal completion, matching data |
| S3-3 | 64 | `0x0C00` | `0x0100` | 10% | 0 | Normal completion, matching data |
| S3-4 | 4 | `0x0100` | `0x0500` | 50% | 0 | Normal completion, matching data |
| S3-5 | 16 | `0x0500` | `0x0C00` | 50% | 0 | Normal completion, matching data |
| S3-6 | 64 | `0x0C00` | `0x0100` | 50% | 0 | Normal completion, matching data |
| S3-7 | 4 | `0x0100` | `0x0500` | 90% | 0 | Normal completion, matching data |
| S3-8 | 16 | `0x0500` | `0x0C00` | 90% | 0 | Normal completion, matching data |
| S3-9 | 64 | `0x0C00` | `0x0100` | 90% | 0 | Normal completion, matching data |

### 4.4 S4: BRESP SLVERR

| Test ID | Size (B) | Source | Destination | Backpressure | Error Inject | Expected Result |
|---|---:|---:|---:|---:|---:|---|
| S4-1 | 64 | `0x0200` | `0x0A00` | 0% | 1 | `error_code=0x3`, error interrupt, matching data |

### 4.5 S5: Combined Backpressure and SLVERR

| Test ID | Size (B) | Source | Destination | Backpressure | Error Inject | Expected Result |
|---|---:|---:|---:|---:|---:|---|
| S5-1 | 4 | `0x0300` | `0x0700` | 10% | 1 | `error_code=0x3`, error interrupt, matching data |
| S5-2 | 16 | `0x0700` | `0x0C00` | 50% | 1 | `error_code=0x3`, error interrupt, matching data |
| S5-3 | 64 | `0x0C00` | `0x0300` | 90% | 1 | `error_code=0x3`, error interrupt, matching data |

### 4.6 S6: Error Recovery

| Test ID | Size (B) | Source | Destination | Backpressure | Error Inject | Expected Result |
|---|---:|---:|---:|---:|---:|---|
| S6-1 | 3 | `0x0100` | `0x0900` | 0% | 0 | Size error, `error_code=0x2` |
| S6-2 | 16 | `0x0200` | `0x0A00` | 0% | 0 | Normal completion after the size error |
| S6-3 | 64 | `0x0300` | `0x0B00` | 0% | 1 | SLVERR, `error_code=0x3` |
| S6-4 | 16 | `0x0400` | `0x0C00` | 0% | 0 | Normal completion after SLVERR |

## 5. Constrained-Random Test Matrix

S7 generates five transactions under the same constraints. Because the directed tests cover the main
boundary values and coverage combinations, S7 serves as a supplemental test of constrained-random
generation and random normal transfers. Five iterations do not claim statistical random-regression
or coverage-closure sufficiency.

The values below are not fixed before execution; the generated values are recorded in the S7 transactions in the simulation log.

| Test ID | Size | Source/Destination | Backpressure | Error Inject | Expected Result |
|---|---|---|---|---:|---|
| S7-1–S7-5 | 4–256B, divisible by 4 | 4-byte aligned, inside 4 KB, non-overlapping | 1–99% | 0 | Normal completion, matching data |

Weights distribute source and destination start addresses across the low/mid/high memory regions,
and apply equal weights to the low (1-30%), medium (31-70%), and high (71-99%) backpressure ranges.

## 6. Expected UVM Errors

Because the existing Driver and Scoreboard reporting behavior is retained, intentional error
transactions also raise `UVM_ERROR`.

| Error Condition | Transactions | UVM Errors per Transaction | Total |
|---|---|---:|---:|
| Size error | S2-1~S2-4, S6-1 | Driver 1 + Scoreboard 2 | 15 |
| BRESP SLVERR | S4-1, S5-1~S5-3, S6-3 | Driver 1 | 5 |
| Total | 10 negative transactions |  | **20** |

The fixed Step 4 test matrix sets `EXPECTED_UVM_ERROR_COUNT=20`. If the number of scenarios or the
negative-test reporting behavior changes, the expected value must be updated accordingly.

## 7. Final Pass Criteria

- Expected and actual UVM error counts both equal 20
- Zero UVM warnings and fatals
- 37 generated and checked transactions
- Zero AXI4 W-channel assertion violations
- 100% coverage for each of the Transaction, FSM, and AXI-event covergroups

When every condition is satisfied, the `dma_test` report phase prints `FINAL TEST RESULT: PASSED`.
Otherwise, it reports `FINAL TEST RESULT: FAILED`.
