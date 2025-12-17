// layernorm_behav.sv
`timescale 1ns/1ps
module layernorm_behav #(
    parameter int DIM = 8,
    parameter int DATA_W = 16
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,
    input  logic signed [DATA_W-1:0] in_vec [DIM],
    output logic valid_out,
    output logic signed [DATA_W-1:0] out_vec [DIM]
);
    real mean, var, tmp;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 0;
            for (int i=0;i<DIM;i++) out_vec[i] <= '0;
        end else if (valid_in) begin
            mean = 0.0;
            for (int i=0;i<DIM;i++) mean = mean + $itor(in_vec[i]);
            mean = mean / DIM;
            var = 0.0;
            for (int i=0;i<DIM;i++) begin
                tmp = $itor(in_vec[i]) - mean;
                var = var + tmp*tmp;
            end
            var = var / DIM;
            real denom = $sqrt(var + 1e-5);
            for (int i=0;i<DIM;i++) begin
                real normalized = ($itor(in_vec[i]) - mean) / denom;
                out_vec[i] <= $rtoi(normalized); // simple scaling; replace with affine gamma/beta as needed
            end
            valid_out <= 1'b1;
        end else valid_out <= 1'b0;
    end
endmodule

