module tile_scheduler_fsm #(
    parameter int IMG_W  = 1920,
    parameter int IMG_H  = 1080,
    parameter int TILE_W = 32,
    parameter int TILE_H = 32
)(
    input  logic clk,
    input  logic rst,

    input  logic start,

    // DMA interface
    output logic dma_start,
    input  logic dma_done,

    // compute engine
    output logic compute_start,
    input  logic compute_done,

    // writeback
    output logic store_start,
    input  logic store_done,

    // tile coordinates
    output logic [$clog2(IMG_W/TILE_W)-1:0] tile_x,
    output logic [$clog2(IMG_H/TILE_H)-1:0] tile_y,

    // ping/pong select
    output logic buf_sel,   // 0=ping, 1=pong

    output logic frame_done
);

    // ------------------------------------------------------------
    // Derived params
    // ------------------------------------------------------------
    localparam int TX = IMG_W / TILE_W;
    localparam int TY = IMG_H / TILE_H;

    // ------------------------------------------------------------
    // FSM states
    // ------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_LOAD,
        S_COMPUTE,
        S_STORE,
        S_NEXT,
        S_DONE
    } state_t;

    state_t state, next;

    // ------------------------------------------------------------
    // FSM register
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            state <= S_IDLE;
        else
            state <= next;
    end

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always_comb begin
        next = state;

        case (state)
        S_IDLE:
            if (start) next = S_LOAD;

        S_LOAD:
            if (dma_done) next = S_COMPUTE;

        S_COMPUTE:
            if (compute_done) next = S_STORE;

        S_STORE:
            if (store_done) next = S_NEXT;

        S_NEXT:
            next = (tile_x == TX-1 && tile_y == TY-1) ? S_DONE : S_LOAD;

        S_DONE:
            next = S_IDLE;
        endcase
    end

    // ------------------------------------------------------------
    // Control outputs
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            tile_x      <= 0;
            tile_y      <= 0;
            buf_sel     <= 0;
            frame_done  <= 0;
            dma_start   <= 0;
            compute_start <= 0;
            store_start <= 0;
        end
        else begin
            dma_start      <= 0;
            compute_start  <= 0;
            store_start    <= 0;
            frame_done     <= 0;

            case (state)

            S_LOAD:
                dma_start <= 1;

            S_COMPUTE:
                compute_start <= 1;

            S_STORE:
                store_start <= 1;

            S_NEXT: begin
                // flip ping/pong
                buf_sel <= ~buf_sel;

                if (tile_x == TX-1) begin
                    tile_x <= 0;
                    tile_y <= tile_y + 1;
                end
                else
                    tile_x <= tile_x + 1;
            end

            S_DONE:
                frame_done <= 1;

            endcase
        end
    end

endmodule
