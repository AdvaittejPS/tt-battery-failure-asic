`default_nettype none

module tt_um_advaittej_bms (
    input  wire [7:0] ui_in,    // Thermal Sensor Data
    output wire [7:0] uo_out,   // Hardware Alarm Interrupt
    input  wire [7:0] uio_in,   // Unused
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
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            d0 <= 0; d1 <= 0;
        end else begin
            d0 <= ui_in;
            d1 <= d0;
        end
    end

    // --- 4-Tap Pipeline ---
    reg [7:0] v1, v2, v3, v4;
    wire event_valid = |d1; 
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            v1 <= 0; v2 <= 0; v3 <= 0; v4 <= 0;
        end else if (event_valid) begin
            v4 <= v3; v3 <= v2; v2 <= v1; v1 <= d1;
        end
    end

    // --- Thermal Weights (KCM Logic) ---
    wire signed [17:0] sv1 = $signed({1'b0, v1});
    wire signed [17:0] sv2 = $signed({1'b0, v2});
    wire signed [17:0] sv3 = $signed({1'b0, v3});
    wire signed [17:0] sv4 = $signed({1'b0, v4});

    // Hardcoded Math:
    // p0 (x111) = (x << 7) - (x << 4) - x
    // p1 (x11)  = (x << 3) + (x << 1) + x
    // p2 (x127) = (x << 7) - x
    // p3 (x99)  = (x << 6) + (x << 5) + (x << 1) + x
    wire signed [17:0] p0 = (sv4 << 7) - (sv4 << 4) - sv4;
    wire signed [17:0] p1 = (sv3 << 3) + (sv3 << 1) + sv3;
    wire signed [17:0] p2 = (sv2 << 7) - sv2;
    wire signed [17:0] p3 = (sv1 << 6) + (sv1 << 5) + (sv1 << 1) + sv1;

    // --- Accumulation ---
    wire signed [17:0] fir_sum = (p0 + p1) + (p2 + p3);
    
    // Fire alarm if sum > 24765 AND pipeline is primed
    assign uo_out[0] = (fir_sum > 18'sd24765) && (v4 != 8'd0);
    assign uo_out[7:1] = 7'b0;

    wire _unused = &{uio_in, ena, 1'b0};
endmodule
