// pixel_cache.v
// Simple line-based Pixel Cache for display/framebuffer pipelines
//--------------------------------------------------------------

`timescale 1ns/1ps

module pixel_cache #(
    parameter PIXEL_WIDTH = 24,         // RGB888 default
    parameter IMAGE_WIDTH = 1920,       // pixels per line
    parameter CACHE_LINES = 4,          // number of cached scanlines
    parameter LINE_BITS   = $clog2(CACHE_LINES)
)(
    input  wire                       clk,
    input  wire                       rst_n,

    // ---- Pixel Fetch Request ----
    input  wire [15:0]                req_x,       // pixel X position
    input  wire [15:0]                req_y,       // pixel Y position
    input  wire                       req_valid,
    output reg                        req_ready,

    // ---- Pixel Output ----
    output reg  [PIXEL_WIDTH-1:0]     pixel_out,
    output reg                        pixel_valid,

    // ---- External Memory Interface ----
    output reg                        mem_req,
    output reg  [31:0]                mem_addr,    // address of start of line
    input  wire                       mem_ready,
    input  wire [PIXEL_WIDTH-1:0]     mem_pixel,   // one pixel per read
    input  wire                       mem_pixel_valid
);

    // -----------------------------------
    // Cache Structures
    // -----------------------------------
    // tag stores which Y-line is stored
    reg [15:0] line_tag [0:CACHE_LINES-1];
    reg        line_valid [0:CACHE_LINES-1];

    // pixel data memory: CACHE_LINES x IMAGE_WIDTH pixels
    reg [PIXEL_WIDTH-1:0] cache_mem [0:CACHE_LINES-1][0:IMAGE_WIDTH-1];

    integer i;

    // -----------------------------------
    // Hit Detection
    // -----------------------------------
    reg hit;
    reg [LINE_BITS-1:0] hit_index;

    always @(*) begin
        hit = 0;
        hit_index = 0;
        for (i = 0; i < CACHE_LINES; i = i + 1) begin
            if (line_valid[i] && line_tag[i] == req_y) begin
                hit = 1'b1;
                hit_index = i[LINE_BITS-1:0];
            end
        end
    end

    // -----------------------------------
    // FSM for Miss Handling & Line Fill
    // -----------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_HIT,
        S_MISS,
        S_MEM_FETCH,
        S_FILL_WAIT
    } state_t;

    state_t state, next_state;

    reg [LINE_BITS-1:0]   victim_line;     // line to overwrite
    reg [15:0]            fill_x;          // fill counter
    reg [15:0]            fill_y;          // line being filled

    // Victim = simple round-robin
    reg [LINE_BITS-1:0] rr_ptr;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) rr_ptr <= 0;
        else if (state == S_MISS) rr_ptr <= rr_ptr + 1;
    always @(*) victim_line = rr_ptr;

    // -----------------------------------
    // FSM Sequential
    // -----------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            pixel_valid <= 0;
            req_ready <= 1;
            mem_req <= 0;
        end else begin
            state <= next_state;
        end
    end

    // -----------------------------------
    // FSM Combinational
    // -----------------------------------
    always @(*) begin
        next_state = state;
        case (state)

            S_IDLE: begin
                pixel_valid = 0;
                req_ready = 1;

                if (req_valid) begin
                    if (hit) next_state = S_HIT;
                    else     next_state = S_MISS;
                end
            end

            S_HIT: begin
                next_state = S_IDLE;
            end

            S_MISS: begin
                // request memory line read
                next_state = S_MEM_FETCH;
            end

            S_MEM_FETCH: begin
                if (mem_ready)
                    next_state = S_FILL_WAIT;
            end

            S_FILL_WAIT: begin
                if (fill_x == IMAGE_WIDTH)
                    next_state = S_IDLE;
            end

        endcase
    end

    // -----------------------------------
    // Data Path Logic / Memory Fill
    // -----------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < CACHE_LINES; i = i + 1) begin
                line_valid[i] <= 0;
                line_tag[i]   <= 0;
            end
            fill_x <= 0;
        end else begin

            case (state)

                S_HIT: begin
                    pixel_out <= cache_mem[hit_index][req_x];
                    pixel_valid <= 1'b1;
                end

                S_MISS: begin
                    // Kick memory read
                    mem_req  <= 1;
                    mem_addr <= {req_y, 16'h0000}; // simple: base + y*line_size
                    fill_y   <= req_y;
                    fill_x   <= 0;
                end

                S_MEM_FETCH: begin
                    mem_req <= 0;
                end

                S_FILL_WAIT: begin
                    if (mem_pixel_valid) begin
                        cache_mem[victim_line][fill_x] <= mem_pixel;
                        fill_x <= fill_x + 1;

                        if (fill_x == IMAGE_WIDTH-1) begin
                            line_tag[victim_line]   <= fill_y;
                            line_valid[victim_line] <= 1;
                        end
                    end
                end
            endcase

        end
    end

endmodule

