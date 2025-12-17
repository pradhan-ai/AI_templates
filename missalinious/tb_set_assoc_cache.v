// file: tb_set_assoc_cache.v
`timescale 1ns/1ps
module tb_set_assoc_cache;
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;

    reg clk = 0;
    always #5 clk = ~clk; // 100MHz-ish for sim

    reg rst_n;
    reg [ADDR_WIDTH-1:0] cpu_addr;
    reg cpu_rd_en;
    reg cpu_wr_en;
    reg [DATA_WIDTH-1:0] cpu_wr_data;
    wire [DATA_WIDTH-1:0] cpu_rd_data;
    wire cpu_hit;
    wire cpu_stall;

    // memory wires
    wire [ADDR_WIDTH-1:0] mem_addr;
    wire mem_rd;
    wire mem_wr;
    wire [DATA_WIDTH-1:0] mem_wr_data;
    wire [DATA_WIDTH-1:0] mem_rdata;
    wire mem_ready;

    // instantiate cache
    set_assoc_cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .LINE_BYTES(16),
        .NUM_SETS(16),
        .NUM_WAYS(2)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr(cpu_addr),
        .cpu_rd_en(cpu_rd_en),
        .cpu_wr_en(cpu_wr_en),
        .cpu_wr_data(cpu_wr_data),
        .cpu_rd_data(cpu_rd_data),
        .cpu_hit(cpu_hit),
        .cpu_stall(cpu_stall),
        .mem_addr(mem_addr),
        .mem_rd(mem_rd),
        .mem_wr(mem_wr),
        .mem_wr_data(mem_wr_data),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

    // simple memory model: mem_ready is 1 immediately, mem_rdata returns address LSBs as data
    assign mem_ready = 1'b1;
    assign mem_rdata = mem_addr[31:0] ^ 32'hA5A5A5A5; // just return something deterministic

    initial begin
        rst_n = 0;
        cpu_rd_en = 0;
        cpu_wr_en = 0;
        cpu_addr = 0;
        cpu_wr_data = 32'h0;
        #20;
        rst_n = 1;
        #20;

        // Read from address 0x1000 (miss -> fill)
        cpu_addr = 32'h00001000;
        cpu_rd_en = 1;
        #10;
        cpu_rd_en = 0;
        #50;

        // Read same address -> should be hit
        cpu_addr = 32'h00001000;
        cpu_rd_en = 1;
        #10;
        cpu_rd_en = 0;
        #20;

        // Write to another address -> miss then allocate
        cpu_addr = 32'h00002000;
        cpu_wr_data = 32'hDEADBEEF;
        cpu_wr_en = 1;
        #10;
        cpu_wr_en = 0;
        #50;

        // Read it back -> hit (if write-allocate worked)
        cpu_addr = 32'h00002000;
        cpu_rd_en = 1;
        #10;
        cpu_rd_en = 0;
        #50;

        $stop;
    end

endmodule

