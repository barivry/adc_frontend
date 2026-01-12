`timescale 1ns/1ps

module word_assembler #(
  parameter int LANES = 8
)(
  input  logic               dco_clk,
  input  logic               rst_n,
  input  logic [LANES-1:0]   bit_rise,
  input  logic [LANES-1:0]   bit_fall,
  output logic [2*LANES-1:0] sample_word,
  output logic               word_valid
);

  integer i;

  always_ff @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) begin
      sample_word       <= '0;
      word_valid <= 1'b0;
    end else begin
      
      for (i = 0; i < LANES-2; i++) begin
        sample_word[2*i]   <= bit_rise[i];
        sample_word[2*i+1] <= bit_fall[i];
      end
      sample_word[15:14] <='0;
      word_valid <= 1'b1;
    end
  end

endmodule
