// layernorm.sv
`include "transformer_pkg.sv"
module layernorm #(
    parameter int DIM = 64,
    parameter int DATA_W = 16,
    // small epsilon
    parameter real EPS = 1e-5
)(
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      valid_in,
    input  logic signed [DATA_W-1:0]  in_vec [DIM],
    output logic                      valid_out,
    output logic signed [DATA_W-1:0]  out_vec [DIM],

    // gamma & beta for affine (config)
    input  logic                      cfg_we,
    input  logic [$clog2(2*DIM)-1:0]  cfg_addr,
    input  logic signed [DATA_W-1:0]  cfg_wdata
);
    // gamma & beta
    logic signed [DATA_W-1:0] gamma [DIM];
    logic signed [DATA_W-1:0] beta  [DIM];

    // config write
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i=0;i<DIM;i++) gamma[i]<= '0;
            for (int i=0;i<DIM;i++) beta[i] <= '0;
        end else if (cfg_we) begin
            if (cfg_addr < DIM) gamma[cfg_addr] <= cfg_wdata;
            else beta[cfg_addr - DIM] <= cfg_wdata;
        end
    end

    // compute mean and variance (behavioral with real for simulation accuracy).
    // This block is synthesizable if you replace real arithmetic with fixed-point approximations.
    real sum;
    real mean;
    real var;
    real tmp;
    always_comb begin
        sum = 0.0;
        for (int i=0;i<DIM;i++) sum = sum + $itor(in_vec[i]);
        mean = sum / DIM;
        var = 0.0;
        for (int i=0;i<DIM;i++) begin
            tmp = $itor(in_vec[i]) - mean;
            var = var + tmp*tmp;
        end
        var = var / DIM;
        for (int i=0;i<DIM;i++) begin
            // normalized = (x - mean) / sqrt(var + eps)
            real norm = ($itor(in_vec[i]) - mean) / $sqrt(var + EPS);
            // affine: gamma * norm + beta
            real outv = $itor(gamma[i]) * norm + $itor(beta[i]);
            // convert back to fixed width - simple truncation
            out_vec[i] = $rtoi(outv);
        end
    end

    assign valid_out = valid_in;
endmodule

