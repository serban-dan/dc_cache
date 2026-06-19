`default_nettype none
`timescale 1ns/1ps

module cache_controller #(
    parameter BLOCK_SIZE = 256,
    parameter ADDRESS_WIDTH = 21,
    parameter INDEX_WIDTH = 8,
    parameter TAG_WIDTH = 10,
    parameter OFFSET_WIDTH = 3,
    parameter WORD_SIZE = 32
)(
    input  wire                                  clock,
    input  wire                                  rst_n,
    input  wire [ADDRESS_WIDTH - 1:0]            caddress,
    input  wire [WORD_SIZE - 1:0]                cdin,
    input  wire [BLOCK_SIZE - 1:0]               mdin,
    input  wire                                  rden,
    input  wire                                  wren,
    
    output wire                                  hit,
    output wire [WORD_SIZE - 1:0]                cdout,
    output reg  [BLOCK_SIZE - 1:0]               mdout,
    output reg  [TAG_WIDTH + INDEX_WIDTH - 1:0]  maddress,
    output reg                                   mrden,
    output reg                                   mwren
);

    // ==========================================
    // 1. ADDRESS DECODING
    // ==========================================
    localparam OFFSET_LSB = 0;
    localparam OFFSET_MSB = OFFSET_WIDTH - 1;
    localparam INDEX_LSB  = OFFSET_WIDTH;
    localparam INDEX_MSB  = OFFSET_WIDTH + INDEX_WIDTH - 1;
    localparam TAG_LSB    = OFFSET_WIDTH + INDEX_WIDTH;
    localparam TAG_MSB    = ADDRESS_WIDTH - 1;

    // FSM Latched Inputs
    reg [ADDRESS_WIDTH-1:0] req_addr;
    reg                     req_read;
    reg                     req_write;
    reg [WORD_SIZE-1:0]     req_wdata;

    localparam STATE_IDLE       = 3'd0;
    localparam STATE_READ_MISS  = 3'd1;
    localparam STATE_WRITE_MISS = 3'd2;
    localparam STATE_REPLACE    = 3'd3;
    localparam STATE_FETCH      = 3'd4;
    localparam STATE_FILL       = 3'd5;
    localparam STATE_WRITE_HIT  = 3'd6;

    reg [2:0] current_state, next_state;

    // Dynamically route the address based on the FSM state
    wire [ADDRESS_WIDTH-1:0] active_addr   = (current_state == STATE_IDLE) ? caddress : req_addr;
    wire [OFFSET_WIDTH-1:0]  active_offset = active_addr[OFFSET_MSB:OFFSET_LSB];
    wire [INDEX_WIDTH-1:0]   active_index  = active_addr[INDEX_MSB:INDEX_LSB];
    wire [TAG_WIDTH-1:0]     active_tag    = active_addr[TAG_MSB:TAG_LSB];

    // ==========================================
    // 2. INTERNAL WIRES
    // ==========================================
    wire hit_w0, hit_w1, hit_w2, hit_w3;
    wire valid_w0, valid_w1, valid_w2, valid_w3;
    wire dirty_w0, dirty_w1, dirty_w2, dirty_w3;
    
    wire [TAG_WIDTH-1:0]  tag_w0, tag_w1, tag_w2, tag_w3;
    wire [BLOCK_SIZE-1:0] data_w0, data_w1, data_w2, data_w3;
    
    reg we_w0, we_w1, we_w2, we_w3;
    reg dirty_write_val;
    reg [BLOCK_SIZE-1:0] write_data_val;

    // ==========================================
    // 3. INSTANTIATE THE 4 WAYS
    // ==========================================
    cache_way #(.N_SETS(256), .INDEX_WIDTH(8), .TAG_WIDTH(10), .BLOCK_SIZE(256)) way_0 (
        .clock(clock), .rst_n(rst_n), .index(active_index), .tag_in(active_tag),
        .data_in(write_data_val), .write_en(we_w0), .dirty_in(dirty_write_val),
        .hit(hit_w0), .data_out(data_w0), .tag_out(tag_w0), .dirty_out(dirty_w0), .valid_out(valid_w0)
    );

    cache_way #(.N_SETS(256), .INDEX_WIDTH(8), .TAG_WIDTH(10), .BLOCK_SIZE(256)) way_1 (
        .clock(clock), .rst_n(rst_n), .index(active_index), .tag_in(active_tag),
        .data_in(write_data_val), .write_en(we_w1), .dirty_in(dirty_write_val),
        .hit(hit_w1), .data_out(data_w1), .tag_out(tag_w1), .dirty_out(dirty_w1), .valid_out(valid_w1)
    );

    cache_way #(.N_SETS(256), .INDEX_WIDTH(8), .TAG_WIDTH(10), .BLOCK_SIZE(256)) way_2 (
        .clock(clock), .rst_n(rst_n), .index(active_index), .tag_in(active_tag),
        .data_in(write_data_val), .write_en(we_w2), .dirty_in(dirty_write_val),
        .hit(hit_w2), .data_out(data_w2), .tag_out(tag_w2), .dirty_out(dirty_w2), .valid_out(valid_w2)
    );

    cache_way #(.N_SETS(256), .INDEX_WIDTH(8), .TAG_WIDTH(10), .BLOCK_SIZE(256)) way_3 (
        .clock(clock), .rst_n(rst_n), .index(active_index), .tag_in(active_tag),
        .data_in(write_data_val), .write_en(we_w3), .dirty_in(dirty_write_val),
        .hit(hit_w3), .data_out(data_w3), .tag_out(tag_w3), .dirty_out(dirty_w3), .valid_out(valid_w3)
    );

    // ==========================================
    // 4. PARALLEL LOOKUP & MULTIPLEXING
    // ==========================================
    wire lookup_hit = hit_w0 | hit_w1 | hit_w2 | hit_w3;
    assign hit = lookup_hit;
   
    wire [BLOCK_SIZE-1:0] hit_block_data = 
        ({BLOCK_SIZE{hit_w0}} & data_w0) |
        ({BLOCK_SIZE{hit_w1}} & data_w1) |
        ({BLOCK_SIZE{hit_w2}} & data_w2) |
        ({BLOCK_SIZE{hit_w3}} & data_w3);
    
    //For active_offset = 0, we want bits [31:0]
    //Basically a mux
    assign cdout = hit_block_data[(active_offset * WORD_SIZE) +: WORD_SIZE];

    // Word Modification Logic for CPU Writes
    reg [255:0] modified_block;
    always @(*) begin
        // By default, the block is unchanged. Then, overwrite the specific word.
        modified_block = hit_block_data;
        case (active_offset)
            3'd0: modified_block[31:0]     = req_wdata;
            3'd1: modified_block[63:32]    = req_wdata;
            3'd2: modified_block[95:64]    = req_wdata;
            3'd3: modified_block[127:96]   = req_wdata;
            3'd4: modified_block[159:128]  = req_wdata;
            3'd5: modified_block[191:160]  = req_wdata;
            3'd6: modified_block[223:192]  = req_wdata;
            3'd7: modified_block[255:224]  = req_wdata;
            default: modified_block = hit_block_data; // Should not happen
        endcase
    end

    // ==========================================
    // 5. LRU COUNTERS (2 Bits per Way)
    // ==========================================
    localparam N_SETS = 256;
    reg [1:0] age_w0 [0:N_SETS-1];
    reg [1:0] age_w1 [0:N_SETS-1];
    reg [1:0] age_w2 [0:N_SETS-1];
    reg [1:0] age_w3 [0:N_SETS-1];

    wire [1:0] cur_age_w0 = age_w0[active_index];
    wire [1:0] cur_age_w1 = age_w1[active_index];
    wire [1:0] cur_age_w2 = age_w2[active_index];
    wire [1:0] cur_age_w3 = age_w3[active_index];

    // ==========================================
    // 6. VICTIM DECODING
    // ==========================================
    reg victim_is_w0, victim_is_w1, victim_is_w2, victim_is_w3;
    always @(*) begin
        // Default to no victim selected
        victim_is_w0 = 1'b0; victim_is_w1 = 1'b0;
        victim_is_w2 = 1'b0; victim_is_w3 = 1'b0;

        // Priority: First, find an invalid way to fill.
        if (!valid_w0) victim_is_w0 = 1'b1;
        else if (!valid_w1) victim_is_w1 = 1'b1;
        else if (!valid_w2) victim_is_w2 = 1'b1;
        else if (!valid_w3) victim_is_w3 = 1'b1;
        // If all ways are valid, find the LRU way (age == 3) to evict.
        else begin
            if (cur_age_w0 == 2'd3) victim_is_w0 = 1'b1;
            else if (cur_age_w1 == 2'd3) victim_is_w1 = 1'b1;
            else if (cur_age_w2 == 2'd3) victim_is_w2 = 1'b1;
            else if (cur_age_w3 == 2'd3) victim_is_w3 = 1'b1;
        end
    end


    // ==========================================
    // 7. COUNTER UPDATE LOGIC
    // ==========================================
    reg [1:0] next_age_w0, next_age_w1, next_age_w2, next_age_w3;
    reg [1:0] old_age;
    
    always @(*) begin
        next_age_w0 = cur_age_w0; next_age_w1 = cur_age_w1;
        next_age_w2 = cur_age_w2; next_age_w3 = cur_age_w3;

        if (hit_w0 || we_w0) begin
            old_age = cur_age_w0; 
            next_age_w0 = 2'd0;
            
            if (cur_age_w1 < old_age) next_age_w1 = cur_age_w1 + 1;
            if (cur_age_w2 < old_age) next_age_w2 = cur_age_w2 + 1;
            if (cur_age_w3 < old_age) next_age_w3 = cur_age_w3 + 1;
        end 
        else if (hit_w1 || we_w1) begin
            old_age = cur_age_w1;
            next_age_w1 = 2'd0;
            if (cur_age_w0 < old_age) next_age_w0 = cur_age_w0 + 1;
            if (cur_age_w2 < old_age) next_age_w2 = cur_age_w2 + 1;
            if (cur_age_w3 < old_age) next_age_w3 = cur_age_w3 + 1;
        end
        else if (hit_w2 || we_w2) begin
            old_age = cur_age_w2;
            next_age_w2 = 2'd0;
            if (cur_age_w0 < old_age) next_age_w0 = cur_age_w0 + 1;
            if (cur_age_w1 < old_age) next_age_w1 = cur_age_w1 + 1;
            if (cur_age_w3 < old_age) next_age_w3 = cur_age_w3 + 1;
        end
        else if (hit_w3 || we_w3) begin
            old_age = cur_age_w3;
            next_age_w3 = 2'd0;
            if (cur_age_w0 < old_age) next_age_w0 = cur_age_w0 + 1;
            if (cur_age_w1 < old_age) next_age_w1 = cur_age_w1 + 1;
            if (cur_age_w2 < old_age) next_age_w2 = cur_age_w2 + 1;
        end
    end
    // ==========================================
    // 8. FINITE STATE MACHINE (FSM)
    // ==========================================
    always @(*) begin
        next_state = current_state;
        mrden = 0; mwren = 0; maddress = 0; mdout = 0;
        we_w0 = 0; we_w1 = 0; we_w2 = 0; we_w3 = 0;
        dirty_write_val = 0; write_data_val = mdin; 

        case (current_state)
            STATE_IDLE: begin
                if (rden && lookup_hit) begin
                    next_state = STATE_IDLE;
                end else if (wren && lookup_hit) begin
                    next_state = STATE_WRITE_HIT;
                end else if (rden) begin
                    next_state = STATE_READ_MISS;
                end else if (wren) begin
                    next_state = STATE_WRITE_MISS;
                end
            end
            STATE_READ_MISS, STATE_WRITE_MISS: begin
                if ((victim_is_w0 && dirty_w0) || (victim_is_w1 && dirty_w1) ||
                    (victim_is_w2 && dirty_w2) || (victim_is_w3 && dirty_w3)) begin
                    next_state = STATE_REPLACE;
                end else begin
                    next_state = STATE_FETCH;
                end
            end
            STATE_REPLACE: begin
                mwren = 1;
                if (victim_is_w0) begin maddress = {tag_w0, active_index}; mdout = data_w0; end
                else if (victim_is_w1) begin maddress = {tag_w1, active_index}; mdout = data_w1; end
                else if (victim_is_w2) begin maddress = {tag_w2, active_index}; mdout = data_w2; end
                else begin maddress = {tag_w3, active_index}; mdout = data_w3; end
                next_state = STATE_FETCH;
            end
            STATE_FETCH: begin
                mrden = 1;
                maddress = {active_tag, active_index};
                next_state = STATE_FILL;
            end
            STATE_FILL: begin
                mrden = 1;
                maddress = {active_tag, active_index};
                write_data_val = mdin;
                dirty_write_val = 0;
                if (victim_is_w0) we_w0 = 1;
                else if (victim_is_w1) we_w1 = 1;
                else if (victim_is_w2) we_w2 = 1;
                else we_w3 = 1;

                if (req_read) next_state = STATE_IDLE; 
                else if (req_write) next_state = STATE_WRITE_HIT; 
                else next_state = STATE_IDLE;
            end
            STATE_WRITE_HIT: begin
                write_data_val = modified_block;
                dirty_write_val = 1;
                if (hit_w0) we_w0 = 1;
                else if (hit_w1) we_w1 = 1;
                else if (hit_w2) we_w2 = 1;
                else if (hit_w3) we_w3 = 1;
                next_state = STATE_IDLE;
            end
            default: next_state = STATE_IDLE;
        endcase
    end

    integer k;
    always @(posedge clock) begin
        if (!rst_n) begin
            current_state <= STATE_IDLE;
            for (k = 0; k < N_SETS; k = k + 1) begin
                age_w0[k] <= 2'd0;
                age_w1[k] <= 2'd1;
                age_w2[k] <= 2'd2;
                age_w3[k] <= 2'd3;
            end
        end else begin
            current_state <= next_state;
            
            // Latch requests on Miss or Write Hit
            if (current_state == STATE_IDLE && (rden || wren)) begin
                req_addr  <= caddress;
                req_read  <= rden;
                req_write <= wren;
                req_wdata <= cdin;
            end

            // Apply LRU Updates
            if ((current_state == STATE_IDLE && rden && lookup_hit) ||
                (current_state == STATE_IDLE && wren && lookup_hit) ||
                (current_state == STATE_FILL) ||
                (current_state == STATE_WRITE_HIT)) begin
                
                age_w0[active_index] <= next_age_w0;
                age_w1[active_index] <= next_age_w1;
                age_w2[active_index] <= next_age_w2;
                age_w3[active_index] <= next_age_w3;
            end
        end
    end

endmodule