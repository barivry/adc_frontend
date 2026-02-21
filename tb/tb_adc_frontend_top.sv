`timescale 1ns/1ps

module tb_adc_frontend_top;

  // =========================================================
  // Parameters
  // =========================================================
  localparam int LANES         = 8;
  localparam int W             = 2*LANES;
  localparam int FIFO_DEPTH    = 8192;
  localparam int EXPECT_PERIOD = 16;

  // Default snapshot lengths per test
  localparam int SMOKE_SNAP_LEN = 6304;
  localparam int PRBS_SNAP_LEN  = 6304;

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
  // Snapshot control (from snapshot_trigger)
  // =========================================================
  logic        snap_trigger;
  logic        snapshot_enable;   // output of snapshot_trigger
  logic        snapshot_done;     // output of snapshot_trigger

  // =========================================================
  // CSR bus
  // =========================================================
  logic        csr_wr_en;
  logic        csr_rd_en;
  logic [3:0]  csr_addr;
  logic [31:0] csr_wdata;
  logic [31:0] csr_rdata;

  // CSR outputs (separate signals)
  logic        csr_stream_enable;
  logic [31:0] csr_snap_len;
  logic [7:0]  csr_align_lock_n;
  logic        csr_align_deassert_on_err;

  // =========================================================
  // TEST selection: +TEST=smoke / +TEST=prbs
  // =========================================================
  typedef enum int { TEST_SMOKE = 0, TEST_PRBS = 1 } test_t;
  test_t test_sel;

  typedef enum int { STIM_RAMP = 0, STIM_PRBS = 1 } stim_t;
  stim_t stim_mode;

  // =========================================================
  // CSR regs
  // =========================================================
  csr_regs u_csr (
    .clk            (sys_clk),
    .rst_n          (sys_rst_n),

    .csr_wr_en      (csr_wr_en),
    .csr_rd_en      (csr_rd_en),
    .csr_addr       (csr_addr),
    .csr_wdata      (csr_wdata),
    .csr_rdata      (csr_rdata),

    .stream_enable  (csr_stream_enable),
    .snap_len       (csr_snap_len),

    .align_lock_n          (csr_align_lock_n),
    .align_deassert_on_err (csr_align_deassert_on_err),

    .snapshot_done  (snapshot_done)
  );

  // =========================================================
  // DUT
  // =========================================================
  adc_lvds_frontend_top #(
    .LANES(LANES),
    .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
    .dco_clk           (dco_clk),
    .rst_n             (rst_n),
    .lvds_data         (lvds_data),
    .lvds_fco          (lvds_fco),

    .sys_clk           (sys_clk),
    .sys_rst_n         (sys_rst_n),
    .out_ready         (out_ready),
    .out_word          (out_word),
    .out_valid         (out_valid),

    .aligned           (aligned),
    .word_valid_dco_dbg(word_valid_dco_dbg),

    // stream_enable gated by both snapshot window and CSR arm
    .stream_enable     (snapshot_enable & csr_stream_enable),

    // DUT gets snap_len from CSR
    .snap_len          (csr_snap_len),

    // Alignment controls from CSR
    .align_lock_n          (csr_align_lock_n),
    .align_deassert_on_err (csr_align_deassert_on_err),

    .stall_dco_dbg     (stall_dco_dbg)
  );

  // =========================================================
  // snapshot_trigger
  // =========================================================
  snapshot_trigger #(
    .CNT_W(32)
  ) u_snap (
    .sys_clk         (sys_clk),
    .sys_rst_n       (sys_rst_n),

    .trigger         (snap_trigger),
    .snap_len        (csr_snap_len),    // from CSR

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
      csr_addr  <= '0;
      csr_wdata <= '0;
    end
  endtask

  // =========================================================
  // Parse +TEST plusarg
  // =========================================================
  function automatic test_t parse_test_plusarg();
    string s;
    begin
      if ($value$plusargs("TEST=%s", s)) begin
        if (s == "smoke") return TEST_SMOKE;
        if (s == "prbs")  return TEST_PRBS;
        if (s == "fco_glitch") return TEST_SMOKE; // run like smoke but inject glitch
      end
      return TEST_SMOKE; // default
    end
  endfunction

  // =========================================================
  // Reset sequence + CSR programming
  // =========================================================
  initial begin
    // defaults
    lvds_data     = '0;
    lvds_fco      = 1'b0;
    out_ready     = 1'b0;
    snap_trigger  = 1'b0;

    csr_wr_en     = 1'b0;
    csr_rd_en     = 1'b0;
    csr_addr      = '0;
    csr_wdata     = '0;

    // decide test
    test_sel  = parse_test_plusarg();
    stim_mode = (test_sel == TEST_PRBS) ? STIM_PRBS : STIM_RAMP;

    rst_n     = 1'b0;
    sys_rst_n = 1'b0;

    repeat (20) @(posedge dco_clk);
    repeat (5)  @(posedge sys_clk);

    rst_n     = 1'b1;
    sys_rst_n = 1'b1;

    // let CSR settle
    repeat (3) @(posedge sys_clk);

    // program snap_len based on test
    if (test_sel == TEST_PRBS) begin
      csr_write(4'h4, PRBS_SNAP_LEN);
    end else begin
      csr_write(4'h4, SMOKE_SNAP_LEN);
    end

    // program ALIGN_CFG: lock_n=16, deassert_on_err=1
    csr_write(4'hC, {23'b0, 1'b1, 8'd16});

    // arm stream_enable
    csr_write(4'h0, 32'h1);

    $display("START t=%0t TEST=%0d snap_len=%0d", $time, test_sel, csr_snap_len);
  end

  // =========================================================
  // ✅ FIX MSB00: helper to force top-2 bits to 0
  // =========================================================
  function automatic logic [W-1:0] force_msb00(input logic [W-1:0] x);
    logic [W-1:0] y;
    begin
      y = x;
      y[W-1 -: 2] = 2'b00;   // bits [W-1:W-2] = 00
      force_msb00 = y;
    end
  endfunction

  // =========================================================
  // Stimulus helpers: Ramp + PRBS
  // =========================================================
  // PRBS16 (maximal-length example poly; good enough for TB stimulus)
  function automatic logic [15:0] prbs16_next(input logic [15:0] s);
    logic fb;
    begin
      // x^16 + x^14 + x^13 + x^11 + 1
      fb = s[15] ^ s[13] ^ s[12] ^ s[10];
      prbs16_next = {s[14:0], fb};
    end
  endfunction

  function automatic logic [15:0] make_ramp16(input int unsigned k);
    begin
      make_ramp16 = k[15:0];
    end
  endfunction

  // Golden model reconstruction (currently identity mapping)
  // If later you add lane swap / bit reordering, fix it HERE only.
  function automatic logic [W-1:0] golden_model(input logic [W-1:0] raw);
    begin
      // ✅ FIX MSB00: expected also has MSB00 by spec
      golden_model = force_msb00(raw);
    end
  endfunction

  // =========================================================
  // DDR stimulus generation (FIXED: rise/fall always same word)
  // =========================================================
  int unsigned gen_word;

  logic [W-1:0] cur_word;       // word being transmitted on BOTH edges
  logic [W-1:0] cur_word_dly;   // completed word (latched for expected queue)

  logic [15:0]  prbs_state;
  logic [15:0]  prbs_next;
  logic [W-1:0] next_word;

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

  // =========================================================
  // ✅ FIX MSB00: build next_word and then force MSB00 (both ramp and prbs)
  // =========================================================
  always @* begin
    prbs_next = prbs16_next(prbs_state);

    if (stim_mode == STIM_RAMP) begin
      next_word = force_msb00(make_ramp16(gen_word + 1));
    end else begin
      next_word = force_msb00(prbs_next);
    end
  end

  // posedge: drive RISE bits for current word (stable)
  always @(posedge dco_clk) begin
    if (!rst_n) begin
      gen_word     <= 0;
      prbs_state   <= 16'hACE1;
      cur_word     <= '0;
      cur_word_dly <= '0;
      drive_rise('0);
    end else begin
      // even in stall we keep output stable
      drive_rise(cur_word);
    end
  end

  // negedge: drive FALL bits for same word, then advance to next word (if not stalled)
  always @(negedge dco_clk) begin
    if (rst_n) begin
      drive_fall(cur_word);

      if (!stall_dco_dbg) begin
        // completed word
        cur_word_dly <= cur_word;

        // advance generator + state
        if (stim_mode == STIM_RAMP) begin
          gen_word <= gen_word + 1;
        end else begin
          prbs_state <= prbs_next;
        end

        // update cur_word to next_word (already forced MSB00)
        cur_word <= next_word;
      end
      // else: stall keeps cur_word constant
    end
  end

  // =========================================================
  // FCO generation (based on word_valid)
  // =========================================================
  // IMPORTANT:
  // Drive lvds_fco on the *negedge* so it's stable before the DUT samples it
  // on the posedge. Driving it on the same posedge can cause the DUT to miss
  // the pulse due to NBA scheduling order.
  int unsigned fco_cnt;

  // Glitch injection control (TB)
  logic glitch_pending;
  initial glitch_pending = 1'b0;

  always @(negedge dco_clk or negedge rst_n) begin
    if (!rst_n) begin
      fco_cnt  <= 0;
      lvds_fco <= 1'b0;
    end else begin
      // default low; a pulse will be held until the next negedge update
      lvds_fco <= 1'b0;
      if (word_valid_dco) begin
        // Optional: inject one EARLY FCO pulse to induce misalignment
        // Done once, after we have locked and snapshot started.
        if (glitch_pending && (fco_cnt == 3)) begin
          lvds_fco <= 1'b1;
          fco_cnt  <= 0;       // reset phase so subsequent pulses are clean
          glitch_pending <= 1'b0;
        end else if (fco_cnt == EXPECT_PERIOD-1) begin
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

  // Sticky alignment for expected-queue gating (matches RTL aligned_sticky)
  logic aligned_sticky_tb;

  // IMPORTANT: keep this in the DCO domain (matches DUT)
  always @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) aligned_sticky_tb <= 1'b0;
    else if (aligned) aligned_sticky_tb <= 1'b1;
  end

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

        // Arm glitch injection only for the dedicated glitch test
        if ($test$plusargs("TEST=fco_glitch")) begin
          glitch_pending <= 1'b1;
          $display("TB: FCO glitch armed @ t=%0t", $time);
        end
      end
    end
  end

  // =========================================================
  // Output ready policy: ONLY when snapshot_enable is active + CSR arm
  // =========================================================
  always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      out_ready <= 1'b0;
    end else begin
      // Keep streaming even if aligned deasserts due to a violation
      out_ready <= snapshot_enable && csr_stream_enable;
    end
  end

  // =========================================================
  // Scoreboard (expected queue built from COMPLETED words)
  // =========================================================
  logic [W-1:0] exp_q[$];
  logic [W-1:0] exp;
  int unsigned  rd_cnt;

  // Enqueue expected when DUT writes into FIFO (same condition as in RTL: aligned & word_valid & !stall)
  always @(negedge dco_clk) begin
    if (rst_n && aligned_sticky_tb && word_valid_dco && !stall_dco_dbg) begin
      exp_q.push_back(golden_model(cur_word_dly));
    end
  end

  // =========================================================
  // Glitch acceptance checks
  // =========================================================
  logic [15:0] err_cnt_start;
  logic        glitch_fired;
  logic        saw_err;
  logic        saw_aligned_drop;
  logic        saw_relock;

  always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      err_cnt_start     <= '0;
      glitch_fired      <= 1'b0;
      saw_err           <= 1'b0;
      saw_aligned_drop  <= 1'b0;
      saw_relock        <= 1'b0;
    end else begin
      if (snap_trigger) begin
        err_cnt_start    <= dut.u_align.err_count;
        glitch_fired     <= 1'b0;
        saw_err          <= 1'b0;
        saw_aligned_drop <= 1'b0;
        saw_relock       <= 1'b0;
      end

      if ($test$plusargs("TEST=fco_glitch") && fired_snapshot) begin
        // Detect that glitch was injected (glitch_pending drops after injection)
        if (!glitch_pending) glitch_fired <= 1'b1;

        if (glitch_fired && (dut.u_align.err_count > err_cnt_start)) begin
          if (!saw_err) $display("TB: align_err_cnt incremented (%0d -> %0d) @ t=%0t",
                                 err_cnt_start, dut.u_align.err_count, $time);
          saw_err <= 1'b1;
        end

        if (glitch_fired && !aligned) begin
          if (!saw_aligned_drop)
            $display("TB: aligned DEASSERTED on violation @ t=%0t", $time);
          saw_aligned_drop <= 1'b1;
        end

        if (glitch_fired && saw_aligned_drop && (aligned && !aligned_d)) begin
          if (!saw_relock) $display("TB: aligned RE-LOCKED after %0d good frames @ t=%0t", csr_align_lock_n, $time);
          saw_relock <= 1'b1;
        end
      end
    end
  end

  // Compare only on AXIS handshake
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
        $display("MISMATCH @ t=%0t rd_cnt=%0d exp_q=%0d", $time, rd_cnt, exp_q.size());
        $display(" expected=%b", exp);
        $display(" got     =%b", out_word);
        $fatal;
      end

      rd_cnt <= rd_cnt + 1;
    end
  end

  // =========================================================
  // Snapshot done -> check count and finish
  // =========================================================
  always @(posedge sys_clk) begin
    if (snapshot_done) begin
      $display("SNAPSHOT DONE @ t=%0t rd_cnt=%0d exp_q=%0d", $time, rd_cnt, exp_q.size());

      if ($test$plusargs("TEST=fco_glitch")) begin
        if (!saw_err) begin
          $display("TB ERROR: expected at least one alignment error (align_err_cnt increment)");
          $fatal;
        end
        if (!saw_aligned_drop) begin
          $display("TB ERROR: expected aligned to deassert on violation");
          $fatal;
        end
        if (!saw_relock) begin
          $display("TB ERROR: expected aligned to re-lock after N good frames");
          $fatal;
        end
      end

      if (rd_cnt != csr_snap_len) begin
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
    $display("TIMEOUT aligned=%0b rd_cnt=%0d exp_q=%0d out_ready=%0b out_valid=%0b snapshot_en=%0b csr_en=%0b snap_len=%0d",
             aligned, rd_cnt, exp_q.size(), out_ready, out_valid, snapshot_enable, csr_stream_enable, csr_snap_len);
    $fatal;
  end

endmodule