module tile_buffer_bank #(
    parameter int DATA_W      = 8,
    parameter int TILE_W      = 32,
    parameter int TILE_H      = 32,
    parameter int PIX_PER_CLK = 8
)(
    input  logic clk,

    // DMA write
    input  logic wr_en,
    input  logic [DATA_W*PIX_PER_CLK-1:0] wr_data,
    input  logic [$clog2(TILE_W*TILE_H/PIX_PER_CLK)-1:0] wr_addr,

    // read to window engine
    input  logic rd_en,
    input  logic [$clog2(TILE_W*TILE_H/PIX_PER_CLK)-1:0] rd_addr,
    output logic [DATA_W*PIX_PER_CLK-1:0] rd_data
);

    logic [DATA_W*PIX_PER_CLK-1:0]
        mem [0:(TILE_W*TILE_H/PIX_PER_CLK)-1];

    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;

        if (rd_en)
            rd_data <= mem[rd_addr];
    end

endmodule
