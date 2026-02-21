`timescale 1ns/1ps

module csr_regs #(
  parameter int ADDR_W = 4,   // מספיק ל-0x0..0xC
  parameter int DATA_W = 32
)(
  input  logic              clk,
  input  logic              rst_n,

  // Simple CSR bus (TB / CPU)
  input  logic              csr_wr_en,
  input  logic              csr_rd_en,
  input  logic [ADDR_W-1:0] csr_addr,
  input  logic [DATA_W-1:0] csr_wdata,
  output logic [DATA_W-1:0] csr_rdata,

  // Control outputs
  output logic              stream_enable,
  output logic [DATA_W-1:0] snap_len,

  // Alignment controls
  output logic [7:0]        align_lock_n,
  output logic              align_deassert_on_err,

  // Status inputs
  input  logic              snapshot_done
);

  // ----------------------------
  // Registers
  // ----------------------------
  logic ctrl_reg;
  logic [DATA_W-1:0] snap_len_reg;
  logic [7:0] align_lock_n_reg;
  logic       align_deassert_on_err_reg;

  // ----------------------------
  // Write logic
  // ----------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_reg     <= 1'b0;
      snap_len_reg <= '0;
      align_lock_n_reg <= 8'd16;
      align_deassert_on_err_reg <= 1'b1;
    end else if (csr_wr_en) begin
      case (csr_addr)
        4'h0: ctrl_reg     <= csr_wdata[0];      // CTRL
        4'h4: snap_len_reg <= csr_wdata;          // SNAP_LEN
        // ALIGN_CFG: [7:0]=lock_n (0 -> default), [8]=deassert_on_err
        4'hC: begin
          align_lock_n_reg <= csr_wdata[7:0];
          align_deassert_on_err_reg <= csr_wdata[8];
        end
        default: ;
      endcase
    end
  end

  // ----------------------------
  // Read logic
  // ----------------------------
  always_comb begin
    csr_rdata = '0;
    if (csr_rd_en) begin
      case (csr_addr)
        4'h0: csr_rdata = {{31{1'b0}}, ctrl_reg};
        4'h4: csr_rdata = snap_len_reg;
        4'h8: csr_rdata = {{31{1'b0}}, snapshot_done};
        4'hC: csr_rdata = {23'b0, align_deassert_on_err_reg, align_lock_n_reg};
        default: csr_rdata = '0;
      endcase
    end
  end

  // ----------------------------
  // Outputs
  // ----------------------------
  assign stream_enable = ctrl_reg;
  assign snap_len      = snap_len_reg;
  assign align_lock_n          = align_lock_n_reg;
  assign align_deassert_on_err = align_deassert_on_err_reg;

endmodule