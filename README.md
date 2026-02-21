# ADC Sample Capture Front-End (LVDS DDR)

## Overview
This repository implements an LVDS DDR ADC capture front-end:

- Captures LVDS data on **both clock edges** (DDR)
- Assembles **16-bit words** from 8 LVDS lanes
- Uses FCO for word alignment
- Crosses clock domains using an async FIFO
- Streams data using an AXI-Stream-like interface with backpressure
- Supports **snapshot capture windows** controlled by trigger + CSR
- Includes a **self-checking SystemVerilog testbench** with:
  - Ramp stimulus
  - PRBS stimulus
  - Golden model reconstruction
  - Scoreboard with pass/fail

---

## Output Word Format (Project Requirement)

Each output word is **16 bits**:

```
[15:14] = 2'b00   // RESERVED – MUST always be zero
[13:0]  = ADC sample data
```

This requirement is enforced in:
- Testbench stimulus generation
- Golden model comparison
- Scoreboard checking

---

## RTL Structure

```
rtl/
├── adc_lvds_frontend_top.sv   # Top-level integration
├── ddr_lane_capture.sv        # DDR capture (posedge/negedge)
├── word_assembler.sv          # Builds 16-bit word, forces [15:14]=0
├── align_monitor_fco.sv       # FCO-based alignment detection
├── cdc_async_fifo.sv          # Async FIFO (dco_clk → sys_clk)
├── axis_stream_out.sv         # AXI-stream output stage
├── snapshot_trigger.sv        # Snapshot window controller
└── csr_regs.sv                # Control/status registers
```

---

## Snapshot Mechanism

### snapshot_trigger.sv
Controls capture windows:

- Inputs:
  - `trigger` – 1-cycle pulse
  - `snap_len` – number of samples
- Counts accepted AXI beats (`valid && ready`)
- Outputs:
  - `snapshot_enable` – high during capture
  - `snapshot_done` – 1-cycle pulse at completion

### Stream Enable Gating
Streaming is enabled only when:

```
stream_enable = snapshot_enable && csr_stream_enable
```

---

## CSR Interface

| Address | Register | Description |
|-------:|---------|-------------|
| 0x0 | CTRL | bit0 = stream_enable |
| 0x4 | SNAP_LEN | Snapshot length |

The testbench programs these registers after reset.

---

## Testbench

File:
```
tb/tb_adc_frontend_top.sv
```

The testbench is **fully self-checking**.

### Supported Tests (plusargs)

- `+TEST=smoke`
  - Ramp stimulus
  - Snapshot length = 6304
- `+TEST=prbs`
  - PRBS16 stimulus
  - Snapshot length = 4096

---

## Stimulus Types

### Ramp
Monotonic counter, masked to enforce:

```
word[15:14] = 2'b00
```

### PRBS
PRBS16 generator using polynomial:

```
x^16 + x^14 + x^13 + x^11 + 1
```

Upper bits are forced:

```
word[15:14] = 2'b00
```

---

## Golden Model

Golden model reconstructs expected output:

```
golden_word = { 2'b00, raw_word[13:0] }
```

If lane mapping or bit order changes, **only the golden model must be updated**.

---

## Scoreboard

- Expected words are enqueued only when DUT writes:
  ```
  aligned && word_valid_dco && !stall
  ```
- Comparison happens only on AXI handshake:
  ```
  out_valid && out_ready
  ```
- Any mismatch causes immediate failure
- Snapshot completes only if:
  ```
  rd_cnt == snap_len
  ```

---

## Running Simulations

### Compile
```
mkdir -p sim

iverilog -g2012 -Wall -o sim/sim_top \
  tb/tb_adc_frontend_top.sv \
  rtl/ddr_lane_capture.sv \
  rtl/word_assembler.sv \
  rtl/align_monitor_fco.sv \
  rtl/cdc_async_fifo.sv \
  rtl/axis_stream_out.sv \
  rtl/snapshot_trigger.sv \
  rtl/csr_regs.sv \
  rtl/adc_lvds_frontend_top.sv
```

### Run Smoke Test (Ramp)
```
vvp sim/sim_top +TEST=smoke
```

Expected:
```
SNAPSHOT PASS ✅ samples=6304
```

### Run PRBS Test
```
vvp sim/sim_top +TEST=prbs
```

Expected:
```
SNAPSHOT PASS ✅ samples=4096
```

---

## Waveforms

The testbench generates:
```
waves_top.vcd
```

View with:
```
gtkwave waves_top.vcd
```

---

## Acceptance Criteria (P0)

- `+TEST=smoke` passes with **0 mismatches**
- `+TEST=prbs` passes with **0 mismatches**
- Snapshot length equals programmed `snap_len`
- Output format always satisfies:
  ```
  [15:14] = 2'b00
  ```

---

## Status

- DDR capture verified
- Snapshot + CSR verified
- Ramp stimulus verified
- PRBS stimulus verified
- Golden model + scoreboard active