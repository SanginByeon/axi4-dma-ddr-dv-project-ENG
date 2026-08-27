# AXI4-Based DMA–DDR Memory Model System Verification Enhancement Project

Starting from a course-provided AXI4 DMA design, I split the baseline into separate modules and built
a UVM testbench with randomized W-channel backpressure, BRESP error injection, functional coverage,
assertions, and multi-seed regression.

The project ultimately achieved 100% closure across all three functional coverage groups in Step 4
and confirmed matching data for 25,560 words with zero AXI4 W assertion violations across the
10-seed, 360-transaction regression in Step 5.

## Project Scope and Code Source

The baseline files preserve the design and test logic supplied with the course. This edition
translates the source comments, project documentation, and commit messages into English.

- Code source:
[Fast Campus, SamCoach's Semiconductor Practice Roadmap: Design · Verification · Layout · AI Semiconductor](https://fastcampus.co.kr/data_online_samcoach2)

The scope of this project is as follows.

- Separate the AXI4 interface, DMA controller, and DDR memory model defined together in `design.sv` into role-specific files
- Rebuild the task-based testbench as a UVM sequence- and transaction-based verification environment
- Add AXI4 W-channel random backpressure and BRESP SLVERR injection to the verification DDR memory model
- Build a scoreboard that checks source/destination data integrity, X/Z values, and transaction counts
- Enhance the functional coverage model based on transactions, the DMA FSM, and AXI events
- Implement an SVA-based assertion checker for AXI4 W-channel protocol verification
- Analyze and fix DUT bugs found through backpressure, error-response, and coverage analysis
- Perform functional coverage closure and regression using 10 seeds
- Document the verification plan, debugging process, waveforms, and simulation results for each step

The structure and operation of the baseline system are described in
[`BASELINE_SYSTEM_ANALYSIS.md`](baseline/BASELINE_SYSTEM_ANALYSIS.md).

## System and Verification Architecture

The DMA controller uses the source address, destination address, and transfer size configured through
MMIO to copy data with AXI4 read/write transactions. The DDR memory model is an AXI4 slave used to
verify the DUT and provides 4 KB of memory along with controllable W-channel backpressure and BRESP
error responses.

### System Architecture

```text
                  dma_test / dma_regression_test
                                │
                                ▼
                Sequence ─► Sequencer
                                │
                                ▼
                              Driver
                                │
              ┌─────────────────┴────────────────┐
              │                                  │
              │ mmio_if                          │ ddr_model_if
              │ Configure SRC/DST/SIZE/CTRL      │ Configure Backpressure/SLVERR
              ▼                                  ▼
     ┌────────────────────┐       AXI4        ┌─────────────────────┐
     │ DMA Controller     │ ◄───────────────► │ DDR Memory Model    │
     │       DUT          │    AR/R/AW/W/B    │ 4 KB mem[]          │
     └─────────┬──────────┘                   └─┬────────┬──────────┘
               │                                │        ▲
               │ mmio_if           ddr_model_if │        │
               │                                │        │
               ├────────────────────────────────┘        │
               │                                         │
               ▼                                         │
            Monitor ◄── Observe mmio_if / ddr_model_if    │
               │        SRC/DST/SIZE/CTRL                │
               │        done/error interrupt             │
               │        Backpressure/SLVERR              │
               │                                         │
               │ Collected DMA transaction               │
               ▼                                         │
           Scoreboard ─────── backdoor read ─────────────┘
               │
               └─ Compare source data with destination data

     AXI4 W signals ─────────► SVA Assertion Checker
     Transaction/FSM/AXI ────► Functional Coverage
```

### Verification Flow

```text
[1] Select Test
    dma_test
      └─ Run the Step 4 S1–S7 functional verification scenarios

    dma_regression_test
      └─ Run 36 backpressure transactions for each Step 5 seed
                           │
                           ▼
[2] Generate Transaction
    Sequence generates SRC / DST / SIZE / CTRL / backpressure conditions
                           │
                           ├─ Generate data_payload pattern
                           └─ Preload source memory through utility_pkg
                           │
                           ▼
[3] Configure DUT and DDR Memory Model
    Sequencer → Driver
              ├─ Configure DMA SRC / DST / SIZE / CTRL registers through mmio_if
              └─ Configure backpressure probability / error injection through ddr_model_if
                           │
                           ▼
[4] DMA Transfer
    DMA Controller
       ├─ AXI4 AR/R   : Read source memory
       ├─ FIFO        : Buffer read data
       └─ AXI4 AW/W/B : Write destination memory and check response
                           │
                           ▼
[5] DDR Memory Model Response
    DDR Memory Model
       ├─ Randomly deassert WREADY according to the configured probability
       ├─ Store valid write data in mem[]
       └─ Return BRESP OKAY or SLVERR according to the configuration
                           │
                           ▼
[6] Observe Completion
    DMA Controller
       ├─ Normal completion → dma_done_int
       └─ Error occurrence  → dma_error_int

    Monitor reconstructs the transaction from the MMIO configuration and interrupt
                           │
                           ▼
[7] Check Data Integrity
    Monitor → Scoreboard
              ├─ Backdoor read data at source address      : expected
              ├─ Backdoor read data at destination address : actual
              ├─ Compare expected and actual across the complete transfer range
              ├─ Detect X/Z data
              └─ Compare expected and collected transaction counts
                           │
                           ▼
[8] Parallel Verification
    SVA Assertion Checker
       └─ Check W payload / WVALID / WLAST protocol conditions

    Functional Coverage
       └─ Measure Transaction / DMA FSM / AXI events
                           │
                           ▼
[9] Final Decision
    UVM error / warning / fatal
    + Scoreboard transaction count
    + AXI assertion violation
    + Functional coverage or regression result
                           │
                           ▼
                      PASS / FAIL
```

## Verification Enhancement Process

| Step | Main Work | Result | Document |
|---|---|---|---|
| Baseline | Preserve the course-provided code and initial results | Functional coverage 64.80% | [System Analysis](baseline/BASELINE_SYSTEM_ANALYSIS.md) |
| Step 1 | Separate code by design, interface, and testbench roles | Reproduced baseline behavior and coverage | [Code Structure Separation](docs/steps/STEP1_CODE_REFACTORING.md) |
| Step 2 | Build UVM Driver, Monitor, Scoreboard, Agent, and Environment | 4 transactions, 340 matching words | [UVM Environment Construction](docs/steps/STEP2_UVM_VERIFICATION_ENVIRONMENT.md) |
| Step 3 | Inject random WREADY backpressure and BRESP SLVERR | Reproduced and fixed DUT issues; all 340 words matched | [Backpressure and Error Injection](docs/steps/STEP3_BACKPRESSURE_ERROR_INJECTION.md) |
| Step 4 | Functional verification with seven scenarios, coverage-model enhancement, and assertion-checker implementation | 37/37 transactions, all three covergroups at 100% | [Scenario Expansion and Coverage Closure](docs/steps/STEP4_SCENARIO_EXPANSION_AND_COVERAGE_CLOSURE.md) |
| Step 5 | Backpressure regression with 10 seeds | 360/360 transactions, 25,560 matching words | [Multi-Seed Regression](docs/steps/STEP5_REGRESSION.md) |

The coverage results through Step 3 and those from Step 4 use different coverage models, so their
percentages are not compared directly. Step 4 used a new coverage model and reached closure when all
targeted, reachable coverpoint and cross bins had been hit.

## Key Verification Items

- Data integrity for 1-, 4-, and 16-beat bursts and multi-burst/tail transfers
- `error_code=0x2` handling for transfer sizes smaller than 4 bytes or not divisible by 4 bytes
- Handshake and payload stability under low, medium, and high W-channel backpressure
- BRESP SLVERR `error_code=0x3`, error interrupt, and recovery to a normal transfer after an error
- Source/destination memory regions and non-overlapping address constraints
- Functional coverage of DMA FSM states/transitions, transaction conditions, and actual AXI events
- Assertions for W-payload stability during a stall, WVALID persistence, and WLAST timing on the final beat
- Repeated verification of random stall timing across 10 different seeds

The verification plans and implementation items are defined in the following documents.

| Document | Description |
|---|---|
| [Verification Plan](docs/VERIFICATION_PLAN.md) | Verification objectives, target, scope, and result criteria |
| [Test Plan](docs/TEST_PLAN.md) | Transaction matrix for each S1–S7 sequence |
| [Coverage Plan](docs/COVERAGE_PLAN.md) | Coverpoint and cross definitions and coverage goals |
| [Assertion Set](docs/ASSERTION_SET.md) | AXI4 W-channel A-01–A-03 assertion definitions |
| [Regression Plan](docs/REGRESSION_PLAN.md) | Seed, backpressure, and transfer-size matrix and result criteria |

## DUT Debugging Cases

| Case | Observed Behavior | Cause and Fix | Detailed Document |
|---|---|---|---|
| W-channel data mismatch | Source and destination differed under backpressure | Changed the DUT payload-update condition from WVALID-only to handshake-based and removed unnecessary FIFO prefetch | [W-Channel Data Mismatch](docs/debug/AXI4_W_CHANNEL_DATA_MISMATCH_DEBUGGING.md) |
| BRESP error-state transition | When BRESP indicated SLVERR, the FSM entered `S_DONE` instead of `S_ERROR` | Removed the reference to stale `stat.error` and checked the response directly at the current BRESP handshake | [BRESP Error Path](docs/debug/AXI4_BRESP_ERROR_PATH_DEBUGGING.md) |
| WLAST timing | WLAST asserted after the final data of a four-beat burst | Computed WLAST for the next data beat as the DUT loaded WDATA | [WLAST Timing](docs/debug/AXI4_WLAST_TIMING_DEBUGGING.md) |

For each case, the repository preserves the reproduction log, before-and-after waveforms, source code
showing the cause, and re-verification results.

## Final Verification Results

| Item | Result |
|---|---:|
| Step 4 sequences / transactions | 7 / 37 |
| Step 4 expected / actual UVM errors | 20 / 20 |
| Transaction coverage | 100.00% |
| DMA FSM coverage | 100.00% |
| AXI event coverage | 100.00% |
| AXI4 W assertion violations | 0 |
| Regression seeds | 10/10 PASS |
| Regression transactions | 360/360 PASS |
| Regression data comparison | 25,560 matching words |
| Regression UVM warning/error/fatal | 0/0/0 |

Step 4 passed with 20 expected UVM error reports, zero warnings or fatals, 37 checked transactions,
zero W-channel assertion violations, and 100% reported coverage in all three covergroups. Step 5
repeatedly runs only normal backpressure transfers, so every seed passes without a UVM error.

- Step 4 result: [`step4_simulation.log`](runs/step4_simulation.log)
- Step 5 result: [`runs/regression`](runs/regression)

## Running the Verification

### Environment

- Simulator: Synopsys VCS 2025.06
- Verification methodology: UVM 1.2
- Target environment: EDA Playground

In EDA Playground, use [`design.sv`](design.sv) and [`dv/testbench.sv`](dv/testbench.sv) as the
top-level source files for design and testbench compilation, respectively, and add the repository's
included sources to their respective panes.

Compile options:

```text
-timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog -debug_access+all
```

Run the comprehensive Step 4 verification without Run options. If `UVM_TESTNAME` is absent,
`testbench.sv` runs `dma_test` by default.

For the Step 5 regression, use the following Run options for each seed.

```text
+UVM_TESTNAME=dma_regression_test +ntb_random_seed=1001
```

Change the seed from `1001` through `1010` and run the simulation 10 times. The results are preserved
as seed-specific logs in [`runs/regression`](runs/regression).

## Repository Structure

```text
.
├── .gitattributes
├── README.md
├── design.sv
│
├── baseline/                              # Course-provided source, system analysis, and initial run result
│   ├── design.sv
│   ├── testbench.sv
│   ├── BASELINE_SYSTEM_ANALYSIS.md
│   └── baseline_simulation.log
│
├── rtl/                                   # DMA controller DUT
│   └── dma_controller.sv
│
├── interface/                             # AXI4, MMIO, and DDR memory-model control interfaces
│   ├── axi4_if.sv
│   ├── mmio_if.sv
│   └── ddr_model_if.sv
│
├── dv/                                    # DDR model, coverage, testbench, and UVM verification environment
│   ├── coverage.sv
│   ├── ddr_memory_model.sv
│   ├── testbench.sv
│   ├── utility_pkg.sv
│   │
│   ├── checkers/                          # AXI4 W-channel SVA checker
│   │   └── axi_checker.sv
│   │
│   └── uvm/                               # Transaction, UVM components, and tests
│       ├── dma_tx.sv
│       ├── dma_driver.sv
│       ├── dma_monitor.sv
│       ├── dma_scoreboard.sv
│       ├── dma_agent.sv
│       ├── dma_env.sv
│       ├── dma_test.sv
│       │
│       ├── sequences/                     # Step 4 functional-verification sequences
│       │   ├── dma_base_seq.sv
│       │   ├── dma_s1_boundary_seq.sv
│       │   ├── dma_s2_size_error_seq.sv
│       │   ├── dma_s3_backpressure_seq.sv
│       │   ├── dma_s4_slverr_seq.sv
│       │   ├── dma_s5_backpressure_slverr_seq.sv
│       │   ├── dma_s6_error_recovery_seq.sv
│       │   └── dma_s7_random_seq.sv
│       │
│       └── regression/                    # Step 5 multi-seed regression components
│           ├── dma_regression_seq.sv
│           └── dma_regression_test.sv
│
├── docs/                                  # Verification, test, coverage, assertion, and regression documents
│   ├── VERIFICATION_PLAN.md
│   ├── TEST_PLAN.md
│   ├── COVERAGE_PLAN.md
│   ├── ASSERTION_SET.md
│   ├── REGRESSION_PLAN.md
│   │
│   ├── steps/                             # Changes and run results for each project step
│   │   ├── STEP1_CODE_REFACTORING.md
│   │   ├── STEP2_UVM_VERIFICATION_ENVIRONMENT.md
│   │   ├── STEP3_BACKPRESSURE_ERROR_INJECTION.md
│   │   ├── STEP4_SCENARIO_EXPANSION_AND_COVERAGE_CLOSURE.md
│   │   └── STEP5_REGRESSION.md
│   │
│   ├── debug/                             # DUT bug reproduction, cause, fix, and re-verification records
│   │   ├── AXI4_W_CHANNEL_DATA_MISMATCH_DEBUGGING.md
│   │   ├── AXI4_BRESP_ERROR_PATH_DEBUGGING.md
│   │   └── AXI4_WLAST_TIMING_DEBUGGING.md
│   │
│   └── images/                            # Debugging waveforms
│       ├── step3/                         # W-payload, FIFO-prefetch, and BRESP debugging waveforms
│       │   ├── axi_w_payload_stability_violation.png
│       │   ├── axi_w_payload_fixed.png
│       │   ├── axi_w_payload_prefetch_fixed.png
│       │   ├── bresp_error_path_failure.png
│       │   └── bresp_error_path_fixed.png
│       └── step4/                         # WLAST-timing debugging waveforms
│           ├── wlast_timing_failure.png
│           └── wlast_timing_fixed.png
│
└── runs/                                  # VCS run logs for each project step
    ├── step1_simulation.log
    ├── step2_simulation.log
    ├── step3_simulation.log
    ├── step4_simulation.log
    │
    ├── debug/                             # DUT bug and coverage-gap reproduction logs
    │   ├── step3_w_payload_failure.log
    │   ├── step3_bresp_error_path_failure.log
    │   └── step4_wlast_coverage_gap.log
    │
    └── regression/                        # Step 5 regression-result logs
        ├── step5_seed_1001.log
        ├── step5_seed_1002.log
        ├── step5_seed_1003.log
        ├── step5_seed_1004.log
        ├── step5_seed_1005.log
        ├── step5_seed_1006.log
        ├── step5_seed_1007.log
        ├── step5_seed_1008.log
        ├── step5_seed_1009.log
        └── step5_seed_1010.log
```

## Verification Scope and Limitations

- The baseline DDR memory model implements 4 KB of memory, so the verification address range is limited accordingly.
- Verification focuses on the 4-byte-aligned, 32-bit word transfers supported by the DUT.
- Random backpressure is applied to the AXI4 W channel, and error injection is limited to BRESP SLVERR.
- A-01–A-03 check the W-channel protocol items emphasized in this project and do not imply complete
  AXI4 protocol compliance.
- Functional coverage of 100% means that all targeted, reachable coverpoint and cross bins defined by
  this project were hit; it does not mean exhaustive exploration of every input combination.
- The existing throughput calculation in the simulation logs does not reflect the actual transaction
  configuration and is therefore not used as a performance result. Throughput measurement is outside
  the project scope.
