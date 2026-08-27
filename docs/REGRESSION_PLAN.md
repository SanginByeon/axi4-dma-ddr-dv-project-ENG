# DMA Backpressure Regression Plan

## 1. Overview

This document defines the Step 5 regression plan used after Step 4 exercised the planned functional
scenarios and met the functional coverage targets. It checks that the DMA controller continues to
operate reliably under repeated AXI4 W-channel backpressure.

Step 5 does not repeat every Step 4 scenario. Instead, it runs a dedicated regression sequence scoped
to normal transfers under backpressure. Its purpose is not to gain additional functional coverage,
but to detect intermittent data mismatches, timeouts, and AXI4 protocol violations that may occur
during repeated execution.

## 2. Objective

Confirm that the functionally verified DUT continues to operate normally without data loss, timeout,
or AXI4 protocol violations under different backpressure timing and repeated-transfer conditions.

## 3. Regression Scope

### 3.1 Verification Items

- Confirm that source data is copied correctly to the destination despite changes in backpressure probability and timing
- Check for missing, duplicated, or reordered data across repeated transfers and for effects of state
  retained from a previous transaction
- Confirm that 1-, 4-, 16-beat, and multi-burst transfers complete without timeout under heavy backpressure
- Confirm W-channel payload stability during stalls, WVALID persistence, and correct WLAST timing
- Exercise the DUT fixes related to W payload, FIFO prefetch, and WLAST at each of the six planned
  transfer sizes

### 3.2 Exclusions

- Repeated verification of size-error and BRESP SLVERR paths
- Re-execution of functional coverage closure
- Throughput measurement and performance comparison

Step 4 tested size errors and BRESP SLVERR responses and met the functional coverage targets. These
items are therefore not repeated in Step 5.

## 4. Common Configuration

- `enable=1`, `start=1`, `irq=1`
- `error_inject=0`
- Source address: `0x0000`
- Destination address: `0x0800`
- Source and destination are 4-byte aligned and non-overlapping within the 4 KB memory
- Initialize source memory with a verification data pattern before each transaction
- Disable internal DUT progress logs and use `UVM_MEDIUM` verbosity
- Use the specified seed for each run and record it in the result log

With the destination at `0x0800`, even the maximum 1,028-byte transfer keeps the source region
`0x0000–0x0403` separate from the destination region `0x0800–0x0C03`.

## 5. Regression Matrix

For each backpressure probability, every seed runs the following six transfer sizes in order.

| Transfer Size | Main Condition |
|---:|---|
| 4B | 1-beat burst |
| 16B | 4-beat burst |
| 64B | 16-beat burst |
| 80B | 16-beat + 4-beat bursts |
| 512B | Multi-burst |
| 1,028B | Multi-burst + 1-beat tail |

The following 10 seeds are used. Each seed runs every combination of backpressure probability and
transfer size once.

```text
1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010
```

| Backpressure Probability | Seeds | Transactions per Seed | Total |
|---:|---:|---:|---:|
| 0% | 10 | 6 | 60 |
| 10% | 10 | 6 | 60 |
| 30% | 10 | 6 | 60 |
| 50% | 10 | 6 | 60 |
| 70% | 10 | 6 | 60 |
| 90% | 10 | 6 | 60 |
| **Overall** | **10** | **36** | **360** |

One seed executes 36 transactions representing every combination of six backpressure probabilities
and six transfer sizes. The complete Step 5 regression consists of 10 simulations and 360 DMA
transactions.

## 6. Execution Structure

The regression runs 10 independent VCS simulations, one for each seed. Each simulation configures the
applicable seed and executes 36 transactions sequentially.

Specify the regression test and numeric seed together in the EDA Playground Run Options.

```text
+UVM_TESTNAME=dma_regression_test +ntb_random_seed=1001
```

After each run, change the seed from `1002` through `1010` and execute the same regression test again.
Without `+UVM_TESTNAME`, the existing Step 4 `dma_test` runs by default.

```systemverilog
foreach (backpressure_probs[p]) begin
    foreach (size_bytes[s]) begin
        // Generate and execute a DMA transaction
    end
end
```

The DDR memory model randomly decides whether to apply backpressure on every cycle during a write
burst. Different seeds produce different random sequences, enabling different stall timing to be
verified at the same backpressure probability. Reusing a failing seed reproduces the same condition.

Each transaction's scenario name records its seed, backpressure probability, and transfer size.

```text
[REGR-SEED1001-P90-S1028] Backpressure Regression
```

## 7. Implementation

The following dedicated regression sequence and test are added.

| File | Role |
|---|---|
| `dma_regression_seq.sv` | Generate 36 transactions from the backpressure-probability and transfer-size matrix for one seed |
| `dma_regression_test.sv` | Run the regression sequence and evaluate each seed from transaction, UVM error, and AXI checker results |

The existing `dma_tx`, Driver, Monitor, Scoreboard, Agent, Environment, and AXI checker are reused
without modification. The Step 4 S1–S7 sequences and `TEST_PLAN.md` are also preserved as the existing
verification record.

## 8. Pass Criteria

Each seed passes when its simulation satisfies all of the following conditions.

- Expected/checked transactions: `36 / 36`
- UVM warning/error/fatal: all zero
- Scoreboard data mismatches and X/Z detections: zero
- DMA timeouts: zero
- AXI4 W-channel A-01–A-03 assertion violations: zero
- Completion of all six transfer sizes at every backpressure probability

The complete Step 5 regression passes when all 10 seeds pass and the overall expected/checked
transaction count is `360 / 360`. If any seed fails, the regression fails and that seed is reused to
reproduce the failure condition.

Functional coverage results are not used in the final Step 5 decision. Coverage closure was completed
in Step 4; Step 5 evaluates functional and protocol stability under repeated execution.

## 9. Preserved Results

- Per-seed regression log: `runs/regression/step5_seed_<seed>.log`
- Step 5 result document: `docs/steps/STEP5_REGRESSION.md`
- If a failure occurs, add its reproduction log and analysis waveform under `runs/debug` and `docs/images/step5`

The logs for all 10 successful seeds are preserved as evidence. Waveforms are stored only when a data
mismatch, timeout, or assertion violation requires additional analysis.
