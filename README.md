# ADC Sample Capture Front-End (LVDS DDR)

## Overview
This repository implements an **industry‑realistic LVDS DDR ADC capture front‑end** targeted at FPGA‑based instrumentation and quantum‑readout systems. The design captures high‑speed LVDS data on **both edges of a source‑synchronous clock (DDR)**, assembles correctly ordered samples, monitors alignment using a frame clock (FCO), and safely transfers data into the system clock domain via an asynchronous FIFO.

The project is designed to be **bring‑up ready**:
- Clear, frozen assumptions and bit mapping
- Clean RTL hierarchy
- Self‑checking SystemVerilog testbench
- Regression‑ready simulation flow
- Evidence waveforms for correctness and determinism

---

## Key Features
- **LVDS DDR capture** (rising + falling edges of DCO)
- **8 data lanes → 16 bits per DCO cycle**
- **Deterministic word assembly** with documented bit ordering
- **FCO‑based alignment monitoring** and error detection
- **Per‑lane deskew controls** (edge swap + 1‑bit bitslip)
- **Safe CDC** using async FIFO (DCO → system clock)
- **AXI‑Stream‑like output interface** with backpressure handling
- **Instrumentation / quantum‑grade options**:
  - Deterministic latency mode
  - Trigger + snapshot buffer (pre/post samples)
  - Timestamping

---

## Target Use‑Case
High‑speed **ADC LVDS DDR capture into an FPGA**, followed by safe transfer into the system clock domain and clean streaming to downstream processing logic.

The design follows a **Xilinx 7‑Series‑style flow** (IBUFDS + IDDR). For simulation, vendor primitives are replaced by behavioral models.

---

## Frozen Configuration (Locked)
These parameters are fixed and enforced in RTL, TB, and verification:

- **ADC sample width:** 14 bits (unsigned, straight binary)
- **LVDS data lanes:** 8
- **DDR capture:** 2 bits per lane per DCO cycle → 16 bits total
- **Output word format:**
  - `sample_word[13:0]` = ADC sample
  - `sample_word[15:14]` = `2'b00` (reserved)
- **Frame clock:** FCO present and required
- **CDC policy:** async FIFO (DCO clock → system clock)
- **Streaming interface:** AXI‑Stream‑like (`m_valid`, `m_ready`, `m_data[15:0]`)

---

## Bit Mapping (Locked)
For lane `i ∈ [0..7]`:

- Capture `bit_rise[i]` on **DCO rising edge**
- Capture `bit_fall[i]` on **DCO falling edge**

Assemble one word per full DCO cycle:
```
word[2*i]   = bit_rise[i]
word[2*i+1] = bit_fall[i]
```

Final output word:
```
sample[13:0] = word[13:0]
word[15:14]  = 2'b00
```

This mapping is **documented, verified, and asserted** in the testbench.

---

## Clock Domains
- **dco_clk** – source‑synchronous clock from ADC (capture domain)
- **sys_clk** – system / fabric clock (processing + output domain)

---

## Alignment & Deskew
### FCO Alignment Monitor
- Waits for stable FCO behavior at startup
- Asserts `aligned` once lock is achieved
- Detects runtime FCO violations
- Increments `align_err_cnt`
- Optional policy to deassert `aligned` on errors

### Per‑Lane Deskew (Practical / Industry‑Style)
- `swap_edges[i]` – swap rising/falling edge assignment
- `bitslip[i]` – 1‑bit slip to correct half‑cycle ambiguity

Calibration is performed in **training mode** using a known pattern supplied by the testbench or external controller.

---

## External Interfaces
### Clocks & Reset
- `input  logic sys_clk`
- `input  logic sys_rst_n` (active‑low)
- `input  logic dco_clk`

### LVDS Inputs (Logical‑Level for Simulation)
- `input logic [7:0] lvds_data`
- `input logic       fco`

*(Synthesis wrappers may replace these with IBUFDS ports.)*

### Control / Status (CSR‑like)
**Inputs:**
- `enable`
- `train_mode`
- `swap_edges[7:0]`
- `bitslip[7:0]`
- `clear_counters`
- Trigger controls (`trig_arm`, `trig_source`, optional `trig_level`)

**Outputs / Status:**
- `aligned`
- `align_err_cnt`
- `fifo_ovf_cnt`
- `samples_dropped_cnt`
- `timestamp`
- Snapshot status (`snap_ready`, `snap_overrun`)

### Streaming Output
AXI‑Stream‑like interface:
- `output logic        m_valid`
- `input  logic        m_ready`
- `output logic [15:0] m_data`

Optional sideband (`m_user`) may include alignment flags, timestamps, or sample index.

---

## Functional Block Diagram (Concept)
```
LVDS DDR Capture (dco_clk)
   → Word Assembly + Deskew
   → FCO Alignment Monitor
   → Async FIFO (CDC)
   → Stream Out + Trigger/Snapshot (sys_clk)
```

---

## Deterministic Latency Mode
When enabled:
- Pipeline stages and FIFO behavior are constrained
- End‑to‑end latency is **fixed and documented** in sys_clk cycles
- Testbench verifies identical input edges produce identical output latency (±0 cycles)

This mode is intended for **quantum / instrumentation systems** where timing determinism is critical.

---

## Trigger & Snapshot Buffer
- Circular buffer in sys_clk domain
  - `PRE_SAMPLES = 1024`
  - `POST_SAMPLES = 1024`
- On trigger:
  - Freeze pre‑samples
  - Collect post‑samples
  - Assert `snap_ready`
- Snapshot can be read via BRAM interface or streamed out

---

## Verification Strategy
### Testbench
- LVDS stimulus generator (ramp / PRBS / sine LUT)
- Golden model for expected output stream
- Error injection (bitslip, edge swap, FCO glitches)
- Scoreboard + counters
- Latency and determinism checks

### Minimum Required Tests
1. Clean capture (smoke test)
2. Deskew calibration (swap + bitslip)
3. FCO glitch detection
4. Backpressure stress (`m_ready` random)
5. Reset mid‑run recovery
6. Trigger + snapshot integrity
7. Deterministic latency verification

---

## Running Simulation
Example (Icarus / Verilator style):
```bash
make sim TEST=smoke
make sim TEST=fco_glitch
make regress
```

Waveforms are generated for GTKWave inspection.

---

## Repository Structure
```
rtl/
  adc_lvds_frontend_top.sv
  ddr_lane_capture.sv
  word_assembler.sv
  align_monitor_fco.sv
  cdc_async_fifo.sv
  axis_stream_out.sv
  snapshot_trigger.sv
  csr_regs.sv

sim/
  tb_adc_lvds_frontend.sv
  Makefile
  run_regress.py (optional)

docs/
  block_diagram.png
  timing_notes.md
  evidence_waveforms/
```

---

## Known Limitations
- Deskew is digital (no analog delay taps)
- Behavioral LVDS models used in simulation
- Synthesis wrappers are FPGA‑family specific

---

## License
MIT (or project‑specific license)

---

## Status
Actively developed. Contributions, issues, and review comments are welcome.

