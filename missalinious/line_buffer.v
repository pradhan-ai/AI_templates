//===========================================================
// Parameterized Line Buffer
// Stores N lines, each of width W pixels.
// Useful for imaging pipelines, convolution preprocessors,
// rasterizers, interpolation, etc.
//===========================================================

module line_buffer #(
    parameter int PIXEL_WIDTH = 8,        // bits per pixel
    parameter int LINE_WIDTH  = 1920,     // pixels per line
    parameter int NUM_LINES   = 3         // number of buffered lines
)(
    input  logic                        clk,
    input  logic                        rst_n,

    // Write pixel stream
    input  logic [PIXEL_WIDTH-1:0]      pixel_in,
    input  logic                        pixel_in_valid,

    // Read pixel stream from a selected line and column
    input  logic [$clog2(NUM_LINES)-1:0] rd_line_sel,
    input  logic [$clog2(LINE_WIDTH)-1:0] rd_col_sel,
    output logic [PIXEL_WIDTH-1:0]      pixel_out,
    output logic                        pixel_out_valid
);

    // -------------------------------------------------------
    // Memory: NUM_LINES × LINE_WIDTH pixels
    // ---------------------------------
    logic [PIXEL_WIDTH-1:0] mem [NUM_LINES][LINE_WIDTH];

    // Write pointer increments for each input pixel
    logic [$clog2(LINE_WIDTH)-1:0] wr_col;

    // Write row pointer to determine which line to fill
    logic [$clog2(NUM_LINES)-1:0] wr_line;

    // -------------------------------------------------------
    // Write Logic
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_col  <= 0;
            wr_line <= 0;
        end else if (pixel_in_valid) begin

            // Write incoming pixel
            mem[wr_line][wr_col] <= pixel_in;

            // Advance write column
            wr_col <= wr_col + 1;

            // Wrap to next line on full row
            if (wr_col == LINE_WIDTH-1) begin
                wr_col  <= 0;
                wr_line <= wr_line + 1;

                // Wrap lines
                if (wr_line == NUM_LINES-1)
                    wr_line <= 0;
            end
        end
    end

    // -------------------------------------------------------
    // Read Logic
    // -------------------------------------------------------
    logic [PIXEL_WIDTH-1:0] read_data;

    always_comb begin
        // Direct memory access
        read_data = mem[rd_line_sel][rd_col_sel];
    end

    // Pixel output is always valid if a read coordinate is driven
    assign pixel_out       = read_data;
    assign pixel_out_valid = 1'b1;

endmodule

