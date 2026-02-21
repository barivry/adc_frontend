`timescale 1ns/1ps

module snapshot_trigger #(
  parameter int CNT_W = 32
)(
  input  logic             sys_clk,
  input  logic             sys_rst_n,

  // Control
  input  logic             trigger,     // start snapshot (pulse)
  input  logic [CNT_W-1:0] snap_len,    // number of samples

  // AXI-stream handshake
  input  logic             axis_valid,
  input  logic             axis_ready,

  // Outputs
  output logic             snapshot_enable,
  output logic             snapshot_done,
  output logic [CNT_W-1:0] snap_count_dbg
);

  typedef enum logic [1:0] {
    IDLE,
    ACTIVE,
    DONE
  } state_t;

  state_t state;

  logic [CNT_W-1:0] count;

  wire beat = axis_valid && axis_ready;

  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      state            <= IDLE;
      count            <= '0;
      snapshot_enable  <= 1'b0;
      snapshot_done    <= 1'b0;

    end else begin
      snapshot_done <= 1'b0; // default pulse

      case (state)

        // ======================
        IDLE: begin
          snapshot_enable <= 1'b0;
          count <= '0;

          if (trigger) begin
            snapshot_enable <= 1'b1;
            state <= ACTIVE;
          end
        end

        // ======================
        ACTIVE: begin
          snapshot_enable <= 1'b1;

          if (beat) begin
            count <= count + 1;

            if (count + 1 == snap_len) begin
              snapshot_enable <= 1'b0;
              snapshot_done   <= 1'b1;
              state <= DONE;
            end
          end
        end

        // ======================
        DONE: begin
          snapshot_enable <= 1'b0;

          // מחכה שה-trigger ירד לפני חזרה ל-IDLE
          if (!trigger) begin
            state <= IDLE;
          end
        end

      endcase
    end
  end

  assign snap_count_dbg = count;

endmodule