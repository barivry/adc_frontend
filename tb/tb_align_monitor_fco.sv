`timescale 1ns/1ps

module tb_align_monitor_fco;

  localparam int EXPECT_PERIOD = 8;
  localparam int LOCK_COUNT    = 3;

  logic dco_clk, rst_n;
  logic fco_in;

  logic aligned, align_pulse, align_err_pulse;
  logic [15:0] err_count;

  fco_align_monitor #(
    .EXPECT_PERIOD(EXPECT_PERIOD),
    .LOCK_COUNT(LOCK_COUNT),
    .ERR_W(16)
  ) dut (
    .dco_clk(dco_clk),
    .rst_n(rst_n),
    .fco_in(fco_in),
    .aligned(aligned),
    .align_pulse(align_pulse),
    .align_err_pulse(align_err_pulse),
    .err_count(err_count)
  );

  // clock 10ns period
  initial dco_clk = 1'b0;
  always  #5 dco_clk = ~dco_clk;

  // VCD
  initial begin
    $dumpfile("waves_fco_align.vcd");
    $dumpvars(0, tb_align_monitor_fco);
  end

  task automatic tick(int n);
    repeat(n) @(posedge dco_clk);
  endtask

  // Generate a 1-cycle pulse for fco_in (rising edge)
  task automatic pulse_fco;
    begin
      fco_in = 1'b0;
      @(negedge dco_clk); // change away from posedge
      fco_in = 1'b1;
      @(posedge dco_clk); // edge will be seen here
      @(negedge dco_clk);
      fco_in = 1'b0;
    end
  endtask

  initial begin
    // init
    rst_n = 1'b0;
    fco_in = 1'b0;

    tick(2);
    rst_n = 1'b1;

    
    for (int k = 0; k < (LOCK_COUNT + 2); k++) begin
      tick(EXPECT_PERIOD);  // wait EXPECT_PERIOD words
      pulse_fco();          // marker
      $display("t=%0t marker k=%0d aligned=%0b good_pulse=%0b err_pulse=%0b err=%0d",
               $time, k, aligned, align_pulse, align_err_pulse, err_count);
    end

    if (!aligned) begin
      $display("FAIL: expected aligned=1 after lock sequence");
      $fatal(1);
    end else begin
      $display("PASS: locked (aligned=1)");
    end

    
    tick(EXPECT_PERIOD - 2); // wrong timing
    pulse_fco();

    
    tick(1);

    if (aligned) begin
      $display("FAIL: expected aligned=0 after bad marker");
      $fatal(1);
    end
    if (err_count == 0) begin
      $display("FAIL: expected err_count increment");
      $fatal(1);
    end

    $display("PASS: detected mismatch (aligned=0, err_count=%0d)", err_count);

    $display("ALL TESTS PASSED ✅");
    #20;
    $finish;
  end

endmodule
