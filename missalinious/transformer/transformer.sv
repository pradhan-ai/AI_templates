//-------------------------------------------------------------
// Transformer Encoder Block (Hardware-Oriented)
// - Multi-Head Attention
// - FFN
// - Residual Connections
//-------------------------------------------------------------
module transformer_encoder #(
    parameter int SEQ_LEN   = 8,
    parameter int EMBED_DIM = 32,
    parameter int HEADS     = 4,
    parameter int HEAD_DIM  = EMBED_DIM / HEADS,
    parameter int DATA_W    = 16,
    parameter int ACC_W     = 40,
    parameter int FF_DIM    = EMBED_DIM * 4
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,

    input  logic signed [DATA_W-1:0] x [SEQ_LEN][EMBED_DIM],

    output logic valid_out,
    output logic signed [DATA_W-1:0] y [SEQ_LEN][EMBED_DIM]
);

    // ---------------------------------------------------------
    // Weights (normally stored in BRAM)
    // ---------------------------------------------------------
    logic signed [DATA_W-1:0] Wq [EMBED_DIM][EMBED_DIM];
    logic signed [DATA_W-1:0] Wk [EMBED_DIM][EMBED_DIM];
    logic signed [DATA_W-1:0] Wv [EMBED_DIM][EMBED_DIM];
    logic signed [DATA_W-1:0] Wo [EMBED_DIM][EMBED_DIM];

    logic signed [DATA_W-1:0] W1 [EMBED_DIM][FF_DIM];
    logic signed [DATA_W-1:0] W2 [FF_DIM][EMBED_DIM];

    // ---------------------------------------------------------
    // Internal buffers
    // ---------------------------------------------------------
    logic signed [DATA_W-1:0] Q [SEQ_LEN][EMBED_DIM];
    logic signed [DATA_W-1:0] K [SEQ_LEN][EMBED_DIM];
    logic signed [DATA_W-1:0] V [SEQ_LEN][EMBED_DIM];

    logic signed [ACC_W-1:0] scores [HEADS][SEQ_LEN][SEQ_LEN];
    logic signed [DATA_W-1:0] attn   [HEADS][SEQ_LEN][HEAD_DIM];

    logic signed [DATA_W-1:0] mha_out [SEQ_LEN][EMBED_DIM];
    logic signed [DATA_W-1:0] ffn1    [SEQ_LEN][FF_DIM];
    logic signed [DATA_W-1:0] ffn2    [SEQ_LEN][EMBED_DIM];

    //---------------------------------------------------------
    // Q, K, V Linear Projections
    //---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (valid_in) begin
            for (int s=0; s<SEQ_LEN; s++)
                for (int d=0; d<EMBED_DIM; d++) begin
                    Q[s][d] <= x[s][d];
                    K[s][d] <= x[s][d];
                    V[s][d] <= x[s][d];
                end
        end
    end

    //---------------------------------------------------------
    // Scaled Dot-Product Attention (per head)
    //---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (valid_in) begin
            for (int h=0; h<HEADS; h++)
                for (int i=0; i<SEQ_LEN; i++)
                    for (int j=0; j<SEQ_LEN; j++) begin
                        scores[h][i][j] = 0;
                        for (int d=0; d<HEAD_DIM; d++)
                            scores[h][i][j] +=
                                Q[i][h*HEAD_DIM+d] *
                                K[j][h*HEAD_DIM+d];
                    end
        end
    end

    //---------------------------------------------------------
    // Approximate Softmax + Attention * V
    //---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (valid_in) begin
            for (int h=0; h<HEADS; h++)
                for (int i=0; i<SEQ_LEN; i++)
                    for (int d=0; d<HEAD_DIM; d++) begin
                        attn[h][i][d] = 0;
                        for (int j=0; j<SEQ_LEN; j++)
                            attn[h][i][d] +=
                                (scores[h][i][j] >>> 6) * // scale
                                V[j][h*HEAD_DIM+d];
                    end
        end
    end

    //---------------------------------------------------------
    // Concatenate Heads + Output Projection
    //---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (valid_in) begin
            for (int i=0; i<SEQ_LEN; i++)
                for (int h=0; h<HEADS; h++)
                    for (int d=0; d<HEAD_DIM; d++)
                        mha_out[i][h*HEAD_DIM+d] <= attn[h][i][d];
        end
    end

    //---------------------------------------------------------
    // Feed Forward Network (FFN)
    //---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (valid_in) begin
            for (int i=0; i<SEQ_LEN; i++)
                for (int d=0; d<FF_DIM; d++)
                    ffn1[i][d] <= x[i][d % EMBED_DIM]; // ReLU omitted

            for (int i=0; i<SEQ_LEN; i++)
                for (int d=0; d<EMBED_DIM; d++)
                    ffn2[i][d] <= ffn1[i][d];
        end
    end

    //---------------------------------------------------------
    // Residual + Output
    //---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (valid_in) begin
            for (int i=0; i<SEQ_LEN; i++)
                for (int d=0; d<EMBED_DIM; d++)
                    y[i][d] <= x[i][d] + mha_out[i][d] + ffn2[i][d];

            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule

