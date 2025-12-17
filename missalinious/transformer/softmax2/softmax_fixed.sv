module softmax_fixed #(
    parameter int LEN = 8,
    parameter int IN_W = 16,   // Q8.8
    parameter int OUT_W = 16   // Q0.16
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,

    input  logic signed [IN_W-1:0] in_vec [LEN],

    output logic valid_out,
    output logic [OUT_W-1:0] out_vec [LEN]
);

    logic signed [IN_W-1:0] max_val;
    logic [OUT_W-1:0] exp_val [LEN];
    logic [31:0] sum_exp;
    logic [31:0] recip;   // reciprocal of sum_exp (Q0.16)

    // ---------------------------------------
    // Stage 1: Max
    // ---------------------------------------
    always_comb begin
        max_val = in_vec[0];
        for (int i=1;i<LEN;i++)
            if (in_vec[i] > max_val)
                max_val = in_vec[i];
    end

    // ---------------------------------------
    // Stage 2: exp(x - max)
    // ---------------------------------------
    genvar i;
    generate
        for (i=0;i<LEN;i++) begin
            exp_lut lut (
                .x(in_vec[i] - max_val),
                .y(exp_val[i])
            );
        end
    endgenerate

    // ---------------------------------------
    // Stage 3: sum(exp)
    // ---------------------------------------
    always_comb begin
        sum_exp = 0;
        for (int i=0;i<LEN;i++)
            sum_exp += exp_val[i];
    end

    // ---------------------------------------
    // Stage 4: reciprocal (1 / sum_exp)
    // Using simple LUT-free approximation:
    // recip = (1 << 16) / sum_exp
    // ---------------------------------------
    always_comb begin
        if (sum_exp != 0)
            recip = (32'd1 << 16) / sum_exp;
        else
            recip = 0;
    end

    // ---------------------------------------
    // Stage 5: normalize
    // ---------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 0;
        end else if (valid_in) begin
            for (int i=0;i<LEN;i++)
                out_vec[i] <= (exp_val[i] * recip) >> 16;
            valid_out <= 1;
        end else begin
            valid_out <= 0;
        end
    end

endmodule

