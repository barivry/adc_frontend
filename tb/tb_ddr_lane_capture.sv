`timescale 1ns/1ps

module tb_ddr_lane_capture;

  // ===== Parameters =====
  localparam int LANES = 8;

  // ===== DUT signals =====
  logic              dco_clk;
  logic              rst_n;
  logic [LANES-1:0]  lvds_data;
  logic [LANES-1:0]  bit_rise;
  logic [LANES-1:0]  bit_fall;

  // ===== Instantiate DUT =====
  ddr_lane_capture #(.LANES(LANES)) dut (
    .dco_clk   (dco_clk),
    .rst_n     (rst_n),
    .lvds_data (lvds_data),
    .bit_rise  (bit_rise),
    .bit_fall  (bit_fall)
  );

  // ===== Clock generation (100MHz -> 10ns period) =====
  initial dco_clk = 1'b0;
  always  #5 dco_clk = ~dco_clk; // toggles every 5ns => full period 10ns

  // ===== VCD dump =====
  initial begin
    $dumpfile("waves_ddr.vcd");
    $dumpvars(0, tb_ddr_lane_capture);
  end

  // ===== Simple helper task: expect equality =====
  task automatic expect_eq(input logic [LANES-1:0] got,
                           input logic [LANES-1:0] exp,
                           input string            msg);
    if (got !== exp) begin
      $display("FAIL @ t=%0t : %s | got=%b exp=%b", $time, msg, got, exp);
      $fatal(1);
    end else begin
      $display("PASS @ t=%0t : %s | %b", $time, msg, got);
    end
  endtask

  // ===== Main stimulus =====
  initial begin
    // init
    rst_n     = 1'b0;
    lvds_data = '0;

    // hold reset for a couple cycles
    repeat (2) @(posedge dco_clk);
    rst_n = 1'b1;
    $display("Released reset @ t=%0t", $time);

    // -------- Test 1: basic DDR capture --------
    // Set data BEFORE posedge, check bit_rise updates on posedge
    lvds_data = 8'b1010_1010;
    #1; // small setup time before edge
    @(posedge dco_clk);
    #1ps;
    // after posedge, bit_rise should equal lvds_data value present before posedge
    expect_eq(bit_rise, 8'b1010_1010, "bit_rise captures on posedge");

    // Set data BEFORE negedge, check bit_fall updates on negedge
    lvds_data = 8'b0101_0101;
    #1;
    @(negedge dco_clk);
    #1ps;
    expect_eq(bit_fall, 8'b0101_0101, "bit_fall captures on negedge");

    // -------- Test 2: multiple patterns --------
    // Pattern A for posedge
    lvds_data = 8'h3C; // 00111100
    #1;
    @(posedge dco_clk);
    #1ps;
    expect_eq(bit_rise, 8'h3C, "bit_rise captures 0x3C");

    // Pattern B for negedge
    lvds_data = 8'hA7; // 10100111
    #1;
    @(negedge dco_clk);
    #1ps;
    expect_eq(bit_fall, 8'hA7, "bit_fall captures 0xA7");

    // -------- Test 3: reset behavior --------
    // Drive something, then reset and ensure outputs go to 0
    lvds_data = 8'hFF;
    #1;
    @(posedge dco_clk);
    #1ps;
    expect_eq(bit_rise, 8'hFF, "bit_rise captures 0xFF before reset");

    rst_n = 1'b0; // assert reset
    // outputs should clear on next async reset event (negedge rst_n triggers)
    #1;
    expect_eq(bit_rise, 8'h00, "bit_rise cleared by reset");
    expect_eq(bit_fall, 8'h00, "bit_fall cleared by reset");

    // release reset
    repeat (1) @(posedge dco_clk);
    rst_n = 1'b1;

    $display("ALL TESTS PASSED ✅");
    #20;
    $finish;
  end

endmodule
