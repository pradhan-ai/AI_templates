module tile_pingpong_vec #(
    parameter int DATA_W      = 8,
    parameter int TILE_W      = 32,
    parameter int TILE_H      = 32,
    parameter int WIN_SIZE    = 3,
    parameter int PIX_PER_CLK = 8
)(
    input  logic clk,
    input  logic rst,

    // ---------------- DMA ----------------
    input  logic dma_valid,
    input  logic [DATA_W*PIX_PER_CLK-1:0] dma_pixels,
    output logic dma_ready,

    // ---------------- compute output -----
    output logic out_valid,
    output logic [DATA_W-1:0]
           window [PIX_PER_CLK][WIN_SIZE][WIN_SIZE]
);

    localparam int DEPTH = TILE_W*TILE_H/PIX_PER_CLK;

    // ------------------------------------------------------------
    // Two banks
    // ------------------------------------------------------------
    logic wr_sel;   // 0=ping write, 1=pong write
    logic rd_sel;   // opposite

    assign rd_sel = ~wr_sel;

    // ------------------------------------------------------------
    // addresses
    // ------------------------------------------------------------
    logic [$clog2(DEPTH)-1:0] wr_addr, rd_addr;

    // ------------------------------------------------------------
    // banks
    // ------------------------------------------------------------
    logic [DATA_W*PIX_PER_CLK-1:0] rd_ping, rd_pong;

    tile_buffer_bank #(
        .DATA_W(DATA_W),
        .TILE_W(TILE_W),
        .TILE_H(TILE_H),
        .PIX_PER_CLK(PIX_PER_CLK)
    ) ping (
        .clk(clk),
        .wr_en(dma_valid & ~wr_sel),
        .wr_data(dma_pixels),
        .wr_addr(wr_addr),
        .rd_en(rd_sel==0),
        .rd_addr(rd_addr),
        .rd_data(rd_ping)
    );

    tile_buffer_bank #(
        .DATA_W(DATA_W),
        .TILE_W(TILE_W),
        .TILE_H(TILE_H),
        .PIX_PER_CLK(PIX_PER_CLK)
    ) pong (
        .clk(clk),
        .wr_en(dma_valid & wr_sel),
        .wr_data(dma_pixels),
        .wr_addr(wr_addr),
        .rd_en(rd_sel==1),
        .rd_addr(rd_addr),
        .rd_data(rd_pong)
    );

    // ------------------------------------------------------------
    // DMA write pointer
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            wr_addr <= 0;
        else if (dma_valid)
            wr_addr <= wr_addr + 1;
    end

    assign dma_ready = 1;

    // ------------------------------------------------------------
    // compute read pointer
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            rd_addr <= 0;
        else
            rd_addr <= rd_addr + 1;
    end

    // ------------------------------------------------------------
    // select compute bank
    // ------------------------------------------------------------
    logic [DATA_W*PIX_PER_CLK-1:0] rd_data;

    assign rd_data = rd_sel ? rd_pong : rd_ping;

    // ------------------------------------------------------------
    // window engine
    // ------------------------------------------------------------
    tile_window2d_vec #(
        .DATA_W(DATA_W),
        .TILE_W(TILE_W),
        .TILE_H(TILE_H),
        .WIN_SIZE(WIN_SIZE),
        .PIX_PER_CLK(PIX_PER_CLK)
    ) win (
        .clk(clk),
        .rst(rst),
        .load_valid(1'b1),
        .load_pixels(rd_data),
        .out_valid(out_valid),
        .window(window)
    );

    // ------------------------------------------------------------
    // swap banks every tile
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rd_addr == DEPTH-1)
            wr_sel <= ~wr_sel;
    end

endmodule
