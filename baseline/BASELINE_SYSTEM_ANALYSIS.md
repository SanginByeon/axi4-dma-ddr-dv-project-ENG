# Baseline System Analysis for an AXI4-Based DMA–DDR Memory Model

## 1. Overview

This document describes the structure and operation of the baseline system composed of `design.sv`
and `testbench.sv`.

### System Summary

This memory-copy environment connects the DUT `dma_controller`, an AXI4 master, to the verification
memory model `ddr_controller`, an AXI4 slave. The testbench configures the DUT through MMIO and checks
the transfer status and results.

### Code Source

- Fast Campus, SamCoach's Semiconductor Practice Roadmap: Design · Verification · Layout · AI Semiconductor
- <https://fastcampus.co.kr/data_online_samcoach2>

### Terminology

The verification environment's `ddr_controller` is not actual DDR control logic or a PHY; it is a
**DDR memory model (AXI4 slave)**. **DDR Controller** in this document refers to this memory model.

---

## 2. System Components

| Category | Component | Role |
| --- | --- | --- |
| DUT | `dma_controller` | Perform AXI4 read/write transactions from the MMIO-configured SRC, DST, and SIZE values to copy data from the source address to the destination address |
| Interface | `axi4_if` | Define the AXI4 signals and modports between the DUT and memory model |
| Verification memory model | `ddr_controller` | Respond to DUT read/write requests as an AXI4 slave |
| Verification environment | `tb` | Generate clock/reset, run test scenarios, check results, and measure functional coverage |

---

## 3. System Architecture

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        Testbench Environment                           │
│                                                                        │
│ ┌────────────────────────┐         MMIO          ┌─────────────────┐   │
│ │ Software Tasks         │◄─────────────────────►│ dma_controller  │   │
│ │                        │  ┌─────────────────┐  │      (DUT)      │   │
│ │ • write_dma_reg        │  │  Register Map   │  │ ┌─────────────┐ │   │
│ │ • read_dma_reg         │  │                 │  │ │    FSM      │ │   │
│ │ • wait_dma_completion  │  │ 0x00: CTRL      │  │ │   Engine    │ │   │
│ │ • verify_data_integrity│  │ 0x04: STAT      │  │ │ IDLE→SETUP  │ │   │
│ └────────────────────────┘  │ 0x08: SRC       │  │ │ →RD→WR→DONE │ │   │
│             │               │ 0x0C: DST       │  │ └─────────────┘ │   │
│             │               │ 0x10: SIZE      │  │                 │   │
│             │               │ 0x14: BYTES     │  │ ┌─────────────┐ │   │
│             │               └─────────────────┘  │ │   16-deep   │ │   │
│             │                                    │ │    FIFO     │ │   │
│             │                                    │ │   Buffer    │ │   │
│             │                                    │ └─────────────┘ │   │
│             │                                    └─────────────────┘   │
│             │                                             │            │
│             │                 AXI4 Interface              │            │
│             │         ┌─────────────────────────────┐     │            │
│             │         │ Write Addr (AW) Channel     │     │            │
│             │         │ Write Data (W) Channel      │     │            │
│             │         │ Write Resp (B) Channel      │     │            │
│             │         │ Read Addr (AR) Channel      │     │            │
│             │         │ Read Data (R) Channel       │     │            │
│             │         └─────────────────────────────┘     │            │
│             │                                             │            │
│             │                                             ▼            │
│             ▼                                    ┌─────────────────┐   │
│ ┌──────────────────────────────────────┐         │ ddr_controller  │   │
│ │      Functional Coverage Model       │         │ (Memory Model)  │   │
│ │                                      │         │ ┌─────────────┐ │   │
│ │ • cp_size                            │         │ │   Memory    │ │   │
│ │ • cp_dma_state/cp_state_transitions  │         │ │   Array     │ │   │
│ │ • cp_src_alignment/cp_dst_alignment  │         │ │  [0:1023]   │ │   │
│ │ • cp_burst_len                       │         │ │             │ │   │
│ │ • cx_size_alignment                  │         │ │  4KB Model  │ │   │
│ └──────────────────────────────────────┘         │ └─────────────┘ │   │
│                                                  │ ┌─────────────┐ │   │
│                                                  │ │   Latency   │ │   │
│                                                  │ │    Model    │ │   │
│                                                  │ │  (3 cycles) │ │   │
│                                                  │ └─────────────┘ │   │
│                                                  └─────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

## 4. Data Flow

```text
[Phase 1: Configuration]
Software → MMIO → DMA Registers
   ↓
SRC_ADDR = 0x00000000
DST_ADDR = 0x00000400
SIZE = 256 bytes
CTRL = enable | start | irq_en
─────────────────────────────────────────
[Phase 2: Read Burst]
DMA → AXI AR Channel → DDR
   ↓
DDR → AXI R Channel → DMA FIFO
   ↓
FIFO[0] = 0xCAFE0000
FIFO[1] = 0xCAFE0001
...
FIFO[15] = 0xCAFE000F
─────────────────────────────────────────
[Phase 3: Write Burst]
DMA FIFO → AXI W Channel → DDR
   ↓
DDR[256] = 0xCAFE0000
DDR[257] = 0xCAFE0001
...
DDR[271] = 0xCAFE000F
─────────────────────────────────────────
[Phase 4: Completion]
DMA → Interrupt → Software
   ↓
STATUS.done = 1
BYTES_DONE = 256
```

### Operational Summary

After the testbench configures the source address, destination address, and transfer size through MMIO
and starts the DMA, the DMA Controller reads source data in AXI4 bursts into its internal FIFO and
writes the data to the destination address. It repeats this process while data remains and generates
completion status and an interrupt after the entire transfer finishes.

## 5. DUT: `dma_controller`

### 5.1 DMA Register Map

| Offset | Name | Access | Fields | Description |
| --- | --- | --- | --- | --- |
| `0x00` | `CTRL` | R/W | `[15:8] channel_id`, `[2] irq_en`, `[1] start`, `[0] enable` | Configure start, interrupt, and AXI ID |
| `0x04` | `STAT` | R | `[11:8] error_code`, `[2] error`, `[1] done`, `[0] busy` | DMA execution status and error information |
| `0x08` | `SRC` | R/W | `[31:0] src_addr` | Source start address |
| `0x0C` | `DST` | R/W | `[31:0] dst_addr` | Destination start address |
| `0x10` | `SIZE` | R/W | `[31:0] size` | Total transfer size in bytes |
| `0x14` | `BYTES` | R | `[31:0] bytes_done` | Cumulative bytes received on the R channel |

The configuration order is `SRC → DST → SIZE → CTRL.start`. `enable` is stored but does not gate
execution, while `irq_en` controls completion and error interrupts.

### 5.2 DMA Control Flow

The normal flow is `IDLE → SETUP → RD_ADDR → RD_DATA → WR_ADDR → WR_DATA → WR_RESP`. If data
remains, the controller repeats `NEXT → SETUP`; after completion, it transitions `DONE → IDLE`.
Configuration errors transition to `ERROR`. AXI parameters are fixed at 32-bit address/data, 4-bit ID,
4-byte beats, and INCR bursts.

### 5.3 Burst Splitting and FIFO Operation

Because the AXI4 data width is 32 bits, each beat transfers 4 bytes. The DMA does not copy the entire
transfer at once; it divides the operation into 64-byte, 16-byte, or 4-byte bursts according to
`bytes_left`.

| `bytes_left` | Burst Length | `ARLEN`/`AWLEN` | Data per Burst |
| --- | ---: | ---: | ---: |
| 64 bytes or more | 16 beats | 15 | 64 bytes |
| 16–63 bytes | 4 beats | 3 | 16 bytes |
| 4–15 bytes | 1 beat | 0 | 4 bytes |
| 1–3 bytes | Unsupported | - | `error_code=0x2` |

Following AXI4 rules, `ARLEN` and `AWLEN` are one less than the actual beat count. For example, a
16-beat transfer uses `AxLEN=15`.

Each burst copies data in the following order.

```text
Read one burst from SRC
        ↓
Store the read data in the FIFO
        ↓
Write one burst of FIFO data to DST
        ↓
Start the next burst if data remains
```

The FIFO holds sixteen 32-bit words, enough for one 64-byte burst. The DMA stores a complete burst
in the FIFO before transferring it to the destination.

For every received read beat, `cur_src` increases by 4, `bytes_left` decreases by 4, and `bytes_done`
increases by 4. For every transmitted write beat, `cur_dst` increases by 4. When the write response
for the final burst arrives with `bytes_left==0`, the transfer completes.

If the transfer size is not divisible by 4, the DMA first copies every complete 4-byte unit and then
raises `error_code=0x2` for the remaining 1–3 bytes. For example, with `SIZE=15`, it copies 12 bytes
and raises an error for the remaining 3 bytes.

---

## 6. Verification DDR Memory Model

`ddr_controller` is not actual DDR control logic; it is a simple memory model that responds to the
DMA's AXI4 requests.

| Item | Implementation |
| --- | --- |
| Memory | 1,024 × 32-bit (4 KB); use `address[11:2]` as the word index |
| Initial values | `mem[0:63] = 0xCAFE_0000 + index`; all remaining locations are zero |
| Read latency | Apply an initial `R_LAT=3` delay counter |
| Response | Both `RRESP` and `BRESP` return `OKAY` |

---

## 7. Baseline Implementation Scope and Limitations

- Successful transfers use 4-byte-aligned addresses and sizes that are multiples of four bytes. A
  request with a 1–3-byte remainder takes the size-error path.
- The DMA does not check `RRESP` or `RLAST`.
- A `BRESP` error sets `stat.error` and `error_code=0x3` in the DMA, but this error code cannot be
  verified because the DDR memory model always returns `OKAY` for `BRESP`.
- The design sequentially reads and then writes one burst at a time and does not support multiple
  outstanding transactions.
