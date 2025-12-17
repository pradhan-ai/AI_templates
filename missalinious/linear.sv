// 2 linear.sv - dense linear layer (Matrix x Vector)

// linear.sv
`include "transformer_pkg.sv"
module linear #(
    parameter int IN_DIM  = 8,
    parameter int OUT_DIM = 8,
    parameter int DATA_W  = 16
)(
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           valid_in,
    input  logic signed [DATA_W-1:0]       in_vec [IN_DIM],
    output logic                           ready_in,

    // weight/bias config (simple write interface)
    input  logic                           cfg_we,
    input  logic [$clog2(IN_DIM*OUT_DIM + OUT_DIM)-1:0] cfg_addr,
    input  logic signed [DATA_W-1:0]       cfg_wdata,

    output logic                           valid_out,
    output logic signed [DATA_W-1:0]      out_vec [OUT_DIM]
);
    localparam int WCOUNT = IN_DIM*OUT_DIM;

    // weight mem and bias mem
    logic signed [DATA_W-1:0] W [0:WCOUNT-1];
    logic signed [DATA_W-1:0] B [0:OUT_DIM-1];

    // config write
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i=0;i<WCOUNT;i++) W[i] <= '0;
            for (int j=0;j<OUT_DIM;j++) B[j] <= '0;
        end else if (cfg_we) begin
            if (cfg_addr < WCOUNT) W[cfg_addr] <= cfg_wdata;
            else B[cfg_addr - WCOUNT] <= cfg_wdata;
        end
    end

    // simple combinational multiply-accumulate per output (unrolled loops synthesizable but heavy)
    // For area/speed tradeoffs, implement pipelined/iterative multiply-accumulate.
    always_comb begin
        for (int o=0; o<OUT_DIM; o++) begin
            // accumulator in wider bits: double width
            logic signed [2*DATA_W+7:0] acc;
            acc = B[o];
            for (int i=0; i<IN_DIM; i++) begin
                int widx = o*IN_DIM + i;
                acc = acc + $signed(W[widx]) * $signed(in_vec[i]);
            end
            // Saturate/truncate to DATA_W
            out_vec[o] = acc[DATA_W-1:0];
        end
    end

    assign ready_in = 1'b1;
    assign valid_out = valid_in;

endmodule

