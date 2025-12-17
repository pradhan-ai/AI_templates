//-------------------------------------------------------------
// TESTBENCH for sliding_window_buffer
//-------------------------------------------------------------
module tb_sliding_window_buffer;

    // ---- PARAMETERS ----
    localparam int WIDTH        = 8;
    localparam int HEIGHT       = 8;
    localparam int PIXEL_WIDTH  = 8;
    localparam int WINDOW       = 3;

    logic clk = 0;
    logic rst = 1;

    always #5 clk = ~clk;

    // DUT IO
    logic                        in_valid;
    logic [PIXEL_WIDTH-1:0]      in_pixel;
    logic                        in_ready;

    logic                        win_valid;
    logic [PIXEL_WIDTH-1:0]      window [WINDOW][WINDOW];

    // DUT instance
    sliding_window_buffer #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .WINDOW(WINDOW)
    ) dut (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .in_pixel(in_pixel),
        .in_ready(in_ready),
        .win_valid(win_valid),
        .window(window)
    );

    // ---- Input Image Buffer ----
    logic [PIXEL_WIDTH-1:0] img [HEIGHT][WIDTH];

    initial begin
        $display("Generating random image…");
        for (int r = 0; r < HEIGHT; r++)
            for (int c = 0; c < WIDTH; c++)
                img[r][c] = $urandom_range(0,255);
    end

    // Golden reference function
    function automatic [PIXEL_WIDTH-1:0] golden(int rr,int cc);
        if (rr < 0 || rr >= HEIGHT || cc < 0 || cc >= WIDTH)
            golden = '0;
        else
            golden = img[rr][cc];
    endfunction

    // Feed pixels
    int r = 0, c = 0;

    initial begin
        $dumpfile("sliding_window.vcd");
        $dumpvars(0, tb_sliding_window_buffer);

        repeat(5) @(posedge clk);
        rst = 0;

        in_valid = 0;

        @(posedge clk);

        // Begin streaming
        forever begin
            @(posedge clk);

            in_valid <= 1;
            in_pixel <= img[r][c];

            if (c == WIDTH-1) begin
                c = 0;
                r = r + 1;
                if (r == HEIGHT) begin
                    in_valid <= 0;
                    disable feed_done;
                end
            end else begin
                c++;
            end
        end

        feed_done: ;
        $display("Input image complete.");
    end

    // ---- Scoreboard ----
    initial begin
        wait(!rst);

        int out_r = 0;
        int out_c = 0;

        forever begin
            @(posedge clk);

            if (win_valid) begin
                // Coordinates of center pixel
                int cr = out_r;
                int cc = out_c;

                // Compare window output
                for (int wr = 0; wr < WINDOW; wr++)
                    for (int wc = 0; wc < WINDOW; wc++) begin
                        int rr = cr + wr - (WINDOW-1);
                        int cc_ = cc + wc - (WINDOW-1);

                        if (window[wr][wc] !== golden(rr,cc_)) begin
                            $error("Mismatch at (%0d,%0d) win(%0d,%0d): got %0d expected %0d",
                                    cr,cc,wr,wc,window[wr][wc],golden(rr,cc_));
                        end
                    end

                // Advance window center
                if (out_c == WIDTH-1)
                    out_c = 0, out_r++;
                else
                    out_c++;
            end
        end
    end

endmodule

