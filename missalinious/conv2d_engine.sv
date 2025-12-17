// conv2d_engine.sv
// Parameterized 2D convolution engine (SystemVerilog)
// - Accepts KxK windows with IN_CH channels packed per pixel
// - Produces OUT_CH output channels
// - Weight/bias configuration interface
// - Handshake style: win_valid/win_ready -> out_valid/out_ready
`timescale 1ns/1ps

module conv2d_engine #(
    parameter int DATA_W    = 8,    // bits per channel (input / weight)
    parameter int ACC_W     = 32,   // accumulator width
    parameter int IN_CH     = 1,
    parameter int OUT_CH    = 1,
    parameter int K         = 3     // kernel size (KxK)
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // ---- Window input ----
    // window[r][c] is a packed pixel containing IN_CH channels (LSB channel0).
    input  logic [DATA_W*IN_CH-1:0]      window  [K-1:0][K-1:0],
    input  logic                          win_valid,
    output logic                          win_ready,

    // ---- Output ----
    output logic signed [ACC_W-1:0]       out_data   [OUT_CH-1:0],
    output logic                          out_valid,
    input  logic                          out_ready,

    // ---- Config / weight loading interface (simple) ----
    // cfg_addr: write address increments 0..(OUT_CH*IN_CH*K*K + OUT_CH -1)
    // Layout: weights for out_ch0: [in_ch0 k0 k0, in_ch0 k0 k1,...], then out_ch1..., then biases
    input  logic                          cfg_write,
    input  logic [$clog2(OUT_CH*IN_CH*K*K + OUT_CH + 1)-1:0] cfg_addr,
    input  logic signed [DATA_W-1:0]     cfg_wdata
);

    // Derived sizes
    localparam int WEIGHT_COUNT = OUT_CH * IN_CH * K * K;
    localparam int BIAS_OFFSET  = WEIGHT_COUNT; // bias start index

    // Weight and bias memories (synthesizable regs; for large nets move to BRAM)
    logic signed [DATA_W-1:0] weight_mem [WEIGHT_COUNT-1:0];
    logic signed [DATA_W-1:0] bias_mem   [OUT_CH-1:0];

    // Write config interface
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // optional initialization to zero
            for (int i = 0; i < WEIGHT_COUNT; i++) weight_mem[i] <= '0;
            for (int oc = 0; oc < OUT_CH; oc++) bias_mem[oc] <= '0;
        end else begin
            if (cfg_write) begin
                if (cfg_addr < WEIGHT_COUNT)
                    weight_mem[cfg_addr] <= cfg_wdata;
                else begin
                    int b_idx = cfg_addr - BIAS_OFFSET;
                    if (b_idx < OUT_CH) bias_mem[b_idx] <= cfg_wdata;
                end
            end
        end
    end

    // Simple finite-state machine to compute convolution per output channel
    typedef enum logic [1:0] { IDLE, START, MAC, RESPOND } state_t;
    state_t state, next_state;

    // indices
    int oc_idx; // output channel index
    int in_ch_idx;
    int kr, kc;
    int waddr_base;

    // accumulator register
    logic signed [ACC_W-1:0] acc;

    // Counters that step through kernel & in_ch
    int total_taps;   // IN_CH*K*K
    int tap_idx;      // 0 .. total_taps-1

    // hold window locally for stable reads across cycles
    logic signed [DATA_W-1:0] win_chan [K-1:0][K-1:0][IN_CH-1:0];

    // ready/valid signals
    assign win_ready = (state == IDLE);

    // Output registers
    logic signed [ACC_W-1:0] out_reg [OUT_CH-1:0];
    logic out_reg_valid;

    // pipeline: capture window when valid & engine idle
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            oc_idx <= 0;
            tap_idx <= 0;
            acc <= '0;
            out_reg_valid <= 1'b0;
            for (int r=0; r<K; r++)
                for (int c=0; c<K; c++)
                    for (int ch=0; ch<IN_CH; ch++)
                        win_chan[r][c][ch] <= '0;
            for (int o=0; o<OUT_CH; o++) out_reg[o] <= '0;
        end else begin
            case (state)
                IDLE: begin
                    out_reg_valid <= 1'b0;
                    if (win_valid) begin
                        // latch window channels
                        for (int r=0; r<K; r++) begin
                            for (int c=0; c<K; c++) begin
                                for (int ch=0; ch<IN_CH; ch++) begin
                                    // extract channel ch from packed window[r][c]
                                    win_chan[r][c][ch] <= window[r][c][DATA_W*ch +: DATA_W];
                                end
                            end
                        end
                        oc_idx <= 0;
                        state <= START;
                    end
                end

                START: begin
                    // initialize accumulator and counters for oc_idx
                    acc <= bias_mem[oc_idx];
                    total_taps = IN_CH * K * K;
                    tap_idx <= 0;
                    state <= MAC;
                end

                MAC: begin
                    // compute indices from tap_idx
                    in_ch_idx = tap_idx % IN_CH;
                    int tmp = tap_idx / IN_CH;
                    kr = tmp / K;
                    kc = tmp % K;

                    // find weight address for oc_idx, in_ch_idx, kr, kc
                    // layout: weights are ordered with outermost oc, then in_ch, then kr,kc
                    waddr_base = oc_idx * (IN_CH * K * K);
                    int waddr = waddr_base + (in_ch_idx * (K*K)) + (kr * K) + kc;

                    // multiply-accumulate (signed)
                    acc <= acc + $signed(win_chan[kr][kc][in_ch_idx]) * $signed(weight_mem[waddr]);

                    tap_idx <= tap_idx + 1;

                    if (tap_idx + 1 == total_taps) begin
                        // finished this output channel
                        out_reg[oc_idx] <= acc;
                        // prepare for next oc
                        if (oc_idx + 1 < OUT_CH) begin
                            oc_idx <= oc_idx + 1;
                            state <= START;
                        end else begin
                            // all output channels done -> respond
                            out_reg_valid <= 1'b1;
                            state <= RESPOND;
                        end
                    end
                end

                RESPOND: begin
                    // wait until downstream accepts
                    if (out_ready) begin
                        out_reg_valid <= 1'b0;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // assign outputs
    assign out_valid = out_reg_valid;
    always_comb begin
        for (int o=0; o<OUT_CH; o++) out_data[o] = out_reg[o];
    end

endmodule

