// file: set_assoc_cache.v
`timescale 1ns/1ps

module set_assoc_cache #(
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32,
    parameter LINE_BYTES  = 16,  // bytes per cache line (must be power of two)
    parameter NUM_SETS    = 64,  // number of sets (power of two)
    parameter NUM_WAYS    = 4    // associativity (e.g., 1 = direct mapped)
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // CPU interface
    input  wire [ADDR_WIDTH-1:0]    cpu_addr,
    input  wire                     cpu_rd_en,
    input  wire                     cpu_wr_en,
    input  wire [DATA_WIDTH-1:0]    cpu_wr_data,
    output reg  [DATA_WIDTH-1:0]    cpu_rd_data,
    output reg                      cpu_hit,   // 1 -> hit (data available)
    output reg                      cpu_stall, // 1 -> cache busy / miss processing

    // Simple memory interface (assume word-addressable memory at DATA_WIDTH granularity)
    // This is a small handshake: memory returns mem_ready when rdata valid.
    output reg  [ADDR_WIDTH-1:0]    mem_addr,
    output reg                      mem_rd,
    output reg                      mem_wr,
    output reg  [DATA_WIDTH-1:0]    mem_wr_data,
    input  wire [DATA_WIDTH-1:0]    mem_rdata,
    input  wire                     mem_ready
);

    // Derived constants
    localparam OFFSET_BITS = $clog2(LINE_BYTES);       // byte offset inside line
    localparam INDEX_BITS  = $clog2(NUM_SETS);
    localparam TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam WORDS_PER_LINE = LINE_BYTES / (DATA_WIDTH/8);
    localparam WORD_INDEX_BITS = $clog2(WORDS_PER_LINE);

    // Break CPU address
    wire [OFFSET_BITS-1:0] offset = cpu_addr[OFFSET_BITS-1:0];
    wire [INDEX_BITS-1:0]  index  = cpu_addr[OFFSET_BITS +: INDEX_BITS];
    wire [TAG_BITS-1:0]    tag    = cpu_addr[OFFSET_BITS+INDEX_BITS +: TAG_BITS];
    wire [WORD_INDEX_BITS-1:0] word_idx = offset >> $clog2(DATA_WIDTH/8);

    // Tag RAM, data RAM, valid, dirty, LRU
    // tag_array[set][way] : stores TAG_BITS
    // data_array[set][way][word] : DATA_WIDTH words per line
    integer i,j,k;
    reg [TAG_BITS-1:0] tag_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg valid_array      [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg dirty_array      [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [DATA_WIDTH-1:0] data_array [0:NUM_SETS-1][0:NUM_WAYS-1][0:WORDS_PER_LINE-1];

    // Simple LRU: keep a counter order per set (store MRU index at position 0...).
    // A simple approach: store recency order as array of way indices, update on access.
    reg [$clog2(NUM_WAYS)-1:0] lru_order [0:NUM_SETS-1][0:NUM_WAYS-1];

    // Internal state machine for handling misses and writebacks
    typedef enum logic [2:0] {
        IDLE,
        CHECK,
        ALLOCATE_READ,   // read line from memory into a victim way
        WRITEBACK,       // write back dirty victim line
        FILL_WAIT,       // wait for mem_ready after read
        WRITEBACK_WAIT,  // wait for mem_ready after write
        RESPOND
    } state_t;
    state_t state, next_state;

    // selection signals
    reg [NUM_WAYS-1:0] way_match; // one-hot per way
    reg [($clog2(NUM_WAYS)-1):0] hit_way_idx;
    reg any_way_valid;
    reg any_way_hit;

    // victim selection (LRU = last in order)
    reg [$clog2(NUM_WAYS)-1:0] victim_way;

    // temp regs for read/write data buffering
    reg [DATA_WIDTH-1:0] read_word_buffer;
    reg [ADDR_WIDTH-1:0] pending_cpu_addr;
    reg                   pending_cpu_wr;
    reg [DATA_WIDTH-1:0]   pending_cpu_wr_data;
    reg                   pending_cpu_rd;

    // memory word address calculation: we read/write single words from memory for simplicity
    // align mem_addr to word boundary
    wire [ADDR_WIDTH-1:0] aligned_mem_addr = {cpu_addr[ADDR_WIDTH-1:WORD_INDEX_BITS + OFFSET_BITS - OFFSET_BITS], {(WORD_INDEX_BITS+OFFSET_BITS){1'b0}}};

    // Initialize arrays
    initial begin
        for (i=0;i<NUM_SETS;i=i+1) begin
            for (j=0;j<NUM_WAYS;j=j+1) begin
                valid_array[i][j] = 1'b0;
                dirty_array[i][j] = 1'b0;
                tag_array[i][j] = {TAG_BITS{1'b0}};
                for (k=0;k<WORDS_PER_LINE;k=k+1)
                    data_array[i][j][k] = {DATA_WIDTH{1'b0}};
                // initial LRU: 0,1,2,... way indices meaning 0 is MRU, last is LRU
                lru_order[i][j] = j[$clog2(NUM_WAYS)-1:0];
            end
        end
        state = IDLE;
    end

    // combinational: check for hits in current set
    always @(*) begin
        way_match = {NUM_WAYS{1'b0}};
        any_way_valid = 1'b0;
        any_way_hit = 1'b0;
        hit_way_idx = 0;
        for (j=0;j<NUM_WAYS;j=j+1) begin
            if (valid_array[index][j]) begin
                any_way_valid = 1'b1;
                if (tag_array[index][j] == tag) begin
                    way_match[j] = 1'b1;
                    any_way_hit = 1'b1;
                    hit_way_idx = j[$clog2(NUM_WAYS)-1:0];
                end
            end
        end
    end

    // pick victim = LRU (the way stored at last position of lru_order)
    always @(*) begin
        victim_way = lru_order[index][NUM_WAYS-1];
    end

    // Update LRU array: move accessed way to front (MRU = position 0), shift others right.
    task automatic update_lru_on_access(input [INDEX_BITS-1:0] set_idx, input [$clog2(NUM_WAYS)-1:0] accessed_way);
        integer p,q;
        reg [$clog2(NUM_WAYS)-1:0] temp;
        begin
            // find position of accessed_way in lru_order[set_idx]
            integer found_pos;
            found_pos = 0;
            for (p=0;p<NUM_WAYS;p=p+1) begin
                if (lru_order[set_idx][p] == accessed_way) begin
                    found_pos = p;
                    disable for; // not synthesizable 'disable for' in some flows — but using generic behavioral for clarity
                end
            end
            // shift left everything from 0..found_pos-1 unchanged; move elements 0..found_pos-1 to right by 1
            temp = lru_order[set_idx][found_pos];
            for (q=found_pos; q>0; q=q-1) begin
                lru_order[set_idx][q] = lru_order[set_idx][q-1];
            end
            lru_order[set_idx][0] = temp;
        end
    endtask

    // FSM sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cpu_stall <= 1'b0;
            cpu_hit <= 1'b0;
            mem_rd <= 1'b0;
            mem_wr <= 1'b0;
            mem_addr <= {ADDR_WIDTH{1'b0}};
            mem_wr_data <= {DATA_WIDTH{1'b0}};
            pending_cpu_addr <= {ADDR_WIDTH{1'b0}};
            pending_cpu_wr <= 1'b0;
            pending_cpu_wr_data <= {DATA_WIDTH{1'b0}};
            pending_cpu_rd <= 1'b0;
            cpu_rd_data <= {DATA_WIDTH{1'b0}};
        end else begin
            case (state)
                IDLE: begin
                    cpu_stall <= 1'b0;
                    cpu_hit <= 1'b0;
                    mem_rd <= 1'b0;
                    mem_wr <= 1'b0;
                    if (cpu_rd_en || cpu_wr_en) begin
                        // capture cpu request
                        pending_cpu_addr <= cpu_addr;
                        pending_cpu_wr <= cpu_wr_en;
                        pending_cpu_wr_data <= cpu_wr_data;
                        pending_cpu_rd <= cpu_rd_en;
                        state <= CHECK;
                    end
                end
                CHECK: begin
                    // check hit/miss (combinational earlier)
                    if (any_way_hit) begin
                        // Hit: respond immediately (synchronous read)
                        cpu_stall <= 1'b0;
                        cpu_hit <= 1'b1;
                        // fetch data from the matching way
                        cpu_rd_data <= data_array[index][hit_way_idx][word_idx];
                        // write if needed
                        if (pending_cpu_wr) begin
                            data_array[index][hit_way_idx][word_idx] <= pending_cpu_wr_data;
                            dirty_array[index][hit_way_idx] <= 1'b1;
                        end
                        // update LRU
                        update_lru_on_access(index, hit_way_idx);
                        state <= IDLE;
                    end else begin
                        // Miss: need to bring line (writeback if victim dirty)
                        cpu_stall <= 1'b1;
                        cpu_hit <= 1'b0;
                        // if victim dirty, write it back first
                        if (valid_array[index][victim_way] && dirty_array[index][victim_way]) begin
                            // initiate writeback of victim line word-by-word
                            // For simplicity we write back single word (could be full line).
                            // Set mem_wr and mem_addr accordingly. Here, pick word 0 address for demonstration.
                            mem_addr <= {tag_array[index][victim_way], index, {OFFSET_BITS{1'b0}}}; // base address of victim line
                            mem_wr <= 1'b1;
                            mem_wr_data <= data_array[index][victim_way][0];
                            state <= WRITEBACK_WAIT;
                        end else begin
                            // no writeback needed => issue read to memory to fill victim
                            mem_addr <= {pending_cpu_addr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS], index, {OFFSET_BITS{1'b0}}}; // aligned to line
                            mem_rd <= 1'b1;
                            state <= FILL_WAIT;
                        end
                    end
                end
                WRITEBACK_WAIT: begin
                    mem_wr <= 1'b0;
                    if (mem_ready) begin
                        // after writeback, clear dirty and mark free for fill
                        dirty_array[index][victim_way] <= 1'b0;
                        valid_array[index][victim_way] <= 1'b0; // we'll overwrite on fill
                        // now issue read for new line
                        mem_addr <= {pending_cpu_addr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS], index, {OFFSET_BITS{1'b0}}};
                        mem_rd <= 1'b1;
                        state <= FILL_WAIT;
                    end
                end
                FILL_WAIT: begin
                    mem_rd <= 1'b0;
                    if (mem_ready) begin
                        // assume mem_rdata contains word 0 of the line; write into data_array (only word 0 for simplicity)
                        data_array[index][victim_way][0] <= mem_rdata;
                        // mark tag, valid, clear dirty
                        tag_array[index][victim_way] <= pending_cpu_addr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS];
                        valid_array[index][victim_way] <= 1'b1;
                        dirty_array[index][victim_way] <= 1'b0;
                        // now perform CPU access: if write, write that word; if read, return it.
                        if (pending_cpu_wr) begin
                            data_array[index][victim_way][word_idx] <= pending_cpu_wr_data;
                            dirty_array[index][victim_way] <= 1'b1;
                        end
                        cpu_rd_data <= data_array[index][victim_way][word_idx];
                        // update LRU
                        update_lru_on_access(index, victim_way);
                        cpu_stall <= 1'b0;
                        cpu_hit <= 1'b1; // after fill, we can respond
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule

