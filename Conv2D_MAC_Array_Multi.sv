module conv2d_mac_array_multi #(
    parameter int DATA_W      = 8,
    parameter int COEF_W      = 8,
    parameter int WIN_SIZE    = 3,
    parameter int PIX_PER_CLK = 8,
    parameter int CIN         = 8,     // <<< NEW
    parameter int COUT        = 16,    // <<< NEW
    parameter int SUM_W       = 32
)(
    input  logic clk,
    input  logic rst,

    input  logic in_valid,

    // windows from tile engine
    input  logic signed [DATA_W-1:0]
           window [PIX_PER_CLK][CIN][WIN_SIZE][WIN_SIZE],

    // weights
    input  logic signed [COEF_W-1:0]
           kernel [COUT][CIN][WIN_SIZE][WIN_SIZE],

    output logic out_valid,
    output logic signed [SUM_W-1:0]
           result [PIX_PER_CLK][COUT]
);

    integer l,o,c,i,j;

    // ------------------------------------------------------------
    // Accumulator registers
    // ------------------------------------------------------------
    logic signed [SUM_W-1:0]
        acc [PIX_PER_CLK][COUT];

    // ------------------------------------------------------------
    // MAC compute
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            for(l=0;l<PIX_PER_CLK;l++)
                for(o=0;o<COUT;o++)
                    acc[l][o] <= 0;
        end
        else if (in_valid) begin

            for (l=0;l<PIX_PER_CLK;l++) begin
                for (o=0;o<COUT;o++) begin
                    acc[l][o] <= 0;

                    for (c=0;c<CIN;c++)
                        for (i=0;i<WIN_SIZE;i++)
                            for (j=0;j<WIN_SIZE;j++)
                                acc[l][o] <= acc[l][o] +
                                  window[l][c][i][j] *
                                  kernel[o][c][i][j];
                end
            end
        end
    end

    // ------------------------------------------------------------
    // outputs
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        out_valid <= in_valid;

        for(l=0;l<PIX_PER_CLK;l++)
            for(o=0;o<COUT;o++)
                result[l][o] <= acc[l][o];
    end

endmodule
