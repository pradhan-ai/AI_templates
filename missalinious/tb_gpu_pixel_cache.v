// tb_gpu_pixel_cache.v
`timescale 1ns/1ps
module tb_gpu_pixel_cache;
    parameter TILE_W = 8;
    parameter TILE_H = 8;
    parameter PIXEL_WIDTH = 32;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
    end

    // DUT signals
    reg [31:0] req_x, req_y;
    reg [1:0]  req_mip;
    reg        req_valid;
    wire       req_ready;
    wire [PIXEL_WIDTH-1:0] pixel_out;
    wire       pixel_valid;

    // mem interface
    wire mem_req;
    wire [31:0] mem_addr;
    wire [15:0] mem_burst_len;
    reg  mem_rvalid;
    reg  [PIXEL_WIDTH-1:0] mem_rdata;
    reg  mem_rlast;
    wire mem_rready;

    // Instantiate DUT
    gpu_pixel_cache #(
        .ADDR_WIDTH(32),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .TILE_W(TILE_W),
        .TILE_H(TILE_H),
        .NUM_SETS(16),
        .NUM_WAYS(4),
        .NUM_MIP_LEVELS(4),
        .TAG_XY_BITS(12)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_x(req_x),
        .req_y(req_y),
        .req_mip(req_mip),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .pixel_out(pixel_out),
        .pixel_valid(pixel_valid),
        .mem_req(mem_req),
        .mem_addr(mem_addr),
        .mem_burst_len(mem_burst_len),
        .mem_rdata(mem_rdata),
        .mem_rvalid(mem_rvalid),
        .mem_rlast(mem_rlast),
        .mem_rready(mem_rready),
        .wb_req(), .wb_addr(), .wb_burst_len(), .wb_data_valid(), .wb_data(), .wb_ready(1'b0)
    );

    // Simple memory model: when mem_req asserted, stream mem_rdata for mem_burst_len cycles.
    reg [15:0] burst_remain;
    reg mem_busy;
    assign mem_rready = 1'b1;

    always @(posedge clk) begin
        if (!rst_n) begin
            mem_rvalid <= 0;
            mem_rdata <= 0;
            mem_rlast <= 0;
            mem_busy <= 0;
            burst_remain <= 0;
        end else begin
            if (mem_req && !mem_busy) begin
                // start streaming
                mem_busy <= 1;
                burst_remain <= mem_burst_len;
                mem_rvalid <= 0; // will assert next cycle
            end

            if (mem_busy) begin
                if (burst_remain > 0) begin
                    mem_rvalid <= 1;
                    mem_rdata <= {24'h00, burst_remain[7:0]}; // deterministic pattern
                    mem_rlast <= (burst_remain == 1);
                    burst_remain <= burst_remain - 1;
                end else begin
                    mem_rvalid <= 0;
                    mem_rlast <= 0;
                    mem_busy <= 0;
                end
            end
        end
    end

    // test sequence
    initial begin
        req_valid = 0;
        req_x = 0; req_y = 0; req_mip = 0;
        #40;

        // Request pixel at (10, 6) -> will cause miss and fetch tile (tile coords = 1,0 for 8x8)
        req_x = 10; req_y = 6; req_mip = 0; req_valid = 1;
        #10; req_valid = 0;
        // wait for response
        wait (pixel_valid == 1);
        $display("Got pixel (10,6) mip0 data = %h at time %t", pixel_out, $time);

        #20;
        // Request another pixel in same tile (hit)
        req_x = 12; req_y = 5; req_mip = 0; req_valid = 1;
        #10; req_valid = 0;
        wait (pixel_valid == 1);
        $display("Got pixel (12,5) mip0 data = %h at time %t (should be hit)", pixel_out, $time);

        #50;
        // Request pixel in different tile and different mip -> miss + fetch
        req_x = 300; req_y = 200; req_mip = 1; req_valid = 1;
        #10; req_valid = 0;
        wait (pixel_valid == 1);
        $display("Got pixel (300,200) mip1 data = %h at time %t", pixel_out, $time);

        #100;
        $stop;
    end

endmodule

