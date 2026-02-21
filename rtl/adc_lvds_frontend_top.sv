`timescale 1ns/1ps

module adc_lvds_frontend_top #(
  parameter int LANES      = 8,
  parameter int FIFO_DEPTH = 1024
)(
  //csr registers
 
  input  logic [31:0] snap_len,
  output logic        snapshot_done,

  // Alignment controls (from CSR)
  input  logic [7:0]  align_lock_n,
  input  logic        align_deassert_on_err,
  // ADC / capture domain
  input  logic               dco_clk,
  input  logic               rst_n,
  input  logic [LANES-1:0]   lvds_data,
  input  logic               lvds_fco,

  // System / output domain
  input  logic               sys_clk,
  input  logic               sys_rst_n,

  // NEW: stream enable (from TB/snapshot/CSR)
  input  logic               stream_enable,

  input  logic               out_ready,
  output logic [2*LANES-1:0] out_word,
  output logic               out_valid,

  // Status
  output logic               aligned,

  // Debug
  output logic               word_valid_dco_dbg,
  output logic               stall_dco_dbg
);

  logic [LANES-1:0]   rise, fall;
  logic [2*LANES-1:0] word_dco;
  logic               word_valid_dco;

  // FIFO flags
  logic fifo_full, fifo_empty;

  // Sticky "ever aligned" flag: once we lock the first time, we keep streaming/writing
  // even if aligned temporarily deasserts due to a violation.
  logic aligned_sticky;

  always_ff @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) aligned_sticky <= 1'b0;
    else if (aligned) aligned_sticky <= 1'b1;
  end

  // ----------------------------
  // Backpressure (DCO domain)
  // ----------------------------
  logic stall_dco;
  assign stall_dco = fifo_full;

  // ----------------------------
  // FIFO -> AXIS internal wires (sys_clk domain)
  // ----------------------------
  logic [2*LANES-1:0] fifo_rd_data;
  logic               fifo_rd_valid;
  logic               fifo_rd_en;

  // AXIS internal wires
  logic               axis_valid;
  logic               axis_ready;
  logic [2*LANES-1:0] axis_data;

  // ----------------------------
  // DDR capture
  // ----------------------------
  ddr_lane_capture #(.LANES(LANES)) u_cap (
    .dco_clk(dco_clk),
    .rst_n  (rst_n),
    .lvds   (lvds_data),
    .rise   (rise),
    .fall   (fall)
  );

  // ----------------------------
  // Word assembler WITH stall
  // ----------------------------
  word_assembler #(.LANES(LANES)) u_asm (
    .dco_clk     (dco_clk),
    .rst_n       (rst_n),
    .stall       (stall_dco),
    .bit_rise    (rise),
    .bit_fall    (fall),
    .sample_word (word_dco),
    .word_valid  (word_valid_dco)
  );

  // ----------------------------
  // Alignment monitor
  // ----------------------------
  align_monitor_fco #(
    .EXPECT_PERIOD(16),
    .LOCK_N_DFLT(16)
  ) u_align (
    .dco_clk         (dco_clk),
    .rst_n           (rst_n),
    .fco_in          (lvds_fco),
    .word_valid      (word_valid_dco),

    .lock_n_cfg          (align_lock_n),
    .deassert_on_err_cfg (align_deassert_on_err),

    .aligned         (aligned),
    .align_pulse     (),
    .align_err_pulse (),
    .err_count       ()
  );

  // ----------------------------
  // Async FIFO (CDC)
  // ----------------------------
  cdc_async_fifo #(
    .WIDTH(2*LANES),
    .DEPTH(FIFO_DEPTH)
  ) u_fifo (
    .wr_clk   (dco_clk),
    .wr_rst_n (rst_n),
    // Write only after first lock; keep writing through temporary aligned drops
    .wr_en    (word_valid_dco && aligned_sticky && !fifo_full),
    .wr_data  (word_dco),
    .wr_full  (fifo_full),

    .rd_clk   (sys_clk),
    .rd_rst_n (sys_rst_n),
    .rd_en    (fifo_rd_en),
    .rd_data  (fifo_rd_data),
    .rd_valid (fifo_rd_valid),
    .rd_empty (fifo_empty)
  );

  // ----------------------------
  // AXI-stream output stage
  // ----------------------------
  axis_stream_out u_axis (
    .sys_clk       (sys_clk),
    .sys_rst_n     (sys_rst_n),

    .enable        (stream_enable),  // <<< NEW
    // Keep streaming even if aligned temporarily deasserts (status-only)
    .aligned       (aligned_sticky),

    .fifo_rd_data  (fifo_rd_data),
    .fifo_rd_valid (fifo_rd_valid),
    .fifo_rd_empty (fifo_empty),
    .fifo_rd_en    (fifo_rd_en),

    .m_valid       (axis_valid),
    .m_ready       (axis_ready),
    .m_data        (axis_data)
  );

  // ----------------------------
  // Top outputs
  // ----------------------------
  assign out_valid      = axis_valid;
  assign axis_ready     = out_ready;
  assign out_word       = axis_data;

  assign stall_dco_dbg      = stall_dco;
  assign word_valid_dco_dbg = word_valid_dco;

endmodule