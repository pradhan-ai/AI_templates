// texture_cache.sv
// Tile-based texture cache in SystemVerilog
//
// Features:
//  - TILE_W x TILE_H tile (custom)
//  - TAG = {mip, tile_x[TILE_X_BITS-1:0], tile_y[TILE_Y_BITS-1:0]}
//  - Set-associative: NUM_SETS x NUM_WAYS
//  - Per-set LRU via small epoch counters
//  - Burst memory read interface: mem_req, mem_addr, mem_len -> mem_rdata, mem_rvalid, mem_rlast
//
// Notes:
//  - This is a behavioral but synthesizable-friendly model.
//  - For large caches, replace large arrays with inferred BRAMs (pragma or vendor primitives).
//  - Address packing for mem_addr is illustrative; replace with your system's address calc.

`timescale 1ns/1ps
module texture_cache #(
    parameter int ADDR_WIDTH        = 32,
    parameter int BYTES_PER_PIXEL   = 4,               // e.g., 4 bytes = RGBA8
    parameter int PIXEL_WIDTH_BITS  = BYTES_PER_PIXEL * 8,
    parameter int TILE_W            = 8,
    parameter int TILE_H            = 8,
    parameter int NUM_SETS          = 64,
    parameter int NUM_WAYS          = 4,
    parameter int NUM_MIP_LEVELS    = 6,
    // tag XY bits: how many bits of tile_x/tile_y we keep in tag (truncate for size)
    parameter int TAG_X_BITS        = 12
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // Texture fetch request (simple synchronous request)
    input  logic [31:0]                 u,        // texel X (pixel coordinate)
    input  logic [31:0]                 v,        // texel Y
    input  logic [$clog2(NUM_MIP_LEVELS)-1:0] mip,
    input  logic                        req_valid,
    output logic                        req_ready,

    // Output texel (valid for one cycle when pixel_valid asserted)
    output logic [PIXEL_WIDTH_BITS-1:0] texel_out,
    output logic                        texel_valid,

    // Burst read memory master interface
    output logic                        mem_req,       // start burst
    output logic [ADDR_WIDTH-1:0]       mem_addr,      // base address for tile
    output logic [15:0]                 mem_len,       // number of pixels in burst (TILE_W*TILE_H)
    input  logic [PIXEL_WIDTH_BITS-1:0] mem_rdata,
    input  logic                        mem_rvalid,
    input  logic                        mem_rlast,
    // optional: mem_rready (consumer backpressure) - here always assume ready
    input  logic                        mem_rready
);

    // Derived params
    localparam int TILE_PIXELS = TILE_W * TILE_H;
    localparam int PIXEL_INDEX_BITS = $clog2(TILE_PIXELS);
    localparam int WAY_BITS = $clog2(NUM_WAYS);
    localparam int SET_BITS = $clog2(NUM_SETS);
    localparam int MIP_BITS = $clog2(NUM_MIP_LEVELS);
    localparam int TAG_BITS = MIP_BITS + TAG_X_BITS*2; // [mip|tx|ty]
    localparam int TILE_X_BITS = TAG_X_BITS;
    localparam int TILE_Y_BITS = TAG_X_BITS;

    // ------------------------------------------------------------------
    // Cache storage (arrays) — for synthesis replace with BRAMs if large
    // ------------------------------------------------------------------
    // tag_array[set][way] : stores {mip, tx[TILE_X_BITS-1:0], ty[TILE_Y_BITS-1:0]}
    logic [TAG_BITS-1:0] tag_array   [NUM_SETS-1:0][NUM_WAYS-1:0];
    logic               valid_array [NUM_SETS-1:0][NUM_WAYS-1:0];
    logic [PIXEL_WIDTH_BITS-1:0] data_array [NUM_SETS-1:0][NUM_WAYS-1:0][TILE_PIXELS-1:0];

    // LRU epoch per way per set (32-bit epoch counter)
    logic [31:0] way_epoch [NUM_SETS-1:0][NUM_WAYS-1:0];
    logic [31:0] epoch_counter;

    // ------------------------------------------------------------------
    // Helpers: tile coords, set index, pixel index within tile
    // ------------------------------------------------------------------
    logic [31:0] tile_x = u / TILE_W;
    logic [31:0] tile_y = v / TILE_H;
    logic [PIXEL_INDEX_BITS-1:0] pixel_index_in_tile = (v % TILE_H) * TILE_W + (u % TILE_W);
    logic [TILE_X_BITS-1:0] tag_tx = tile_x[TILE_X_BITS-1:0];
    logic [TILE_Y_BITS-1:0] tag_ty = tile_y[TILE_Y_BITS-1:0];
    logic [MIP_BITS-1:0] tag_mip = mip;

    // simple hash -> set index: XOR truncated parts then take low bits
    logic [SET_BITS+7:0] hash_word;
    logic [SET_BITS-1:0] set_index;
    assign hash_word = {tag_tx, tag_ty, tag_mip} ^ 8'hA5;
    assign set_index = hash_word[SET_BITS-1:0];

    // ------------------------------------------------------------------
    // Hit detection (combinational): scans ways in set
    // ------------------------------------------------------------------
    logic hit;
    logic [WAY_BITS-1:0] hit_way;
    int wi;
    always_comb begin
        hit = 1'b0;
        hit_way = '0;
        for (wi = 0; wi < NUM_WAYS; wi++) begin
            if (valid_array[set_index][wi]) begin
                if ( tag_array[set_index][wi] == { tag_mip, tag_tx, tag_ty } ) begin
                    hit = 1'b1;
                    hit_way = wi;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Victim selection (LRU): choose invalid way if available else min epoch
    // ------------------------------------------------------------------
    logic [WAY_BITS-1:0] victim_way;
    logic [31:0] min_epoch;
    always_comb begin
        min_epoch = 32'hFFFFFFFF;
        victim_way = '0;
        for (wi = 0; wi < NUM_WAYS; wi++) begin
            if (!valid_array[set_index][wi]) begin
                min_epoch = 32'h0;
                victim_way = wi;
            end else if (way_epoch[set_index][wi] < min_epoch) begin
                min_epoch = way_epoch[set_index][wi];
                victim_way = wi;
            end
        end
    end

    // ------------------------------------------------------------------
    // FSM for miss handling and fill
    // ------------------------------------------------------------------
    typedef enum logic [2:0] { IDLE, CHECK_TAG, ISSUE_FETCH, FILL, RESPOND } state_t;
    state_t state, next_state;

    // fetch bookkeeping
    logic [31:0] fetch_tile_x, fetch_tile_y;
    logic [MIP_BITS-1:0] fetch_mip;
    logic [SET_BITS-1:0] fetch_set_index;
    logic [WAY_BITS-1:0] fetch_way;
    logic [15:0] fetch_ctr; // counts pixels received (0..TILE_PIXELS-1)

    // request capture
    logic [31:0] u_r, v_r;
    logic [MIP_BITS-1:0] mip_r;
    logic req_valid_r;

    // initialization
    integer si, sj, sk;
    initial begin
        for (si = 0; si < NUM_SETS; si++) begin
            for (sj = 0; sj < NUM_WAYS; sj++) begin
                valid_array[si][sj] = 1'b0;
                tag_array[si][sj] = '0;
                way_epoch[si][sj] = 32'h0;
                for (sk = 0; sk < TILE_PIXELS; sk++) begin
                    data_array[si][sj][sk] = '0;
                end
            end
        end
        epoch_counter = 32'h1;
        state = IDLE;
    end

    // sequential FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            req_ready <= 1'b1;
            texel_valid <= 1'b0;
            mem_req <= 1'b0;
            mem_addr <= '0;
            mem_len <= '0;
            fetch_ctr <= 16'd0;
            u_r <= 0; v_r <= 0; mip_r <= 0; req_valid_r <= 1'b0;
            texel_out <= '0;
        end else begin
            // update epoch counter
            epoch_counter <= epoch_counter + 1;

            case (state)
                IDLE: begin
                    texel_valid <= 1'b0;
                    req_ready <= 1'b1;
                    mem_req <= 1'b0;
                    mem_len <= '0;
                    if (req_valid) begin
                        // capture
                        u_r <= u; v_r <= v; mip_r <= mip; req_valid_r <= 1'b1;
                        state <= CHECK_TAG;
                        req_ready <= 1'b0;
                    end
                end

                CHECK_TAG: begin
                    // Use combinational hit (computed from current u/v/mip)
                    if (hit) begin
                        // produce texel from data_array
                        texel_out <= data_array[set_index][hit_way][pixel_index_in_tile];
                        texel_valid <= 1'b1;
                        // update LRU
                        way_epoch[set_index][hit_way] <= epoch_counter;
                        state <= RESPOND;
                    end else begin
                        // miss -> select victim and issue fetch
                        fetch_tile_x <= tile_x;
                        fetch_tile_y <= tile_y;
                        fetch_mip <= tag_mip;
                        fetch_set_index <= set_index;
                        fetch_way <= victim_way;
                        fetch_ctr <= 16'd0;
                        // mark victim invalid until filled
                        valid_array[fetch_set_index][fetch_way] <= 1'b0;
                        state <= ISSUE_FETCH;
                    end
                end

                ISSUE_FETCH: begin
                    // start mem burst for full tile
                    mem_req <= 1'b1;
                    // *Important*: mem_addr must be calculated using your texture layout:
                    // Here we pack illustrative fields; replace with actual byte address calc.
                    mem_addr <= { fetch_mip, fetch_tile_y[11:0], fetch_tile_x[11:0], 2'b00 };
                    mem_len <= TILE_PIXELS[15:0];
                    // after asserting mem_req, wait for mem_rvalid stream in FILL state
                    state <= FILL;
                    mem_req <= 1'b0; // pulse request
                end

                FILL: begin
                    if (mem_rvalid) begin
                        // write incoming pixel into data_array
                        data_array[fetch_set_index][fetch_way][fetch_ctr] <= mem_rdata;
                        fetch_ctr <= fetch_ctr + 1;
                        // on last beat commit tag & valid
                        if (mem_rlast || (fetch_ctr == TILE_PIXELS-1)) begin
                            tag_array[fetch_set_index][fetch_way] <= { fetch_mip, fetch_tile_x[TILE_X_BITS-1:0], fetch_tile_y[TILE_Y_BITS-1:0] };
                            valid_array[fetch_set_index][fetch_way] <= 1'b1;
                            way_epoch[fetch_set_index][fetch_way] <= epoch_counter;
                            // respond to original request (serve texel)
                            texel_out <= data_array[fetch_set_index][fetch_way][pixel_index_in_tile];
                            texel_valid <= 1'b1;
                            state <= RESPOND;
                        end
                    end
                end

                RESPOND: begin
                    // hold texel_valid one cycle; then go idle
                    req_ready <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

