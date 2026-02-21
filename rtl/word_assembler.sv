`timescale 1ns/1ps

module word_assembler #(
  parameter int LANES = 8
)(
  input  logic               dco_clk,
  input  logic               rst_n,

  // keep port for now (so top doesn't need edits),
  // but we intentionally DO NOT use it to stop word production.
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
    end else begin
      // ALWAYS assemble a new word each DCO cycle
      for (i = 0; i < LANES; i++) begin
        sample_word[2*i]   <= bit_rise[i];
        sample_word[2*i+1] <= bit_fall[i];
      end

      // reserved MSBs = 0 (for LANES=8 -> [15:14]=0)
      sample_word[2*LANES-1 -: 2] <= 2'b00;

      // "a new ADC word exists" every cycle
      word_valid <= 1'b1;
    end
  end

endmodule