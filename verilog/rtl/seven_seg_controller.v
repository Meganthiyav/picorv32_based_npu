// ============================================================================
// seven_seg_controller.v
//
// 7-Segment Display Controller for Real Digital Spartan-7 Boolean Board.
// Supports both 4-digit displays (D0 and D1), common anode (active low),
// active low cathodes. Includes 100 MHz clock divider for flicker-free
// multiplexing (~1.5 kHz refresh rate).
//
// Pin Mappings on Boolean Board:
//   D0_a   [3:0] : A8, C7, C4, D5 (Active Low Anodes for Digit Group 0)
//   D0_seg [6:0] : B5, D6, A7, B7, A5, C5, D7 (Active Low Segments G..A)
//   D1_a   [3:0] : E4, F3, J4, H3 (Active Low Anodes for Digit Group 1)
//   D1_seg [6:0] : D1, H4, B1, C2, D2, J3, F4 (Active Low Segments G..A)
// ============================================================================

`timescale 1ns / 1ps

module seven_seg_controller (
    input  wire        clk,            // 100 MHz oscillator
    input  wire        rst_n,          // Active-low reset
    
    // Display data inputs (hex/digit nibbles 0x0 - 0xF)
    input  wire [3:0]  d0_digit0,      // Rightmost digit on D0 (displays predicted digit 0-9)
    input  wire [3:0]  d0_digit1,
    input  wire [3:0]  d0_digit2,
    input  wire [3:0]  d0_digit3,
    input  wire [3:0]  d0_enable,      // 1 = digit enabled, 0 = blanked
    
    input  wire [3:0]  d1_digit0,      // D1 group digits
    input  wire [3:0]  d1_digit1,
    input  wire [3:0]  d1_digit2,
    input  wire [3:0]  d1_digit3,
    input  wire [3:0]  d1_enable,
    
    // Physical FPGA pins to 7-segment displays (Active LOW)
    output reg  [3:0]  D0_a,           // Anodes for D0
    output reg  [6:0]  D0_seg,         // Segments for D0 (bit 0 = A, bit 6 = G)
    output reg  [3:0]  D1_a,           // Anodes for D1
    output reg  [6:0]  D1_seg          // Segments for D1 (bit 0 = A, bit 6 = G)
);

    // 16-bit clock divider: 100 MHz / 65536 = ~1526 Hz total (~381 Hz per digit)
    reg [16:0] clk_div = 17'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clk_div <= 17'd0;
        else
            clk_div <= clk_div + 17'd1;
    end

    wire [1:0] scan_idx = clk_div[16:15]; // Cycles through digits 0, 1, 2, 3

    // Mux digit values based on current scan index
    reg [3:0] cur_d0_nibble;
    reg       cur_d0_en;
    reg [3:0] cur_d1_nibble;
    reg       cur_d1_en;

    always @(*) begin
        case (scan_idx)
            2'b00: begin
                cur_d0_nibble = d0_digit0;
                cur_d0_en     = d0_enable[0];
                cur_d1_nibble = d1_digit0;
                cur_d1_en     = d1_enable[0];
            end
            2'b01: begin
                cur_d0_nibble = d0_digit1;
                cur_d0_en     = d0_enable[1];
                cur_d1_nibble = d1_digit1;
                cur_d1_en     = d1_enable[1];
            end
            2'b10: begin
                cur_d0_nibble = d0_digit2;
                cur_d0_en     = d0_enable[2];
                cur_d1_nibble = d1_digit2;
                cur_d1_en     = d1_enable[2];
            end
            2'b11: begin
                cur_d0_nibble = d0_digit3;
                cur_d0_en     = d0_enable[3];
                cur_d1_nibble = d1_digit3;
                cur_d1_en     = d1_enable[3];
            end
        endcase
    end

    // Function to decode 4-bit nibble into active-low 7-segment pattern:
    // Segments: {G, F, E, D, C, B, A} = [6:0]
    function [6:0] hex2seg(input [3:0] val);
        case (val)
            4'h0: hex2seg = 7'b100_0000; // 0
            4'h1: hex2seg = 7'b111_1001; // 1
            4'h2: hex2seg = 7'b010_0100; // 2
            4'h3: hex2seg = 7'b011_0000; // 3
            4'h4: hex2seg = 7'b001_1001; // 4
            4'h5: hex2seg = 7'b001_0010; // 5
            4'h6: hex2seg = 7'b000_0010; // 6
            4'h7: hex2seg = 7'b111_1000; // 7
            4'h8: hex2seg = 7'b000_0000; // 8
            4'h9: hex2seg = 7'b001_0000; // 9
            4'hA: hex2seg = 7'b000_1000; // A
            4'hB: hex2seg = 7'b000_0011; // b
            4'hC: hex2seg = 7'b100_0110; // C
            4'hD: hex2seg = 7'b010_0001; // d
            4'hE: hex2seg = 7'b000_0110; // E
            4'hF: hex2seg = 7'b000_1110; // F
            default: hex2seg = 7'b111_1111; // Blank
        endcase
    endfunction

    // Drive outputs synchronously
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            D0_a   <= 4'b1111;
            D0_seg <= 7'b111_1111;
            D1_a   <= 4'b1111;
            D1_seg <= 7'b111_1111;
        end else begin
            // Anodes: Active Low (only selected digit enabled if enable bit is high)
            case (scan_idx)
                2'b00: D0_a <= cur_d0_en ? 4'b1110 : 4'b1111; // Digit 0 (pin D5)
                2'b01: D0_a <= cur_d0_en ? 4'b1101 : 4'b1111; // Digit 1 (pin C4)
                2'b10: D0_a <= cur_d0_en ? 4'b1011 : 4'b1111; // Digit 2 (pin C7)
                2'b11: D0_a <= cur_d0_en ? 4'b0111 : 4'b1111; // Digit 3 (pin A8)
            endcase
            D0_seg <= cur_d0_en ? hex2seg(cur_d0_nibble) : 7'b111_1111;

            case (scan_idx)
                2'b00: D1_a <= cur_d1_en ? 4'b1110 : 4'b1111; // Digit 0 (pin H3)
                2'b01: D1_a <= cur_d1_en ? 4'b1101 : 4'b1111; // Digit 1 (pin J4)
                2'b10: D1_a <= cur_d1_en ? 4'b1011 : 4'b1111; // Digit 2 (pin F3)
                2'b11: D1_a <= cur_d1_en ? 4'b0111 : 4'b1111; // Digit 3 (pin E4)
            endcase
            D1_seg <= cur_d1_en ? hex2seg(cur_d1_nibble) : 7'b111_1111;
        end
    end

endmodule
