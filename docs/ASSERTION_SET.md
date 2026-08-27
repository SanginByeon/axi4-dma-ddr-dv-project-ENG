# AXI4 W-Channel Assertion Set

## 1. Overview

This document defines the assertion items and pass/fail criteria for the DMA controller's AXI4 W
channel. The checker verifies that `WVALID` stays asserted and that `WDATA`, `WSTRB`, and `WLAST`
remain stable after a stalled cycle. It also checks `WLAST` on every accepted write beat. The checker
observes the AXI4 interface between the DUT and the DDR memory model without affecting DUT behavior.

## 2. Verification Scope

- Sampling clock: rising edge of `axi.aclk`
- Reset condition: assertions are disabled while `axi.aresetn=0`
- Verification target: AXI4 W-channel `WVALID`, `WREADY`, `WDATA`, `WSTRB`, and `WLAST`; burst
  information `AWLEN`; and DUT signal `w_beats_sent`
- Implementation file: [`axi_checker.sv`](../dv/checkers/axi_checker.sv)
- Checker instance: `tb.axi_w_checker`

## 3. Assertion Items

| ID | Property | Condition | Verification | Violation Counter |
|---|---|---|---|---|
| A-01 | `p_w_payload_stable_on_stall` | `WVALID && !WREADY` | Confirm that `WDATA`, `WSTRB`, and `WLAST` remain stable through the next cycle | `vio_w_payload_stable_on_stall` |
| A-02 | `p_wvalid_hold` | `WVALID && !WREADY` | Confirm that `WVALID=1` is maintained in the next cycle | `vio_wvalid_hold` |
| A-03 | `p_wlast_timing` | `WVALID && WREADY` | Detect a missing WLAST on the final beat or an incorrectly asserted WLAST before the final beat | `vio_wlast_timing` |

`p_wlast_timing` checks that `WLAST=1` on the final beat and that `WLAST=0` on every non-final
handshake. It therefore detects both a missing WLAST on the final beat and an incorrectly asserted
WLAST before the final beat with a single property.

When an assertion fails, it raises `$error` and increments both the corresponding violation counter
and the aggregate `vio_total` counter. The report phases of `dma_test` and `dma_regression_test` print
the count for each assertion and the final PASS/FAIL result.

## 4. Pass Criteria

- `vio_w_payload_stable_on_stall=0`
- `vio_wvalid_hold=0`
- `vio_wlast_timing=0`
- `vio_total=0`

The AXI4 W-channel checker passes when every counter is zero. If one or more violations occur, analyze
the assertion error together with the report result to determine the cause.
