// tb_conv2d_engine.sv
`timescale 1ns/1ps
module tb_conv2d_engine;

    // parameters
    localparam int DATA_W = 8;
    localparam int ACC_W  = 32;
    localparam int IN_CH  = 1;
    localparam int OUT_CH = 1;
    localparam int K      = 3;

    logic clk = 0;
    always #5 clk = ~clk;

    logic rst_n = 0;

    // DUT I/O
    logic [DATA_W*IN_CH-1:0] win [K-1:0][K-1:0];
    logic win_valid;
    logic win_ready;
    logic signed [ACC_W-1:0] out_data [OUT_CH-1:0];
    logic out_valid;
    logic out_ready;

    // cfg interface
    logic cfg_write;
    logic [$clog2(OUT_CH*IN_CH*K*K + OUT_CH + 1)-1:0] cfg_addr;
    logic signed [DATA_W-1:0] cfg_wdata;

    // instantiate DUT
    conv2d_engine #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .IN_CH(IN_CH),
        .OUT_CH(OUT_CH),
        .K(K)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .window(win),
        .win_valid(win_valid),
        .win_ready(win_ready),
        .out_data(out_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .cfg_write(cfg_write),
        .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata)
    );

    // simple 5x5 test image (single channel)
    int IMG_W = 5;
    int IMG_H = 5;
    logic signed [DATA_W-1:0] image [0:IMG_H-1][0:IMG_W-1];

    // Golden kernel (3x3) and bias
    logic signed [DATA_W-1:0] kernel[0:K-1][0:K-1];
    logic signed [DATA_W-1:0] bias;

    // prepare image and kernel
    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;

        // sample image
        int v = 1;
        for (int r=0; r<IMG_H; r++)
            for (int c=0; c<IMG_W; c++) begin
                image[r][c] = v;
                v = v + 1;
            end

        // example kernel (edge detector)
        kernel[0][0] =  1; kernel[0][1] =  0; kernel[0][2] = -1;
        kernel[1][0] =  1; kernel[1][1] =  0; kernel[1][2] = -1;
        kernel[2][0] =  1; kernel[2][1] =  0; kernel[2][2] = -1;
        bias = 0;

        // load weights into DUT via cfg interface
        // We use the mapping described in the engine:
        // addr 0..8 : weights for out_ch0 (in_ch0, kr,kc order)
        // addr 9     : bias
        #10;
        for (int rr=0; rr<K; rr++) begin
            for (int cc=0; cc<K; cc++) begin
                cfg_write = 1;
                cfg_addr  = rr*K + cc; // since IN_CH=1 and OUT_CH=1
                cfg_wdata = kernel[rr][cc];
                @(posedge clk);
            end
        end
        // write bias
        cfg_write = 1;
        cfg_addr = K*K; // bias offset = WEIGHT_COUNT
        cfg_wdata = bias;
        @(posedge clk);
        cfg_write = 0;
        @(posedge clk);

        // now drive windows for every valid center pixel (no padding assumed)
        out_ready = 1;

        // Generate windows for positions where kernel fully fits: r=1..H-2, c=1..W-2
        for (int r=1; r<IMG_H-1; r++) begin
            for (int c=1; c<IMG_W-1; c++) begin
                // build the 3x3 window
                for (int kr=0; kr<K; kr++)
                    for (int kc=0; kc<K; kc++) begin
                        win[kr][kc] = image[r + kr - 1][c + kc - 1];
                    end
                // present window
                win_valid = 1;
                @(posedge clk);
                // consume win_valid cycle
                win_valid = 0;

                // wait for output valid
                wait (out_valid == 1);
                // compute golden
                int golden = 0;
                for (int kr=0; kr<K; kr++)
                    for (int kc=0; kc<K; kc++)
                        golden += image[r + kr - 1][c + kc - 1] * kernel[kr][kc];
                $display("Pos (%0d,%0d): conv=%0d dut=%0d", r, c, golden, out_data[0]);
                if (golden !== out_data[0]) $error("Mismatch at %0d,%0d : golden %0d dut %0d", r, c, golden, out_data[0]);

                @(posedge clk);
            end
        end

        $display("Testbench finished.");
        $stop;
    end

endmodule

