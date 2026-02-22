module conv2d_mac_array_vec #(
    parameter int DATA_W      = 8,     // pixel width
    parameter int COEF_W      = 8,     // weight width
    parameter int WIN_SIZE    = 3,
    parameter int PIX_PER_CLK = 8,
    parameter int SUM_W       = 32
)(
    input  logic clk,
    input  logic rst,

    input  logic in_valid,

    input  logic signed [DATA_W-1:0]
           window [PIX_PER_CLK][WIN_SIZE][WIN_SIZE],

    input  logic signed [COEF_W-1:0]
           kernel [WIN_SIZE][WIN_SIZE],

    output logic out_valid,
    output logic signed [SUM_W-1:0]
           result [PIX_PER_CLK]
);

    // ------------------------------------------------------------
    // Multiply stage
    // ------------------------------------------------------------
    logic signed [DATA_W+COEF_W-1:0]
        mult [PIX_PER_CLK][WIN_SIZE][WIN_SIZE];

    integer l,i,j;

    always_ff @(posedge clk) begin
        for (l=0;l<PIX_PER_CLK;l++)
            for (i=0;i<WIN_SIZE;i++)
                for (j=0;j<WIN_SIZE;j++)
                    mult[l][i][j] <=
                        window[l][i][j] * kernel[i][j];
    end

    // ------------------------------------------------------------
    // Adder tree stage
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        for (l=0;l<PIX_PER_CLK;l++) begin
            result[l] <= '0;

            for (i=0;i<WIN_SIZE;i++)
                for (j=0;j<WIN_SIZE;j++)
                    result[l] <= result[l] + mult[l][i][j];
        end
    end

    // ------------------------------------------------------------
    // valid pipeline
    // ------------------------------------------------------------
    logic v1;

    always_ff @(posedge clk) begin
        if (rst) begin
            v1 <= 0;
            out_valid <= 0;
        end
        else begin
            v1 <= in_valid;
            out_valid <= v1;
        end
    end

endmodule
