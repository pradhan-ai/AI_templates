module layernorm_gamma_beta #(
    parameter int LEN = 8,
    parameter int W   = 16   // Q8.8
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,

    input  logic signed [W-1:0] in_vec   [LEN],
    input  logic signed [W-1:0] gamma    [LEN],
    input  logic signed [W-1:0] beta     [LEN],

    output logic valid_out,
    output logic signed [W-1:0] out_vec  [LEN]
);

    // --------------------------------
    // Mean
    // --------------------------------
    logic signed [31:0] sum;
    logic signed [W-1:0] mean;

    always_comb begin
        sum = 0;
        for (int i=0;i<LEN;i++)
            sum += in_vec[i];
        mean = sum / LEN;
    end

    // --------------------------------
    // Variance
    // --------------------------------
    logic [31:0] var_acc;
    logic [31:0] variance;   // Q16.16

    always_comb begin
        var_acc = 0;
        for (int i=0;i<LEN;i++) begin
            logic signed [31:0] diff;
            diff = in_vec[i] - mean;
            var_acc += diff * diff;
        end
        variance = var_acc / LEN;
    end

    // --------------------------------
    // Inverse sqrt
    // --------------------------------
    logic [15:0] inv_std;

    rsqrt_lut rsqrt (
        .var_q16(variance[31:16]),
        .inv_std(inv_std)
    );

    // --------------------------------
    // Normalize + Affine
    // --------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 0;
        end else if (valid_in) begin
            for (int i=0;i<LEN;i++) begin
                logic signed [31:0] norm;
                logic signed [31:0] scaled;

                // (x - mean) * inv_std → Q8.8
                norm = (in_vec[i] - mean) * inv_std;
                norm = norm >>> 16;

                // norm * gamma → Q8.8
                scaled = norm * gamma[i];
                scaled = scaled >>> 8;

                // + beta
                out_vec[i] <= scaled + beta[i];
            end
            valid_out <= 1;
        end else begin
            valid_out <= 0;
        end
    end

endmodule

