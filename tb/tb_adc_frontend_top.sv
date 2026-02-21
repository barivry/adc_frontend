`timescale 1ns/1ps

module tb_adc_frontend_top;

  // =========================================================
  // Parameters
  // =========================================================
  localparam int LANES         = 8;
  localparam int W             = 2*LANES;
  localparam int FIFO_DEPTH    = 8192;
  localparam int EXPECT_PERIOD = 16;

  localparam int SNAP_LEN      = 16304;
  localparam int MAX_CHECKS    = 16304;

  // =========================================================
  // Clocks / Reset
  // =========================================================
  logic dco_clk = 0;
  logic sys_clk = 0;
  logic rst_n = 0;
  logic sys_rst_n = 0;
  logic stall_dco_dbg;

  always #2 dco_clk = ~dco_clk;   // 250 MHz
  always #5 sys_clk = ~sys_clk;   // 100 MHz

  // =========================================================
  // DUT I/O
  // =========================================================
  logic [LANES-1:0] lvds_data;
  logic             lvds_fco;

  logic             out_ready;
  logic [W-1:0]     out_word;
  logic             out_valid;
  logic             aligned;

  logic             word_valid_dco_dbg;
  wire              word_valid_dco = word_valid_dco_dbg;

  // =========================================================
  // Snapshot control
  // =========================================================
  logic        snap_trigger;
  logic        snapshot_enable;   // <<< זה יוצא מ-snapshot_trigger בלבד
  logic        snapshot_done;

  // =========================================================
  // CSR bus
  // =========================================================
  logic        csr_wr_en;
  logic        csr_rd_en;
  logic [3:0]  csr_addr;
  logic [31:0] csr_wdata;
  logic [31:0] csr_rdata;

  // CSR outputs (separate signals!)
  logic        csr_stream_enable;
  logic [31:0] csr_snap_len;

  csr_regs u_csr (
    .clk            (sys_clk),
    .rst_n          (sys_rst_n),

    .csr_wr_en      (csr_wr_en),
    .csr_rd_en      (csr_rd_en),
    .csr_addr       (csr_addr),
    .csr_wdata      (csr_wdata),
    .csr_rdata      (csr_rdata),

    .stream_enable  (csr_stream_enable), // <<< לא snapshot_enable !
    .snap_len       (csr_snap_len),      // <<< לא snap_len של TB

    .snapshot_done  (snapshot_done)
  );

  // =========================================================
  // DUT
  // =========================================================
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
  .word_valid_dco_dbg(word_valid_dco_dbg),

  .stream_enable(snapshot_enable & csr_stream_enable),
  .snap_len      (csr_snap_len),        

  .stall_dco_dbg(stall_dco_dbg)
  );

  // =========================================================
  // snapshot_trigger instance
  // =========================================================
  snapshot_trigger #(
    .CNT_W(32)
  ) u_snap (
    .sys_clk         (sys_clk),
    .sys_rst_n       (sys_rst_n),

    .trigger         (snap_trigger),
    .snap_len        (csr_snap_len),   // <<< מה-CSR

    .axis_valid      (out_valid),
    .axis_ready      (out_ready),

    .snapshot_enable (snapshot_enable),
    .snapshot_done   (snapshot_done),
    .snap_count_dbg  ()
  );

  // =========================================================
  // VCD
  // =========================================================
  initial begin
    $dumpfile("waves_top.vcd");
    $dumpvars(0, tb_adc_frontend_top);
  end

  // =========================================================
  // CSR write task
  // =========================================================
  task automatic csr_write(input [3:0] addr, input [31:0] data);
    begin
      @(posedge sys_clk);
      csr_addr  <= addr;
      csr_wdata <= data;
      csr_wr_en <= 1'b1;
      @(posedge sys_clk);
      csr_wr_en <= 1'b0;
    end
  endtask

  // =========================================================
  // Reset sequence + CSR programming
  // =========================================================
  initial begin
    lvds_data     = '0;
    lvds_fco      = 1'b0;
    out_ready     = 1'b0;
    snap_trigger  = 1'b0;

    csr_wr_en     = 1'b0;
    csr_rd_en     = 1'b0;
    csr_addr      = '0;
    csr_wdata     = '0;

    rst_n     = 1'b0;
    sys_rst_n = 1'b0;

    repeat (20) @(posedge dco_clk);
    repeat (5)  @(posedge sys_clk);

    rst_n     = 1'b1;
    sys_rst_n = 1'b1;

    // <<< Program CSR regs AFTER reset
    csr_write(4'h4, SNAP_LEN);   // SNAP_LEN reg
    csr_write(4'h0, 32'h1);      // CTRL bit0 = stream_enable (arm)

    $display("START t=%0t", $time);
  end

  // =========================================================
  // DDR stimulus generation
  // =========================================================
  int unsigned gen_word;
  logic [W-1:0] cur_word;
  logic [W-1:0] cur_word_dly;

  function automatic logic [W-1:0] make_word(input int unsigned k);
    return k[W-1:0];
  endfunction

  task automatic drive_rise(input logic [W-1:0] w);
    int i;
    begin
      for (i = 0; i < LANES; i++)
        lvds_data[i] = w[2*i];
    end
  endtask

  task automatic drive_fall(input logic [W-1:0] w);
    int i;
    begin
      for (i = 0; i < LANES; i++)
        lvds_data[i] = w[2*i+1];
    end
  endtask

  always @(posedge dco_clk) begin
    if (!rst_n) begin
      gen_word     <= 0;
      cur_word     <= '0;
      cur_word_dly <= '0;
      drive_rise('0);
    end else begin
      if (!stall_dco_dbg) begin
        cur_word_dly <= cur_word;
        cur_word     <= make_word(gen_word);
        drive_rise(make_word(gen_word));
      end else begin
        drive_rise(cur_word);
      end
    end
  end

  always @(negedge dco_clk) begin
    if (rst_n) begin
      drive_fall(cur_word);
      if (!stall_dco_dbg) begin
        gen_word <= gen_word + 1;
      end
    end
  end

  // =========================================================
  // FCO generation (based on word_valid)
  // =========================================================
  int unsigned fco_cnt;

  always @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) begin
      fco_cnt  <= 0;
      lvds_fco <= 1'b0;
    end else begin
      lvds_fco <= 1'b0;
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

  // =========================================================
  // Alignment print
  // =========================================================
  logic aligned_d;
  always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) aligned_d <= 1'b0;
    else            aligned_d <= aligned;
  end
  always @(posedge sys_clk) begin
    if (aligned && !aligned_d)
      $display("ALIGNED (rising) @ t=%0t", $time);
  end

  // =========================================================
  // Snapshot trigger pulse (one-shot after alignment)
  // =========================================================
  logic fired_snapshot;

  always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      snap_trigger   <= 1'b0;
      fired_snapshot <= 1'b0;
    end else begin
      snap_trigger <= 1'b0;
      if (aligned && !aligned_d && !fired_snapshot) begin
        snap_trigger   <= 1'b1;
        fired_snapshot <= 1'b1;
        $display("SNAPSHOT TRIGGER @ t=%0t len=%0d", $time, csr_snap_len);
      end
    end
  end

  // =========================================================
  // Output ready policy: ONLY when snapshot_enable is active
  // =========================================================
  always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      out_ready <= 1'b0;
    end else begin
      out_ready <= aligned && snapshot_enable;
    end
  end

  // =========================================================
  // Scoreboard
  // =========================================================
  logic [W-1:0] exp_q[$];
  logic [W-1:0] exp;
  int unsigned  rd_cnt;

  always @(negedge dco_clk) begin
    if (rst_n && aligned && word_valid_dco && !stall_dco_dbg) begin
      exp_q.push_back(cur_word_dly);
    end
  end

  always @(posedge sys_clk) begin
    if (!sys_rst_n) begin
      rd_cnt <= 0;
    end else if (out_valid && out_ready) begin

      if (exp_q.size() == 0) begin
        $display("TB ERROR: exp_q empty at t=%0t rd_cnt=%0d", $time, rd_cnt);
        $fatal;
      end

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
    end
  end

  // =========================================================
  // Snapshot done -> check count and finish
  // =========================================================
  always @(posedge sys_clk) begin
    if (snapshot_done) begin
      $display("SNAPSHOT DONE @ t=%0t rd_cnt=%0d exp_q=%0d", $time, rd_cnt, exp_q.size());
      if (rd_cnt !== csr_snap_len) begin
        $display("SNAPSHOT ERROR: expected %0d samples, got %0d", csr_snap_len, rd_cnt);
        $fatal;
      end else begin
        $display("SNAPSHOT PASS ✅ samples=%0d", rd_cnt);
        $finish;
      end
    end
  end

  // =========================================================
  // Timeout
  // =========================================================
  initial begin
    #400_000_000;
    $display("TIMEOUT aligned=%0b rd_cnt=%0d exp_q=%0d out_ready=%0b out_valid=%0b snapshot_en=%0b",
             aligned, rd_cnt, exp_q.size(), out_ready, out_valid, snapshot_enable);
    $fatal;
  end

endmodule