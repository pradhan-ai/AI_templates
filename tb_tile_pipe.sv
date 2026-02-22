`timescale 1ns/1ps

module tb_tile_pipeline;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam DATA_W   = 8;
    localparam IMG_W    = 64;
    localparam IMG_H    = 64;
    localparam TILE_W   = 16;
    localparam TILE_H   = 16;
    localparam WIN_SIZE = 3;

    // ------------------------------------------------------------
    // Clock / Reset
    // ------------------------------------------------------------
    logic clk = 0;
    always #5 clk = ~clk;

    logic rst;

    initial begin
        rst = 1;
        #50 rst = 0;
    end

    // ------------------------------------------------------------
    // Image memory
    // ------------------------------------------------------------
    logic [DATA_W-1:0] image_mem [0:IMG_W*IMG_H-1];

    initial begin
        $display("Loading image...");
        $readmemh("image.hex", image_mem);
    end

    // ------------------------------------------------------------
    // Scheduler signals
    // ------------------------------------------------------------
    logic start;
    logic dma_start, dma_done;
    logic compute_start, compute_done;
    logic store_start, store_done;
    logic frame_done;
    logic buf_sel;

    logic [$clog2(IMG_W/TILE_W)-1:0] tile_x;
    logic [$clog2(IMG_H/TILE_H)-1:0] tile_y;

    // ------------------------------------------------------------
    // DUT : Scheduler
    // ------------------------------------------------------------
    tile_scheduler_fsm #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .TILE_W(TILE_W),
        .TILE_H(TILE_H)
    ) scheduler (
        .clk(clk),
        .rst(rst),
        .start(start),

        .dma_start(dma_start),
        .dma_done(dma_done),

        .compute_start(compute_start),
        .compute_done(compute_done),

        .store_start(store_start),
        .store_done(store_done),

        .tile_x(tile_x),
        .tile_y(tile_y),
        .buf_sel(buf_sel),
        .frame_done(frame_done)
    );

    // ------------------------------------------------------------
    // Tile window DUT
    // ------------------------------------------------------------
    logic load_valid;
    logic [DATA_W-1:0] load_pixel;

    logic win_valid;
    logic [DATA_W-1:0] window [WIN_SIZE][WIN_SIZE];

    tile_window2d #(
        .DATA_W(DATA_W),
        .TILE_W(TILE_W),
        .TILE_H(TILE_H),
        .WIN_SIZE(WIN_SIZE)
    ) win_gen (
        .clk(clk),
        .rst(rst),
        .load_valid(load_valid),
        .load_pixel(load_pixel),
        .out_valid(win_valid),
        .window(window)
    );

    // ------------------------------------------------------------
    // DMA MODEL (tile fetch from image_mem)
    // ------------------------------------------------------------
    int load_count;

    always_ff @(posedge clk) begin
        dma_done   <= 0;
        load_valid <= 0;

        if (dma_start) begin
            load_count <= 0;
        end

        if (dma_start || load_count != 0) begin
            int gx, gy, addr;

            gx = tile_x*TILE_W + (load_count % TILE_W);
            gy = tile_y*TILE_H + (load_count / TILE_W);

            addr = gy*IMG_W + gx;

            load_pixel <= image_mem[addr];
            load_valid <= 1;

            load_count++;

            if (load_count == TILE_W*TILE_H) begin
                dma_done <= 1;
                load_count <= 0;
            end
        end
    end

    // ------------------------------------------------------------
    // Compute model (window sweep timing)
    // ------------------------------------------------------------
    int compute_cycles;

    always_ff @(posedge clk) begin
        compute_done <= 0;

        if (compute_start)
            compute_cycles <= 0;

        if (compute_start || compute_cycles != 0) begin
            compute_cycles++;

            if (compute_cycles ==
                (TILE_W-WIN_SIZE+1)*(TILE_H-WIN_SIZE+1)) begin
                compute_done <= 1;
                compute_cycles <= 0;
            end
        end
    end

    // ------------------------------------------------------------
    // Store model (dummy)
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        store_done <= store_start;
    end

    // ------------------------------------------------------------
    // Output dump
    // ------------------------------------------------------------
    integer fp;

    initial fp = $fopen("windows_out.txt","w");

    always_ff @(posedge clk) begin
        if (win_valid) begin
            int i,j;
            for(i=0;i<WIN_SIZE;i++) begin
                for(j=0;j<WIN_SIZE;j++)
                    $fwrite(fp,"%02x ", window[i][j]);
                $fwrite(fp,"| ");
            end
            $fwrite(fp,"\n");
        end
    end

    // ------------------------------------------------------------
    // Run
    // ------------------------------------------------------------
    initial begin
        start = 0;
        #100;
        start = 1;
        #10 start = 0;

        wait(frame_done);

        $display("Frame complete!");
        $fclose(fp);
        #50 $finish;
    end

endmodule
