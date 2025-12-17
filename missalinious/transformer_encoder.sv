// transformer_encoder_block.sv
`timescale 1ns/1ps
`include "transformer_pkg.sv"

module transformer_encoder_block #(
    parameter int SEQ = 4,
    parameter int EMB = 8,
    parameter int HEADS = 2,
    parameter int HEAD_DIM = EMB/HEADS,
    parameter int FF_DIM = EMB*4,
    parameter int DATA_W = 16,
    parameter int ACC_W  = 48,

    // systolic tile sizes
    parameter int PEX = 2,
    parameter int PEY = 2
)(
    input  logic clk,
    input  logic rst,

    // Input sequence (SEQ x EMB)
    input  logic signed [DATA_W-1:0] in_seq [SEQ][EMB],
    input  logic start,       // start processing this input (pulse)
    output logic done         // pulses when output ready
);
    // Weight memories for linear layers (Wq, Wk, Wv, Wo, Wff1, Wff2) stored externally / statically for TB
    // For brevity we declare them as local arrays filled by the TB.
    // This module implements the computation flow and uses the systolic_array_simple externally.

    // Internal buffers for Q, K, V, shapes:
    logic signed [DATA_W-1:0] Q_mat [SEQ][EMB];
    logic signed [DATA_W-1:0] K_mat [SEQ][EMB];
    logic signed [DATA_W-1:0] V_mat [SEQ][EMB];

    // score matrices: SEQ x SEQ (dot products per head)
    logic signed [31:0] scores_int [HEADS][SEQ][SEQ]; // 32-bit for score accumulation before softmax
    real softmax_probs [HEADS][SEQ][SEQ];

    // attention output per head: SEQ x HEAD_DIM
    logic signed [DATA_W-1:0] head_out [HEADS][SEQ][HEAD_DIM];

    // final output after output projection: SEQ x EMB
    logic signed [DATA_W-1:0] out_seq [SEQ][EMB];

    // Instances: systolic tiles — in TB we will call these with proper scheduling / weight loads.
    // For modularity we do not instantiate many tiles here; TB will perform the GEMM calls using the tile module.

    // Control FSM (simple): on start, run steps sequentially (project, compute scores, softmax, attention, out proj, ffn)
    typedef enum logic [2:0] { IDLE, PROJ_QKV, SCORE_AND_SOFTMAX, ATTN_PROD, OUT_PROJ, FFN, DONE } state_t;
    state_t state, next_state;

    integer h, i, j, d;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            done <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) state <= PROJ_QKV;
                end

                PROJ_QKV: begin
                    // For reference TB, do simple identity-projection: Q=X, K=X, V=X
                    // In practice: perform GEMM in hardware (X * Wq, X * Wk, X * Wv)
                    for (i=0;i<SEQ;i++) for (d=0; d<EMB; d++) begin
                        Q_mat[i][d] <= in_seq[i][d];
                        K_mat[i][d] <= in_seq[i][d];
                        V_mat[i][d] <= in_seq[i][d];
                    end
                    state <= SCORE_AND_SOFTMAX;
                end

                SCORE_AND_SOFTMAX: begin
                    // Compute raw scores per head: for head h, treat sub-vectors of size HEAD_DIM
                    for (h=0; h<HEADS; h++) begin
                        for (i=0;i<SEQ;i++) begin
                            for (j=0;j<SEQ;j++) begin
                                int dot = 0;
                                for (d=0; d<HEAD_DIM; d++) begin
                                    int qi = Q_mat[i][h*HEAD_DIM + d];
                                    int kj = K_mat[j][h*HEAD_DIM + d];
                                    dot = dot + qi * kj;
                                end
                                // scale by sqrt(HEAD_DIM) later in softmax input (we cast to 32-bit)
                                scores_int[h][i][j] <= dot;
                            end
                        end
                    end
                    state <= SCORE_AND_SOFTMAX; // keep in this state to run behavioral softmax below via a small sequencing trick
                    // We'll compute softmax in the next clock using softmax_behav module instances created in TB
                end

                ATTN_PROD: begin
                    // After softmax_probs are filled (TB will write them), compute head_out = probs * V_sub
                    for (h=0; h<HEADS; h++) begin
                        for (i=0;i<SEQ;i++) begin
                            for (d=0; d<HEAD_DIM; d++) begin
                                real acc_r = 0.0;
                                for (j=0;j<SEQ;j++) begin
                                    acc_r = acc_r + softmax_probs[h][i][j] * $itor( V_mat[j][h*HEAD_DIM + d] );
                                end
                                // Convert back to integer (simple rounding)
                                head_out[h][i][d] <= $rtoi(acc_r);
                            end
                        end
                    end
                    state <= OUT_PROJ;
                end

                OUT_PROJ: begin
                    // Concatenate heads -> out_seq (identity output-proj in this reference)
                    for (i=0;i<SEQ;i++) begin
                        for (h=0; h<HEADS; h++) begin
                            for (d=0; d<HEAD_DIM; d++) begin
                                out_seq[i][h*HEAD_DIM + d] <= head_out[h][i][d];
                            end
                        end
                    end
                    state <= FFN;
                end

                FFN: begin
                    // Simple FFN: identity pass-through in this ref (replace with GEMM calls for real FFN)
                    // out_seq = out_seq (no-op)
                    state <= DONE;
                end

                DONE: begin
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

