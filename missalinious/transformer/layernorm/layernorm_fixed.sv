module layernorm_fixed #(
    parameter int LEN = 8,
    parameter int W   = 16   // Q8.8
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,

    input  logic signed [W-1:0] in_vec [LEN],

    output logic valid_out,
    output logic signed [W-1:0] out_vec [LEN]
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
    // Normalize
    // --------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 0;
        end else if (valid_in) begin
            for (int i=0;i<LEN;i++) begin
                logic signed [31:0] norm;
                norm = (in_vec[i] - mean) * inv_std;
                out_vec[i] <= norm >>> 16;  // back to Q8.8
            end
            valid_out <= 1;
        end else begin
            valid_out <= 0;
        end
    end

endmodule

