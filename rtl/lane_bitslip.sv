
`timescale 1ns/1ps

module lane_bitslip #(
    parameter int LANES = 8
) (
    input  logic              dco_clk,
    input  logic              rst_n,           // active-low reset

    input  logic [LANES-1:0]  in_rise,         // from DDR capture (posedge)
    input  logic [LANES-1:0]  in_fall,         // from DDR capture (negedge)

    input  logic [LANES-1:0]  bitslip_pulse,   // toggle request (pulse), synchronous to dco_clk

    output logic [LANES-1:0]  out_rise,        // corrected, registered
    output logic [LANES-1:0]  out_fall         // corrected, registered
);

    logic [LANES-1:0] slip_offset;   // 0=normal, 1=half-bit slipped
    logic [LANES-1:0] prev_fall;     // stores f_k to be used as f_(k-1) next posedge
    logic [LANES-1:0] rise_hold;     // holds current rise (r_k) for use at negedge

    
    always_ff @(posedge dco_clk or negedge rst_n) begin
        if (!rst_n) begin
            slip_offset <= '0;
        end else begin
            slip_offset <= slip_offset ^ bitslip_pulse; 
    end

    
    always_ff @(posedge dco_clk or negedge rst_n) begin
        if (!rst_n) begin
            rise_hold <= '0;
            out_rise  <= '0;
        end else begin
            rise_hold <= in_rise;

            
            out_rise <= (slip_offset) ? prev_fall : in_rise;
        end
    end

    
    always_ff @(negedge dco_clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_fall <= '0;
            out_fall  <= '0;
        end else begin
          
            out_fall <= (slip_offset) ? rise_hold : in_fall;

            
            prev_fall <= in_fall;
        end
    end

endmodule
