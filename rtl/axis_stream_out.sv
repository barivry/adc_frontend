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
  input  logic        fifo_rd_empty,
  output logic        fifo_rd_en,

  // AXI-Stream-like output
  output logic        m_valid,
  input  logic        m_ready,
  output logic [15:0] m_data
);

  // ----------------------------
  // 2-deep buffer: hold + prefetch
  // ----------------------------
  logic        hold_valid;
  logic [15:0] hold_data;

  logic        pf_valid;
  logic [15:0] pf_data;

  logic        will_consume;
  assign will_consume = hold_valid && m_ready;

  assign m_valid = hold_valid;
  assign m_data  = hold_data;

  // ============================
  // FIFO read request
  // ============================
  // אצלך fifo_rd_valid הוא רשום (מגיע מחזור אחרי fifo_rd_en),
  // לכן קוראים "קדימה" אל pf כשיש מקום.
  always_comb begin
    fifo_rd_en = 1'b0;

    // לא חובה לבדוק fifo_rd_empty (מותר לבקש גם כשהוא ריק),
    // אבל אפשר כדי להקטין פעילות:
    if (enable && aligned && !pf_valid && !fifo_rd_empty) begin
      fifo_rd_en = 1'b1;
    end
  end

  // ============================
  // Buffer update
  // ============================
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      hold_valid <= 1'b0;
      hold_data  <= '0;
      pf_valid   <= 1'b0;
      pf_data    <= '0;
    end else begin
      // flush אם לא מאופשר / לא מיושר
      if (!enable || !aligned) begin
        hold_valid <= 1'b0;
        pf_valid   <= 1'b0;
      end else begin
        // 1) consume: אם צורכים ויש pf מוכן -> גלגול מיידי בלי bubble
        if (will_consume) begin
          if (pf_valid) begin
            hold_data  <= pf_data;
            hold_valid <= 1'b1;
            pf_valid   <= 1'b0;
          end else begin
            hold_valid <= 1'b0;
          end
        end

        // 2) קליטת דאטה מה-FIFO (מגיע כשה-fifo_rd_valid=1)
        if (fifo_rd_valid) begin
          // אם hold ריק (או בדיוק התרוקן בלי pf), נטען ישירות ל-hold
          if (!hold_valid || (will_consume && !pf_valid)) begin
            hold_data  <= fifo_rd_data;
            hold_valid <= 1'b1;
          end else begin
            // אחרת - נכנס ל-prefetch
            pf_data  <= fifo_rd_data;
            pf_valid <= 1'b1;
          end
        end
      end
    end
  end

endmodule