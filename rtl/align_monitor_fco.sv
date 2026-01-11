`timescale 1ns/1ps

module align_monitor_fco #(
  parameter int EXPECT_PERIOD = 16,
  parameter int LOCK_COUNT    = 4,
  parameter int ERR_W         = 16
)(
  input  logic             dco_clk,
  input  logic             rst_n,
  input  logic             fco_in,
  input  logic             word_valid,

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

  function automatic logic [ERR_W-1:0] sat_inc(input logic [ERR_W-1:0] x);
    if (&x) sat_inc = x;
    else    sat_inc = x + 1;
  endfunction

  always_ff @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) begin
      fco_d <= 1'b0;
    end else begin
      fco_d <= fco_in;
    end
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
          end else begin
            if (next_words == EXPECT_PERIOD) begin
              align_pulse <= 1'b1;

              if (good_streak < LOCK_COUNT) good_streak <= good_streak + 1;
              if (good_streak + 1 >= LOCK_COUNT) aligned <= 1'b1;

            end else begin
              align_err_pulse <= 1'b1;
              err_count       <= sat_inc(err_count);
              good_streak     <= 0;
              aligned         <= 1'b0;
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
