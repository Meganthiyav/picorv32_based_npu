// ============================================================================
// npu_controller.v - Memory-Efficient INT8 Neural Processing Unit Accelerator
//
// Accelerates fully connected layers for MNIST inference (784 -> 16 -> 10).
// Synthesizes cleanly into Spartan-7 Block RAM primitives (RAMB36) with zero
// logic overhead, pipelined MAC arithmetic, ReLU requantization, and argmax.
// ============================================================================

`timescale 1ns / 1ps

module npu_controller #(
    parameter WEIGHTS_L1_FILE = "weights_l1.mem",
    parameter BIASES_L1_FILE  = "biases_l1.mem",
    parameter WEIGHTS_L2_FILE = "weights_l2.mem",
    parameter BIASES_L2_FILE  = "biases_l2.mem"
)(
    input  wire               clk,
    input  wire               rst_n,

    // Control & Status
    input  wire               start_full,     // Run L1 + L2 + Argmax
    input  wire               start_l1,       // Run L1 only
    input  wire               start_l2,       // Run L2 only
    input  wire [4:0]         l1_shift,       // Quantization shift (default 10)
    output reg                busy,
    output reg                done,
    output reg  [31:0]        cycle_count,
    output reg  [3:0]         predicted_digit,

    // Interface to Input Image Dual-Port BRAM (Port B)
    output reg  [9:0]         img_addr,       // 0 to 783
    input  wire [7:0]         img_rdata,

    // Output Scores & Activations
    output wire signed [31:0] score_0,
    output wire signed [31:0] score_1,
    output wire signed [31:0] score_2,
    output wire signed [31:0] score_3,
    output wire signed [31:0] score_4,
    output wire signed [31:0] score_5,
    output wire signed [31:0] score_6,
    output wire signed [31:0] score_7,
    output wire signed [31:0] score_8,
    output wire signed [31:0] score_9,
    output wire [7:0]         act1_0,
    output wire [7:0]         act1_1,
    output wire [7:0]         act1_2,
    output wire [7:0]         act1_3,
    output wire [7:0]         act1_4,
    output wire [7:0]         act1_5,
    output wire [7:0]         act1_6,
    output wire [7:0]         act1_7,
    output wire [7:0]         act1_8,
    output wire [7:0]         act1_9,
    output wire [7:0]         act1_10,
    output wire [7:0]         act1_11,
    output wire [7:0]         act1_12,
    output wire [7:0]         act1_13,
    output wire [7:0]         act1_14,
    output wire [7:0]         act1_15
);

    // ------------------------------------------------------------------------
    // Layer 1 Model Storage (Weights: 16x784 = 12544 bytes, Biases: 16x32-bit)
    // Synchronous read ensures Block RAM (RAMB36) inference by Vivado
    // ------------------------------------------------------------------------
    (* ram_style = "block" *) reg signed [7:0] weights_l1 [0:12543];
    reg signed [31:0] biases_l1  [0:15];
    initial begin
        $readmemh(WEIGHTS_L1_FILE, weights_l1);
        $readmemh(BIASES_L1_FILE,  biases_l1);
    end

    reg [13:0]        wt_l1_addr;
    reg signed [7:0]  wt_l1_rdata;
    always @(posedge clk) begin
        wt_l1_rdata <= weights_l1[wt_l1_addr];
    end

    // ------------------------------------------------------------------------
    // Layer 2 Model Storage (Weights: 10x16 = 160 bytes, Biases: 10x32-bit)
    // ------------------------------------------------------------------------
    reg signed [7:0]  weights_l2 [0:159];
    reg signed [31:0] biases_l2  [0:9];
    initial begin
        $readmemh(WEIGHTS_L2_FILE, weights_l2);
        $readmemh(BIASES_L2_FILE,  biases_l2);
    end

    // ------------------------------------------------------------------------
    // Intermediate Activations & Output Score Registers
    // ------------------------------------------------------------------------
    reg [7:0]         act1_mem   [0:15];
    reg signed [31:0] scores_mem [0:9];

    assign score_0 = scores_mem[0]; assign score_1 = scores_mem[1];
    assign score_2 = scores_mem[2]; assign score_3 = scores_mem[3];
    assign score_4 = scores_mem[4]; assign score_5 = scores_mem[5];
    assign score_6 = scores_mem[6]; assign score_7 = scores_mem[7];
    assign score_8 = scores_mem[8]; assign score_9 = scores_mem[9];

    assign act1_0  = act1_mem[0];  assign act1_1  = act1_mem[1];
    assign act1_2  = act1_mem[2];  assign act1_3  = act1_mem[3];
    assign act1_4  = act1_mem[4];  assign act1_5  = act1_mem[5];
    assign act1_6  = act1_mem[6];  assign act1_7  = act1_mem[7];
    assign act1_8  = act1_mem[8];  assign act1_9  = act1_mem[9];
    assign act1_10 = act1_mem[10]; assign act1_11 = act1_mem[11];
    assign act1_12 = act1_mem[12]; assign act1_13 = act1_mem[13];
    assign act1_14 = act1_mem[14]; assign act1_15 = act1_mem[15];

    // ------------------------------------------------------------------------
    // Hardware MAC Unit
    // ------------------------------------------------------------------------
    reg                mac_clr;
    reg                mac_load_bias;
    reg signed [31:0]  mac_bias_in;
    reg                mac_en;
    reg signed [7:0]   mac_act_in;
    reg signed [7:0]   mac_wt_in;
    wire signed [31:0] mac_acc_out;

    npu_mac u_mac (
        .clk       (clk),
        .rst_n     (rst_n),
        .clr       (mac_clr),
        .load_bias (mac_load_bias),
        .bias_in   (mac_bias_in),
        .en        (mac_en),
        .act_in    (mac_act_in),
        .wt_in     (mac_wt_in),
        .acc_out   (mac_acc_out)
    );

    // ------------------------------------------------------------------------
    // FSM State Definitions
    // ------------------------------------------------------------------------
    localparam STATE_IDLE      = 4'd0;
    localparam STATE_L1_LOAD_B = 4'd1;
    localparam STATE_L1_READ   = 4'd2;
    localparam STATE_L1_MAC    = 4'd3;
    localparam STATE_L1_STORE  = 4'd4;
    localparam STATE_L2_LOAD_B = 4'd5;
    localparam STATE_L2_MAC    = 4'd6;
    localparam STATE_L2_STORE  = 4'd7;
    localparam STATE_ARGMAX    = 4'd8;
    localparam STATE_DONE      = 4'd9;

    reg [3:0]  state = STATE_IDLE;
    reg        full_mode = 1'b0;

    // Loop counters
    reg [4:0]  neuron_idx = 5'd0; // 0..15 for L1, 0..9 for L2
    reg [9:0]  input_idx  = 10'd0; // 0..783 for L1, 0..15 for L2
    reg [13:0] neuron_base_addr = 14'd0;
    reg [7:0]  wt_l2_addr = 8'd0;

    // Argmax registers
    reg signed [31:0] max_score;
    reg [3:0]         argmax_idx;

    // Cycle counting
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 32'd0;
        end else if (busy) begin
            cycle_count <= cycle_count + 32'd1;
        end else if (start_full || start_l1 || start_l2) begin
            cycle_count <= 32'd0;
        end
    end

    // ------------------------------------------------------------------------
    // Main Control FSM
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= STATE_IDLE;
            busy             <= 1'b0;
            done             <= 1'b0;
            full_mode        <= 1'b0;
            neuron_idx       <= 5'd0;
            input_idx        <= 10'd0;
            neuron_base_addr <= 14'd0;
            wt_l1_addr       <= 14'd0;
            wt_l2_addr       <= 8'd0;
            img_addr         <= 10'd0;
            mac_clr          <= 1'b1;
            mac_load_bias    <= 1'b0;
            mac_bias_in      <= 32'sd0;
            mac_en           <= 1'b0;
            mac_act_in       <= 8'sd0;
            mac_wt_in        <= 8'sd0;
            predicted_digit  <= 4'd0;
            max_score        <= -32'sd2147483647;
            argmax_idx       <= 4'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    done    <= 1'b0;
                    mac_clr <= 1'b0;
                    mac_en  <= 1'b0;
                    
                    if (start_full) begin
                        busy             <= 1'b1;
                        full_mode        <= 1'b1;
                        neuron_idx       <= 5'd0;
                        neuron_base_addr <= 14'd0;
                        wt_l1_addr       <= 14'd0;
                        state            <= STATE_L1_LOAD_B;
                    end else if (start_l1) begin
                        busy             <= 1'b1;
                        full_mode        <= 1'b0;
                        neuron_idx       <= 5'd0;
                        neuron_base_addr <= 14'd0;
                        wt_l1_addr       <= 14'd0;
                        state            <= STATE_L1_LOAD_B;
                    end else if (start_l2) begin
                        busy       <= 1'b1;
                        full_mode  <= 1'b0;
                        neuron_idx <= 5'd0;
                        wt_l2_addr <= 8'd0;
                        state      <= STATE_L2_LOAD_B;
                    end else begin
                        busy       <= 1'b0;
                    end
                end

                // ------------------------------------------------------------
                // LAYER 1: 16 Neurons x 784 Inputs
                // ------------------------------------------------------------
                STATE_L1_LOAD_B: begin
                    // Preload 32-bit bias for current neuron
                    mac_load_bias <= 1'b1;
                    mac_bias_in   <= biases_l1[neuron_idx[3:0]];
                    mac_en        <= 1'b0;
                    input_idx     <= 10'd0;
                    img_addr      <= 10'd0;            // Request pixel 0
                    wt_l1_addr    <= neuron_base_addr; // Request weight 0
                    state         <= STATE_L1_READ;
                end

                STATE_L1_READ: begin
                    mac_load_bias <= 1'b0;
                    // BRAM outputs valid on next clock edge
                    img_addr      <= 10'd1;
                    wt_l1_addr    <= neuron_base_addr + 14'd1;
                    state         <= STATE_L1_MAC;
                end

                STATE_L1_MAC: begin
                    // Accumulate current pixel and weight
                    mac_en     <= 1'b1;
                    mac_act_in <= img_rdata;
                    mac_wt_in  <= wt_l1_rdata;

                    if (input_idx == 10'd783) begin
                        state <= STATE_L1_STORE;
                    end else begin
                        input_idx  <= input_idx + 10'd1;
                        img_addr   <= input_idx + 10'd2;
                        wt_l1_addr <= wt_l1_addr + 14'd1;
                    end
                end

                STATE_L1_STORE: begin
                    mac_en <= 1'b0;
                    // ReLU & Requantization
                    if (mac_acc_out <= 32'sd0) begin
                        act1_mem[neuron_idx[3:0]] <= 8'd0;
                    end else if ((mac_acc_out >> l1_shift) > 32'd127) begin
                        act1_mem[neuron_idx[3:0]] <= 8'd127;
                    end else begin
                        act1_mem[neuron_idx[3:0]] <= (mac_acc_out >> l1_shift);
                    end

                    neuron_base_addr <= neuron_base_addr + 14'd784;

                    // Check if all 16 neurons complete
                    if (neuron_idx == 5'd15) begin
                        if (full_mode) begin
                            neuron_idx <= 5'd0;
                            wt_l2_addr <= 8'd0;
                            state      <= STATE_L2_LOAD_B;
                        end else begin
                            state <= STATE_DONE;
                        end
                    end else begin
                        neuron_idx <= neuron_idx + 5'd1;
                        state      <= STATE_L1_LOAD_B;
                    end
                end

                // ------------------------------------------------------------
                // LAYER 2: 10 Neurons x 16 Hidden Activations
                // ------------------------------------------------------------
                STATE_L2_LOAD_B: begin
                    mac_load_bias <= 1'b1;
                    mac_bias_in   <= biases_l2[neuron_idx];
                    mac_en        <= 1'b0;
                    input_idx     <= 10'd0;
                    state         <= STATE_L2_MAC;
                end

                STATE_L2_MAC: begin
                    mac_load_bias <= 1'b0;
                    mac_en        <= 1'b1;
                    mac_act_in    <= act1_mem[input_idx[3:0]];
                    mac_wt_in     <= weights_l2[wt_l2_addr];
                    wt_l2_addr    <= wt_l2_addr + 8'd1;

                    if (input_idx == 10'd15) begin
                        state <= STATE_L2_STORE;
                    end else begin
                        input_idx <= input_idx + 10'd1;
                    end
                end

                STATE_L2_STORE: begin
                    mac_en <= 1'b0;
                    scores_mem[neuron_idx] <= mac_acc_out;

                    if (neuron_idx == 5'd9) begin
                        neuron_idx <= 5'd0;
                        state      <= STATE_ARGMAX;
                    end else begin
                        neuron_idx <= neuron_idx + 5'd1;
                        state      <= STATE_L2_LOAD_B;
                    end
                end

                // ------------------------------------------------------------
                // ARGMAX: Find Class (0-9) With Highest Score
                // ------------------------------------------------------------
                STATE_ARGMAX: begin
                    if (neuron_idx == 5'd0) begin
                        max_score  <= scores_mem[0];
                        argmax_idx <= 4'd0;
                        neuron_idx <= 5'd1;
                    end else if (neuron_idx <= 5'd9) begin
                        if (scores_mem[neuron_idx] > max_score) begin
                            max_score  <= scores_mem[neuron_idx];
                            argmax_idx <= neuron_idx[3:0];
                        end
                        neuron_idx <= neuron_idx + 5'd1;
                    end else begin
                        predicted_digit <= argmax_idx;
                        state           <= STATE_DONE;
                    end
                end

                // ------------------------------------------------------------
                // COMPLETION
                // ------------------------------------------------------------
                STATE_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    if (!start_full && !start_l1 && !start_l2) begin
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
