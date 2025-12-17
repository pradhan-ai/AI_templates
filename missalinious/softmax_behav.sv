// softmax_behav.sv
// BEHAVIORAL softmax for simulation only (uses real & $exp).
// Replace for synthesis with fixed-point approximation / LUT.

module softmax_behav #(
    parameter int LEN = 16
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 valid_in,
    input  logic signed [31:0]   scores [LEN],  // use 32-bit signed fixed point or integer
    output logic                 valid_out,
    output real                  probs [LEN]    // output as real for TB convenience
);
    real smax;
    real exps [LEN];
    real sumexp;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0;
            for (int i=0;i<LEN;i++) probs[i]=0.0;
        end else if (valid_in) begin
            // compute max for numerical stability
            smax = $itor(scores[0]);
            for (int i=1;i<LEN;i++) if ($itor(scores[i]) > smax) smax = $itor(scores[i]);
            sumexp = 0.0;
            for (int i=0;i<LEN;i++) begin
                exps[i] = $exp( $itor(scores[i]) - smax );
                sumexp = sumexp + exps[i];
            end
            for (int i=0;i<LEN;i++)
                probs[i] = exps[i] / sumexp;
            valid_out <= 1;
        end else valid_out <= 0;
    end
endmodule

