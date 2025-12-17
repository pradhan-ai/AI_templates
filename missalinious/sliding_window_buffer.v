//======================================================================
// Multi-Line Sliding Window Buffer
// Parameterized N x M sliding window generator for image pipelines.
//
// Produces a sliding window of size:
//     WINDOW_ROWS x WINDOW_COLS
//
// Example: 3x3 CNN filter → WINDOW_ROWS=3, WINDOW_COLS=3
//
// After pipeline fill, produces a valid window every cycle.
//======================================================================

module sliding_window_buffer #(
    parameter int PIXEL_WIDTH  = 8,         // bits per pixel
    parameter int IMAGE_WIDTH  = 1920,      // pixels per line
    parameter int WINDOW_ROWS  = 3,         // number of lines in window
    parameter int WINDOW_COLS  = 3          // horizontal tap size
)(
    input  logic                             clk,
    input  logic                             rst_n,

    // Input pixel stream
    input  logic [PIXEL_WIDTH-1:0]            pixel_in,
    input  logic                              pixel_in_valid,

    // Output sliding window
    output logic [PIXEL_WIDTH-1:0]            window[WINDOW_ROWS][WINDOW_COLS],
    output logic                              window_valid
);

    // --------------------------------------------------------------
    // INTERNAL STORAGE
    // --------------------------------------------------------------

    // --- Line buffers: (WINDOW_ROWS - 1) lines, each IMAGE_WIDTH long
    logic [PIXEL_WIDTH-1:0] line_buf [WINDOW_ROWS-1][IMAGE_WIDTH];

    // --- Horizontal shift registers
    logic [PIXEL_WIDTH-1:0] shift_reg [WINDOW_ROWS][WINDOW_COLS];

    // write column counter (0 .. IMAGE_WIDTH-1)
    logic [$clog2(IMAGE_WIDTH)-1:0] col;

    // Pipeline valid shift
    logic [WINDOW_ROWS + WINDOW_COLS - 1:0] valid_shift;


    // --------------------------------------------------------------
    // WRITE PIXELS → LINE BUFFERS
    // --------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col <= 0;
        end else if (pixel_in_valid) begin
            
            // Shift: Move rows downward
            integer r;
            for (r = WINDOW_ROWS-2; r >= 0; r--) begin
                // Top line buffer writes from input first
                if (r == 0)
                    line_buf[r][col] <= pixel_in;
                else
                    line_buf[r][col] <= line_buf[r-1][col];
            end

            // Advance column
            col <= (col == IMAGE_WIDTH-1) ? 0 : col + 1;
        end
    end


    // --------------------------------------------------------------
    // HORIZONTAL SHIFT REGISTERS FOR EACH ROW
    // --------------------------------------------------------------
    integer i, j;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin

            // Clear shift registers
            for (i = 0; i < WINDOW_ROWS; i++)
                for (j = 0; j < WINDOW_COLS; j++)
                    shift_reg[i][j] <= 0;

        end else if (pixel_in_valid) begin

            // Row 0 -> comes from pixel input directly
            shift_reg[0][0] <= pixel_in;
            for (j = 1; j < WINDOW_COLS; j++)
                shift_reg[0][j] <= shift_reg[0][j-1];

            // Remaining rows -> read from line buffers
            for (i = 1; i < WINDOW_ROWS; i++) begin
                shift_reg[i][0] <= line_buf[i-1][col];
                for (j = 1; j < WINDOW_COLS; j++)
                    shift_reg[i][j] <= shift_reg[i][j-1];
            end
        end
    end


    // --------------------------------------------------------------
    // OUTPUT WINDOW + VALID SIGNAL
    // --------------------------------------------------------------
    always_comb begin
        for (i = 0; i < WINDOW_ROWS; i++)
            for (j = 0; j < WINDOW_COLS; j++)
                window[i][j] = shift_reg[i][j];
    end

    // Pipeline valid generation (after buffer is filled)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_shift <= '0;
        else
            valid_shift <= {valid_shift[$bits(valid_shift)-2:0], pixel_in_valid};
    end

    assign window_valid =
        valid_shift[$bits(valid_shift)-1];

endmodule

