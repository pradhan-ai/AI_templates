module rle_single_cycle_sv #(
    parameter int N         = 16,          // input width
    parameter int MAX_RUNS  = N           // worst case: 1010... => N runs
)(
    input  logic [N-1:0]                      data,
    output logic [$clog2(MAX_RUNS+1)-1:0]     num_runs,
    output logic [MAX_RUNS-1:0]               run_sym,
    output logic [$clog2(N+1)-1:0]            run_len [MAX_RUNS]
);

    // Mark start of each run
    logic [N-1:0] start_of_run;
    logic [$clog2(N+1)-1:0] run_id [N];

    // First bit is always a start
    assign start_of_run[0] = 1'b1;

    genvar i;
    generate
        for (i = 1; i < N; i++) begin : GEN_START
            assign start_of_run[i] = (data[i] != data[i-1]);
        end
    endgenerate

    // Prefix-sum style run index: run_id[i] = index of run containing bit i
    assign run_id[0] = '0;

    generate
        for (i = 1; i < N; i++) begin : GEN_RUN_ID
            assign run_id[i] = run_id[i-1] + start_of_run[i-1];
        end
    endgenerate

    // Number of runs
    assign num_runs = run_id[N-1] + start_of_run[N-1];

    // Accumulate run lengths and symbols in one combinational block
    int j;
    always_comb begin
        // Initialize
        for (j = 0; j < MAX_RUNS; j++) begin
            run_len[j] = '0;
            run_sym[j] = 1'b0;
        end

        // Build runs
        for (j = 0; j < N; j++) begin
            run_len[ run_id[j] ] = run_len[ run_id[j] ] + 1;
            run_sym[ run_id[j] ] = data[j];
        end
    end

endmodule
