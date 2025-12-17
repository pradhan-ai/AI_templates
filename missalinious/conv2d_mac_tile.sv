//-------------------------------------------------------------
// Fully-Pipelined 2D Convolution – Tiled MAC Array
// Computes TILE_OUT_CH channels in parallel
// TILE_IN_CH multiplies per kernel position (KxK)
// Throughput: 1 window → 1 result per cycle (after pipeline fill)
//-------------------------------------------------------------
module conv2d_mac_tile #(
    parameter int DATA_W      = 8,
    parameter int ACC_W       = 32,
    parameter int IN_CH       = 16,
    parameter int OUT_CH      = 16,
    parameter int K           = 3,

    // Tiling
    parameter int TILE_IN_CH  = 4,
    parameter int TILE_OUT_CH = 4
)(
    input  logic clk,
    input  logic rst,

    // Input window (KxK pixels, each pixel = IN_CH channels)
    // window[r][c][channel]
    input  logic [DATA_W-1:0] window [K][K][IN_CH],

    input  logic win_valid,

    // Output TILE_OUT_CH channels (one output pixel)
    output logic signed [ACC_W-1:0] out_pix [TILE_OUT_CH],
    output logic out_valid,

    // Weight load
    input  logic cfg_write,
    input  logic [$clog2(OUT_CH*IN_CH*K*K)-1:0] cfg_addr,
    input  logic signed [DATA_W-1:0] cfg_wdata
);

    //---------------------------------------------------------
    // Weight Memory: OUT_CH × IN_CH × K × K
    //---------------------------------------------------------
    logic signed [DATA_W-1:0] W [OUT_CH][IN_CH][K][K];

    always_ff @(posedge clk) begin
        if (cfg_write) begin
            int a = cfg_addr;
            int oc = a / (IN_CH*K*K);
            int rem1 = a % (IN_CH*K*K);
            int ic = rem1 / (K*K);
            int rem2 = rem1 % (K*K);
            int kr = rem2 / K;
            int kc = rem2 % K;

            W[oc][ic][kr][kc] <= cfg_wdata;
        end
    end

    //---------------------------------------------------------
    // MAC TILE
    // TILE_OUT_CH outputs × TILE_IN_CH inputs per cycle × K*K
    //---------------------------------------------------------
    logic signed [ACC_W-1:0] partial_sum   [TILE_OUT_CH];
    logic signed [ACC_W-1:0] next_sum      [TILE_OUT_CH];

    // Pipeline registers
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            for (int o=0; o<TILE_OUT_CH; o++)
                partial_sum[o] <= '0;
        else if (win_valid)
            for (int o=0; o<TILE_OUT_CH; o++)
                partial_sum[o] <= next_sum[o];
    end

    //---------------------------------------------------------
    // Parallel Multiply-Accumulate for the tile
    //---------------------------------------------------------
    always_comb begin
        for (int o=0; o<TILE_OUT_CH; o++)
            next_sum[o] = 0;

        for (int oc = 0; oc < TILE_OUT_CH; oc++) begin
            for (int ich = 0; ich < TILE_IN_CH; ich++) begin
                int in_ch_global = ich;
                int out_ch_global = oc;

                for (int kr = 0; kr < K; kr++) begin
                    for (int kc = 0; kc < K; kc++) begin
                        next_sum[oc] += 
                            $signed(window[kr][kc][in_ch_global])
                            * 
                            $signed(W[out_ch_global][in_ch_global][kr][kc]);
                    end
                end
            end
        end
    end

    //---------------------------------------------------------
    // Output register stage
    //---------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int o=0; o<TILE_OUT_CH; o++)
                out_pix[o] <= '0;
        end
        else if (win_valid) begin
            for (int o=0; o<TILE_OUT_CH; o++)
                out_pix[o] <= next_sum[o];
        end
    end

    //---------------------------------------------------------
    // Output valid generation
    //---------------------------------------------------------
    logic v_reg;
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            v_reg <= 0;
        else
            v_reg <= win_valid;
    end

    assign out_valid = v_reg;

endmodule

