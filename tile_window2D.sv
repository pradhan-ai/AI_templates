module tile_window2d #(
    parameter int DATA_W   = 8,
    parameter int TILE_W   = 16,
    parameter int TILE_H   = 16,
    parameter int WIN_SIZE = 3
)(
    input  logic clk,
    input  logic rst,

    // tile loading
    input  logic                    load_valid,
    input  logic [DATA_W-1:0]       load_pixel,

    // window output
    output logic                    out_valid,
    output logic [DATA_W-1:0]       window [WIN_SIZE][WIN_SIZE]
);

    // ------------------------------------------------------------
    // Tile SRAM buffer (BRAM inferred)
    // ------------------------------------------------------------
    logic [DATA_W-1:0] tile_mem [TILE_H-1:0][TILE_W-1:0];

    logic [$clog2(TILE_W)-1:0] load_x;
    logic [$clog2(TILE_H)-1:0] load_y;

    // ------------------------------------------------------------
    // Tile load (raster order)
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            load_x <= 0;
            load_y <= 0;
        end
        else if (load_valid) begin
            tile_mem[load_y][load_x] <= load_pixel;

            if (load_x == TILE_W-1) begin
                load_x <= 0;
                load_y <= load_y + 1;
            end
            else
                load_x <= load_x + 1;
        end
    end

    // ------------------------------------------------------------
    // Sliding window inside tile
    // ------------------------------------------------------------
    logic [$clog2(TILE_W)-1:0] rd_x;
    logic [$clog2(TILE_H)-1:0] rd_y;

    integer i,j;

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_x <= 0;
            rd_y <= 0;
            out_valid <= 0;
        end
        else begin
            // read window pixels
            for (i = 0; i < WIN_SIZE; i++)
                for (j = 0; j < WIN_SIZE; j++)
                    window[i][j] <= tile_mem[rd_y+i][rd_x+j];

            // advance window position
            if (rd_x == TILE_W-WIN_SIZE) begin
                rd_x <= 0;

                if (rd_y == TILE_H-WIN_SIZE)
                    rd_y <= 0;
                else
                    rd_y <= rd_y + 1;
            end
            else
                rd_x <= rd_x + 1;

            out_valid <= 1;
        end
    end

endmodule
