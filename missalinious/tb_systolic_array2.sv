// tb_systolic_array.sv
`timescale 1ns/1ps
module tb_systolic_array;
    parameter int DATA_W = 16;
    parameter int ACC_W  = 48;
    parameter int PEX = 2; // small array for TB demo
    parameter int PEY = 2;

    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;

    initial begin
        rst = 1;
        #20;
        rst = 0;
    end

    // instantiate systolic array with bindable done (we will connect done inside TB via hierarchical override)
    logic signed [DATA_W-1:0] A_in;
    logic A_in_valid;
    logic signed [DATA_W-1:0] B_in;
    logic B_in_valid;
    logic start;
    logic done; // TB will derive done
    logic signed [ACC_W-1:0] C_tile [PEX-1:0][PEY-1:0];

    // Simple wrapper module instantiation (we will talk to internal PEs via hierarchical paths in TB)
    systolic_array #(.DATA_W(DATA_W), .ACC_W(ACC_W), .PEX(PEX), .PEY(PEY)) dut (
        .clk(clk), .rst(rst),
        .A_in(A_in), .A_in_valid(A_in_valid),
        .B_in(B_in), .B_in_valid(B_in),
        .start(start), .K_len(3), .done() , .C_tile() // We will not use these direct ports; use hierarchical refs
    );

    // For simplicity we will access DUT internal signals to sample C_tile values and to toggle done.
    // This style is okay for a TB. For synthesis/higher abstraction, propose a proper interface.
    // Wait for reset release
    initial begin
        @(negedge rst);
        #1;
        // set up small matrices: A (M x K), B (K x N) where M=PEX, N=PEY, K=3
        int M = PEX;
        int N = PEY;
        int K = 3;

        // define small matrices
        int A [M-1:0][K-1:0];
        int B [K-1:0][N-1:0];
        int goldC [M-1:0][N-1:0];

        // populate A and B with small numbers
        for (int i=0;i<M;i++) for (int k=0;k<K;k++) A[i][k] = i*10 + k + 1;
        for (int k=0;k<K;k++) for (int j=0;j<N;j++) B[k][j] = k*10 + j + 2;

        // compute golden C = A * B (small int arithmetic)
        for (int i=0;i<M;i++) for (int j=0;j<N;j++) begin
            int sum = 0;
            for (int k=0;k<K;k++) sum += A[i][k] * B[k][j];
            goldC[i][j] = sum;
        end

        // Clear DUT internal buses (they were initialized on reset)
        A_in_valid = 0; B_in_valid = 0;
        start = 1'b0;

        // Scheduler for classic 2D systolic array feeding:
        // The schedule runs for T = K + max(M,N) - 1 + extra drain cycles.
        int T = K + max(M,N) + 2;
        // We'll drive boundary inputs (A to left edges for each row; B to top edges for each col).
        // For the small array we can broadcast A values to the entire left column and B values to top row at scheduled times.

        // Create arrays of input sequences for each cycle
        int cycA [0:T-1][0:M-1];
        int cycA_v [0:T-1][0:M-1];
        int cycB [0:T-1][0:N-1];
        int cycB_v [0:T-1][0:N-1];
        // Initialize zeros
        for (int t=0;t<T;t++) begin
            for (int i=0;i<M;i++) begin cycA_v[t][i] = 0; cycA[t][i] = 0; end
            for (int j=0;j<N;j++) begin cycB_v[t][j] = 0; cycB[t][j] = 0; end
        end

        // Build schedule:
        // At time t = 0..(K-1): inject A[:, t] into left edges at times t + row_index
        // and B[t, :] into top edges at times t + col_index
        for (int k=0;k<K;k++) begin
            for (int i=0;i<M;i++) begin
                int t = k + i;
                cycA_v[t][i] = 1;
                cycA[t][i] = A[i][k];
            end
            for (int j=0;j<N;j++) begin
                int t = k + j;
                cycB_v[t][j] = 1;
                cycB[t][j] = B[k][j];
            end
        end

        // run cycles and drive DUT boundary inputs accordingly
        // Note: our systolic_array module exposes only single A_in and B_in. For simplicity in TB,
        // we will drive A_in with the left-most row value for row 0 each cycle and then use hierarchical
        // writes to place other rows into the left boundary buses of the DUT (directly writing internal signals).
        // This is a TB convenience to avoid changing top-level interface.

        // run cycles
        for (int t=0; t<T; t++) begin
            // drive left boundary a_bus[r][0] for each row
            for (int i=0;i<M;i++) begin
                // hierarchical write into DUT's internal bus a_bus[i][0]
                // cast to signed data width
                int val = cycA[t][i];
                // hierarchical path:
                dut.a_bus[i][0] <= val;
                dut.a_bus_v[i][0] <= cycA_v[t][i];
            end

            // drive top boundary b_bus[0][j] for each col
            for (int j=0;j<N;j++) begin
                int valb = cycB[t][j];
                dut.b_bus[0][j] <= valb;
                dut.b_bus_v[0][j] <= cycB_v[t][j];
            end

            @(posedge clk);
        end

        // After schedule, give a few drain cycles for values to propagate and accumulate
        int drain = M + N + 2;
        for (int d=0; d<drain; d++) begin
            @(posedge clk);
        end

        // Now sample internal PE accumulators for result (they were captured to psum_pe inside each PE)
        // In our PE implementation we exposed psum_out as internal; we can read them by hierarchical reference:
        $display("Checking results vs golden:");
        for (int i=0;i<M;i++) begin
            for (int j=0;j<N;j++) begin
                // PE at row i, col j inside dut.ROWS[i].COLS[j].pe_inst
                logic signed [ACC_W-1:0] got;
                got = dut.ROWS[i].COLS[j].pe_inst.acc; // access internal acc reg (TB only)
                $display("C[%0d][%0d] = %0d (gold %0d)", i, j, got, goldC[i][j]);
                if (got !== goldC[i][j]) begin
                    $error("Mismatch at (%0d,%0d): got %0d expected %0d", i, j, got, goldC[i][j]);
                end
            end
        end

        $display("Systolic array TB done.");
        #20 $finish;
    end
endmodule

