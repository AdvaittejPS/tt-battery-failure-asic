`default_nettype none

module tt_um_advaittej_bms (
    input  wire [7:0] ui_in,    // Sensor Data
    output wire [7:0] uo_out,   // Alarm Trigger
    input  wire [7:0] uio_in,   // Mode Select
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
);

    // --- TT Pin Tie-offs ---
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;
    wire reset_active = !rst_n;

    // --- Synchronizers ---
    reg [7:0] sync_data_0, sync_data_1;
    reg sync_mode_0, sync_mode_1;
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            sync_data_0 <= 0; sync_data_1 <= 0;
            sync_mode_0 <= 0; sync_mode_1 <= 0;
        end else begin
            sync_data_0 <= ui_in;
            sync_data_1 <= sync_data_0;
            sync_mode_0 <= uio_in[0];
            sync_mode_1 <= sync_mode_0;
        end
    end

    // --- 4-Tap Pipeline ---
    reg [7:0] v1, v2, v3, v4;
    wire event_valid = |sync_data_1; // Sparsity Gating
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            v1 <= 0; v2 <= 0; v3 <= 0; v4 <= 0;
        end else if (event_valid) begin
            v4 <= v3; v3 <= v2; v2 <= v1; v1 <= sync_data_1;
        end
    end

    // --- Weight Muxing (Gate Count Optimization) ---
    wire signed [8:0] w0 = sync_mode_1 ? 9'sd111 : 9'sd69;
    wire signed [8:0] w1 = sync_mode_1 ? 9'sd11  : -9'sd127;
    wire signed [8:0] w2 = sync_mode_1 ? 9'sd127 : 9'sd63;
    wire signed [8:0] w3 = sync_mode_1 ? 9'sd99  : -9'sd118;

    // --- Multipliers ---
    wire signed [8:0] sv1 = {1'b0, v1};
    wire signed [8:0] sv2 = {1'b0, v2};
    wire signed [8:0] sv3 = {1'b0, v3};
    wire signed [8:0] sv4 = {1'b0, v4};

    wire signed [17:0] p0 = sv4 * w0;
    wire signed [17:0] p1 = sv3 * w1;
    wire signed [17:0] p2 = sv2 * w2;
    wire signed [17:0] p3 = sv1 * w3;

    // --- Approximate Accumulator ---
    wire signed [17:0] sum_exact = (p0 + p1) + (p2 + p3);
    // Use the OR-approximation for only the 3 LSBs to save gates
    wire [17:0] fir_sum_approx;
    assign fir_sum_approx[17:3] = sum_exact[17:3];
    assign fir_sum_approx[2:0]  = p0[2:0] | p1[2:0] | p2[2:0] | p3[2:0];

    // --- Trigger Logic ---
    wire signed [17:0] fir_sum = $signed(fir_sum_approx);
    wire signed [15:0] threshold = sync_mode_1 ? 16'sd24765 : -16'sd12000;
    
    // Safety: Trigger only after 4 frames of data are present
    assign uo_out[0] = (fir_sum > threshold) && (v4 != 8'd0);
    assign uo_out[7:1] = 7'b0;

    wire _unused = &{uio_in[7:1], ena, 1'b0};
endmodule
