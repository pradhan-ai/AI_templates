module tile_conv2d_top #(
    parameter int DATA_W      = 8,
    parameter int COEF_W      = 8,
    parameter int IMG_W       = 256,
    parameter int IMG_H       = 256,
    parameter int TILE_W      = 32,
    parameter int TILE_H      = 32,
    parameter int WIN_SIZE    = 3,
    parameter int PIX_PER_CLK = 8,
    parameter int SUM_W       = 32
)(
    input  logic clk,
    input  logic rst,

    // vector DMA input stream
    input  logic dma_valid,
    input  logic [DATA_W*PIX_PER_CLK-1:0] dma_pixels,

    // convolution kernel
    input  logic signed [COEF_W-1:0]
           kernel [WIN_SIZE][WIN_SIZE],

    // results
    output logic out_valid,
    output logic signed [SUM_W-1:0] out_pixels [PIX_PER_CLK]
);

    // =========================================================
    // 1. Ping/Pong tile engine + vector windows
    // =========================================================
    logic win_valid;

    logic signed [DATA_W-1:0]
        windows [PIX_PER_CLK][WIN_SIZE][WIN_SIZE];

    tile_pingpong_vec #(
        .DATA_W(DATA_W),
        .TILE_W(TILE_W),
        .TILE_H(TILE_H),
        .WIN_SIZE(WIN_SIZE),
        .PIX_PER_CLK(PIX_PER_CLK)
    ) tile_core (
        .clk(clk),
        .rst(rst),
        .dma_valid(dma_valid),
        .dma_pixels(dma_pixels),
        .dma_ready(),
        .out_valid(win_valid),
        .window(windows)
    );

    // =========================================================
    // 2. Convolution MAC array
    // =========================================================
    conv2d_mac_array_vec #(
        .DATA_W(DATA_W),
        .COEF_W(COEF_W),
        .WIN_SIZE(WIN_SIZE),
        .PIX_PER_CLK(PIX_PER_CLK),
        .SUM_W(SUM_W)
    ) mac (
        .clk(clk),
        .rst(rst),
        .in_valid(win_valid),
        .window(windows),
        .kernel(kernel),
        .out_valid(out_valid),
        .result(out_pixels)
    );

endmodule
