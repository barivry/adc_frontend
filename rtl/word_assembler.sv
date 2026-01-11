`timescale 1ns/1ps

module word_assembler #(
  parameter int LANES = 8
)(
  input  logic               clk,
  input  logic               rst_n,
  input  logic [LANES-1:0]   in_rise,
  input  logic [LANES-1:0]   in_fall,
  output logic [2*LANES-1:0] word,
  output logic               word_valid
);

  integer i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      word       <= '0;
      word_valid <= 1'b0;
    end else begin
      
      for (i = 0; i < LANES; i++) begin
        word[2*i]   <= in_rise[i];
        word[2*i+1] <= in_fall[i];
      end
      word_valid <= 1'b1;
    end
  end

endmodule
