`timescale 1ns/1ps

module axis_stream_out (
  input  logic        sys_clk,
  input  logic        sys_rst_n,

  // Control
  input  logic        enable,
  input  logic        aligned,

  // FIFO read side (sys_clk domain)
  input  logic [15:0] fifo_rd_data,
  input  logic        fifo_rd_valid,
  input  logic        fifo_rd_empty,   // נשאר, אבל לא קריטי
  output logic        fifo_rd_en,

  // AXI-Stream-like output
  output logic        m_valid,
  input  logic        m_ready,
  output logic [15:0] m_data
);

  // ----------------------------
  // Hold register
  // ----------------------------
  logic        hold_valid;
  logic [15:0] hold_data;

  assign m_valid = hold_valid;
  assign m_data  = hold_data;

  // ============================
  // FIFO read request
  // ============================
  // בקשה לקריאה כשאין לנו דאטה מוחזק
  always_comb begin
    fifo_rd_en = 1'b0;
    if (enable && aligned && !hold_valid) begin
      fifo_rd_en = 1'b1;
    end
  end

  // ============================
  // Hold register update
  // ============================
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      hold_valid <= 1'b0;
      hold_data  <= '0;
    end else begin

      // flush אם לא מאופשר / לא מיושר
      if (!enable || !aligned) begin
        hold_valid <= 1'b0;
      end else begin

        // consume
        if (hold_valid && m_ready) begin
          hold_valid <= 1'b0;
        end

        // load ONLY when FIFO באמת סיפק דאטה
        if (fifo_rd_valid) begin
          hold_valid <= 1'b1;
          hold_data  <= fifo_rd_data;
        end

      end
    end
  end

endmodule