`timescale 1ns/1ps

module ddr_lane_capture #(
  parameter int LANES = 8
)(
  input  logic               dco_clk,
  input  logic               rst_n,
  input  logic [LANES-1:0]   lvds,
  output logic [LANES-1:0]   rise,
  output logic [LANES-1:0]   fall
);

  always_ff @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) rise <= '0;
    else        rise <= lvds;
  end

  always_ff @(negedge dco_clk or negedge rst_n) begin
    if (!rst_n) fall <= '0;
    else        fall <= lvds;
  end

endmodule
