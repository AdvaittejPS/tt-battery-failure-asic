`default_nettype none

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

    // --- Synchronizers (Flattened for Simulator Stability) ---
    reg [7:0] sync_d0, sync_d1;
    reg sync_m0, sync_m1;
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            sync_d0 <= 0; sync_d1 <= 0;
            sync_m0 <= 0; sync_m1 <= 0;
        end else begin
            sync_d0 <= ui_in;
            sync_d1 <= sync_d0;
            sync_m0 <= uio_in[0];
            sync_m1 <= sync_m0;
        end
    end

    // --- 4-Tap Pipeline ---
    reg [7:0] v1, v2, v3, v4;
    wire ev = |sync_d1; 
    always @(posedge clk or posedge reset_active) begin
        if (reset_active) begin
            v1 <= 0; v2 <= 0; v3 <= 0; v4 <= 0;
        end else if (ev) begin
            v4 <= v3; v3 <= v2; v2 <= v1; v1 <= sync_d1;
        end
    end

    // --- Explicit Constant Muxing (The Key to < 1000 Cells) ---
    // By separating the math, the tool uses hardcoded shift-add trees.
    wire signed [8:0] sv1 = {1'b0, v1};
    wire signed [8:0] sv2 = {1'b0, v2};
    wire signed [8:0] sv3 = {1'b0, v3};
    wire signed [8:0] sv4 = {1'b0, v4};

    wire signed [17:0] p0 = sync_m1 ? (sv4 * 18'sd111) : (sv4 * 18'sd69);
    wire signed [17:0] p1 = sync_m1 ? (sv3 * 18'sd11)  : (sv3 * -18'sd127);
    wire signed [17:0] p2 = sync_m1 ? (sv2 * 18'sd127) : (sv2 * 18'sd63);
    wire signed [17:0] p3 = sync_m1 ? (sv1 * 18'sd99)  : (sv1 * -18'sd118);

    // --- High-Efficiency Approximate Accumulator ---
    wire signed [17:0] sum_full = (p0 + p1) + (p2 + p3);
    wire [17:0] sum_out;
    
    // Bits 6-17: Exact addition for detection accuracy
    assign sum_out[17:6] = sum_full[17:6];
    
    // Bits 0-5: OR-based approximation (Massive cell reduction)
    // This breaks the carry chain for the bottom 6 bits.
    assign sum_out[5:0]  = p0[5:0] | p1[5:0] | p2[5:0] | p3[5:0];

    // --- Trigger ---
    wire signed [17:0] final_mac = $signed(sum_out);
    wire signed [15:0] thresh = sync_m1 ? 16'sd24765 : -16'sd12000;
    
    // Only fire if the pipeline has valid data (prevents power-on spikes)
    assign uo_out[0] = (final_mac > thresh) && (v4 != 8'd0);
    assign uo_out[7:1] = 7'b0;

    wire _unused = &{uio_in[7:1], ena, 1'b0};
endmodule
