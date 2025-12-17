`timescale 1ns/1ps

module tb_transformer_encoder;

    // ---------------- PARAMETERS ----------------
    localparam int SEQ_LEN   = 4;
    localparam int EMBED_DIM = 8;
    localparam int HEADS     = 2;
    localparam int HEAD_DIM  = EMBED_DIM / HEADS;
    localparam int DATA_W    = 16;

    // ---------------- CLOCK / RESET ----------------
    logic clk = 0;
    always #5 clk = ~clk;

    logic rst;
    logic valid_in, valid_out;

    // ---------------- DUT IO ----------------
    logic signed [DATA_W-1:0] x [SEQ_LEN][EMBED_DIM];
    logic signed [DATA_W-1:0] y [SEQ_LEN][EMBED_DIM];

    // ---------------- DUT ----------------
    transformer_encoder #(
        .SEQ_LEN(SEQ_LEN),
        .EMBED_DIM(EMBED_DIM),
        .HEADS(HEADS),
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .x(x),
        .valid_out(valid_out),
        .y(y)
    );

    // ---------------- TEST SEQUENCE ----------------
    initial begin
        rst = 1;
        valid_in = 0;
        #20 rst = 0;

        // Deterministic input (MATCH PYTHON)
        for (int i=0;i<SEQ_LEN;i++)
            for (int j=0;j<EMBED_DIM;j++)
                x[i][j] = (i+1)*(j+2);

        @(posedge clk);
        valid_in = 1;

        @(posedge clk);
        valid_in = 0;

        // Wait for output
        wait(valid_out);

        $display("\n=== TRANSFORMER OUTPUT ===");
        for (int i=0;i<SEQ_LEN;i++) begin
            $write("y[%0d]: ", i);
            for (int j=0;j<EMBED_DIM;j++)
                $write("%0d ", y[i][j]);
            $display("");
        end

        // Dump output for Python comparison
        int fd = $fopen("rtl_output.txt","w");
        for (int i=0;i<SEQ_LEN;i++)
            for (int j=0;j<EMBED_DIM;j++)
                $fwrite(fd,"%0d\n", y[i][j]);
        $fclose(fd);

        $display("\nRTL output written to rtl_output.txt");
        #20 $finish;
    end

endmodule

