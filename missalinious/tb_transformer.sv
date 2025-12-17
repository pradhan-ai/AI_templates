// tb_transformer.sv
`timescale 1ns/1ps
module tb_transformer;
    import transformer_pkg::*;

    localparam int SEQ = 4;
    localparam int EMB = 8;
    localparam int HEADS = 2;
    localparam int HEAD_DIM = EMB/HEADS;

    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;

    transformer_pkg::seq_emb_t in_seq;
    transformer_pkg::seq_emb_t out_seq;

    logic valid_in = 0, valid_out;

    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
    end

    // instantiate a simple MHA for functional test
    mha #(.SEQ(SEQ), .EMB(EMB), .HEADS(HEADS), .HEAD_DIM(HEAD_DIM)) dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .in_seq(in_seq),
        .valid_out(valid_out), .out_seq(out_seq),
        .cfg_we(0), .cfg_addr(0), .cfg_wdata(0)
    );

    // feed a tiny sequence
    initial begin
        @(posedge rst_n);
        // populate in_seq with small integers
        for (int t=0;t<SEQ;t++) begin
            for (int e=0;e<EMB;e++) in_seq[t][e] = (t+1)*(e+1);
        end

        // pulse valid
        #10;
        valid_in = 1;
        #10;
        valid_in = 0;

        // wait for output
        wait (valid_out == 1);
        $display("MHA produced output:");
        for (int t=0; t<SEQ; t++) begin
            $write("t=%0d: ", t);
            for (int e=0; e<EMB; e++) $write("%0d ", out_seq[t][e]);
            $display("");
        end
        $display("Testbench done.");
        #10 $finish;
    end
endmodule

