
//-------------------------------------------------------------
// Fixed-Point Softmax (Bit-Accurate, Synthesizable)
// Base-2 exponential using shifts
//-------------------------------------------------------------
module softmax_fixed #(
    parameter int N = 8,                 // vector length
    parameter int IN_W = 16,              // Q8.8 input
    parameter int OUT_W = 16              // Q0.15 output
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,

    input  logic signed [IN_W-1:0]  in_vec [N],

    output logic valid_out,
    output logic [OUT_W-1:0] out_vec [N]
);

    // ---------------- Stage 1: Find max ----------------
    logic signed [IN_W-1:0] max_val;

    always_ff @(posedge clk) begin
        if (valid_in) begin
            max_val = in_vec[0];
            for (int i=1;i<N;i++)
                if (in_vec[i] > max_val)
                    max_val = in_vec[i];
        end
    end

    // ---------------- Stage 2: exp2(x - max) ----------------
    // exp2(x) ≈ 1 << (x >> 8)
    logic [31:0] exp_val [N];

    always_ff @(posedge clk) begin
        if (valid_in) begin
            for (int i=0;i<N;i++) begin
                int shift = (in_vec[i] - max_val) >>> 8;
                if (shift < -15) shift = -15;
                if (shift > 0)   shift = 0;
                exp_val[i] <= 32'd1 << (shift + 15);
            end
        end
    end

    // ---------------- Stage 3: Sum ----------------
    logic [31:0] exp_sum;

    always_ff @(posedge clk) begin
        if (valid_in) begin
            exp_sum = 0;
            for (int i=0;i<N;i++)
                exp_sum += exp_val[i];
        end
    end

    // ---------------- Stage 4: Normalize ----------------
    // out = exp_val / exp_sum → Q0.15
    always_ff @(posedge clk) begin
        if (valid_in) begin
            for (int i=0;i<N;i++)
                out_vec[i] <= (exp_val[i] << 15) / exp_sum;
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule

