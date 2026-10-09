// ============================================================================
// picorv32_npu_top.v
//
// Complete Edge AI System-on-Chip integrating:
//   - PicoRV32 RISC-V CPU
//   - INT8 Neural Processing Unit (NPU) Hardware Accelerator
//   - Multiplexed 7-Segment Display Controller for Spartan-7 Boolean Board
//   - 115200 Baud UART Transceiver
//   - 16 User LEDs and Button Reset Synchronizer
//   - Boot ROM & Data RAM
//   - Input Image Dual-Port BRAM
//
// Designed for Real Digital Boolean Board (Spartan-7 XC7S50-CSGA324-1)
// ============================================================================

`timescale 1ns / 1ps

module picorv32_npu_top (
    input  wire        clk,        // 100 MHz oscillator, pin F14
    input  wire        btn_rst,    // Push-button reset, active-high, pin J2
    output wire [15:0] led,        // 16 user LEDs, pins G1..A4
    input  wire        UART_rxd,   // Serial RX, pin V12
    output wire        UART_txd,   // Serial TX, pin U11
    
    // 7-Segment Display Group 0 (Physical pins on Boolean Board)
    output wire [3:0]  D0_a,       // Anodes: A8, C7, C4, D5 (Active Low)
    output wire [6:0]  D0_seg,     // Cathodes: B5, D6, A7, B7, A5, C5, D7 (Active Low)
    
    // 7-Segment Display Group 1
    output wire [3:0]  D1_a,       // Anodes: E4, F3, J4, H3 (Active Low)
    output wire [6:0]  D1_seg      // Cathodes: D1, H4, B1, C2, D2, J3, F4 (Active Low)
);

    // ------------------------------------------------------------------
    // Reset synchronizer (btn_rst active-high -> resetn active-low)
    // ------------------------------------------------------------------
    reg [1:0] rst_sync = 2'b11;
    always @(posedge clk) begin
        rst_sync <= {rst_sync[0], btn_rst};
    end
    wire resetn = ~rst_sync[1];

    // ------------------------------------------------------------------
    // PicoRV32 Native Memory Interface
    // ------------------------------------------------------------------
    wire        mem_valid;
    wire        mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;

    picorv32 #(
        .ENABLE_COUNTERS (1),
        .ENABLE_MUL      (0),
        .ENABLE_DIV      (0),
        .BARREL_SHIFTER  (1),
        .COMPRESSED_ISA  (0),
        .PROGADDR_RESET  (32'h0000_0000)
    ) cpu (
        .clk       (clk),
        .resetn    (resetn),
        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),
        .irq       (32'b0)
    );

    // ------------------------------------------------------------------
    // Address Decoding
    // ------------------------------------------------------------------
    wire rom_sel     = (mem_addr[31:28] == 4'h0); // 0x0000_0000 - 0x0FFF_FFFF (Boot ROM)
    wire ram_sel     = (mem_addr[31:28] == 4'h1); // 0x1000_0000 - 0x1FFF_FFFF (App RAM)
    wire uart_sel    = (mem_addr[31:28] == 4'h2); // 0x2000_0000 - 0x2FFF_FFFF (UART)
    wire npu_sys_sel = (mem_addr[31:28] == 4'h3); // 0x3000_0000 - 0x3FFF_FFFF (NPU & Periphs)

    // Sub-regions in 0x3000_0000
    wire npu_reg_sel = npu_sys_sel && (mem_addr[15:12] == 4'h0); // 0x3000_0000 - 0x3000_00FF
    wire npu_img_sel = npu_sys_sel && (mem_addr[15:12] == 4'h0) && (mem_addr[11] == 1'b1); // 0x3000_0800 - 0x3000_0BFF

    // ------------------------------------------------------------------
    // Boot ROM: 8192 x 32-bit = 32 KB
    // ------------------------------------------------------------------
    localparam ROM_WORDS = 8192;
    (* ram_style = "block" *) reg [31:0] bootrom [0:ROM_WORDS-1];
    integer r_idx;
    initial begin
        for (r_idx = 0; r_idx < ROM_WORDS; r_idx = r_idx + 1)
            bootrom[r_idx] = 32'h00000013; // NOP
        $readmemh("firmware.hex", bootrom);
    end

    // ------------------------------------------------------------------
    // Application RAM: 2048 x 32-bit = 8 KB
    // ------------------------------------------------------------------
    localparam RAM_WORDS = 2048;
    (* ram_style = "block" *) reg [31:0] appram [0:RAM_WORDS-1];
    integer m_idx;
    initial begin
        for (m_idx = 0; m_idx < RAM_WORDS; m_idx = m_idx + 1)
            appram[m_idx] = 32'h0;
    end

    // ------------------------------------------------------------------
    // UART Peripheral: 115200 baud @ 100 MHz clock
    // ------------------------------------------------------------------
    localparam integer CLKS_PER_BIT = 868; // 100_000_000 / 115200

    reg        tx_busy = 1'b0;
    reg [15:0] tx_clkcnt;
    reg [3:0]  tx_bitidx;
    reg [9:0]  tx_shiftreg;
    reg        uart_txd_reg = 1'b1;
    assign UART_txd = uart_txd_reg;

    wire tx_start = uart_sel && mem_valid && !mem_ready &&
                    (mem_addr[3:2] == 2'b00) && (|mem_wstrb) && !tx_busy;

    always @(posedge clk) begin
        if (!resetn) begin
            tx_busy      <= 1'b0;
            uart_txd_reg <= 1'b1;
        end else if (tx_start) begin
            tx_shiftreg  <= {1'b1, mem_wdata[7:0], 1'b0};
            tx_bitidx    <= 4'd0;
            tx_clkcnt    <= 16'd0;
            tx_busy      <= 1'b1;
            uart_txd_reg <= 1'b0;
        end else if (tx_busy) begin
            if (tx_clkcnt == CLKS_PER_BIT - 1) begin
                tx_clkcnt <= 16'd0;
                if (tx_bitidx == 4'd9) begin
                    tx_busy <= 1'b0;
                end else begin
                    tx_bitidx    <= tx_bitidx + 4'd1;
                    tx_shiftreg  <= {1'b1, tx_shiftreg[9:1]};
                    uart_txd_reg <= tx_shiftreg[1];
                end
            end else begin
                tx_clkcnt <= tx_clkcnt + 16'd1;
            end
        end
    end

    reg [1:0] rxd_sync = 2'b11;
    always @(posedge clk) rxd_sync <= {rxd_sync[0], UART_rxd};
    wire rxd = rxd_sync[1];

    reg        rx_busy = 1'b0;
    reg        rx_aligned = 1'b0;
    reg [15:0] rx_clkcnt;
    reg [3:0]  rx_bitidx;
    reg [7:0]  rx_shiftreg;
    reg        rx_valid = 1'b0;
    reg [7:0]  rx_data;

    wire rx_read_ack = uart_sel && mem_valid && !mem_ready &&
                       (mem_addr[3:2] == 2'b00) && (mem_wstrb == 4'b0000);

    always @(posedge clk) begin
        if (!resetn) begin
            rx_busy  <= 1'b0;
            rx_valid <= 1'b0;
        end else begin
            if (rx_valid && rx_read_ack)
                rx_valid <= 1'b0;

            if (!rx_busy) begin
                if (!rxd) begin
                    rx_busy    <= 1'b1;
                    rx_aligned <= 1'b0;
                    rx_clkcnt  <= CLKS_PER_BIT / 2;
                    rx_bitidx  <= 4'd0;
                end
            end else begin
                if (rx_clkcnt == CLKS_PER_BIT - 1) begin
                    rx_clkcnt <= 16'd0;
                    if (!rx_aligned) begin
                        rx_aligned <= 1'b1;
                    end else if (rx_bitidx == 4'd8) begin
                        rx_busy  <= 1'b0;
                        rx_data  <= rx_shiftreg;
                        rx_valid <= 1'b1;
                    end else begin
                        rx_shiftreg <= {rxd, rx_shiftreg[7:1]};
                        rx_bitidx   <= rx_bitidx + 4'd1;
                    end
                end else begin
                    rx_clkcnt <= rx_clkcnt + 16'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Input Image Dual-Port BRAM (1024 Bytes = 4 banks x 256 bytes)
    // Port A: PicoRV32 32-bit word read/write with byte-strobes
    // Port B: NPU Accelerator 8-bit read
    // ------------------------------------------------------------------
    reg [7:0] img_bram0 [0:255];
    reg [7:0] img_bram1 [0:255];
    reg [7:0] img_bram2 [0:255];
    reg [7:0] img_bram3 [0:255];

    reg [7:0] init_img [0:1023];
    integer init_i;
    initial begin
        for (init_i = 0; init_i < 1023; init_i = init_i + 1)
            init_img[init_i] = 8'h00;
        $readmemh("input_test_image.mem", init_img);
        for (init_i = 0; init_i < 256; init_i = init_i + 1) begin
            img_bram0[init_i] = init_img[{init_i[7:0], 2'b00}];
            img_bram1[init_i] = init_img[{init_i[7:0], 2'b01}];
            img_bram2[init_i] = init_img[{init_i[7:0], 2'b10}];
            img_bram3[init_i] = init_img[{init_i[7:0], 2'b11}];
        end
    end

    // Port B: NPU Accelerator Read
    wire [9:0] npu_img_addr;
    reg  [7:0] npu_img_b0_reg, npu_img_b1_reg, npu_img_b2_reg, npu_img_b3_reg;
    reg  [1:0] npu_img_sel_reg;

    always @(posedge clk) begin
        npu_img_b0_reg  <= img_bram0[npu_img_addr[9:2]];
        npu_img_b1_reg  <= img_bram1[npu_img_addr[9:2]];
        npu_img_b2_reg  <= img_bram2[npu_img_addr[9:2]];
        npu_img_b3_reg  <= img_bram3[npu_img_addr[9:2]];
        npu_img_sel_reg <= npu_img_addr[1:0];
    end

    wire [7:0] npu_img_rdata = (npu_img_sel_reg == 2'b00) ? npu_img_b0_reg :
                               (npu_img_sel_reg == 2'b01) ? npu_img_b1_reg :
                               (npu_img_sel_reg == 2'b10) ? npu_img_b2_reg :
                                                            npu_img_b3_reg;

    // ------------------------------------------------------------------
    // NPU Hardware Accelerator Instance
    // ------------------------------------------------------------------
    reg        npu_start_full = 1'b0;
    reg        npu_start_l1   = 1'b0;
    reg        npu_start_l2   = 1'b0;
    reg [4:0]  npu_shift_reg  = 5'd10; // Default L1 shift = 10 bits

    wire       npu_busy;
    wire       npu_done;
    reg        npu_done_latched = 1'b0;
    wire [31:0] npu_cycle_count;
    wire [3:0]  npu_predicted_digit;

    wire signed [31:0] score_0, score_1, score_2, score_3, score_4;
    wire signed [31:0] score_5, score_6, score_7, score_8, score_9;
    wire [7:0] act1_0, act1_1, act1_2, act1_3, act1_4, act1_5, act1_6, act1_7;
    wire [7:0] act1_8, act1_9, act1_10, act1_11, act1_12, act1_13, act1_14, act1_15;

    npu_controller #(
        .WEIGHTS_L1_FILE ("weights_l1.mem"),
        .BIASES_L1_FILE  ("biases_l1.mem"),
        .WEIGHTS_L2_FILE ("weights_l2.mem"),
        .BIASES_L2_FILE  ("biases_l2.mem")
    ) u_npu (
        .clk             (clk),
        .rst_n           (resetn),
        .start_full      (npu_start_full),
        .start_l1        (npu_start_l1),
        .start_l2        (npu_start_l2),
        .l1_shift        (npu_shift_reg),
        .busy            (npu_busy),
        .done            (npu_done),
        .cycle_count     (npu_cycle_count),
        .predicted_digit (npu_predicted_digit),
        .img_addr        (npu_img_addr),
        .img_rdata       (npu_img_rdata),
        .score_0         (score_0), .score_1 (score_1), .score_2 (score_2), .score_3 (score_3),
        .score_4         (score_4), .score_5 (score_5), .score_6 (score_6), .score_7 (score_7),
        .score_8         (score_8), .score_9 (score_9),
        .act1_0          (act1_0),  .act1_1  (act1_1),  .act1_2  (act1_2),  .act1_3  (act1_3),
        .act1_4          (act1_4),  .act1_5  (act1_5),  .act1_6  (act1_6),  .act1_7  (act1_7),
        .act1_8          (act1_8),  .act1_9  (act1_9),  .act1_10 (act1_10), .act1_11 (act1_11),
        .act1_12         (act1_12), .act1_13 (act1_13), .act1_14 (act1_14), .act1_15 (act1_15)
    );

    // ------------------------------------------------------------------
    // LED Register & 7-Segment Control Register
    // ------------------------------------------------------------------
    reg [15:0] led_reg = 16'h0000;
    
    // Heartbeat / activity indicator
    reg [25:0] heartbeat_cnt = 26'd0;
    always @(posedge clk) heartbeat_cnt <= heartbeat_cnt + 26'd1;

    // LEDs show:
    // [3:0] : Hardware predicted digit (0-9) in binary
    // [4]   : NPU busy
    // [5]   : NPU done
    // [6]   : Heartbeat blinker
    // [7]   : UART TX active
    // [15:8]: Software controlled LEDs
    assign led = {led_reg[15:8], tx_busy, heartbeat_cnt[25], (npu_done | npu_done_latched), npu_busy, npu_predicted_digit};

    // 7-Segment Register (32-bit):
    // bit 31: 0 = Auto-display predicted digit on D0 (displays: " - <digit>")
    //         1 = Manual display from register fields
    // [15:0] : Digits 3..0
    // [23:16]: Digit enables
    reg [31:0] seven_seg_reg = 32'h0000_0000;

    wire [3:0] sseg_d0_digit0 = (seven_seg_reg[31]) ? seven_seg_reg[3:0]   : npu_predicted_digit;
    wire [3:0] sseg_d0_digit1 = (seven_seg_reg[31]) ? seven_seg_reg[7:4]   : 4'h0;
    wire [3:0] sseg_d0_digit2 = (seven_seg_reg[31]) ? seven_seg_reg[11:8]  : 4'h0;
    wire [3:0] sseg_d0_digit3 = (seven_seg_reg[31]) ? seven_seg_reg[15:12] : 4'h0;
    wire [3:0] sseg_d0_en     = (seven_seg_reg[31]) ? seven_seg_reg[19:16] : 4'b0001; // Only enable digit 0

    seven_seg_controller u_sseg (
        .clk       (clk),
        .rst_n     (resetn),
        .d0_digit0 (sseg_d0_digit0),
        .d0_digit1 (sseg_d0_digit1),
        .d0_digit2 (sseg_d0_digit2),
        .d0_digit3 (sseg_d0_digit3),
        .d0_enable (sseg_d0_en),
        .d1_digit0 (4'h0),
        .d1_digit1 (4'h0),
        .d1_digit2 (4'h0),
        .d1_digit3 (4'h0),
        .d1_enable (4'b0000), // Off or available for expansion
        .D0_a      (D0_a),
        .D0_seg    (D0_seg),
        .D1_a      (D1_a),
        .D1_seg    (D1_seg)
    );

    // ------------------------------------------------------------------
    // Memory-Mapped Access Handshake
    // ------------------------------------------------------------------
    wire npu_ctrl_write = npu_reg_sel && !npu_img_sel && (mem_addr[7:2] == 6'h00) &&
                          mem_valid && !mem_ready && mem_wstrb[0];

    always @(posedge clk) begin
        if (!resetn) begin
            npu_start_full     <= 1'b0;
            npu_start_l1       <= 1'b0;
            npu_start_l2       <= 1'b0;
            npu_done_latched   <= 1'b0;
        end else begin
            // Single cycle start pulse
            if (npu_start_full) npu_start_full <= 1'b0;
            if (npu_start_l1)   npu_start_l1   <= 1'b0;
            if (npu_start_l2)   npu_start_l2   <= 1'b0;

            if (npu_ctrl_write) begin
                npu_start_full   <= mem_wdata[0];
                npu_start_l1     <= mem_wdata[1];
                npu_start_l2     <= mem_wdata[2];
                npu_done_latched <= 1'b0;
            end else if (npu_done) begin
                npu_done_latched <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        mem_ready <= 1'b0;

        if (mem_valid && !mem_ready) begin
            mem_ready <= 1'b1;

            // 1. Boot ROM (0x0000_0000 - 0x0FFF_FFFF)
            if (rom_sel) begin
                mem_rdata <= bootrom[mem_addr[14:2]];
            end

            // 2. Application RAM (0x1000_0000 - 0x1FFF_FFFF)
            else if (ram_sel) begin
                mem_rdata <= appram[mem_addr[12:2]];
                if (mem_wstrb[0]) appram[mem_addr[12:2]][ 7: 0] <= mem_wdata[ 7: 0];
                if (mem_wstrb[1]) appram[mem_addr[12:2]][15: 8] <= mem_wdata[15: 8];
                if (mem_wstrb[2]) appram[mem_addr[12:2]][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) appram[mem_addr[12:2]][31:24] <= mem_wdata[31:24];
            end

            // 3. UART Peripheral (0x2000_0000)
            else if (uart_sel) begin
                if (mem_addr[3:2] == 2'b00)
                    mem_rdata <= {24'h0, rx_data};           // DATA register
                else
                    mem_rdata <= {30'h0, rx_valid, tx_busy};  // STATUS register
            end

            // 4. Input Image BRAM Port A (0x3000_0800 - 0x3000_0BFF)
            else if (npu_img_sel) begin
                mem_rdata <= {img_bram3[mem_addr[9:2]], img_bram2[mem_addr[9:2]],
                              img_bram1[mem_addr[9:2]], img_bram0[mem_addr[9:2]]};
                if (mem_wstrb[0]) img_bram0[mem_addr[9:2]] <= mem_wdata[ 7: 0];
                if (mem_wstrb[1]) img_bram1[mem_addr[9:2]] <= mem_wdata[15: 8];
                if (mem_wstrb[2]) img_bram2[mem_addr[9:2]] <= mem_wdata[23:16];
                if (mem_wstrb[3]) img_bram3[mem_addr[9:2]] <= mem_wdata[31:24];
            end

            // 5. NPU Peripheral Control / Status / Output Registers (0x3000_0000 - 0x3000_00FF)
            else if (npu_reg_sel) begin
                case (mem_addr[7:2])
                    6'h00: begin // 0x3000_0000: NPU CTRL
                        mem_rdata <= {29'b0, npu_start_l2, npu_start_l1, npu_start_full};
                    end
                    6'h01: begin // 0x3000_0004: NPU STATUS
                        mem_rdata <= {30'b0, (npu_done | npu_done_latched), npu_busy};
                    end
                    6'h02: begin // 0x3000_0008: NPU CONFIG (Shift)
                        mem_rdata <= {27'b0, npu_shift_reg};
                        if (mem_wstrb[0]) npu_shift_reg <= mem_wdata[4:0];
                    end
                    6'h03: begin // 0x3000_000C: NPU PREDICTED DIGIT
                        mem_rdata <= {27'b0, (npu_done | npu_done_latched), npu_predicted_digit};
                    end
                    6'h04: begin // 0x3000_0010: NPU CYCLE COUNT
                        mem_rdata <= npu_cycle_count;
                    end
                    6'h05: begin // 0x3000_0014: 7-SEGMENT DISPLAY REGISTER
                        mem_rdata <= seven_seg_reg;
                        if (mem_wstrb[0]) seven_seg_reg[ 7: 0] <= mem_wdata[ 7: 0];
                        if (mem_wstrb[1]) seven_seg_reg[15: 8] <= mem_wdata[15: 8];
                        if (mem_wstrb[2]) seven_seg_reg[23:16] <= mem_wdata[23:16];
                        if (mem_wstrb[3]) seven_seg_reg[31:24] <= mem_wdata[31:24];
                    end
                    6'h06: begin // 0x3000_0018: LED REGISTER
                        mem_rdata <= {16'b0, led_reg};
                        if (mem_wstrb[0]) led_reg[ 7: 0] <= mem_wdata[ 7: 0];
                        if (mem_wstrb[1]) led_reg[15: 8] <= mem_wdata[15: 8];
                    end
                    
                    // Class 0-9 output scores (32-bit signed logits)
                    6'h08: mem_rdata <= score_0; // 0x3000_0020
                    6'h09: mem_rdata <= score_1; // 0x3000_0024
                    6'h0A: mem_rdata <= score_2; // 0x3000_0028
                    6'h0B: mem_rdata <= score_3; // 0x3000_002C
                    6'h0C: mem_rdata <= score_4; // 0x3000_0030
                    6'h0D: mem_rdata <= score_5; // 0x3000_0034
                    6'h0E: mem_rdata <= score_6; // 0x3000_0038
                    6'h0F: mem_rdata <= score_7; // 0x3000_003C
                    6'h10: mem_rdata <= score_8; // 0x3000_0040
                    6'h11: mem_rdata <= score_9; // 0x3000_0044
                    
                    // Hidden layer 1 activations (16 bytes packed into 4 words)
                    6'h14: mem_rdata <= {act1_3,  act1_2,  act1_1,  act1_0};  // 0x3000_0050
                    6'h15: mem_rdata <= {act1_7,  act1_6,  act1_5,  act1_4};  // 0x3000_0054
                    6'h16: mem_rdata <= {act1_11, act1_10, act1_9,  act1_8};  // 0x3000_0058
                    6'h17: mem_rdata <= {act1_15, act1_14, act1_13, act1_12}; // 0x3000_005C
                    
                    default: mem_rdata <= 32'h0000_0000;
                endcase
            end
        end
    end

endmodule
