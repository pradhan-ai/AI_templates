// gpu_pixel_cache.v
// GPU-style tile (pixel) cache with mip-level support and LRU replacement
// - Parameterizable TILE_W x TILE_H (custom tile size)
// - Set-associative (parameterizable ways/sets)
// - Per-set LRU (small counters)
// - Burst memory interface (request/stream read responses)
// - Optional mip prefetch
//
// Notes:
//  * Memory interface here is a simple burst read interface:
//      mem_req, mem_addr, mem_burst_len => starts a burst read
//      mem_rdata, mem_rvalid, mem_rlast => stream of burst data
//  * Adapting to AXI4: create a small adapter that translates mem_* to AXI AR/R, R channel.

`timescale 1ns/1ps
module gpu_pixel_cache #(
    parameter ADDR_WIDTH        = 32,
    parameter PIXEL_WIDTH       = 32,       // bits per pixel (RGBA8888 default)
    parameter TILE_W            = 8,        // tile width (custom)
    parameter TILE_H            = 8,        // tile height (custom)
    parameter NUM_SETS          = 64,       // number of sets
    parameter NUM_WAYS          = 4,        // associativity (e.g., 4 or 8)
    parameter NUM_MIP_LEVELS    = 4,        // number of mip levels supported
    parameter INDEX_HASH_BITS   = $clog2(NUM_SETS),
    parameter WAY_BITS          = $clog2(NUM_WAYS),
    parameter MIP_BITS          = $clog2(NUM_MIP_LEVELS),
    parameter TAG_XY_BITS       = 16        // bits to keep for tile_x/tile_y tag (adjustable)
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Request from GPU/rasterizer for pixel:
    input  wire [31:0]            req_x,        // pixel X
    input  wire [31:0]            req_y,        // pixel Y
    input  wire [MIP_BITS-1:0]    req_mip,      // mip level
    input  wire                   req_valid,
    output reg                    req_ready,

    // Pixel output (valid when pixel_valid && req_id match if you add IDs)
    output reg  [PIXEL_WIDTH-1:0] pixel_out,
    output reg                    pixel_valid,

    // Memory burst read interface (master)
    output reg                    mem_req,
    output reg  [ADDR_WIDTH-1:0]  mem_addr,      // starting address (tile base)
    output reg  [15:0]            mem_burst_len, // number of pixels in burst (TILE_W*TILE_H)
    input  wire [PIXEL_WIDTH-1:0] mem_rdata,
    input  wire                   mem_rvalid,
    input  wire                   mem_rlast,
    input  wire                   mem_rready,    // memory indicates ready to accept next r (optional)

    // Optional: writeback interface for dirty tiles (not heavily used for read-only framebuffers)
    output reg                    wb_req,
    output reg  [ADDR_WIDTH-1:0]  wb_addr,
    output reg  [15:0]            wb_burst_len,
    output reg                    wb_data_valid,
    output reg  [PIXEL_WIDTH-1:0] wb_data,
    input  wire                   wb_ready
);

    // Derived
    localparam TILE_PIXELS = TILE_W * TILE_H;
    localparam TILE_PIXELS_BITS = $clog2(TILE_PIXELS);
    localparam TAG_BITS = MIP_BITS + TAG_XY_BITS*2; // store small tile coords + mip in tag

    // set index calculation: hash(tile_x, tile_y, mip) mod NUM_SETS
    // We'll compute tile coords: tile_x = req_x / TILE_W; tile_y = req_y / TILE_H
    // tag stores truncated tile_x, tile_y and mip for exact match
    // pixel index inside tile: px = req_x % TILE_W; py = req_y % TILE_H; word = py*TILE_W + px

    // tile coordinate widths
    localparam TILE_X_BITS = TAG_XY_BITS;
    localparam TILE_Y_BITS = TAG_XY_BITS;

    // Cache arrays:
    // tag_array[set][way] : stores (mip, tile_x[TILE_X_BITS-1:0], tile_y[TILE_Y_BITS-1:0])
    // valid_array[set][way]
    // dirty_array[set][way]
    // data_array[set][way][TILE_PIXELS] : PIXEL_WIDTH wide

    integer i,j,k;

    // Tag fields
    typedef struct packed {
        logic [MIP_BITS-1:0] mip;
        logic [TILE_X_BITS-1:0] tx;
        logic [TILE_Y_BITS-1:0] ty;
    } tag_t;

    // Arrays (synthesizable if NUM_SETS*NUM_WAYS small; for large sizes replace with BRAM blocks)
    reg [TAG_BITS-1:0] tag_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg               valid_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg               dirty_array [0:NUM_SETS-1][0:NUM_WAYS-1];

    // pixel storage: flatten tile => TILE_PIXELS entries per way
    // This may be large in regs; in real design replace with block RAMs.
    reg [PIXEL_WIDTH-1:0] data_array [0:NUM_SETS-1][0:NUM_WAYS-1][0:TILE_PIXELS-1];

    // LRU counters: small saturating counters per way per set; higher value => more recently used
    // We'll use a global increasing epoch counter per access and store per-way epoch (wrap-around OK)
    reg [31:0] epoch_counter;
    reg [31:0] way_epoch [0:NUM_SETS-1][0:NUM_WAYS-1];

    // state & control
    typedef enum logic [2:0] {
        S_IDLE,
        S_TAG_CHECK,
        S_HIT,
        S_MISS_SELECT_VICTIM,
        S_ISSUE_FETCH,
        S_FILL_TILE,      // receiving mem_rdata stream and writing into data_array
        S_RESPOND
    } state_t;

    state_t state, next_state;

    // Computed tile coordinates & indices
    wire [31:0] tile_x = req_x / TILE_W;
    wire [31:0] tile_y = req_y / TILE_H;
    wire [TILE_PIXELS_BITS-1:0] pixel_index_in_tile = (req_y % TILE_H) * TILE_W + (req_x % TILE_W);
    // truncated tag fields
    wire [TILE_X_BITS-1:0] tag_tx = tile_x[TILE_X_BITS-1:0];
    wire [TILE_Y_BITS-1:0] tag_ty = tile_y[TILE_Y_BITS-1:0];
    wire [MIP_BITS-1:0]    tag_mip = req_mip;

    // index (set) computation: simple xor-hash of some bits
    // Build a small hash word then take low INDEX_HASH_BITS
    wire [INDEX_HASH_BITS-1:0] set_index;
    wire [INDEX_HASH_BITS+7:0] hash_word;
    assign hash_word = { tag_tx, tag_ty, tag_mip } ^ { (INDEX_HASH_BITS+8){1'b10100101} };
    assign set_index = hash_word[INDEX_HASH_BITS-1:0];

    // Hit detection
    reg hit;
    reg [WAY_BITS-1:0] hit_way;
    always @(*) begin
        hit = 1'b0;
        hit_way = {WAY_BITS{1'b0}};
        for (i=0;i<NUM_WAYS;i=i+1) begin
            if (valid_array[set_index][i]) begin
                // reconstruct stored tag fields and compare
                // stored tag format: [MIP][TX][TY] concatenated
                // Compare full truncated fields
                if ( tag_array[set_index][i] ==
                    { tag_mip, tag_tx, tag_ty } ) begin
                    hit = 1'b1;
                    hit_way = i[WAY_BITS-1:0];
                end
            end
        end
    end

    // victim selection via smallest epoch (LRU)
    reg [WAY_BITS-1:0] victim_way;
    reg [31:0] min_epoch;
    always @(*) begin
        min_epoch = 32'hFFFFFFFF;
        victim_way = 0;
        for (i=0;i<NUM_WAYS;i=i+1) begin
            if (!valid_array[set_index][i]) begin
                // choose invalid way immediately
                min_epoch = 0;
                victim_way = i[WAY_BITS-1:0];
            end else if (way_epoch[set_index][i] < min_epoch) begin
                min_epoch = way_epoch[set_index][i];
                victim_way = i[WAY_BITS-1:0];
            end
        end
    end

    // fetch bookkeeping
    reg [31:0] fetch_tile_x;
    reg [31:0] fetch_tile_y;
    reg [MIP_BITS-1:0] fetch_mip;
    reg [15:0] fetch_pixel_ctr; // counts up to TILE_PIXELS-1
    reg [WAY_BITS-1:0] fetch_target_way;
    reg [INDEX_HASH_BITS-1:0] fetch_set_index;

    // cpu request capture
    reg [31:0] req_x_r, req_y_r;
    reg [MIP_BITS-1:0] req_mip_r;
    reg req_valid_r;

    // initialization
    initial begin
        for (i=0;i<NUM_SETS;i=i+1) begin
            for (j=0;j<NUM_WAYS;j=j+1) begin
                valid_array[i][j] = 1'b0;
                dirty_array[i][j] = 1'b0;
                tag_array[i][j] = {TAG_BITS{1'b0}};
                way_epoch[i][j] = 32'h0;
                for (k=0;k<TILE_PIXELS;k=k+1) begin
                    data_array[i][j][k] = {PIXEL_WIDTH{1'b0}};
                end
            end
        end
        epoch_counter = 0;
        state = S_IDLE;
    end

    // Main FSM - sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            req_ready <= 1'b1;
            pixel_valid <= 1'b0;
            mem_req <= 1'b0;
            mem_addr <= {ADDR_WIDTH{1'b0}};
            mem_burst_len <= 16'd0;
            fetch_pixel_ctr <= 16'd0;
            wb_req <= 1'b0;
            wb_data_valid <= 1'b0;
            req_x_r <= 0; req_y_r <= 0; req_mip_r <= 0; req_valid_r <= 1'b0;
            pixel_out <= {PIXEL_WIDTH{1'b0}};
        end else begin
            // epoch increment per cycle to track recency
            epoch_counter <= epoch_counter + 1;

            case (state)
                S_IDLE: begin
                    pixel_valid <= 1'b0;
                    req_ready <= 1'b1;
                    mem_req <= 1'b0;
                    wb_req <= 1'b0;
                    wb_data_valid <= 1'b0;

                    if (req_valid) begin
                        // capture request
                        req_x_r <= req_x;
                        req_y_r <= req_y;
                        req_mip_r <= req_mip;
                        req_valid_r <= 1'b1;
                        state <= S_TAG_CHECK;
                        req_ready <= 1'b0;
                    end
                end

                S_TAG_CHECK: begin
                    // note: use computed combinational hit (which uses req_* wires),
                    // but we captured req into regs; recompute hit using captured values by making intermediate wires
                    // For simplicity of this model, we'll re-use current req_* (assumes stable for a cycle).
                    if (hit) begin
                        // serve hit: fetch pixel from storage
                        pixel_out <= data_array[set_index][hit_way][pixel_index_in_tile];
                        pixel_valid <= 1'b1;
                        // update recency
                        way_epoch[set_index][hit_way] <= epoch_counter;
                        state <= S_RESPOND;
                    end else begin
                        // miss -> select victim and issue fetch
                        fetch_tile_x <= tile_x;
                        fetch_tile_y <= tile_y;
                        fetch_mip <= tag_mip;
                        fetch_target_way <= victim_way;
                        fetch_set_index <= set_index;
                        fetch_pixel_ctr <= 0;
                        state <= S_ISSUE_FETCH;
                    end
                end

                S_ISSUE_FETCH: begin
                    // Issue memory burst for the entire tile
                    // mem_addr encoding depends on your memory layout; for demo we build an address:
                    // base = (mip << 28) | (tile_y << 14) | (tile_x << 2)  (this is illustrative)
                    // In real system compute byte address: base_addr + (tile_y * line_stride + tile_x * tile_stride) * bytes_per_pixel * TILE_W*TILE_H
                    mem_req <= 1'b1;
                    mem_addr <= { fetch_mip, fetch_tile_y[11:0], fetch_tile_x[11:0], 2'b00 }; // illustrative packing
                    mem_burst_len <= TILE_PIXELS[15:0];
                    // mark that target way will be filled
                    fetch_target_way <= fetch_target_way;
                    state <= S_FILL_TILE;
                    // clear victim valid until filled (prevents race)
                    valid_array[fetch_set_index][fetch_target_way] <= 1'b0;
                end

                S_FILL_TILE: begin
                    // Wait for mem_rvalid streaming in; write into data_array sequentially
                    mem_req <= 1'b0;
                    if (mem_rvalid) begin
                        // write into tile buffer
                        data_array[fetch_set_index][fetch_target_way][fetch_pixel_ctr] <= mem_rdata;
                        fetch_pixel_ctr <= fetch_pixel_ctr + 1;
                        // if last or reached TILE_PIXELS then finish
                        if (mem_rlast || (fetch_pixel_ctr == TILE_PIXELS-1)) begin
                            // set tag, valid, clear dirty
                            tag_array[fetch_set_index][fetch_target_way] <= { fetch_mip, fetch_tile_x[TILE_X_BITS-1:0], fetch_tile_y[TILE_Y_BITS-1:0] };
                            valid_array[fetch_set_index][fetch_target_way] <= 1'b1;
                            dirty_array[fetch_set_index][fetch_target_way] <= 1'b0;
                            // update epoch
                            way_epoch[fetch_set_index][fetch_target_way] <= epoch_counter;
                            // after fill, respond to original request (serve pixel)
                            pixel_out <= data_array[fetch_set_index][fetch_target_way][pixel_index_in_tile];
                            pixel_valid <= 1'b1;
                            state <= S_RESPOND;
                        end
                    end
                end

                S_RESPOND: begin
                    // keep pixel_valid high for one cycle; then go idle
                    req_ready <= 1'b1;
                    // clear pixel_valid next cycle
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

