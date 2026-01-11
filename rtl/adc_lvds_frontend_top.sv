`timescale 1ns/1ps

module adc_lvds_frontend_top #(
  parameter int LANES      = 8,
  parameter int FIFO_DEPTH = 1024
)(
  
  input  logic               dco_clk,
  input  logic               rst_n,
  input  logic [LANES-1:0]   lvds_data,
  input  logic               lvds_fco,

  
  input  logic               sys_clk,
  input  logic               sys_rst_n,
  input  logic               out_ready,
  output logic [2*LANES-1:0] out_word,
  output logic               out_valid,

  
  output logic               aligned,

  
  output logic               word_valid_dco_dbg
);

  logic [LANES-1:0]   rise, fall;
  logic [2*LANES-1:0] word_dco;
  logic               word_valid_dco;

  logic fifo_full, fifo_empty;

  ddr_lane_capture #(.LANES(LANES)) u_cap (
    .dco_clk(dco_clk),
    .rst_n  (rst_n),
    .lvds   (lvds_data),
    .rise   (rise),
    .fall   (fall)
  );

  word_assembler #(.LANES(LANES)) u_asm (
    .clk       (dco_clk),
    .rst_n     (rst_n),
    .in_rise   (rise),
    .in_fall   (fall),
    .word      (word_dco),
    .word_valid(word_valid_dco)
  );

  align_monitor_fco #(
    .EXPECT_PERIOD(16),
    .LOCK_COUNT(4)
  ) u_align (
    .dco_clk(dco_clk),
    .rst_n  (rst_n),
    .fco_in (lvds_fco),
    .word_valid(word_valid_dco),
    .aligned(aligned),
    .align_pulse(),
    .align_err_pulse(),
    .err_count()
  );

  
  cdc_async_fifo #(
    .WIDTH(2*LANES),
    .DEPTH(FIFO_DEPTH)
  ) u_fifo (
    .wr_clk  (dco_clk),
    .wr_rst_n(rst_n),
    .wr_en   (word_valid_dco && aligned),
    .wr_data (word_dco),
    .wr_full (fifo_full),

    .rd_clk  (sys_clk),
    .rd_rst_n(sys_rst_n),
    .rd_en   (out_ready),
    .rd_data (out_word),
    .rd_valid(out_valid),
    .rd_empty(fifo_empty)
  );

  assign word_valid_dco_dbg = word_valid_dco;

endmodule
