// ============================================================================
// tb_picorv32_npu.v - Complete SoC Testbench for PicoRV32 + INT8 NPU
//
// Simulates the full system:
//   - PicoRV32 RISC-V CPU booting from ROM
//   - Execution of firmware.hex
//   - Dual-Port Image BRAM access
//   - Memory-mapped NPU acceleration
//   - Live UART console text decoding
//   - 7-Segment display output monitoring
// ============================================================================

`timescale 1ns / 1ps

module tb_picorv32_npu;

    reg clk = 0;
    always #5 clk = ~clk; // 100 MHz clock

    reg btn_rst = 1; // Active-high reset button
    wire [15:0] led;
    wire UART_rxd = 1'b1;
    wire UART_txd;

    wire [3:0] D0_a;
    wire [6:0] D0_seg;
    wire [3:0] D1_a;
    wire [6:0] D1_seg;

    picorv32_npu_top u_top (
        .clk      (clk),
        .btn_rst  (btn_rst),
        .led      (led),
        .UART_rxd (UART_rxd),
        .UART_txd (UART_txd),
        .D0_a     (D0_a),
        .D0_seg   (D0_seg),
        .D1_a     (D1_a),
        .D1_seg   (D1_seg)
    );

    // ------------------------------------------------------------------------
    // UART Monitor: Captures serial bits at 115200 baud (868 clocks/bit @ 100MHz)
    // ------------------------------------------------------------------------
    localparam CLKS_PER_BIT = 868;
    reg [7:0] rx_byte;
    integer bit_i;

    initial begin
        forever begin
            @(negedge UART_txd); // Start bit detection
            #( (CLKS_PER_BIT * 10) + (CLKS_PER_BIT * 5) ); // Sample center of bit 0
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                rx_byte[bit_i] = UART_txd;
                #(CLKS_PER_BIT * 10);
            end
            $write("%c", rx_byte);
            $fflush();
            #(CLKS_PER_BIT * 5); // Wait until near end of stop bit
        end
    end

    // Monitor 7-Segment Display activity
    always @(u_top.sseg_d0_digit0) begin
        $display("\n[%0t ns] *** 7-SEGMENT DISPLAY UPDATE: Digit D0 = %0d ***", 
                 $time, u_top.sseg_d0_digit0);
    end

    // ------------------------------------------------------------------------
    // Dynamic Simulation Control: Wait for NPU Done event
    // ------------------------------------------------------------------------
    initial begin
        $display("\n==========================================================");
        $display("   STARTING PICORV32 + INT8 NPU FULL SOC TESTBENCH        ");
        $display("==========================================================");

        btn_rst = 1;
        repeat (50) @(posedge clk);
        btn_rst = 0;
        $display("[%0t ns] Reset released. PicoRV32 booting firmware...", $time);

        // Wait until NPU finishes hardware inference
        @(posedge u_top.npu_done);
        $display("\n[%0t ns] *** NPU HARDWARE ACCELERATOR COMPLETED INFERENCE! ***", $time);

        // Allow UART to finish streaming the performance evaluation table
        #25000000;
        $display("\n[%0t ns] Simulation finished successfully.", $time);
        $finish;
    end

endmodule
