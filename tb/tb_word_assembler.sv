`timescale 1ns/1ps

module tb_word_assembler;

  localparam int LANES = 8;

  logic               dco_clk;
  logic               rst_n;
  logic [LANES-1:0]   bit_rise;
  logic [LANES-1:0]   bit_fall;
  logic [2*LANES-1:0] word;
  logic               word_valid;

  // DUT
  word_assembler #(.LANES(LANES)) dut (
    .dco_clk(dco_clk),
    .rst_n(rst_n),
    .bit_rise(bit_rise),
    .bit_fall(bit_fall),
    .sample_word(word),
    .word_valid(word_valid)
  );

  // Clock: 10ns period
  initial dco_clk = 1'b0;
  always  #5 dco_clk = ~dco_clk;

  // VCD
  initial begin
    $dumpfile("waves_word_assembler.vcd");
    $dumpvars(0, tb_word_assembler);
  end

  integer k;
  integer i;

  logic [2*LANES-1:0] exp_word;

  initial begin
    rst_n    = 1'b0;
    bit_rise = '0;
    bit_fall = '0;

    // Hold reset for 2 cycles
    repeat (2) @(posedge dco_clk);
    rst_n = 1'b1;

    // After reset, word_valid should go high on first active cycle (per DUT)
    for (k = 0; k < 10; k++) begin
      // Drive a deterministic pattern each cycle
      bit_rise = k[LANES-1:0];
      bit_fall = ~k[LANES-1:0];

      // Build expected word according to DUT loop:
      // for i=0 .. LANES-3:
      //   word[2*i]   = bit_rise[i]
      //   word[2*i+1] = bit_fall[i]
      exp_word = '0;
      for (i = 0; i < LANES-2; i++) begin
        exp_word[2*i]   = bit_rise[i];
        exp_word[2*i+1] = bit_fall[i];
      end
      // DUT forces word[15:14] = 0 when LANES=8
      exp_word[15:14] = 2'b00;

      @(posedge dco_clk);
      #1; // small settle

      if (word_valid !== 1'b1) begin
        $display("FAIL @t=%0t: word_valid low (k=%0d)", $time, k);
        $fatal(1);
      end

      if (word !== exp_word) begin
        $display("FAIL @t=%0t k=%0d", $time, k);
        $display("  bit_rise = %b", bit_rise);
        $display("  bit_fall = %b", bit_fall);
        $display("  got  word= %b", word);
        $display("  exp  word= %b", exp_word);
        $fatal(1);
      end else begin
        $display("PASS @t=%0t k=%0d word=%b", $time, k, word);
      end
    end

    $display("ALL TESTS PASSED ✅");
    #20;
    $finish;
  end

endmodule
