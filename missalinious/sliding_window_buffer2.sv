
//-------------------------------------------------------------
// Multi-Line Sliding Window Buffer (CNN-Friendly)
// Parameterised for WIDTH, HEIGHT, PIXEL_WIDTH, WINDOW
//-------------------------------------------------------------
module sliding_window_buffer #(
    parameter int WIDTH        = 64,
    parameter int HEIGHT       = 64,
    parameter int PIXEL_WIDTH  = 8,
    parameter int WINDOW       = 3         // e.g., 3x3, 5x5 etc.
)(
    input  logic                        clk,
    input  logic                        rst,

    // Streaming pixel input (row-major)
    input  logic                        in_valid,
    input  logic [PIXEL_WIDTH-1:0]      in_pixel,
    output logic                        in_ready,

    // Sliding window output
    output logic                        win_valid,
    output logic [PIXEL_WIDTH-1:0]      window [WINDOW][WINDOW]
);

    // -----------------------------------------------------------
    // Internal line buffers: WINDOW-1 FIFOs
    // Each FIFO stores one full row of WIDTH pixels
    // -----------------------------------------------------------
    logic [PIXEL_WIDTH-1:0] linebuf [WINDOW-1][WIDTH];

    int write_ptr = 0;
    int read_ptr  = 0;

    // Internal signals
    logic [PIXEL_WIDTH-1:0] cur_row_shift [WIDTH];
    int row_count = 0;
    int col_count = 0;

    assign in_ready = 1'b1; // always ready for streaming

    // -----------------------------------------------------------
    // Pixel processing
    // -----------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            row_count <= 0;
            col_count <= 0;
        end else if (in_valid) begin

            // SHIFT: right shift current row pixels
            for (int i = WIDTH-1; i > 0; i--)
                cur_row_shift[i] <= cur_row_shift[i-1];

            cur_row_shift[0] <= in_pixel;

            // Move column/row forward
            if (col_count == WIDTH-1) begin
                col_count <= 0;
                row_count <= row_count + 1;

                // Store shifted row into line buffers
                for (int lb = WINDOW-2; lb >= 0; lb--) begin
                    for (int c = 0; c < WIDTH; c++) begin
                        if (lb == 0)
                            linebuf[0][c] <= cur_row_shift[c];
                        else
                            linebuf[lb][c] <= linebuf[lb-1][c];
                    end
                end
            end else begin
                col_count <= col_count + 1;
            end
        end
    end

    // -----------------------------------------------------------
    // Assemble window
    // -----------------------------------------------------------
    always_comb begin
        win_valid = (row_count >= WINDOW-1) && (col_count >= WINDOW-1);

        for (int r = 0; r < WINDOW; r++) begin
            for (int c = 0; c < WINDOW; c++) begin
                // Handle borders via zero-padding
                int rr = row_count - (WINDOW-1-r);
                int cc = col_count - (WINDOW-1-c);

                if (rr < 0 || cc < 0)
                    window[r][c] = '0;
                else if (rr == row_count)
                    window[r][c] = cur_row_shift[cc];
                else
                    window[r][c] = linebuf[(WINDOW-2)-(row_count-rr)][cc];
            end
        end
    end
endmodule
