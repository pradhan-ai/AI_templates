// tb_transformer_encoder.sv
`timescale 1ns/1ps
`include "transformer_pkg.sv"

module tb_transformer_encoder;
    parameter int SEQ = 4;
    parameter int EMB = 8;
    parameter int HEADS = 2;
    parameter int HEAD_DIM = EMB / HEADS;
    parameter int DATA_W = 16;
    parameter int ACC_W  = 48;

    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;

    // instantiate DUT
    logic signed [DATA_W-1:0] in_seq [SEQ][EMB];
    logic start;
    logic done;

    transformer_encoder_block #(
        .SEQ(SEQ), .EMB(EMB), .HEADS(HEADS), .HEAD_DIM(HEAD_DIM),
        .FF_DIM(EMB*4), .DATA_W(DATA_W), .ACC_W(ACC_W),
        .PEX(2), .PEY(2)
    ) dut (
        .clk(clk),
        .rst(rst),
        .in_seq(in_seq),
        .start(start),
        .done(done)
    );

    // softmax module instances (one per head for one query at a time in this small TB)
    // But transformer block expects TB to fill softmax_probs — for clarity we compute softmax here from scores produced in block (scores_int).
    // For the educational TB we will compute scores using same formula as block and feed to softmax.

    initial begin
        // reset
        #20; rst = 0;
        #10; rst = 1;

        // prepare a small example sequence
        for (int t=0; t<SEQ; t++) begin
            for (int e=0; e<EMB; e++) begin
                in_seq[t][e] = (t+1)*(e+1); // deterministic values
            end
        end

        // pulse start and wait for done
        start = 1;
        @(posedge clk);
        start = 0;

        // wait until done asserted
        wait (dut.state == dut.DONE);

        // For demonstration, print some internals in TB:
        $display("Q matrix (token x emb):");
        for (int i=0;i<SEQ;i++) begin
            $write("Q[%0d]: ", i);
            for (int e=0;e<EMB;e++) $write("%0d ", dut.Q_mat[i][e]);
            $display("");
        end

        // Compute scores and softmax externally to show final attention output
        for (int h=0; h<HEADS; h++) begin
            $display("Head %0d scores and softmax:", h);
            for (int qi=0; qi<SEQ; qi++) begin
                real scores_r [0:SEQ-1];
                real expsum = 0.0;
                real maxs = -1e30;
                for (int sj=0; sj<SEQ; sj++) begin
                    int dot = 0;
                    for (int d=0; d<HEAD_DIM; d++) begin
                        dot += dut.Q_mat[qi][h*HEAD_DIM + d] * dut.K_mat[sj][h*HEAD_DIM + d];
                    end
                    scores_r[sj] = $itor(dot) / $sqrt(HEAD_DIM);
                    if (scores_r[sj] > maxs) maxs = scores_r[sj];
                end
                for (int sj=0; sj<SEQ; sj++) begin
                    scores_r[sj] = $exp(scores_r[sj] - maxs);
                    expsum = expsum + scores_r[sj];
                end
                $write("Q=%0d probs: ", qi);
                for (int sj=0; sj<SEQ; sj++) $write("%0f ", scores_r[sj]/expsum);
                $display("");
            end
        end

        // Print final out_seq (produced by block)
        $display("Final output sequence (out_seq):");
        for (int i=0;i<SEQ;i++) begin
            $write("out[%0d]: ", i);
            for (int e=0;e<EMB;e++) $write("%0d ", dut.out_seq[i][e]);
            $display("");
        end

        $display("Testbench complete.");
        #20 $finish;
    end
endmodule

