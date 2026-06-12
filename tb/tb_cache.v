`default_nettype none
`timescale 1ns/1ps

/* =============================================================================
 * Module: tb_cache
 * Description: Master demonstration testbench for the 32 KiB 4-Way 
 * Set-Associative Cache. 
 * Policy:      True LRU Replacement, Write-Back, Write-Allocate.
 * Features:    Self-checking data validation and automated memory state dumping.
 * ============================================================================= */

module tb_cache;

    // -------------------------------------------------------------------------
    // Architecture Parameters
    // -------------------------------------------------------------------------
    localparam BLOCK_SIZE    = 256;
    localparam ADDRESS_WIDTH = 21;
    localparam WORD_SIZE     = 32;

    // -------------------------------------------------------------------------
    // CPU Interface Signals
    // -------------------------------------------------------------------------
    reg                      clock;
    reg                      rst_n;
    reg  [ADDRESS_WIDTH-1:0] caddress;
    reg  [WORD_SIZE-1:0]     cdin;
    reg                      rden;
    reg                      wren;
    
    wire                     hit;
    wire [WORD_SIZE-1:0]     cdout;

    // -------------------------------------------------------------------------
    // Main Memory Interface Signals
    // -------------------------------------------------------------------------
    wire [17:0]              maddress;
    wire                     mrden;
    wire                     mwren;
    wire [BLOCK_SIZE-1:0]    mdout_cache;
    wire [BLOCK_SIZE-1:0]    mdout_mem;

    // -------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiations
    // -------------------------------------------------------------------------
    cache_controller uut_cache (
        .clock(clock), 
        .rst_n(rst_n),
        .caddress(caddress), 
        .cdin(cdin), 
        .mdin(mdout_mem),
        .rden(rden), 
        .wren(wren),
        .hit(hit), 
        .cdout(cdout), 
        .mdout(mdout_cache),
        .maddress(maddress), 
        .mrden(mrden), 
        .mwren(mwren)
    );

    main_memory uut_mem (
        .clock(clock), 
        .maddress(maddress), 
        .mdin(mdout_cache),
        .mrden(mrden), 
        .mwren(mwren), 
        .mdout(mdout_mem)
    );

    // -------------------------------------------------------------------------
    // Clock Generation (10ns Period / 100MHz)
    // -------------------------------------------------------------------------
    initial clock = 0;
    always #5 clock = ~clock;

    // =========================================================================
    // AUTOMATED VALIDATION TASKS
    // Note: CPU stimulus is driven on the negative edge of the clock to avoid 
    // delta-cycle race conditions with the FSM's positive-edge latches.
    // =========================================================================
    
    task read_and_check;
        input [ADDRESS_WIDTH-1:0] test_addr;
        reg   [BLOCK_SIZE-1:0]    expected_block;
        reg   [WORD_SIZE-1:0]     expected_word;
        begin
            @(negedge clock); 
            caddress = test_addr; 
            rden = 1; 
            
            @(negedge clock); 
            rden = 0; 
            wait(hit == 1); 
            
            @(negedge clock); // Wait for combinational data to settle on cdout

            // Direct memory peek for self-checking validation
            expected_block = uut_mem.ram[test_addr[20:3]]; 
            expected_word  = expected_block[(test_addr[2:0] * 32) +: 32];

            if (cdout === expected_word) begin
                $display("  [PASS] Read Addr %06h | Expected: %08h | Got: %08h", test_addr, expected_word, cdout);
            end else begin
                $display("  [FAIL] Read Addr %06h | Expected: %08h | Got: %08h <--- ERROR!", test_addr, expected_word, cdout);
            end
        end
    endtask

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
            #10; // Allow FSM to transition back to STATE_IDLE safely
            $display("  [INFO] Wrote %08h to Addr %06h", write_data, test_addr);
        end
    endtask

    task dump_memory_to_file;
        integer f;
        integer idx;
        begin
            $display("\n  [!] Exporting final RAM state to disk. Please wait...");
            f = $fopen("tb/mem_data_final.txt", "w");
            for (idx = 0; idx < 262144; idx = idx + 1) begin
                $fdisplay(f, "%b", uut_mem.ram[idx]);
            end
            $fclose(f);
            $display("  [SUCCESS] Memory dumped to tb/mem_data_final.txt");
        end
    endtask

    // =========================================================================
    // MASTER DEMO SEQUENCE
    // =========================================================================
    initial begin
        $dumpfile("build/cache_waves.vcd");
        $dumpvars(0, tb_cache);
        
        $display("\n=======================================================");
        $display("   32 KiB 4-WAY SET-ASSOCIATIVE CACHE - FINAL DEMO");
        $display("=======================================================\n");

        // System Cold Boot & Reset
        rst_n = 0; caddress = 0; cdin = 0; rden = 0; wren = 0;
        #20 rst_n = 1;

        // ---------------------------------------------------------------------
        // PHASE 1: Fill the Cache Set (Cold Misses)
        // ---------------------------------------------------------------------
        $display("--- PHASE 1: Filling Index 0 (Ways 0 through 3) ---");
        read_and_check(21'h00800); // Loads Tag 1 into Way 0
        read_and_check(21'h01000); // Loads Tag 2 into Way 1
        read_and_check(21'h01800); // Loads Tag 3 into Way 2
        read_and_check(21'h02000); // Loads Tag 4 into Way 3
        // Current LRU State: W0 is oldest (Age 3), W3 is newest (Age 0).

        // ---------------------------------------------------------------------
        // PHASE 2: True LRU Re-Sorting (Hit)
        // ---------------------------------------------------------------------
        $display("\n--- PHASE 2: Read Hit on Way 0 (Updates LRU Counters) ---");
        // Accessing Way 0 promotes it to Age 0. Way 1 cascades to become oldest.
        read_and_check(21'h00801); // Tag 1, Word Offset 1

        // ---------------------------------------------------------------------
        // PHASE 3: Dirty Block Modification (Write-Allocate & Hit)
        // ---------------------------------------------------------------------
        $display("\n--- PHASE 3: Write Hit on Way 0 (Sets Dirty Bit) ---");
        // Surgically updates the word in Way 0. Main Memory is NOT touched.
        write_word(21'h00802, 32'hDEADBEEF); // Tag 1, Word Offset 2

        // ---------------------------------------------------------------------
        // PHASE 4: Clean Eviction
        // ---------------------------------------------------------------------
        $display("\n--- PHASE 4: Clean Eviction of Way 1 ---");
        // Way 1 (the current LRU) is overwritten. Since its Dirty Bit is 0,
        // it skips the replacement write-back and goes straight to fetch.
        read_and_check(21'h02800); // Loads Tag 5

        // ---------------------------------------------------------------------
        // PHASE 5: Dirty Write-Back Execution
        // ---------------------------------------------------------------------
        $display("\n--- PHASE 5: Forcing a Dirty Write-Back ---");
        // Load two more unique tags to push Way 0 back to Age 3.
        read_and_check(21'h03000); // Loads Tag 6
        read_and_check(21'h03800); // Loads Tag 7
        
        $display("\n  [!] Evicting the Dirty Block (Tag 1)...");
        // This request targets Index 0 while it is full. The LRU logic selects 
        // Way 0. Because Way 0's Dirty Bit is 1, the FSM enters STATE_REPLACE.
        read_and_check(21'h04000); // Loads Tag 8

        // ---------------------------------------------------------------------
        // PHASE 6: Hardware State Validation
        // ---------------------------------------------------------------------
        $display("\n--- PHASE 6: Validating Main Memory Integration ---");
        @(negedge clock);
        
        // Ensure the write-back physically arrived at the correct RAM index.
        // Address 21'h00802 maps to memory index 18'h0100, word offset 2.
        if (uut_mem.ram[18'h0100][(2 * 32) +: 32] === 32'hDEADBEEF) begin
            $display("  [SUCCESS] Memory contains DEADBEEF at the correct offset!");
        end else begin
            $display("  [FAILED] Memory did not receive the dirty write-back!");
        end

        dump_memory_to_file();

        $display("\n=======================================================");
        $display("                   DEMO COMPLETE");
        $display("=======================================================\n");
        $finish;
    end
endmodule