`timescale 1ns/1ps

module tb_adc_frontend_top;

  localparam int LANES         = 8;
  localparam int W             = 2*LANES;
  localparam int FIFO_DEPTH    = 8192;
  localparam int EXPECT_PERIOD = 16;
  localparam int MAX_CHECKS    = 10000;
  ;

  logic dco_clk = 0;
  logic sys_clk = 0;
  logic rst_n = 0;
  logic sys_rst_n = 0;

  always #2 dco_clk = ~dco_clk;   // 250MHz
  always #5 sys_clk = ~sys_clk;   // 100MHz

  logic [LANES-1:0] lvds_data;
  logic             lvds_fco;

  logic             out_ready;
  logic [W-1:0]     out_word;
  logic             out_valid;
  logic             aligned;
  logic [W-1:0] cur_word_dly;


  logic             word_valid_dco_dbg;
  wire              word_valid_dco = word_valid_dco_dbg;

  adc_lvds_frontend_top #(
    .LANES(LANES),
    .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
    .dco_clk(dco_clk),
    .rst_n(rst_n),
    .lvds_data(lvds_data),
    .lvds_fco(lvds_fco),

    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .out_ready(out_ready),
    .out_word(out_word),
    .out_valid(out_valid),

    .aligned(aligned),
    .word_valid_dco_dbg(word_valid_dco_dbg)
  );

  initial begin
    $dumpfile("waves_top.vcd");
    $dumpvars(0, tb_adc_frontend_top);
  end

  // reset
  initial begin
    lvds_data = '0;
    lvds_fco  = 0;
    out_ready = 0;

    rst_n     = 0;
    sys_rst_n = 0;
    repeat (20) @(posedge dco_clk);
    repeat (5)  @(posedge sys_clk);
    rst_n     = 1;
    sys_rst_n = 1;
    $display("START t=%0t", $time);
  end

  // ========= DDR stimulus =========
  int unsigned gen_word;
  logic [W-1:0] cur_word;

  function automatic logic [W-1:0] make_word(input int unsigned k);
    logic [W-1:0] w;
    begin
      w = k[W-1:0];
      return w;
    end
  endfunction

  task automatic drive_rise(input logic [W-1:0] w);
    int i;
    begin
      for (i = 0; i < LANES; i++) lvds_data[i] = w[2*i];
    end
  endtask

  task automatic drive_fall(input logic [W-1:0] w);
    int i;
    begin
      for (i = 0; i < LANES; i++) lvds_data[i] = w[2*i+1];
    end
  endtask

  always @(posedge dco_clk) begin
  if (!rst_n) begin
    gen_word      <= 0;
    cur_word      <= '0;
    cur_word_dly  <= '0;
  end else begin
    cur_word_dly <= cur_word;          
    cur_word     <= make_word(gen_word);
    drive_rise(make_word(gen_word));
  end
end


  always @(negedge dco_clk) begin
    if (rst_n) begin
      drive_fall(cur_word);
      gen_word <= gen_word + 1;
    end
  end

  // ========= FCO generation based on word_valid =========
  int unsigned fco_cnt;

  always @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) begin
      fco_cnt <= 0;
      lvds_fco <= 0;
    end else begin
      lvds_fco <= 0;
      if (word_valid_dco) begin
        if (fco_cnt == EXPECT_PERIOD-1) begin
          lvds_fco <= 1'b1;
          fco_cnt  <= 0;
        end else begin
          fco_cnt <= fco_cnt + 1;
        end
      end
    end
  end

  // ========= consume only after aligned =========
  always @(posedge sys_clk) begin
    if (!sys_rst_n) out_ready <= 1'b0;
    else if (aligned) out_ready <= 1'b1; // latch-on
  end

  // print aligned only on rising edge
  logic aligned_d;
  always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) aligned_d <= 1'b0;
    else            aligned_d <= aligned;
  end
  always @(posedge sys_clk) begin
    if (aligned && !aligned_d)
      $display("ALIGNED (rising) @ t=%0t", $time);
  end

  // ========= scoreboard =========
  logic [W-1:0] exp_q[$];
  int unsigned rd_cnt;

  // Push expected ONLY when DUT actually WRITES to FIFO (same wr_en condition)
 always @(negedge dco_clk) begin
  if (rst_n && aligned && word_valid_dco) begin
    exp_q.push_back(cur_word_dly);     // <<< היה cur_word
  end
end


  always @(posedge sys_clk) begin
    if (!sys_rst_n) begin
      rd_cnt <= 0;
    end else if (out_valid && out_ready) begin
      logic [W-1:0] exp;
      exp = exp_q.pop_front();

      if (out_word !== exp) begin
        $display("FAIL t=%0t rd_cnt=%0d exp_q=%0d", $time, rd_cnt, exp_q.size());
        $display("expected=%b", exp);
        $display("got     =%b", out_word);
        $fatal;
      end

      rd_cnt <= rd_cnt + 1;

      if ((rd_cnt % 200) == 0)
        $display("PROGRESS t=%0t rd_cnt=%0d exp_q=%0d", $time, rd_cnt, exp_q.size());

      if (rd_cnt == MAX_CHECKS) begin
        $display("PASS ✅ rd_cnt=%0d", rd_cnt);
        $finish;
      end
    end
  end

  initial begin
    #20_000_000;
    $display("TIMEOUT aligned=%0b rd_cnt=%0d exp_q=%0d out_ready=%0b out_valid=%0b",
             aligned, rd_cnt, exp_q.size(), out_ready, out_valid);
    $fatal;
  end

endmodule
