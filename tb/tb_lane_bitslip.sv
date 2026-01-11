`timescale 1ns/1ps

module tb_lane_bitslip;

  localparam int LANES = 2;     
  logic              dco_clk;
  logic              rst_n;

  logic [LANES-1:0]  in_rise;
  logic [LANES-1:0]  in_fall;
  logic [LANES-1:0]  bitslip_pulse;

  logic [LANES-1:0]  out_rise;
  logic [LANES-1:0]  out_fall;

  // DUT
  lane_bitslip #(.LANES(LANES)) dut (
    .dco_clk(dco_clk),
    .rst_n(rst_n),
    .in_rise(in_rise),
    .in_fall(in_fall),
    .bitslip_pulse(bitslip_pulse),
    .out_rise(out_rise),
    .out_fall(out_fall)
  );

  // clock: 10ns period
  initial dco_clk = 1'b0;
  always  #5 dco_clk = ~dco_clk;

  // VCD
  initial begin
    $dumpfile("waves_bitslip_adv.vcd");
    $dumpvars(0, tb_lane_bitslip);
  end

  task automatic expect_eq(input logic [LANES-1:0] got,
                           input logic [LANES-1:0] exp,
                           input string msg);
    if (got !== exp) begin
      $display("FAIL @ t=%0t : %s | got=%b exp=%b", $time, msg, got, exp);
      $fatal(1);
    end else begin
      $display("PASS @ t=%0t : %s | %b", $time, msg, got);
    end
  endtask

  
  task automatic drive_cycle(input int k);
    
    in_rise[0] = k[0];
    in_rise[1] = k[1];
    in_fall[0] = ~k[0];
    in_fall[1] = ~k[1];
  endtask

  
  logic [LANES-1:0] prev_fall_exp;
  logic [LANES-1:0] slip_offset_exp;

  initial begin
    
    rst_n         = 1'b0;
    in_rise       = '0;
    in_fall       = '0;
    bitslip_pulse = '0;

    prev_fall_exp  = '0;
    slip_offset_exp = '0;

    
    repeat (2) @(posedge dco_clk);
    rst_n = 1'b1;
    $display("Released reset @ t=%0t", $time);

    // -------------------------
    // Phase A: offset=0 (normal)
    // -------------------------
    // k=0..2
    for (int k = 0; k < 3; k++) begin
      
      drive_cycle(k);
      #1;

      @(posedge dco_clk);
      #1ps;
      expect_eq(out_rise, in_rise, $sformatf("normal: out_rise=r_%0d", k));

      
      #1;
      @(negedge dco_clk);
      #1ps;
      
      expect_eq(out_fall, in_fall, $sformatf("normal: out_fall=f_%0d", k));

      
      prev_fall_exp = in_fall;
    end

    // -------------------------
    // Phase B: Toggle slip_offset (bitslip_pulse)
    // -------------------------
    drive_cycle(3);
    bitslip_pulse = '1; 
    #1;
    @(posedge dco_clk);
    #1ps;
    bitslip_pulse = '0;
    expect_eq(out_rise, in_rise, "toggle edge: still normal out_rise = r_3");

    #1;
    @(negedge dco_clk);
    #1ps;
    expect_eq(out_fall, in_rise, "slipped: out_fall = r_3");

    
    prev_fall_exp = in_fall;

    
    drive_cycle(4);
    #1;
    @(posedge dco_clk); #0;
    #1ps;
    expect_eq(out_rise, prev_fall_exp, "slipped: out_rise = f_3");

    #1;
    @(negedge dco_clk); #0;
    #1ps;
    expect_eq(out_fall, in_rise, "slipped: out_fall = r_4");

    $display("ALL TESTS PASSED ✅");
    #20;
    $finish;
  end

endmodule
