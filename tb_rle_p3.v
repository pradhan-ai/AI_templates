module tb_run_length_encoder;
    
    // Parameters
    localparam INPUT_WIDTH = 8;
    localparam MAX_RUNS = 4;
    localparam RUN_LENGTH_BITS = 3;
    
    // Signals
    logic [INPUT_WIDTH-1:0] data_in;
    logic [MAX_RUNS-1:0][RUN_LENGTH_BITS-1:0] run_lengths;
    logic [MAX_RUNS-1:0] run_values;
    logic [$clog2(MAX_RUNS+1)-1:0] num_runs;
    logic valid;
    
    // Instantiate DUT
    run_length_encoder #(
        .INPUT_WIDTH(INPUT_WIDTH),
        .MAX_RUNS(MAX_RUNS),
        .RUN_LENGTH_BITS(RUN_LENGTH_BITS)
    ) dut (
        .data_in(data_in),
        .run_lengths(run_lengths),
        .run_values(run_values),
        .num_runs(num_runs),
        .valid(valid)
    );
    
    // Test stimulus
    initial begin
        $display("Testing Run-Length Encoder");
        $display("========================");
        
        // Test case 1: 11100010
        data_in = 8'b11100010;
        #1;
        $display("Input: %8b", data_in);
        $display("Runs: %0d, Valid: %0b", num_runs, valid);
        for (int i = 0; i < num_runs; i++) begin
            $display("  Run %0d: Value=%0b, Length=%0d", i, run_values[i], run_lengths[i]);
        end
        
        // Test case 2: 10101010
        data_in = 8'b10101010;
        #1;
        $display("\nInput: %8b", data_in);
        $display("Runs: %0d, Valid: %0b", num_runs, valid);
        for (int i = 0; i < num_runs && i < MAX_RUNS; i++) begin
            $display("  Run %0d: Value=%0b, Length=%0d", i, run_values[i], run_lengths[i]);
        end
        
        // Test case 3: 11111111
        data_in = 8'b11111111;
        #1;
        $display("\nInput: %8b", data_in);
        $display("Runs: %0d, Valid: %0b", num_runs, valid);
        for (int i = 0; i < num_runs; i++) begin
            $display("  Run %0d: Value=%0b, Length=%0d", i, run_values[i], run_lengths[i]);
        end
        
        $finish;
    end

endmodule
