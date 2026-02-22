module window2d_generator #(
    parameter int DATA_W   = 8,    // pixel bits
    parameter int IMG_W    = 640,  // image width
    parameter int WIN_SIZE = 3     // window dimension (odd only)
)(
    input  logic                    clk,
    input  logic                    rst,

    input  logic                    in_valid,
    input  logic [DATA_W-1:0]       in_pixel,

    output logic                    out_valid,
    output logic [DATA_W-1:0]       window [WIN_SIZE][WIN_SIZE]
);

    // ------------------------------------------------------------
    // Line buffers (WIN_SIZE-1 rows stored)
    // ------------------------------------------------------------
    logic [DATA_W-1:0] linebuf [WIN_SIZE-2:0][IMG_W-1:0];

    logic [$clog2(IMG_W)-1:0] wr_ptr;

    // shift registers for horizontal sliding
    logic [DATA_W-1:0] shift [WIN_SIZE-1:0][WIN_SIZE-1:0];

    // row counter
    logic [$clog2(WIN_SIZE+1)-1:0] row_cnt;

    // ------------------------------------------------------------
    // Write pointer
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            wr_ptr <= 0;
        else if (in_valid)
            wr_ptr <= (wr_ptr == IMG_W-1) ? 0 : wr_ptr + 1;
    end

    // ------------------------------------------------------------
    // Line buffer update
    // ------------------------------------------------------------
    genvar r;
    generate
        for (r = 0; r < WIN_SIZE-1; r++) begin : LINEBUF
            always_ff @(posedge clk) begin
                if (in_valid) begin
                    if (r == 0)
                        linebuf[r][wr_ptr] <= in_pixel;
                    else
                        linebuf[r][wr_ptr] <= linebuf[r-1][wr_ptr];
                end
            end
        end
    endgenerate

    // ------------------------------------------------------------
    // Horizontal shift registers
    // ------------------------------------------------------------
    integer i, j;

    always_ff @(posedge clk) begin
        if (in_valid) begin

            // Row 0 (current input)
            shift[0][0] <= in_pixel;
            for (j = 1; j < WIN_SIZE; j++)
                shift[0][j] <= shift[0][j-1];

            // Rows from line buffers
            for (i = 1; i < WIN_SIZE; i++) begin
                shift[i][0] <= linebuf[i-1][wr_ptr];
                for (j = 1; j < WIN_SIZE; j++)
                    shift[i][j] <= shift[i][j-1];
            end
        end
    end

    // ------------------------------------------------------------
    // Output window mapping
    // ------------------------------------------------------------
    always_comb begin
        for (i = 0; i < WIN_SIZE; i++)
            for (j = 0; j < WIN_SIZE; j++)
                window[i][j] = shift[i][j];
    end

    // ------------------------------------------------------------
    // Valid generation
    // valid only after enough rows + columns received
    // ------------------------------------------------------------
    logic [$clog2(IMG_W+1)-1:0] col_cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            row_cnt <= 0;
            col_cnt <= 0;
            out_valid <= 0;
        end
        else if (in_valid) begin

            col_cnt <= col_cnt + 1;

            if (col_cnt == IMG_W-1) begin
                col_cnt <= 0;
                row_cnt <= row_cnt + 1;
            end

            out_valid <= (row_cnt >= WIN_SIZE-1) &&
                         (col_cnt >= WIN_SIZE-1);
        end
    end

endmodule
