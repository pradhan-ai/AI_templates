module run_length_encoder_multibit #(
    parameter SYMBOL_WIDTH = 2,         // Width of each symbol
    parameter NUM_SYMBOLS = 4,          // Number of input symbols
    parameter MAX_RUNS = 4,             // Maximum runs to encode
    parameter RUN_LENGTH_BITS = 3       // Bits for run length
)(
    input  logic [NUM_SYMBOLS-1:0][SYMBOL_WIDTH-1:0] symbols_in,
    output logic [MAX_RUNS-1:0][RUN_LENGTH_BITS-1:0] run_lengths,
    output logic [MAX_RUNS-1:0][SYMBOL_WIDTH-1:0] run_symbols,
    output logic [$clog2(MAX_RUNS+1)-1:0] num_runs,
    output logic valid
);

    // Boundary detection between different symbols
    logic [NUM_SYMBOLS-1:0] boundaries;
    
    always_comb begin
        boundaries[0] = 1'b1; // First symbol always starts a run
        for (int i = 1; i < NUM_SYMBOLS; i++) begin
            boundaries[i] = (symbols_in[i] != symbols_in[i-1]);
        end
    end
    
    // Run-length encoding logic
    always_comb begin
        automatic int run_idx = 0;
        automatic int current_length = 0;
        automatic logic [SYMBOL_WIDTH-1:0] current_symbol = symbols_in[0];
        
        // Initialize outputs
        for (int i = 0; i < MAX_RUNS; i++) begin
            run_lengths[i] = '0;
            run_symbols[i] = '0;
        end
        
        // Process each symbol position
        for (int i = 0; i < NUM_SYMBOLS; i++) begin
            if (boundaries[i] && i > 0) begin
                // Store completed run
                if (run_idx < MAX_RUNS) begin
                    run_lengths[run_idx] = current_length[RUN_LENGTH_BITS-1:0];
                    run_symbols[run_idx] = current_symbol;
                    run_idx++;
                end
                // Start new run
                current_length = 1;
                current_symbol = symbols_in[i];
            end else begin
                current_length++;
            end
        end
        
        // Store final run
        if (run_idx < MAX_RUNS) begin
            run_lengths[run_idx] = current_length[RUN_LENGTH_BITS-1:0];
            run_symbols[run_idx] = current_symbol;
        end
    end
    
    // Count number of runs
    always_comb begin
        num_runs = 0;
        for (int i = 0; i < NUM_SYMBOLS; i++) begin
            if (boundaries[i])
                num_runs++;
        end
        // Clamp to maximum
        if (num_runs > MAX_RUNS)
            num_runs = MAX_RUNS;
    end
    
    assign valid = (num_runs <= MAX_RUNS);

endmodule
