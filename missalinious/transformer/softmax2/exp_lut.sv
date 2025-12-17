module exp_lut #(
    parameter int IN_W  = 16,   // Q8.8
    parameter int OUT_W = 16    // Q0.16
)(
    input  logic signed [IN_W-1:0] x,
    output logic [OUT_W-1:0] y
);

    // LUT index: clamp to [-8,0]
    int idx;

    always_comb begin
        // x in Q8.8 → integer
        idx = x >>> 8;

        if (idx > 0)      idx = 0;
        if (idx < -8)     idx = -8;

        case (idx)
            0:   y = 16'd65535; // exp(0)   ≈ 1.0
            -1:  y = 16'd24109; // exp(-1)
            -2:  y = 16'd8869;
            -3:  y = 16'd3265;
            -4:  y = 16'd1202;
            -5:  y = 16'd442;
            -6:  y = 16'd163;
            -7:  y = 16'd60;
            -8:  y = 16'd22;
            default: y = 0;
        endcase
    end
endmodule

