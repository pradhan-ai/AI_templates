module tile_window2d_vec #(
    parameter int DATA_W      = 8,
    parameter int TILE_W      = 32,
    parameter int TILE_H      = 32,
    parameter int WIN_SIZE    = 3,
    parameter int PIX_PER_CLK = 4     // <<< NEW
)(
    input  logic clk,
    input  logic rst,

    // tile load (vector)
    input  logic load_valid,
    input  logic [DATA_W*PIX_PER_CLK-1:0] load_pixels,

    // output windows (vector)
    output logic out_valid,
    output logic [DATA_W-1:0]
           window [PIX_PER_CLK][WIN_SIZE][WIN_SIZE]
);

    // ------------------------------------------------------------
    // Tile memory (1 pixel each entry)
    // ------------------------------------------------------------
    logic [DATA_W-1:0] tile_mem [0:TILE_H-1][0:TILE_W-1];

    // ------------------------------------------------------------
    // VECTOR TILE LOAD
    // ------------------------------------------------------------
    logic [$clog2(TILE_W)-1:0] load_x;
    logic [$clog2(TILE_H)-1:0] load_y;

    integer lane;

    always_ff @(posedge clk) begin
        if (rst) begin
            load_x <= 0;
            load_y <= 0;
        end
        else if (load_valid) begin
            for (lane = 0; lane < PIX_PER_CLK; lane++) begin
                tile_mem[load_y][load_x + lane]
                   <= load_pixels[lane*DATA_W +: DATA_W];
            end

            if (load_x + PIX_PER_CLK >= TILE_W) begin
                load_x <= 0;
                load_y <= load_y + 1;
            end
            else
                load_x <= load_x + PIX_PER_CLK;
        end
    end

    // ------------------------------------------------------------
    // WINDOW SWEEP
    // ------------------------------------------------------------
    logic [$clog2(TILE_W)-1:0] rd_x;
    logic [$clog2(TILE_H)-1:0] rd_y;

    integer i,j,l;

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_x <= 0;
            rd_y <= 0;
            out_valid <= 0;
        end
        else begin
            // generate windows for all lanes
            for (l = 0; l < PIX_PER_CLK; l++) begin
                for (i = 0; i < WIN_SIZE; i++)
                    for (j = 0; j < WIN_SIZE; j++)
                        window[l][i][j]
                            <= tile_mem[rd_y+i][rd_x+l+j];
            end

            // advance pointer
            if (rd_x + PIX_PER_CLK >= TILE_W-WIN_SIZE+1) begin
                rd_x <= 0;

                if (rd_y == TILE_H-WIN_SIZE)
                    rd_y <= 0;
                else
                    rd_y <= rd_y + 1;
            end
            else
                rd_x <= rd_x + PIX_PER_CLK;

            out_valid <= 1;
        end
    end

endmodule
