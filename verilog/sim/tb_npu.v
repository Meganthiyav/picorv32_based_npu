// ============================================================================
// tb_npu.v - Testbench for INT8 Neural Processing Unit Accelerator Core
// ============================================================================

`timescale 1ns / 1ps

module tb_npu;

    reg clk = 0;
    always #5 clk = ~clk; // 100 MHz clock

    reg rst_n = 0;
    reg start_full = 0;
    reg start_l1 = 0;
    reg start_l2 = 0;
    reg [4:0] l1_shift = 5'd10;

    wire busy;
    wire done;
    wire [31:0] cycle_count;
    wire [3:0]  predicted_digit;

    wire [9:0] img_addr;
    reg  [7:0] img_rdata;

    wire signed [31:0] score_0, score_1, score_2, score_3, score_4;
    wire signed [31:0] score_5, score_6, score_7, score_8, score_9;

    // Test image memory (784 bytes)
    reg [7:0] test_image [0:1023];
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            test_image[i] = 8'd0;
        $readmemh("input_test_image.mem", test_image);
    end

    // Synchronous BRAM read for image
    always @(posedge clk) begin
        img_rdata <= test_image[img_addr];
    end

    npu_controller #(
        .WEIGHTS_L1_FILE ("weights_l1.mem"),
        .BIASES_L1_FILE  ("biases_l1.mem"),
        .WEIGHTS_L2_FILE ("weights_l2.mem"),
        .BIASES_L2_FILE  ("biases_l2.mem")
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_full      (start_full),
        .start_l1        (start_l1),
        .start_l2        (start_l2),
        .l1_shift        (l1_shift),
        .busy            (busy),
        .done            (done),
        .cycle_count     (cycle_count),
        .predicted_digit (predicted_digit),
        .img_addr        (img_addr),
        .img_rdata       (img_rdata),
        .score_0         (score_0), .score_1 (score_1), .score_2 (score_2), .score_3 (score_3),
        .score_4         (score_4), .score_5 (score_5), .score_6 (score_6), .score_7 (score_7),
        .score_8         (score_8), .score_9 (score_9)
    );

    initial begin
        $display("\n==========================================================");
        $display("   STARTING INT8 NPU ACCELERATOR STANDALONE TESTBENCH     ");
        $display("==========================================================");
        
        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        $display("[%0t ns] Triggering End-to-End Inference (Layer 1 + Layer 2)...", $time);
        start_full = 1;
        @(posedge clk);
        start_full = 0;

        // Wait until done
        @(posedge done);
        $display("[%0t ns] Inference Completed!", $time);
        $display("----------------------------------------------------------");
        $display(" Execution Cycles: %0d cycles (%0d ns @ 100 MHz)", cycle_count, cycle_count * 10);
        $display(" Predicted Digit:  %0d", predicted_digit);
        $display("----------------------------------------------------------");
        $display(" Class Output Logits:");
        $display("   Digit 0: %0d", score_0);
        $display("   Digit 1: %0d", score_1);
        $display("   Digit 2: %0d", score_2);
        $display("   Digit 3: %0d", score_3);
        $display("   Digit 4: %0d", score_4);
        $display("   Digit 5: %0d", score_5);
        $display("   Digit 6: %0d", score_6);
        $display("   Digit 7: %0d (Target Winner)", score_7);
        $display("   Digit 8: %0d", score_8);
        $display("   Digit 9: %0d", score_9);
        $display("----------------------------------------------------------");

        if (predicted_digit == 4'd7 && score_7 > score_0 && score_7 > score_1 && score_7 > score_2 &&
            score_7 > score_3 && score_7 > score_4 && score_7 > score_5 && score_7 > score_6 &&
            score_7 > score_8 && score_7 > score_9) begin
            $display(">>> TEST PASSED: Hardware prediction matches target digit 7! <<<\n");
        end else begin
            $display(">>> TEST FAILED: Prediction mismatch! <<<\n");
            $fatal(1);
        end

        repeat (20) @(posedge clk);
        $finish;
    end

endmodule
