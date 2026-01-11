`timescale 1ns/1ps

module cdc_async_fifo #(
  parameter int WIDTH = 16,
  parameter int DEPTH = 1024
)(
  
  input  logic             wr_clk,
  input  logic             wr_rst_n,
  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,
  output logic             wr_full,

  
  input  logic             rd_clk,
  input  logic             rd_rst_n,
  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,
  output logic             rd_valid,
  output logic             rd_empty
);

  localparam int ADDR_W = $clog2(DEPTH);

  
  logic [WIDTH-1:0] mem [0:DEPTH-1];

  
  logic [ADDR_W:0] wr_bin, wr_gray;
  logic [ADDR_W:0] rd_bin, rd_gray;

  
  logic [ADDR_W:0] rd_gray_sync1, rd_gray_sync2;
  logic [ADDR_W:0] wr_gray_sync1, wr_gray_sync2;

  
  logic [ADDR_W:0] wr_bin_next, wr_gray_next;
  logic [ADDR_W:0] rd_bin_next, rd_gray_next;

  logic wr_full_next;
  logic rd_empty_next;

  function automatic logic [ADDR_W:0] bin2gray(input logic [ADDR_W:0] b);
    bin2gray = (b >> 1) ^ b;
  endfunction

  function automatic logic full_cond(
    input logic [ADDR_W:0] wgray_next,
    input logic [ADDR_W:0] rgray_sync
  );
    logic [ADDR_W:0] r_inv;
    begin
      r_inv = rgray_sync;
      r_inv[ADDR_W]   = ~rgray_sync[ADDR_W];
      r_inv[ADDR_W-1] = ~rgray_sync[ADDR_W-1];
      full_cond = (wgray_next == r_inv);
    end
  endfunction

  
  wire wr_fire = wr_en && !wr_full;

  always @* begin
    wr_bin_next  = wr_bin + (wr_fire ? 1 : 0);
    wr_gray_next = bin2gray(wr_bin_next);
    wr_full_next = full_cond(wr_gray_next, rd_gray_sync2);
  end

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_bin  <= '0;
      wr_gray <= '0;
      wr_full <= 1'b0;
    end else begin
      wr_bin  <= wr_bin_next;
      wr_gray <= wr_gray_next;
      wr_full <= wr_full_next;

      if (wr_fire) begin
        mem[wr_bin[ADDR_W-1:0]] <= wr_data;
      end
    end
  end

  
  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      rd_gray_sync1 <= '0;
      rd_gray_sync2 <= '0;
    end else begin
      rd_gray_sync1 <= rd_gray;
      rd_gray_sync2 <= rd_gray_sync1;
    end
  end

  
  wire rd_fire = rd_en && !rd_empty;

  always @* begin
    rd_bin_next   = rd_bin + (rd_fire ? 1 : 0);
    rd_gray_next  = bin2gray(rd_bin_next);
    rd_empty_next = (rd_gray_next == wr_gray_sync2);
  end

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_bin   <= '0;
      rd_gray  <= '0;
      rd_data  <= '0;
      rd_valid <= 1'b0;
      rd_empty <= 1'b1;
    end else begin
      rd_bin   <= rd_bin_next;
      rd_gray  <= rd_gray_next;
      rd_valid <= 1'b0;
      rd_empty <= rd_empty_next;

      if (rd_fire) begin
        rd_data  <= mem[rd_bin[ADDR_W-1:0]];
        rd_valid <= 1'b1;
      end
    end
  end

  
  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      wr_gray_sync1 <= '0;
      wr_gray_sync2 <= '0;
    end else begin
      wr_gray_sync1 <= wr_gray;
      wr_gray_sync2 <= wr_gray_sync1;
    end
  end

endmodule
