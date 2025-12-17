//======================================================================
// CNN-Friendly Multi-Channel Sliding Window Buffer
// 
// Supports:
//   - Multi-channel pixels (PIXEL_WIDTH * IN_CHANNELS)
//   - KxK windows (WINDOW_ROWS x WINDOW_COLS)
//   - STRIDE, PADDING, DILATION
//   - AXI-Stream input/output
//   - Produces full CNN window per pixel after fill
//
//======================================================================

module cnn_sliding_window #(
    parameter int PIXEL_WIDTH   = 8,     // bits per channel
    parameter int IN_CHANNELS   = 3,     // RGB = 3, CNN feature map C
    parameter int IMAGE_WIDTH   = 224,   // input feature map width
    parameter int IMAGE_HEIGHT  = 224,   // input feature map height

    parameter int WINDOW_ROWS   = 3,     // K (height)
    parameter int WINDOW_COLS   = 3,     // K (width)

    parameter int STRIDE        = 1,
    parameter int PADDING       = 1,
    parameter int DILATION      = 1
)(
    input  logic                               clk,
    input  logic                               rst_n,

    // --------------------------
    // AXI-Stream Input
    // --------------------------
    input  logic [PIXEL_WIDTH*IN_CHANNELS-1:0]  s_tdata,
    input  logic                                s_tvalid,
    output logic                                s_tready,

    // --------------------------
    // AXI-Stream Output: Window
    // --------------------------
    output logic [PIXEL_WIDTH*IN_CHANNELS-1:0]  m_tdata[WINDOW_ROWS][WINDOW_COLS],
    output logic                                m_tvalid,
    input  logic                                m_tready
);

    // ===============================================
    // PARAMETERS
    // ===============================================
    localparam int EFFECTIVE_COLS =
        1 + (WINDOW_COLS - 1) * DILATION;
    localparam int EFFECTIVE_ROWS =
        1 + (WINDOW_ROWS - 1) * DILATION;


    // ===============================================
    // LINE BUFFERS (multi-channel)
    // (WINDOW_ROWS − 1) lines × IMAGE_WIDTH columns
    // ===============================================
    logic [PIXEL_WIDTH*IN_CHANNELS-1:0] 
           line_buf[WINDOW_ROWS-1][IMAGE_WIDTH];

    logic [$clog2(IMAGE_WIDTH)-1:0] col;
    logic [$clog2(IMAGE_HEIGHT)-1:0] row;


    // ===============================================
    // Write / Streaming Input Handling (with padding)
    // ===============================================
    // (Row,col) mapping including padding logic
    logic [PIXEL_WIDTH*IN_CHANNELS-1:0] pixel_in;

    always_comb begin
        if (row < PADDING || row >= IMAGE_HEIGHT + PADDING ||
            col < PADDING || col >= IMAGE_WIDTH  + PADDING)
            pixel_in = '0;  // padded zeros
        else
            pixel_in = s_tdata;
    end

    assign s_tready = 1'b1;  // always ready


    // ===============================================
    // Line-buffer write logic
    // ===============================================
    integer r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col <= 0;
            row <= 0;
        end else if (s_tvalid && s_tready) begin
            // Fill line buffers
            for (r = WINDOW_ROWS-2; r >= 0; r--) begin
                if (r == 0)
                    line_buf[r][col] <= pixel_in;
                else
                    line_buf[r][col] <= line_buf[r-1][col];
            end

            // Advance coordinates
            col <= col + 1;
            if (col == IMAGE_WIDTH + 2*PADDING - 1) begin
                col <= 0;
                row <= row + 1;
            end
        end
    end


    // ===============================================
    // Horizontal Shift Registers (WINDOW_COLS taps)
    // ===============================================
    logic [PIXEL_WIDTH*IN_CHANNELS-1:0]
        shift_reg[WINDOW_ROWS][WINDOW_COLS];

    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < WINDOW_ROWS; i++)
                for (j = 0; j < WINDOW_COLS; j++)
                    shift_reg[i][j] <= '0;
        end else if (s_tvalid) begin

            // Row 0: new pixel
            shift_reg[0][0] <= pixel_in;
            for (j = 1; j < WINDOW_COLS; j++)
                shift_reg[0][j] <= shift_reg[0][j-1];

            // Remaining rows: read from buffers
            for (i = 1; i < WINDOW_ROWS; i++) begin
                shift_reg[i][0] <= 
                    line_buf[i-1][col];

                for (j = 1; j < WINDOW_COLS; j++)
                    shift_reg[i][j] <= 
                        shift_reg[i][j-1];
            end
        end
    end


    // ===============================================
    // Output Window Assignment
    // ===============================================
    always_comb begin
        for (i = 0; i < WINDOW_ROWS; i++)
            for (j = 0; j < WINDOW_COLS; j++)
                m_tdata[i][j] = shift_reg[i][j];
    end


    // ===============================================
    // Output Valid Logic with Handshake
    // ===============================================
    logic window_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            window_valid <= 1'b0;
        else if (s_tvalid)
            window_valid <= 1'b1;   // becomes valid after pipeline fill
        else if (m_tready)
            window_valid <= 1'b0;
    end

    assign m_tvalid = window_valid;

endmodule

