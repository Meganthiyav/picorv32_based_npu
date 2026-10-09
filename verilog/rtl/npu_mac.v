// ============================================================================
// npu_mac.v - INT8 Multiply-Accumulate (MAC) Unit
//
// Performs signed INT8 x signed INT8 multiplication and 32-bit accumulation.
// Supports loading an initial 32-bit bias, clearing the accumulator,
// and accumulating products over vector elements.
// ============================================================================

`timescale 1ns / 1ps

module npu_mac (
    input  wire               clk,
    input  wire               rst_n,      // Active-low synchronous reset
    input  wire               clr,        // Clear accumulator to 0
    input  wire               load_bias,  // Preload accumulator with 32-bit bias
    input  wire signed [31:0] bias_in,    // 32-bit signed bias input
    input  wire               en,         // MAC enable (acc <= acc + a * b)
    input  wire signed [7:0]  act_in,     // Signed INT8 activation / input feature
    input  wire signed [7:0]  wt_in,      // Signed INT8 weight
    output wire signed [31:0] acc_out     // Current 32-bit accumulated sum
);

    reg signed [31:0] acc;

    // Signed 8x8 multiplication produces a signed 16-bit product
    wire signed [15:0] product = act_in * wt_in;

    always @(posedge clk) begin
        if (!rst_n) begin
            acc <= 32'sd0;
        end else if (clr) begin
            acc <= 32'sd0;
        end else if (load_bias) begin
            // Load bias, optionally adding the first product simultaneously
            if (en)
                acc <= bias_in + {{16{product[15]}}, product};
            else
                acc <= bias_in;
        end else if (en) begin
            acc <= acc + {{16{product[15]}}, product};
        end
    end

    assign acc_out = acc;

endmodule
