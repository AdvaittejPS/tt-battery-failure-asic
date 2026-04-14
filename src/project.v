// ==============================================================================
// PROJECT: DUAL-MODE BATTERY FAILURE ASIC (RADIOGRAPHY & THERMAL)
// TARGET: Tiny Tapeout (1x1 Tile)
// ==============================================================================

`default_nettype none

module tt_um_advaittej_bms (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
);

    // --- Aliases and Constants ---
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;
    wire reset_active = !rst_n;
    wire mode_sel = sync_mode_sel_1;

    // --- Synchronizers ---
    reg [7:0] sync_data_0, sync_data_1;
    reg sync_mode_sel_0, sync_mode_sel_1;

    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            sync_data_0 <= 8'b0; sync_data_1 <= 8'b0;
            sync_mode_sel_0 <= 1'b0; sync_mode_sel_1 <= 1'b0;
        end else begin
            sync_data_0 <= ui_in;
            sync_data_1 <= sync_data_0;
            sync_mode_sel_0 <= uio_in[0];
            sync_mode_sel_1 <= sync_mode_sel_0;
        end
    end

    // --- 4-Tap Pipeline ---
    reg [7:0] v1, v2, v3, v4;
    wire event_valid = |sync_data_1;

    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            v1 <= 0; v2 <= 0; v3 <= 0; v4 <= 0;
        end else if (event_valid) begin
            v4 <= v3; v3 <= v2; v2 <= v1; v1 <= sync_data_1;
        end
    end

    // --- Constant-Folded Multipliers ---
    // Cast to signed for math
    wire signed [8:0] sv1 = {1'b0, v1};
    wire signed [8:0] sv2 = {1'b0, v2};
    wire signed [8:0] sv3 = {1'b0, v3};
    wire signed [8:0] sv4 = {1'b0, v4};

    wire signed [17:0] p0 = mode_sel ? (sv4 * 18'sd111) : (sv4 * 18'sd69);
    wire signed [17:0] p1 = mode_sel ? (sv3 * 18'sd11)  : (sv3 * -18'sd127);
    wire signed [17:0] p2 = mode_sel ? (sv2 * 18'sd127) : (sv2 * 18'sd63);
    wire signed [17:0] p3 = mode_sel ? (sv1 * 18'sd99)  : (sv1 * -18'sd118);

    // --- Structural Accumulator (No loops to prevent simulator crash) ---
    wire signed [17:0] sum_a = p0 + p1;
    wire signed [17:0] sum_b = p2 + p3;
    
    // Approximate Stage for the final sum LSBs
    wire [17:0] fir_sum_raw;
    // Bits 0-3: OR-based approximation
    assign fir_sum_raw[3:0] = sum_a[3:0] | sum_b[3:0];
    // Bits 4-17: Exact addition
    assign fir_sum_raw[17:4] = sum_a[17:4] + sum_b[17:4];

    // --- Trigger Logic ---
    wire signed [17:0] fir_sum = $signed(fir_sum_raw);
    wire signed [15:0] threshold = mode_sel ? 16'sd24765 : -16'sd12000;
    
    // Safety: Only trigger if pipeline has seen data (v4 != 0)
    assign uo_out[0] = (fir_sum > threshold) && (v4 != 8'd0);
    assign uo_out[7:1] = 7'b0;

    // Use unused inputs to satisfy lint
    wire _unused = &{uio_in[7:1], ena, 1'b0};

endmodule
