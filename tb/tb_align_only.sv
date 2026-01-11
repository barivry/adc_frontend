`timescale 1ns/1ps
module tb_align_only;

  localparam int EXPECT_PERIOD = 16;
  localparam int LOCK_COUNT    = 4;

  logic dco_clk = 0;
  logic rst_n   = 0;

  logic fco_in;
  logic word_valid;
  logic aligned;

  // 250MHz DCO
  always #2 dco_clk = ~dco_clk;

  // DUT
  align_monitor_fco #(
    .EXPECT_PERIOD(EXPECT_PERIOD),
    .LOCK_COUNT   (LOCK_COUNT)
  ) dut (
    .dco_clk    (dco_clk),
    .rst_n      (rst_n),
    .fco_in     (fco_in),
    .word_valid (word_valid),
    .aligned    (aligned)
  );

  // Reset
  initial begin
    fco_in     = 0;
    word_valid = 0;
    rst_n      = 0;
    repeat (5) @(posedge dco_clk);
    rst_n      = 1;
  end

  // ------------------------------------------------
  // Stimulus: PERFECT FCO stream
  // ------------------------------------------------
  int unsigned word_cnt;

  always @(posedge dco_clk) begin
    if (!rst_n) begin
      word_cnt   <= 0;
      fco_in     <= 0;
      word_valid <= 0;
    end else begin
      // Always producing valid words
      word_valid <= 1'b1;

      // Generate FCO pulse exactly every EXPECT_PERIOD words
      if (word_cnt == EXPECT_PERIOD-1) begin
        fco_in   <= 1'b1;   // 1-cycle pulse
        word_cnt <= 0;
      end else begin
        fco_in   <= 1'b0;
        word_cnt <= word_cnt + 1;
      end
    end
  end

  // Watch alignment
  always @(posedge dco_clk) begin
    if (aligned)
      $display("ALIGNED at t=%0t", $time);
  end

  // Timeout
  initial begin
    #200000;
    $display("TIMEOUT aligned=%0b", aligned);
    $finish;
  end

  // VCD
  initial begin
    $dumpfile("waves_align_only.vcd");
    $dumpvars(0, tb_align_only);
  end

endmodule
