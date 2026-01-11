# ADC LVDS Frontend – SystemVerilog Simulation

This repository contains a SystemVerilog implementation of an ADC LVDS (DDR)
sample capture frontend, including lane capture, word assembly, alignment
monitoring, and CDC FIFO.

## Requirements
- Linux
- Icarus Verilog (`iverilog`)
- vvp



## How to Run the Testbench 

### Compile and Run

iverilog -g2012 -Wall -o sim/sim_top \
  tb/tb_adc_frontend_top.sv \
  rtl/ddr_lane_capture.sv \
  rtl/word_assembler.sv \
  rtl/align_monitor_fco.sv \
  rtl/cdc_async_fifo.sv \
  rtl/adc_lvds_frontend_top.sv

vvp sim/sim_top
