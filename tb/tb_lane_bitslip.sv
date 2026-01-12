 `timescale 1ns/1ps

module tb_lane_bitslip_1lane;

  localparam int LANES = 1;

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
    .bit_rise(in_rise),
    .bit_fall(in_fall),
    .bitslip_pulse(bitslip_pulse),
    .out_rise(out_rise),
    .out_fall(out_fall)
  );

  // 10ns period clock
  initial dco_clk = 1'b0;
  always  #5 dco_clk = ~dco_clk;

  // VCD
  initial begin
    $dumpfile("waves_bitslip_1lane.vcd");
    $dumpvars(0, tb_lane_bitslip_1lane);
  end

  // Simple pattern generator: r_k = k[0], f_k = ~k[0]
  int k;
  logic prev_fall;

  initial begin
    // init
    rst_n         = 1'b0;
    in_rise       = '0;
    in_fall       = '0;
    bitslip_pulse = '0;
    prev_fall     = 1'b0;

    // hold reset for 2 posedges
    repeat (2) @(posedge dco_clk);
    rst_n = 1'b1;

    // -------------------------
    // Phase A: no slip (expect passthrough)
    // -------------------------
    for (k = 0; k < 4; k = k + 1) begin
      in_rise[0] = k[0];
      in_fall[0] = ~k[0];

      @(posedge dco_clk);
      #1ps;
      if (out_rise[0] !== in_rise[0]) begin
        $display("FAIL normal out_rise @t=%0t k=%0d got=%b exp=%b", $time, k, out_rise[0], in_rise[0]);
        $fatal(1);
      end

      @(negedge dco_clk);
      #1ps;
      if (out_fall[0] !== in_fall[0]) begin
        $display("FAIL normal out_fall @t=%0t k=%0d got=%b exp=%b", $time, k, out_fall[0], in_fall[0]);
        $fatal(1);
      end

      prev_fall = in_fall[0];
    end

    // -------------------------
    // Phase B: toggle slip on next posedge
    // Expect:
    //   - At toggle posedge: out_rise still normal (uses old slip)
    //   - At following negedge: out_fall = rise_hold (current r_k)
    //   - Next posedge: out_rise = prev_fall from previous cycle
    // -------------------------
    k = 4;
    in_rise[0] = k[0];
    in_fall[0] = ~k[0];

    bitslip_pulse[0] = 1'b1;
    @(posedge dco_clk);
    #1ps;
    bitslip_pulse[0] = 1'b0;

    #1ps;
    // still normal on this edge (depends on implementation order; this matches common intent)
    if (out_rise[0] !== in_rise[0]) begin
      $display("FAIL toggle-edge out_rise @t=%0t k=%0d got=%b exp=%b", $time, k, out_rise[0], in_rise[0]);
      $fatal(1);
    end

    @(negedge dco_clk);
    #1ps;
    // slipped: out_fall should become rise_hold == current in_rise
    if (out_fall[0] !== in_rise[0]) begin
      $display("FAIL slipped out_fall @t=%0t k=%0d got=%b exp=%b", $time, k, out_fall[0], in_rise[0]);
      $fatal(1);
    end

    // advance one more cycle with slip active
    prev_fall = in_fall[0];
    k = 5;
    in_rise[0] = k[0];
    in_fall[0] = ~k[0];

    @(posedge dco_clk);
    #1ps;
    // slipped: out_rise should be previous fall
    if (out_rise[0] !== prev_fall) begin
      $display("FAIL slipped out_rise @t=%0t k=%0d got=%b exp=%b", $time, k, out_rise[0], prev_fall);
      $fatal(1);
    end

    @(negedge dco_clk);
    #1ps;
    // slipped: out_fall should be current rise
    if (out_fall[0] !== in_rise[0]) begin
      $display("FAIL slipped out_fall2 @t=%0t k=%0d got=%b exp=%b", $time, k, out_fall[0], in_rise[0]);
      $fatal(1);
    end

    $display("ALL TESTS PASSED ✅");
    #20;
    $finish;
  end

endmodule
