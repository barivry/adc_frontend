`timescale 1ns/1ps

module tb_word_assembler;

  localparam int LANES = 8;
  localparam int W = 2*LANES;

  logic dco_clk;
  logic rst_n;

  logic [LANES-1:0] rise_bits;
  logic [LANES-1:0] fall_bits;

  logic [W-1:0] word;
  logic         word_valid;
  logic         word_ready;

  // DUT
  word_assembler #(.LANES(LANES)) dut (
    .dco_clk   (dco_clk),
    .rst_n     (rst_n),
    .rise_bits (rise_bits),
    .fall_bits (fall_bits),
    .word      (word),
    .word_valid(word_valid),
    .word_ready(word_ready)
  );

  // clock
  initial begin
    dco_clk = 0;
    forever #5 dco_clk = ~dco_clk; // 100 MHz
  end

  
  initial begin
    #2000;
    $display("TIMEOUT");
    $fatal(1);
  end

  // helper: build expected word
  function automatic [W-1:0] exp_word(
    input [LANES-1:0] r,
    input [LANES-1:0] f
  );
    automatic int i;
    begin
      exp_word = '0;
      for (i = 0; i < LANES; i++) begin
        exp_word[2*i]   = r[i];
        exp_word[2*i+1] = f[i];
      end
      exp_word[15:14] = 2'b00;
    end
  endfunction

  initial begin
    // init
    rst_n      = 0;
    rise_bits = '0;
    fall_bits = '0;
    word_ready = 0;

    // release reset
    repeat (3) @(posedge dco_clk);
    rst_n = 1;

    // --------------------------------------
    // TEST 1: basic word assembly
    // --------------------------------------
    @(negedge dco_clk);
    rise_bits = 8'b1010_0101;
    fall_bits = 8'b1100_0011;
    word_ready = 1;

    @(posedge dco_clk); // capture happens here
    @(negedge dco_clk);

    if (!word_valid) begin
      $display("FAIL: word_valid not asserted");
      $fatal(1);
    end

    if (word !== exp_word(rise_bits, fall_bits)) begin
      $display("FAIL: word mismatch");
      $display("expected=%b got=%b", exp_word(rise_bits, fall_bits), word);
      $fatal(1);
    end

    $display("PASS: basic assembly");

    // --------------------------------------
    // TEST 2: backpressure (word_ready=0)
    // --------------------------------------
    @(negedge dco_clk);
    rise_bits = 8'b0000_1111;
    fall_bits = 8'b1111_0000;
    word_ready = 0; // FIFO full → must HOLD

    @(posedge dco_clk);
    @(negedge dco_clk);

    // word must NOT change
    if (word !== exp_word(8'b1010_0101, 8'b1100_0011)) begin
      $display("FAIL: word changed under backpressure");
      $fatal(1);
    end

    $display("PASS: backpressure holds word");

    // --------------------------------------
    // TEST 3: release backpressure
    // --------------------------------------
    @(negedge dco_clk);
    word_ready = 1;

    @(posedge dco_clk);
    @(negedge dco_clk);

    if (word !== exp_word(8'b0000_1111, 8'b1111_0000)) begin
      $display("FAIL: word not updated after ready");
      $fatal(1);
    end

    $display("PASS: update after ready");

    // --------------------------------------
    // DONE
    // --------------------------------------
    $display("ALL word_assembler TESTS PASSED ✅");
    #50;
    $finish;
  end

endmodule
