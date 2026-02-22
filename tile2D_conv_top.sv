`timescale 1ns/1ps

module tb_tile_conv2d_top;

    // --------------------------------------------------------
    // Parameters
    // --------------------------------------------------------
    localparam IMG_W       = 128;
    localparam IMG_H       = 128;
    localparam TILE_W      = 32;
    localparam TILE_H      = 32;
    localparam PIX_PER_CLK = 8;
    localparam DATA_W      = 8;
    localparam WIN_SIZE    = 3;

    // --------------------------------------------------------
    // Clock
    // --------------------------------------------------------
    logic clk=0;
    always #5 clk = ~clk;

    logic rst;

    initial begin
        rst=1;
        #40 rst=0;
    end

    // --------------------------------------------------------
    // Image memory
    // --------------------------------------------------------
    logic [7:0] img_mem [0:IMG_W*IMG_H-1];

    initial begin
        $display("Loading image.hex ...");
        $readmemh("image.hex", img_mem);
    end

    // --------------------------------------------------------
    // Kernel (Gaussian example)
    // --------------------------------------------------------
    logic signed [7:0] kernel [WIN_SIZE][WIN_SIZE];

    initial begin
        kernel = '{
            '{1,2,1},
            '{2,4,2},
            '{1,2,1}
        };
    end

    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------
    logic dma_valid;
    logic [DATA_W*PIX_PER_CLK-1:0] dma_pixels;

    logic out_valid;
    logic signed [31:0] out_pixels [PIX_PER_CLK];

    tile_conv2d_top dut(
        .clk(clk),
        .rst(rst),
        .dma_valid(dma_valid),
        .dma_pixels(dma_pixels),
        .kernel(kernel),
        .out_valid(out_valid),
        .out_pixels(out_pixels)
    );

    // --------------------------------------------------------
    // DMA driver (vector)
    // --------------------------------------------------------
    integer addr;

    always_ff @(posedge clk) begin
        if (rst) begin
            addr <= 0;
            dma_valid <= 0;
        end
        else begin
            dma_valid <= 1;

            for (int i=0;i<PIX_PER_CLK;i++)
                dma_pixels[i*8 +: 8] <= img_mem[addr+i];

            addr <= addr + PIX_PER_CLK;

            if (addr >= IMG_W*IMG_H-PIX_PER_CLK)
                dma_valid <= 0;
        end
    end

    // --------------------------------------------------------
    // Dump output image
    // --------------------------------------------------------
    integer fp;

    initial fp = $fopen("conv_out.hex","w");

    always_ff @(posedge clk) begin
        if (out_valid) begin
            for(int i=0;i<PIX_PER_CLK;i++)
                $fwrite(fp,"%02x\n", out_pixels[i][7:0]);
        end
    end

    // --------------------------------------------------------
    // Run
    // --------------------------------------------------------
    initial begin
        #200000;
        $fclose(fp);
        $display("DONE. Output -> conv_out.hex");
        $finish;
    end

endmodule
