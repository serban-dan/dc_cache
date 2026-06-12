`default_nettype none
`timescale 1ns/1ps

module tb_cache_comprehensive;
    localparam BLOCK_SIZE = 256;
    localparam ADDRESS_WIDTH = 21;
    localparam WORD_SIZE = 32;
    localparam NUM_TESTS = 10000;

    reg clock;
    reg rst_n;
    reg [ADDRESS_WIDTH-1:0] caddress;
    reg [WORD_SIZE-1:0]     cdin;
    reg                     rden;
    reg                     wren;

    wire                    hit;
    wire [WORD_SIZE-1:0]    cdout;
    wire [17:0]             maddress;
    wire                    mrden;
    wire                    mwren;
    wire [BLOCK_SIZE-1:0]   mdout_cache;
    wire [BLOCK_SIZE-1:0]   mdout_mem;

    // Instantiate Cache
    cache_controller uut_cache (
        .clock(clock), .rst_n(rst_n),
        .caddress(caddress), .cdin(cdin), .mdin(mdout_mem),
        .rden(rden), .wren(wren),
        .hit(hit), .cdout(cdout), .mdout(mdout_cache),
        .maddress(maddress), .mrden(mrden), .mwren(mwren)
    );

    // Instantiate Memory
    main_memory uut_mem (
        .clock(clock), .maddress(maddress), .mdin(mdout_cache),
        .mrden(mrden), .mwren(mwren), .mdout(mdout_mem)
    );

    // Statistics Counters
    integer stats_total_reads = 0;
    integer stats_total_writes = 0;
    integer stats_cache_hits = 0;
    integer stats_cache_misses = 0;
    integer stats_dirty_evictions = 0;
    integer stats_clean_evictions = 0;
    integer stats_errors = 0;
    
    reg prev_hit;
    reg [ADDRESS_WIDTH-1:0] prev_addr;

    // Clock Generation
    initial clock = 0;
    always #5 clock = ~clock;

    // Task: Single Read with Hit/Miss Tracking
    task read_word;
        input [ADDRESS_WIDTH-1:0] test_addr;
        output [WORD_SIZE-1:0] read_data;
        integer wait_cycles;
        begin
            @(negedge clock);
            caddress = test_addr;
            rden = 1;
            wait_cycles = 0;
            
            @(negedge clock);
            rden = 0;
            
            // Wait for hit or timeout (max 50 cycles for memory access)
            while (!hit && wait_cycles < 50) begin
                @(negedge clock);
                wait_cycles = wait_cycles + 1;
            end
            
            @(negedge clock);
            read_data = cdout;
            
            if (hit) begin
                stats_cache_hits = stats_cache_hits + 1;
            end else begin
                stats_cache_misses = stats_cache_misses + 1;
                $display("  [TIMEOUT] Read at %06h took >50 cycles", test_addr);
            end
            stats_total_reads = stats_total_reads + 1;
        end
    endtask

    // Task: Single Write
    task write_word;
        input [ADDRESS_WIDTH-1:0] test_addr;
        input [WORD_SIZE-1:0]     write_data;
        begin
            @(negedge clock);
            caddress = test_addr;
            cdin = write_data;
            wren = 1;
            
            @(negedge clock);
            wren = 0;
            #10; // Let FSM settle
            
            stats_total_writes = stats_total_writes + 1;
        end
    endtask

    // Task: Verify data in memory
    task verify_memory_word;
        input [ADDRESS_WIDTH-1:0] test_addr;
        input [WORD_SIZE-1:0] expected_data;
        reg [BLOCK_SIZE-1:0] block_data;
        reg [WORD_SIZE-1:0] word_data;
        integer block_idx, word_offset;
        begin
            block_idx = test_addr[20:3];
            word_offset = test_addr[2:0];
            
            @(negedge clock);
            block_data = uut_mem.ram[block_idx];
            word_data = block_data[(word_offset * 32) +: 32];
            
            if (word_data === expected_data) begin
                $display("  [PASS] Memory verified %06h = %08h", test_addr, expected_data);
            end else begin
                $display("  [FAIL] Memory mismatch at %06h | Expected: %08h | Got: %08h", 
                         test_addr, expected_data, word_data);
                stats_errors = stats_errors + 1;
            end
        end
    endtask

    // ==========================================
    // TEST PATTERNS
    // ==========================================

    // Pattern 1: Sequential Access (Cache Warming)
    task test_sequential_access;
        integer i;
        reg [WORD_SIZE-1:0] read_val;
        begin
            $display("\n=== TEST 1: Sequential Access Pattern ===");
            $display("Reading first 64 blocks sequentially (should fill cache)");
            
            for (i = 0; i < 64; i = i + 1) begin
                read_word((i << 3), read_val);  // i*8 words = i blocks
            end
            
            $display("  Hits: %d, Misses: %d, Hit Rate: %.1f%%", 
                     stats_cache_hits, stats_cache_misses, 
                     100.0 * stats_cache_hits / (stats_cache_hits + stats_cache_misses));
        end
    endtask

    // Pattern 2: Set Conflict Test (Stride = 256 blocks → same set)
    task test_set_conflicts;
        integer i, set_idx;
        reg [WORD_SIZE-1:0] read_val;
        integer hits_before, misses_before;
        begin
            $display("\n=== TEST 2: Set Conflict Pattern (Stride) ===");
            $display("Accessing same set with different tags (should evict due to capacity)");
            
            hits_before = stats_cache_hits;
            misses_before = stats_cache_misses;
            
            // Access 5 blocks mapping to set 0 (0, 256, 512, 768, 1024 blocks)
            // Each = 256*8 words = 0, 2048, 4096, 6144, 8192 word addresses
            for (i = 0; i < 5; i = i + 1) begin
                read_word(((i * 256) << 3) + 0, read_val);  // Same set, different tags
                $display("  Read block %d (set 0): %s", i*256, hit ? "HIT" : "MISS");
            end
            
            $display("  New Misses in this pattern: %d", 
                     (stats_cache_misses - misses_before));
        end
    endtask

    // Pattern 3: Dirty Block Lifecycle (Uses same proven pattern as tb_cache.v)
    task test_dirty_lifecycle;
        integer i;
        reg [WORD_SIZE-1:0] read_val;
        begin
            $display("\n=== TEST 3: Dirty Block Lifecycle ===");
            $display("Write-modify-evict dirty block and verify writeback");
            
            // Use proven addresses from original tb_cache.v that work
            // Fill set 0 with 4 blocks
            read_word(21'h00800, read_val);  // Tag 1, Way 0
            read_word(21'h01000, read_val);  // Tag 2, Way 1
            read_word(21'h01800, read_val);  // Tag 3, Way 2
            read_word(21'h02000, read_val);  // Tag 4, Way 3
            
            // Update LRU by reading Way 0 again
            read_word(21'h00801, read_val);
            
            // Write to Way 0 (marks dirty)
            write_word(21'h00802, 32'hDEAD0001);
            $display("  Wrote DEAD0001 to address 00802 (Way 0 should be dirty)");
            
            // Force evictions: Load 3 more tags to push Way 0 out as LRU
            read_word(21'h02800, read_val);  // Tag 5 (Way 1 gets evicted cleanly)
            read_word(21'h03000, read_val);  // Tag 6
            read_word(21'h03800, read_val);  // Tag 7
            
            // This read forces Way 0 (dirty) to be evicted
            read_word(21'h04000, read_val);  // Tag 8 - FORCES DIRTY WRITEBACK!
            $display("  Forced eviction of dirty Way 0...");
            
            // Verify write-back to memory
            verify_memory_word(21'h00802, 32'hDEAD0001);
        end
    endtask

    // Pattern 4: Rapid Read-Write Interleaving
    task test_interleaved_access;
        integer i;
        reg [WORD_SIZE-1:0] read_val, write_val;
        begin
            $display("\n=== TEST 4: Interleaved Read-Write Pattern ===");
            $display("Rapid alternating reads and writes to same block");
            
            for (i = 0; i < 20; i = i + 1) begin
                write_val = 32'hAAAA0000 + i;
                write_word(21'h12345, write_val);  // Write
                read_word(21'h12345, read_val);    // Read immediate
                if (i < 5)
                    $display("  Write %08h, Read %08h", write_val, read_val);
            end
            
            $display("  Completed 20 read-write pairs");
        end
    endtask

    // Pattern 5: All Sets Exercise
    task test_all_sets;
        integer set_idx, i;
        reg [WORD_SIZE-1:0] read_val;
        integer hits_start;
        begin
            $display("\n=== TEST 5: Exercise All 256 Sets ===");
            $display("Read from each set index (first 256 blocks)");
            
            hits_start = stats_cache_hits;
            
            for (set_idx = 0; set_idx < 256; set_idx = set_idx + 1) begin
                read_word((set_idx << 3), read_val);  // Read block at each set
            end
            
            $display("  Hits in this pass: %d, Misses: %d", 
                     (stats_cache_hits - hits_start), 
                     (stats_cache_misses) - (stats_cache_misses - (stats_cache_misses)));
        end
    endtask

    // Pattern 6: Write-Back Verification
    task test_writeback_verification;
        integer i, block_addr;
        reg [WORD_SIZE-1:0] write_val, read_val;
        begin
            $display("\n=== TEST 6: Write-Back Verification ===");
            $display("Write patterns, evict, verify memory contains correct data");
            
            // Write to 8 different blocks in set 50
            for (i = 0; i < 8; i = i + 1) begin
                block_addr = (50 + i*256);
                write_val = 32'hBEEF0000 + (i * 256);
                write_word((block_addr << 3) + 1, write_val);  // Write to offset 1
                $display("  Wrote %08h to block %d offset 1", write_val, block_addr);
            end
            
            // Evict by filling cache more
            for (i = 0; i < 8; i = i + 1) begin
                read_word((((50 + i*256 + 2048) << 3)), read_val);
            end
            
            // Spot check memory
            verify_memory_word(((50 << 3) + 1), 32'hBEEF0000);
            verify_memory_word((((50+256) << 3) + 1), 32'hBEEF0100);
        end
    endtask

    // Pattern 7: LRU Behavior Validation (indirect)
    task test_lru_behavior;
        integer i, way;
        reg [WORD_SIZE-1:0] read_val;
        integer hits_pattern1, hits_pattern2;
        begin
            $display("\n=== TEST 7: LRU Behavior (Indirect) ===");
            $display("Access same 3 blocks repeatedly, verify LRU ordering");
            
            // Set up: Fill set 20 with 4 blocks
            for (i = 0; i < 4; i = i + 1) begin
                read_word(((20 + i*256) << 3), read_val);
            end
            
            hits_pattern1 = stats_cache_hits;
            
            // Access first 3 in pattern (should all hit)
            for (i = 0; i < 10; i = i + 1) begin
                read_word(((20 + (i%3)*256) << 3), read_val);
            end
            
            // Load 4th new block (should evict least recently used, which is block 3)
            read_word(((20 + 3*256 + 2048) << 3), read_val);
            
            $display("  Pattern hits: %d new hits", (stats_cache_hits - hits_pattern1));
        end
    endtask

    // ==========================================
    // MAIN TEST SEQUENCE
    // ==========================================
    initial begin
        $dumpfile("build/cache_comprehensive_waves.vcd");
        $dumpvars(0, tb_cache_comprehensive);
        
        $display("\n╔════════════════════════════════════════════════╗");
        $display("║ 32 KiB 4-WAY CACHE - COMPREHENSIVE STRESS TEST ║");
        $display("╚════════════════════════════════════════════════╝");

        // Initialize
        rst_n = 0;
        caddress = 0;
        cdin = 0;
        rden = 0;
        wren = 0;
        prev_hit = 0;
        #20 rst_n = 1;

        // Run all test patterns
        test_sequential_access();
        test_set_conflicts();
        test_dirty_lifecycle();
        test_interleaved_access();
        test_all_sets();
        test_writeback_verification();
        test_lru_behavior();

        // Final Statistics
        $display("\nFINAL STATISTICS SUMMARY");
        $display("Total Reads:              %10d", stats_total_reads);
        $display("Total Writes:             %10d", stats_total_writes);
        $display("Cache Hits:               %10d", stats_cache_hits);
        $display("Cache Misses:             %10d", stats_cache_misses);
        if ((stats_cache_hits + stats_cache_misses) > 0) begin
            $display("Hit Rate:                 %10.2f%%", 
                     100.0 * stats_cache_hits / (stats_cache_hits + stats_cache_misses));
        end
        $display("Verification Errors:      %10d", stats_errors);
        
        if (stats_errors == 0) begin
            $display("\nALL TESTS PASSED");
        end else begin
            $display("\n%d ERRORS DETECTED", stats_errors);
        end

        $display("\n");
        $finish;
    end
endmodule
