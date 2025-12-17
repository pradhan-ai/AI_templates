
module rsqrt_lut (
    input  logic [15:0] var_q16,   // Q16.16 variance (clamped)
    output logic [15:0] inv_std     // Q0.16
);
    int idx;

    always_comb begin
        // Normalize variance into LUT range
        idx = var_q16 >> 12;   // coarse bucket

        if (idx < 1) idx = 1;
        if (idx > 16) idx = 16;

        case (idx)
            1:  inv_std = 16'd65535; // 1/sqrt(1)
            2:  inv_std = 16'd46340;
            3:  inv_std = 16'd37837;
            4:  inv_std = 16'd32768;
            5:  inv_std = 16'd29309;
            6:  inv_std = 16'd26755;
            7:  inv_std = 16'd24606;
            8:  inv_std = 16'd23170;
            9:  inv_std = 16'd21845;
            10: inv_std = 16'd20724;
            11: inv_std = 16'd19727;
            12: inv_std = 16'd18868;
            13: inv_std = 16'd18096;
            14: inv_std = 16'd17476;
            15: inv_std = 16'd16861;
            16: inv_std = 16'd16384;
            default: inv_std = 0;
        endcase
    end
endmodule
