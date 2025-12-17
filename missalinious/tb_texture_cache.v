// tb_texture_cache.sv
`timescale 1ns/1ps
module tb_texture_cache;

    // Parameters must match DUT or be compatible
    parameter int TILE_W = 8;
    parameter int TILE_H = 8;
    parameter int BYTES_PER_PIXEL = 4;
    parameter int PIXEL_WIDTH_BITS = BYTES_PER_PIXEL * 8;

    reg clk = 0;
    always #5 clk = ~clk; // 100MHz-ish

    reg rst_n = 0;
    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
    end

    // DUT signals
    reg [31:0] u, v;
    reg [$clog2(6)-1:0] mip;
    reg req_valid;
    wire req_ready;
    wire [PIXEL_WIDTH_BITS-1:0] texel_out;
    wire texel_valid;

    // memory interface signals
    wire mem_req;
    wire [31:0] mem_addr;
    wire [15:0] mem_len;
    reg [PIXEL_WIDTH_BITS-1:0] mem_rdata;
    reg mem_rvalid;
    reg mem_rlast;
    wire mem_rready;

    // Instantiate DUT
    texture_cache #(
        .ADDR_WIDTH(32),
        .BYTES_PER_PIXEL(BYTES_PER_PIXEL),
        .PIXEL_WIDTH_BITS(PIXEL_WIDTH_BITS),
        .TILE_W(TILE_W),
        .TILE_H(TILE_H),
        .NUM_SETS(16),
        .NUM_WAYS(4),
        .NUM_MIP_LEVELS(6),
        .TAG_X_BITS(10)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .u(u),
        .v(v),
        .mip(mip),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .texel_out(texel_out),
        .texel_valid(texel_valid),
        .mem_req(mem_req),
        .mem_addr(mem_addr),
        .mem_len(mem_len),
        .mem_rdata(mem_rdata),
        .mem_rvalid(mem_rvalid),
        .mem_rlast(mem_rlast),
        .mem_rready(mem_rready)
    );

    // Simple memory model: when mem_req asserted, stream mem_len beats of data.
    reg [15:0] burst_rem;
    reg mem_busy;
    assign mem_rready = 1'b1;

    always @(posedge clk) begin
        if (!rst_n) begin
            mem_rvalid <= 0;
            mem_rlast <= 0;
            mem_rdata <= '0;
            mem_busy <= 0;
            burst_rem <= 0;
        end else begin
            if (mem_req && !mem_busy) begin
                // start a burst next cycle
                mem_busy <= 1;
                burst_rem <= mem_len;
                mem_rvalid <= 0;
            end

            if (mem_busy) begin
                if (burst_rem > 0) begin
                    mem_rvalid <= 1;
                    // return deterministic data pattern so we can inspect
                    mem_rdata <= { 8'hAA, mem_addr[7:0], burst_rem[7:0] }; // pattern
                    mem_rlast <= (burst_rem == 1);
                    burst_rem <= burst_rem - 1;
                end else begin
                    mem_rvalid <= 0;
                    mem_rlast <= 0;
                    mem_busy <= 0;
                end
            end
        end
    end

    // test scenario
    initial begin
        // start with idle
        u = 0; v = 0; mip = 0; req_valid = 0;
        #40;

        // Request texel that causes a miss -> tile fetch
        u = 10; v = 6; mip = 0;
        req_valid = 1;
        #10; req_valid = 0;
        // wait response
        wait (texel_valid == 1);
        $display("[%0t] Got texel (10,6,mip0) = %h", $time, texel_out);

        #20;
        // Request another texel inside same tile -> hit (fast)
        u = 12; v = 5; mip = 0;
        req_valid = 1;
        #10; req_valid = 0;
        wait (texel_valid == 1);
        $display("[%0t] Got texel (12,5,mip0) = %h (should be hit)", $time, texel_out);

        #40;
        // Request texel in different tile and different mip -> miss + fetch
        u = 300; v = 200; mip = 1;
        req_valid = 1;
        #10; req_valid = 0;
        wait (texel_valid == 1);
        $display("[%0t] Got texel (300,200,mip1) = %h", $time, texel_out);

        #200;
        $display("Testbench finished.");
        $stop;
    end

endmodule

