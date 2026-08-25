# Verification Plan for an AXI4-Based DMA Controller

## 1. Overview

This document defines the plan for verifying the functionality, error handling, and W-channel
protocol compliance of the AXI4-based `dma_controller`. It expands the directed and
constrained-random tests and performs functional coverage closure using the UVM environment built in
Step 2 and the backpressure and BRESP error-injection capabilities added to the DDR memory model in
Step 3.

Coverage items and sampling criteria are defined in [`COVERAGE_PLAN.md`](./COVERAGE_PLAN.md).
AXI4 W-channel assertions and their pass criteria are defined in
[`ASSERTION_SET.md`](./ASSERTION_SET.md). Stimulus matrices and expected results for each scenario are
defined in [`TEST_PLAN.md`](./TEST_PLAN.md).

## 2. Verification Objectives

- Confirm that source data is copied correctly to the destination between 4-byte-aligned addresses
- Confirm that 1-, 4-, and 16-beat bursts are selected according to the remaining transfer size and
  that multi-burst transfers and the final tail burst are handled correctly
- Confirm that transfers complete without data loss, duplication, or reordering under W-channel backpressure
- Confirm that unsupported transfer sizes and `BRESP=SLVERR` are handled through their defined error states
- Confirm that the next DMA transaction can execute normally after error handling
- Use assertions to verify AXI4 W-channel VALID/READY handshaking, payload stability during
  backpressure, and WLAST timing on the final beat
- Hit every planned functional coverage bin and cross and record the reason for any uncovered item

## 3. Verification Scope

### 3.1 Verification Targets

| Category | Target | Verification |
|---|---|---|
| DUT | `dma_controller` | MMIO configuration, AXI4 read/write bursts, FIFO forwarding, completion/error state, and interrupts |
| AXI4 W channel | `WVALID`, `WREADY`, `WDATA`, `WSTRB`, `WLAST` | Protocol compliance and data stability under backpressure |
| AXI4 B channel | `BVALID`, `BREADY`, `BRESP` | OKAY completion and SLVERR handling |
| Verification slave | `ddr_memory_model` | Random WREADY backpressure and BRESP SLVERR generation |

### 3.2 Verification Conditions

- Addresses are restricted to 4-byte alignment.
- Source and destination regions must lie within the 4 KB memory and must not overlap.
- Transfer sizes are limited to 1–2,048 bytes in consideration of the memory range and non-overlap condition.
- Normal-completion scenarios use transfer sizes divisible by 4 bytes.
- Sizes of 1–3 bytes and sizes not divisible by 4 bytes are used only to verify the size-error path.
- `enable=1`, `start=1`, and `irq_en=1` are the default Step 4 control conditions.

### 3.3 Exclusions

The following items are outside the support range of the current DUT or memory model or are not part
of this project's verification objectives, so they are excluded from Step 4 coverage closure.

- 4-byte-unaligned addresses, sub-word transfers, and overlapping source/destination regions
- Accesses outside the 4 KB memory and non-overlapping transfers larger than 2,048 bytes
- Multiple outstanding transactions and out-of-order responses
- AXI4 AR/R/AW-channel backpressure and `RRESP` error injection
- EXOKAY and DECERR `BRESP` responses
- Verification of `enable=0`, `start=0`, `irq_en=0`, and AXI ID combinations
- Combination verification for the fixed `AxSIZE`, `AxBURST`, and `WSTRB` values
- Throughput measurement and performance optimization based on the actual transfer interval

Coverage-related exclusions are documented in the coverage plan instead of being left as uncovered bins.

## 4. Verification Strategy

### 4.1 Stimulus

- Use directed tests first to verify burst boundaries, size errors, backpressure, SLVERR, error
  recovery, and the main coverage bins
- Generate five constrained-random transactions in S7 to further check alignment, range, non-overlap
  constraints, and random normal-transfer combinations
- Use S7 as a supplemental test rather than the primary means of statistical random regression or coverage closure
- Record the actual S7 transaction values in the simulation log

### 4.2 Result Evaluation

| Result Type | Expected Result |
|---|---|
| Normal transfer | `done=1`, `error=0`, `error_code=0x0`, and matching source/destination data |
| Size error | `done=0`, `error=1`, `error_code=0x2`, error interrupt, and observed `S_SETUP → S_ERROR` |
| BRESP SLVERR | `done=0`, `error=1`, `error_code=0x3`, error interrupt, and observed `S_WR_RESP → S_ERROR` |
| Error recovery | After a transfer ends in error, the next valid transfer completes successfully |

The existing Driver reports the DUT error status with `uvm_error`, and the Scoreboard compares the
entire requested source and destination regions regardless of error type. Step 4 does not change this
behavior. Normal transfers are therefore evaluated using the UVM result and data comparison. For
negative tests that intentionally cause errors, entry into the error path is confirmed using the
`error_code`, interrupt, FSM transition, and functional coverage. Expected UVM errors and Scoreboard
results from negative tests are recorded separately for each scenario in the simulation log.

The Driver reads `bytes_done` and prints it as an informational `UVM_HIGH` message, but it does not
automatically compare it with the requested `size`; it is therefore excluded from PASS/FAIL criteria.

### 4.3 Verification and Evaluation Components

- Driver evaluation: after MMIO configuration, check normal/error termination in STATUS and timeout;
  read `bytes_done` only for an informational `UVM_HIGH` message
- Monitor collection: collect a transaction from the MMIO configuration and completion/error
  interrupt and forward it to the Scoreboard
- Scoreboard evaluation: compare source and destination data across the complete requested size and
  check that the generated and processed transaction counts match
- AXI4 assertions:
  - Hold `WVALID` while `WVALID && !WREADY`
  - Hold `WDATA`, `WSTRB`, and `WLAST` while `WVALID && !WREADY`
  - At `WVALID && WREADY`, match `WLAST` with the final beat indicated by `AWLEN`

## 5. Test Scenarios

The transfer size, address, backpressure, and error-injection values for each scenario are defined in
[`TEST_PLAN.md`](./TEST_PLAN.md).

| ID | Scenario | Main Conditions | Evaluation Items |
|---|---|---|---|
| S1 | Normal-transfer boundaries | 4, 12, 16, 60, 64, 68, 80, 256, 1,024, 1,028, and 2,048B | Basic transfer, burst selection, tail burst, and complete data match |
| S2 | Size error | 1, 2, 3, and 15B | `S_SETUP → S_ERROR`, `error_code=0x2`, and expected error reports from the negative test |
| S3 | W backpressure | Combinations of 1-, 4-, and 16-beat bursts with 10%, 50%, and 90% | Payload stability during stalls, data match, and normal completion |
| S4 | BRESP error injection | Valid size, no backpressure, SLVERR injection | `S_WR_RESP → S_ERROR`, `error_code=0x3`, and expected error reports from the negative test |
| S5 | Backpressure + SLVERR | Valid size, backpressure enabled, SLVERR injection | Stable W transfer, B-response error path, and expected error reports from the negative test |
| S6 | Error recovery | Normal transfer immediately after a size error or SLVERR | `S_ERROR → S_IDLE` and subsequent normal completion |
| S7 | Constrained random | Five transfers with aligned, non-overlapping source and destination regions, randomized transfer sizes, and randomized backpressure probabilities | Additional constraint-based normal-transfer combinations and data matches |

Source and destination addresses for the complete test set are distributed across the low, middle,
and high regions of the 4 KB memory.

## 6. Verification Traceability Matrix

| ID | Verification Item | Stimulus | Checker | Coverage |
|---|---|---|---|---|
| V-01 | Normal data copy | S1, S7 | Scoreboard and normal STATUS completion | C-TX-01·02·04·05·08 |
| V-02 | Burst boundaries and multi-burst | S1 | Scoreboard, WLAST assertion, and coverage analysis | C-FSM-02·03·04, C-AXI-01·05 |
| V-03 | Size-error handling | S2 | STATUS, interrupt, and expected error reports | C-TX-01·03·08, X-TX-01, C-FSM-02·03 |
| V-04 | Backpressure tolerance | S3, S7 | Scoreboard and W assertions | C-TX-06, C-AXI-02·03·04, X-AXI-01 |
| V-05 | BRESP SLVERR handling | S4 | STATUS, interrupt, and expected error reports | C-TX-07·08, X-TX-02, C-FSM-02, C-AXI-06·07, X-AXI-02 |
| V-06 | Backpressure with SLVERR | S5 | Expected error reports, Scoreboard, and W assertions | C-TX-06·07·08, X-TX-03, C-AXI-03·04·06 |
| V-07 | Recovery after an error | S6 | Normal completion of subsequent transaction | C-FSM-02 |
| V-08 | AXI4 W-channel protocol | S1, S3, S5, S7 | Assertion checker | C-AXI-03·04·05 |

## 7. Completion Criteria

- Complete every planned directed test and all five constrained-random tests
- Zero Scoreboard mismatches and X/Z detections in normal-transfer scenarios
- Record expected UVM errors and Scoreboard results from negative tests by scenario
- Zero unexpected UVM warnings/errors/fatals and timeouts
- Match the expected and checked transaction counts
- Zero AXI4 assertion violations
- Achieve 100% of the reachable coverpoints and crosses defined in [`COVERAGE_PLAN.md`](./COVERAGE_PLAN.md)
- Document the reason and follow-up action for every uncovered or excluded item
