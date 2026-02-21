`timescale 1ns/1ps

module word_assembler #(
  parameter int LANES = 8
)(
  input  logic               dco_clk,
  input  logic               rst_n,

  // NEW: backpressure from FIFO
  input  logic               stall,

  input  logic [LANES-1:0]   bit_rise,
  input  logic [LANES-1:0]   bit_fall,
  output logic [2*LANES-1:0] sample_word,
  output logic               word_valid
);

  integer i;

  always_ff @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) begin
      sample_word <= '0;
      word_valid  <= 1'b0;

    end else if (!stall) begin
      // 정상 동작: מייצרים מילה חדשה
      for (i = 0; i < LANES-1; i++) begin
        sample_word[2*i]   <= bit_rise[i];
        sample_word[2*i+1] <= bit_fall[i];
      end

      // שמירת ה־2 ביטים העליונים כ־0 (כמו אצלך)
      sample_word[2*LANES-1 -: 2] <= 2'b00;

      word_valid <= 1'b1;

    end else begin
      // stall: לא מייצרים דגימה חדשה
      word_valid <= 1'b1;
      // sample_word נשאר כפי שהוא (hold)
    end
  end

endmodule