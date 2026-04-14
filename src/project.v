// ==============================================================================
// PROJECT: DUAL-MODE BATTERY FAILURE ASIC (RADIOGRAPHY & THERMAL)
// TARGET: Tiny Tapeout (1x1 Tile)
// ==============================================================================

`default_nettype none

// ──────────────────────────────────────────────────────────────────────────────
// 1. FUNDAMENTAL ADDERS
// ──────────────────────────────────────────────────────────────────────────────
module df_halfadder(input wire a, input wire b, output wire s, output wire c);
    assign s = a ^ b;
    assign c = a & b;
endmodule

module df_fulladder(input wire a, input wire b, input wire ci, output wire s, output wire co);
    wire s1, c1, c2;
    assign c1 = a & b;
    assign s1 = a ^ b;
    assign c2 = s1 & ci;
    assign co = c1 | c2;
    assign s  = s1 ^ ci;
endmodule

module df_approx_fulladder(input wire a, input wire b, input wire ci, output wire s, output wire co);
    assign s  = a | b;
    assign co = a & b;
endmodule

// ──────────────────────────────────────────────────────────────────────────────
// 2. APPROXIMATE MULTIPLY-ACCUMULATE (MAC) TREE
// ──────────────────────────────────────────────────────────────────────────────
module df_approx_mac_tree
(
    input  wire signed [17:0] p0, p1, p2, p3,
    output wire signed [17:0] fir_sum
);
    genvar i;
    wire [17:0] sum_01, sum_23;
    wire [18:1] carry_01, carry_23, carry_final;

    df_halfadder ha_01 (p0[0], p1[0], sum_01[0], carry_01[1]);
    df_halfadder ha_23 (p2[0], p3[0], sum_23[0], carry_23[1]);

    generate
        for (i = 1; i <= 3; i = i + 1) begin : gen_s1_approx
            df_approx_fulladder approx_01 (p0[i], p1[i], carry_01[i], sum_01[i], carry_01[i+1]);
            df_approx_fulladder approx_23 (p2[i], p3[i], carry_23[i], sum_23[i], carry_23[i+1]);
        end
        for (i = 4; i <= 17; i = i + 1) begin : gen_s1_exact
            df_fulladder exact_01 (p0[i], p1[i], carry_01[i], sum_01[i], carry_01[i+1]);
            df_fulladder exact_23 (p2[i], p3[i], carry_23[i], sum_23[i], carry_23[i+1]);
        end
    endgenerate

    df_halfadder ha_fin (sum_01[0], sum_23[0], fir_sum[0], carry_final[1]);

    generate
        for (i = 1; i <= 3; i = i + 1) begin : gen_s2_approx
            df_approx_fulladder approx_fin (sum_01[i], sum_23[i], carry_final[i], fir_sum[i], carry_final[i+1]);
        end
        for (i = 4; i <= 17; i = i + 1) begin : gen_s2_exact
            df_fulladder exact_fin (sum_01[i], sum_23[i], carry_final[i], fir_sum[i], carry_final[i+1]);
        end
    endgenerate
endmodule

// ──────────────────────────────────────────────────────────────────────────────
// 3. CORE DIGITAL FILTER / TRIGGER ENGINE
// ──────────────────────────────────────────────────────────────────────────────
module df_digital_filter
(
    input  wire        CLK,
    input  wire        nRST,
    input  wire        mode_sel, 
    input  wire [7:0]  datain,
    output wire        trigger_alarm
);
    reg [7:0] val1, val2, val3, val4;
    wire event_valid;
    assign event_valid = |datain; 

    always @(posedge CLK or negedge nRST) begin
        if (nRST == 1'b0) begin
            val1 <= 8'b0; val2 <= 8'b0;
            val3 <= 8'b0; val4 <= 8'b0;
        end else begin
            if (event_valid) begin
                val4 <= val3; val3 <= val2;
                val2 <= val1; val1 <= datain;
            end
        end
    end

    wire signed [8:0] s_val1 = {1'b0, val1};
    wire signed [8:0] s_val2 = {1'b0, val2};
    wire signed [8:0] s_val3 = {1'b0, val3};
    wire signed [8:0] s_val4 = {1'b0, val4};

    // ─────────────────────────────────────────────────────────
    // CONSTANT-FOLDED MULTIPLIERS (Massive Cell Count Reduction)
    // ─────────────────────────────────────────────────────────
    // Pre-calculate Radiography paths
    wire signed [17:0] p0_rad = s_val4 * 18'sd69;
    wire signed [17:0] p1_rad = s_val3 * -18'sd127;
    wire signed [17:0] p2_rad = s_val2 * 18'sd63;
    wire signed [17:0] p3_rad = s_val1 * -18'sd118;

    // Pre-calculate Thermal paths
    wire signed [17:0] p0_thm = s_val4 * 18'sd111;
    wire signed [17:0] p1_thm = s_val3 * 18'sd11;
    wire signed [17:0] p2_thm = s_val2 * 18'sd127;
    wire signed [17:0] p3_thm = s_val1 * 18'sd99;

    // Multiplex the highly-optimized results
    wire signed [17:0] p0 = mode_sel ? p0_thm : p0_rad;
    wire signed [17:0] p1 = mode_sel ? p1_thm : p1_rad;
    wire signed [17:0] p2 = mode_sel ? p2_thm : p2_rad;
    wire signed [17:0] p3 = mode_sel ? p3_thm : p3_rad;

    wire signed [17:0] fir_sum;
    df_approx_mac_tree approx_accumulator (
        .p0(p0), .p1(p1), .p2(p2), .p3(p3),
        .fir_sum(fir_sum)
    );

    wire signed [15:0] threshold = mode_sel ? 16'sd24765 : -16'sd12000;
    assign trigger_alarm = (fir_sum > threshold) && (val4 != 8'd0);
endmodule

// ──────────────────────────────────────────────────────────────────────────────
// 4. TINY TAPEOUT TOP WRAPPER
// ──────────────────────────────────────────────────────────────────────────────
module tt_um_advaittej_bms (
    input  wire [7:0] ui_in,   
    output wire [7:0] uo_out,  
    input  wire [7:0] uio_in,  
    output wire [7:0] uio_out, 
    output wire [7:0] uio_oe,  
    input  wire       ena,     
    input  wire       clk,     
    input  wire       rst_n    
);
    assign uio_out = 8'b0; 
    assign uio_oe  = 8'b0;

    wire reset_active = !rst_n;       
    wire [7:0] sensor_data   = ui_in;      
    wire       mode_sel_btn  = uio_in[0];  
    wire trigger_alarm_internal;          

    assign uo_out[0]   = trigger_alarm_internal; 
    assign uo_out[7:1] = 7'b0000000; 

    reg [7:0] sync_sensor_data_0;
    reg [7:0] sync_sensor_data_1;
    reg       sync_mode_sel_0;
    reg       sync_mode_sel_1;

    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            sync_sensor_data_0 <= 8'b0;
            sync_sensor_data_1 <= 8'b0;
            sync_mode_sel_0    <= 1'b0;
            sync_mode_sel_1    <= 1'b0;
        end else begin
            sync_sensor_data_0 <= sensor_data;
            sync_sensor_data_1 <= sync_sensor_data_0;
            sync_mode_sel_0    <= mode_sel_btn;
            sync_mode_sel_1    <= sync_mode_sel_0;
        end
    end

    df_digital_filter digital_filter_inst(
        .CLK(clk),
        .nRST(rst_n), 
        .mode_sel(sync_mode_sel_1),
        .datain(sync_sensor_data_1),
        .trigger_alarm(trigger_alarm_internal)
    );

    wire _unused = &{uio_in[7:1], ena, 1'b0};
endmodule
