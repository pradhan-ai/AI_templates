module rle_single_cycle #(
    parameter N = 16,          // input width
    parameter MAX_RUNS = N     // worst case: 1010... => N runs
)(
    input  wire [N-1:0]                 data,
    output wire [MAX_RUNS-1:0]          run_sym,   // bit value of each run
    output wire [$clog2(N+1)-1:0]       run_len [MAX_RUNS-1:0],
    output wire [$clog2(MAX_RUNS+1)-1:0]num_runs
);

    // Internal wires
    wire [N-1:0] start_of_run;       // 1 where a new run starts
    wire [$clog2(N+1)-1:0] run_id [N-1:0];

    genvar i;

    // A run starts at bit 0, or when data[i] != data[i-1]
    assign start_of_run[0] = 1'b1;
    generate
        for (i = 1; i < N; i = i + 1) begin : GEN_START
            assign start_of_run[i] = (data[i] != data[i-1]);
        end
    endgenerate

    // Prefix-sum of start_of_run to assign run indices (combinational)
    // run_id[i] = number of runs that started up to and including i - 1
    // Implement as a simple linear adder chain (synthesizer will unroll)
    assign run_id[0] = {($clog2(N+1)){1'b0}}; // first run has ID 0

    generate
        for (i = 1; i < N; i = i + 1) begin : GEN_RUN_ID
            assign run_id[i] = run_id[i-1] + start_of_run[i-1];
        end
    endgenerate

    // Number of runs = last run_id + possible new run at last bit
    assign num_runs = run_id[N-1] + start_of_run[N-1];

    // Accumulate run lengths: for each bit, increment len[run_id[i]]
    // Use a combinational always block with temporary registers
    integer j;
    reg [$clog2(N+1)-1:0] len_reg [MAX_RUNS-1:0];
    reg [MAX_RUNS-1:0]    sym_reg;

    always @* begin
        // init lengths to 0
        for (j = 0; j < MAX_RUNS; j = j + 1) begin
            len_reg[j] = '0;
            sym_reg[j] = 1'b0;
        end

        // scan input bits and build runs
        for (j = 0; j < N; j = j + 1) begin
            len_reg[ run_id[j] ] = len_reg[ run_id[j] ] + 1'b1;
            sym_reg[ run_id[j] ] = data[j];
        end
    end

    // Drive outputs
    generate
        for (i = 0; i < MAX_RUNS; i = i + 1) begin : GEN_OUT
            assign run_len[i] = len_reg[i];
            assign run_sym[i] = sym_reg[i];
        end
    endgenerate

endmodule
