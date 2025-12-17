// softmax_behav.sv
`timescale 1ns/1ps
module softmax_behav #(
    parameter int LEN = 8
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,
    input  logic signed [31:0] scores [LEN], // use 32-bit signed fixed-point (sim)
    output logic valid_out,
    output real probs [LEN] // outputs as real probability values
);
    real exps [LEN];
    real sumexp;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 1'b0;
            for (int i=0;i<LEN;i++) probs[i]=0.0;
        end else if (valid_in) begin
            // numerical stable softmax
            real m = $itor(scores[0]);
            for (int i=1;i<LEN;i++) if ($itor(scores[i]) > m) m = $itor(scores[i]);
            sumexp = 0.0;
            for (int i=0;i<LEN;i++) begin
                exps[i] = $exp($itor(scores[i]) - m);
                sumexp = sumexp + exps[i];
            end
            for (int i=0;i<LEN;i++) probs[i] = exps[i]/sumexp;
            valid_out <= 1'b1;
        end else valid_out <= 1'b0;
    end
endmodule

