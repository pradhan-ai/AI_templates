module fused_attention_ln #(
    parameter int SEQ_LEN   = 4,
    parameter int EMBED_DIM = 8,
    parameter int HEADS     = 2,
    parameter int DATA_W    = 16
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,

    input  logic signed [DATA_W-1:0] X [SEQ_LEN][EMBED_DIM],
    input  logic signed [DATA_W-1:0] Q [SEQ_LEN][EMBED_DIM],
    input  logic signed [DATA_W-1:0] K [SEQ_LEN][EMBED_DIM],
    input  logic signed [DATA_W-1:0] V [SEQ_LEN][EMBED_DIM],

    output logic valid_out,
    output logic signed [DATA_W-1:0] Y [SEQ_LEN][EMBED_DIM]
);

    localparam int HEAD_DIM = EMBED_DIM / HEADS;

    // ---------------------------------------------------
    // Stage 1: QKᵀ Scores
    // ---------------------------------------------------
    logic signed [31:0] scores [HEADS][SEQ_LEN][SEQ_LEN];

    genvar h,i,j,k;
    generate
        for (h=0; h<HEADS; h++) begin
            for (i=0; i<SEQ_LEN; i++) begin
                for (j=0; j<SEQ_LEN; j++) begin
                    always_comb begin
                        scores[h][i][j] = 0;
                        for (k=0; k<HEAD_DIM; k++)
                            scores[h][i][j] +=
                              Q[i][h*HEAD_DIM+k] *
                              K[j][h*HEAD_DIM+k];
                        scores[h][i][j] = scores[h][i][j] >>> 4; // scale
                    end
                end
            end
        end
    endgenerate

    // ---------------------------------------------------
    // Stage 2: Softmax per row
    // ---------------------------------------------------
    logic [15:0] softmax_out [HEADS][SEQ_LEN][SEQ_LEN];

    generate
        for (h=0; h<HEADS; h++) begin
            for (i=0; i<SEQ_LEN; i++) begin
                softmax_fixed #(.LEN(SEQ_LEN)) softmax (
                    .clk(clk),
                    .rst(rst),
                    .valid_in(valid_in),
                    .in_vec(scores[h][i]),
                    .valid_out(),
                    .out_vec(softmax_out[h][i])
                );
            end
        end
    endgenerate

    // ---------------------------------------------------
    // Stage 3: Attention × V
    // ---------------------------------------------------
    logic signed [31:0] attn [SEQ_LEN][EMBED_DIM];

    generate
        for (h=0; h<HEADS; h++) begin
            for (i=0; i<SEQ_LEN; i++) begin
                for (k=0; k<HEAD_DIM; k++) begin
                    always_comb begin
                        attn[i][h*HEAD_DIM+k] = 0;
                        for (j=0; j<SEQ_LEN; j++)
                            attn[i][h*HEAD_DIM+k] +=
                              softmax_out[h][i][j] *
                              V[j][h*HEAD_DIM+k];
                        attn[i][h*HEAD_DIM+k] >>= 16;
                    end
                end
            end
        end
    endgenerate

    // ---------------------------------------------------
    // Stage 4: Residual Add
    // ---------------------------------------------------
    logic signed [15:0] res [SEQ_LEN][EMBED_DIM];

    always_comb begin
        for (int i=0;i<SEQ_LEN;i++)
            for (int j=0;j<EMBED_DIM;j++)
                res[i][j] = X[i][j] + attn[i][j][15:0];
    end

    // ---------------------------------------------------
    // Stage 5: LayerNorm (token-wise)
    // ---------------------------------------------------
    generate
        for (i=0;i<SEQ_LEN;i++) begin
            layernorm_fixed #(.LEN(EMBED_DIM)) ln (
                .clk(clk),
                .rst(rst),
                .valid_in(valid_in),
                .in_vec(res[i]),
                .valid_out(valid_out),
                .out_vec(Y[i])
            );
        end
    endgenerate

endmodule

