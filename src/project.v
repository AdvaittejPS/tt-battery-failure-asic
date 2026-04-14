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

    // --- Flattened Synchronizers ---
    reg [7:0] d0, d1;
    reg m0, m1;
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            d0 <= 0; d1 <= 0; m0 <= 0; m1 <= 0;
        end else begin
            d0 <= ui_in;
            d1 <= d0;
            m0 <= uio_in[0];
            m1 <= m0;
        end
    end

    // --- 4-Tap Pipeline ---
    reg [7:0] v1, v2, v3, v4;
    wire ev = |d1; 
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            v1 <= 0; v2 <= 0; v3 <= 0; v4 <= 0;
        end else if (ev) begin
            v4 <= v3; v3 <= v2; v2 <= v1; v1 <= d1;
        end
    end

    // --- Weight Muxing (Gate Count Optimization) ---
    // Choosing the weight before multiplication forces Yosys to use 
    // only 4 multipliers instead of 8.
    wire signed [8:0] w0 = m1 ? 9'sd111 : 9'sd69;
    wire signed [8:0] w1 = m1 ? 9'sd11  : -9'sd127;
    wire signed [8:0] w2 = m1 ? 9'sd127 : 9'sd63;
    wire signed [8:0] w3 = m1 ? 9'sd99  : -9'sd118;

    wire signed [8:0] sv1 = {1'b0, v1};
    wire signed [8:0] sv2 = {1'b0, v2};
    wire signed [8:0] sv3 = {1'b0, v3};
    wire signed [8:0] sv4 = {1'b0, v4};

    wire signed [17:0] p0 = sv4 * w0;
    wire signed [17:0] p1 = sv3 * w1;
    wire signed [17:0] p2 = sv2 * w2;
    wire signed [17:0] p3 = sv1 * w3;

    // --- High-Efficiency Approximate Accumulator ---
    wire signed [17:0] sum_full = (p0 + p1) + (p2 + p3);
    wire [17:0] sum_out;
    
    // Bits 7-17: Exact addition for detection accuracy
    assign sum_out[17:7] = sum_full[17:7];
    
    // Bits 0-6: OR-based approximation (Massive cell reduction)
    // This breaks the carry chain for the bottom 7 bits to fix timing.
    assign sum_out[6:0]  = p0[6:0] | p1[6:0] | p2[6:0] | p3[6:0];

    // --- Trigger Logic ---
    wire signed [17:0] final_mac = $signed(sum_out);
    wire signed [15:0] thresh = m1 ? 16'sd24765 : -16'sd12000;
    
    assign uo_out[0] = (final_mac > thresh) && (v4 != 8'd0);
    assign uo_out[7:1] = 7'b0;

    wire _unused = &{uio_in[7:1], ena, 1'b0};
endmodule
