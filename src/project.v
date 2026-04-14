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

    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;
    wire reset_active = !rst_n;

    // --- Synchronizers ---
    reg [7:0] d0, d1;
    reg m0, m1;
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            d0 <= 0; d1 <= 0; m0 <= 0; m1 <= 0;
        end else begin
            d0 <= ui_in; d1 <= d0;
            m0 <= uio_in[0]; m1 <= m0;
        end
    end

    // --- 4-Tap Pipeline ---
    reg [7:0] v1, v2, v3, v4;
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            v1 <= 0; v2 <= 0; v3 <= 0; v4 <= 0;
        end else if (|d1) begin
            v4 <= v3; v3 <= v2; v2 <= v1; v1 <= d1;
        end
    end

    // --- Constant Coefficient Multiplication (KCM) ---
    // Zero multipliers used. Only Adders/Subtractors.
    wire signed [17:0] sv1 = $signed({1'b0, v1});
    wire signed [17:0] sv2 = $signed({1'b0, v2});
    wire signed [17:0] sv3 = $signed({1'b0, v3});
    wire signed [17:0] sv4 = $signed({1'b0, v4});

    // Radiography Coefficients: 69, -127, 63, -118
    wire signed [17:0] p0_rad = (sv4 << 6) + (sv4 << 2) + sv4;             // x69
    wire signed [17:0] p1_rad = -( (sv3 << 7) - sv3 );                    // x-127
    wire signed [17:0] p2_rad = (sv2 << 6) - sv2;                         // x63
    wire signed [17:0] p3_rad = -( (sv1 << 7) - (sv1 << 3) - (sv1 << 1) );// x-118

    // Thermal Coefficients: 111, 11, 127, 99
    wire signed [17:0] p0_thm = (sv4 << 7) - (sv4 << 4) - sv4;            // x111
    wire signed [17:0] p1_thm = (sv3 << 3) + (sv3 << 1) + sv3;            // x11
    wire signed [17:0] p2_thm = (sv2 << 7) - sv2;                         // x127
    wire signed [17:0] p3_thm = (sv1 << 6) + (sv1 << 5) + (sv1 << 1) + sv1; // x99

    // --- Resource Selection & Accumulation ---
    wire signed [17:0] p0 = m1 ? p0_thm : p0_rad;
    wire signed [17:0] p1 = m1 ? p1_thm : p1_rad;
    wire signed [17:0] p2 = m1 ? p2_thm : p2_rad;
    wire signed [17:0] p3 = m1 ? p3_thm : p3_rad;

    wire signed [17:0] fir_sum = (p0 + p1) + (p2 + p3);
    wire signed [15:0] thresh = m1 ? 16'sd24765 : -16'sd12000;
    
    // Safety: Only fire if pipeline is full (v4 != 0)
    assign uo_out[0] = (fir_sum > thresh) && (v4 != 8'd0);
    assign uo_out[7:1] = 7'b0;

    wire _unused = &{uio_in[7:1], ena, 1'b0};
endmodule
