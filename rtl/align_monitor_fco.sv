`timescale 1ns/1ps

module align_monitor_fco #(
  parameter int EXPECT_PERIOD = 16,
  // Default: require N consecutive good frames before declaring aligned=1
  parameter int LOCK_N_DFLT   = 16,
  // Default behavior on violation: deassert aligned (but datapath should keep streaming)
  parameter bit DEASSERT_ON_ERR_DFLT = 1'b1,
  parameter int ERR_W         = 16
)(
  input  logic             dco_clk,
  input  logic             rst_n,
  input  logic             fco_in,
  input  logic             word_valid,

  // Runtime overrides (CSR): if lock_n_cfg==0 -> use LOCK_N_DFLT
  input  logic [7:0]       lock_n_cfg,
  input  logic             deassert_on_err_cfg,

  output logic             aligned,
  output logic             align_pulse,
  output logic             align_err_pulse,
  output logic [ERR_W-1:0] err_count
);

  logic fco_d;
  logic fco_rise;

  int unsigned words_since;
  int unsigned good_streak;
  logic first_seen;

  // Effective runtime config
  logic [7:0] lock_n_eff;
  logic       deassert_on_err_eff;

  always_comb begin
    // lock_n_cfg == 0 means "use default"
    lock_n_eff = (lock_n_cfg != 8'd0) ? lock_n_cfg : 8'(LOCK_N_DFLT);
    // guard: avoid 0 (would lock immediately)
    if (lock_n_eff == 8'd0) lock_n_eff = 8'd1;

    // Treat X as default
    if (deassert_on_err_cfg === 1'b0)      deassert_on_err_eff = 1'b0;
    else if (deassert_on_err_cfg === 1'b1) deassert_on_err_eff = 1'b1;
    else                                   deassert_on_err_eff = DEASSERT_ON_ERR_DFLT;
  end

  function automatic logic [ERR_W-1:0] sat_inc(input logic [ERR_W-1:0] x);
    if (&x) sat_inc = x;
    else    sat_inc = x + 1;
  endfunction

  always_ff @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) fco_d <= 1'b0;
    else        fco_d <= fco_in;
  end

  assign fco_rise = fco_in & ~fco_d;

  always_ff @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) begin
      aligned         <= 1'b0;
      align_pulse     <= 1'b0;
      align_err_pulse <= 1'b0;
      err_count       <= '0;

      words_since <= 0;
      good_streak <= 0;
      first_seen  <= 1'b0;

    end else begin
      align_pulse     <= 1'b0;
      align_err_pulse <= 1'b0;

      if (word_valid) begin
        int unsigned next_words;
        next_words = words_since + 1;

        if (fco_rise) begin
          if (!first_seen) begin
            first_seen  <= 1'b1;
            words_since <= 0;
            good_streak <= 0;
            aligned     <= 1'b0;
          end else begin
            if (next_words == EXPECT_PERIOD) begin
              align_pulse <= 1'b1;

              // Count consecutive good frames; lock only after N good frames
              if (good_streak < lock_n_eff) good_streak <= good_streak + 1;
              if (good_streak + 1 >= lock_n_eff) aligned <= 1'b1;

            end else begin
              align_err_pulse <= 1'b1;
              err_count       <= sat_inc(err_count);
              good_streak     <= 0;
              if (deassert_on_err_eff) aligned <= 1'b0;
            end

            words_since <= 0;
          end
        end else begin
          words_since <= next_words;
        end
      end
    end
  end

endmodule