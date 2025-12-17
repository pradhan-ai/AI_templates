// pe.sv
// Single processing element for systolic array GEMM
`timescale 1ns/1ps
module pe #(
    parameter int DATA_W = 16,
    parameter int ACC_W  = 48
)(
    input  logic                     clk,
    input  logic                     rst,

    // Inputs arriving from left (a) and top (b)
    input  logic signed [DATA_W-1:0] a_in,
    input  logic signed [DATA_W-1:0] b_in,
    input  logic                     a_valid,
    input  logic                     b_valid,

    // Passthrough to right and down (registered)
    output logic signed [DATA_W-1:0] a_out,
    output logic signed [DATA_W-1:0] b_out,
    output logic                     a_out_valid,
    output logic                     b_out_valid,

    // Partial sum output (available after K cycles; accumulates internally)
    output logic signed [ACC_W-1:0]  psum_out,
    output logic                     psum_valid,

    // control: clear accumulator (start of tile) - synchronous
    input  logic                     start_tile
);

    // internal pipeline registers for a and b
    logic signed [DATA_W-1:0] a_reg;
    logic signed [DATA_W-1:0] b_reg;
    logic a_reg_v, b_reg_v;

    // accumulator
    logic signed [ACC_W-1:0] acc;

    // multiply result (wider)
    logic signed [2*DATA_W-1:0] mul;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            a_reg <= '0; b_reg <= '0;
            a_reg_v <= 1'b0; b_reg_v <= 1'b0;
            acc <= '0;
            a_out <= '0; b_out <= '0;
            a_out_valid <= 1'b0; b_out_valid <= 1'b0;
            psum_out <= '0; psum_valid <= 1'b0;
        end else begin
            // register inputs (systolic movement)
            a_reg <= a_in;
            b_reg <= b_in;
            a_reg_v <= a_valid;
            b_reg_v <= b_valid;

            // passthrough to neighbors (registered)
            a_out <= a_reg;
            b_out <= b_reg;
            a_out_valid <= a_reg_v;
            b_out_valid <= b_reg_v;

            // clear accumulator at start of tile
            if (start_tile) acc <= '0;
            else begin
                // multiply-accumulate only when both regs valid
                if (a_reg_v && b_reg_v) begin
                    mul = $signed(a_reg) * $signed(b_reg);
                    acc <= acc + $signed(mul);
                end
            end

            // Output partial sum when a_reg/b_reg both valid and some external condition indicates end of K stream.
            // We don't know K inside PE; psum_valid will be asserted externally when accumulation for this tile is done.
            // Provide psum_out always as current acc; external controller will sample when psum_valid asserted.
            psum_out <= acc;
            psum_valid <= 1'b0; // default 0; controller toggles capture signal via start_tile end logic
        end
    end

endmodule

