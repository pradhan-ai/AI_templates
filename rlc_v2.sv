module run_length_encoder #(
    parameter INPUT_WIDTH = 8,          // Input data width
    parameter MAX_RUNS = 4,             // Maximum number of runs to encode
    parameter RUN_LENGTH_BITS = 3       // Bits to represent run length (up to 7)
)(
    input  logic [INPUT_WIDTH-1:0] data_in,
    output logic [MAX_RUNS-1:0][RUN_LENGTH_BITS-1:0] run_lengths,
    output logic [MAX_RUNS-1:0] run_values,
    output logic [$clog2(MAX_RUNS+1)-1:0] num_runs,
    output logic valid
);

    // Internal signals for run detection
    logic [INPUT_WIDTH-1:0] run_boundaries;
    logic [INPUT_WIDTH-1:0] run_starts;
    logic [MAX_RUNS-1:0][RUN_LENGTH_BITS-1:0] lengths;
    logic [MAX_RUNS-1:0] values;
    logic [$clog2(MAX_RUNS+1)-1:0] run_count;
    
    // Detect boundaries between different values
    always_comb begin
        run_boundaries[0] = 1'b1; // First bit always starts a run
        for (int i = 1; i < INPUT_WIDTH; i++) begin
            run_boundaries[i] = (data_in[i] != data_in[i-1]);
        end
    end
    
    // Generate run start positions
    always_comb begin
        run_starts = run_boundaries;
    end
    
    // Count total number of runs
    always_comb begin
        run_count = 0;
        for (int i = 0; i < INPUT_WIDTH; i++) begin
            if (run_boundaries[i])
                run_count = run_count + 1;
        end
    end
    
    // Generate run-length encoding
    always_comb begin
        // Initialize outputs
        for (int i = 0; i < MAX_RUNS; i++) begin
            lengths[i] = '0;
            values[i] = '0;
        end
        
        // Process runs
        int run_idx = 0;
        int current_length = 0;
        logic current_value = data_in[0];
        
        for (int i = 0; i < INPUT_WIDTH; i++) begin
            if (run_boundaries[i] && i > 0) begin
                // End of current run, start new one
                if (run_idx < MAX_RUNS) begin
                    lengths[run_idx] = current_length[RUN_LENGTH_BITS-1:0];
                    values[run_idx] = current_value;
                    run_idx = run_idx + 1;
                end
                current_length = 1;
                current_value = data_in[i];
            end else begin
                current_length = current_length + 1;
            end
        end
        
        // Handle the last run
        if (run_idx < MAX_RUNS) begin
            lengths[run_idx] = current_length[RUN_LENGTH_BITS-1:0];
            values[run_idx] = current_value;
        end
    end
    
    // Assign outputs
    assign run_lengths = lengths;
    assign run_values = values;
    assign num_runs = (run_count <= MAX_RUNS) ? run_count : MAX_RUNS;
    assign valid = (run_count <= MAX_RUNS);

endmodule
