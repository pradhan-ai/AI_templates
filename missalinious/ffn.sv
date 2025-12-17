// ffn.sv
`include "transformer_pkg.sv"
module ffn #(
    parameter int EMB = 64,
    parameter int FF  = 256,
    parameter int DATA_W = 16
)(
    input logic clk, rst_n,
    input logic valid_in,
    input transformer_pkg::seq_emb_t in_seq, // [SEQ][EMB]
    output logic valid_out,
    output transformer_pkg::seq_emb_t out_seq,

    // simple config ports for the two linear layers omitted for brevity
    input logic cfg_we,
    input logic [$clog2(EMB*FF + FF + FF*EMB + EMB)-1:0] cfg_addr,
    input logic signed [DATA_W-1:0] cfg_wdata
);
    // For simplicity, implement FFN as two elementwise ops:
    // out = W2 ( GELU ( W1 * x + b1 ) ) + b2
    // Here we use an identity W1/W2 stub for simulation clarity; replace with real linear modules for hardware.

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0;
        end else if (valid_in) begin
            // very small demo: out = in (identity) — replace with real linear layers
            for (int t=0; t<`transformer_pkg::SEQ; t++) begin
                for (int e=0; e<EMB; e++) begin
                    out_seq[t][e] <= in_seq[t][e]; // stub: identity
                end
            end
            valid_out <= 1;
        end else valid_out <= 0;
    end
endmodule

