`default_nettype none
`timescale 1ns/1ps

module main_memory #(
    parameter BLOCK_SIZE = 256,
    parameter M_ADDR_WIDTH = 18 // TAG (10) + INDEX (8)
)(
    input  wire                       clock,
    input  wire [M_ADDR_WIDTH-1:0]    maddress,
    input  wire [BLOCK_SIZE-1:0]      mdin,     // Data from Cache (Write-Back)
    input  wire                       mrden,
    input  wire                       mwren,
    
    output reg  [BLOCK_SIZE-1:0]      mdout     // Data to Cache (Fetch)
);

    // 2^18 = 262,144 blocks (8 MiB ÷ 32 bytes/block)
    reg [BLOCK_SIZE-1:0] ram [0:262143];

    initial begin
        // $readmemb is required because the Python script generates binary strings
        $readmemb("tb/mem_data.txt", ram);
    end

    always @(mrden, maddress) begin
        if (mrden) begin
            mdout = ram[maddress]; 
        end else begin
            mdout = {BLOCK_SIZE{1'b0}};
        end
    end

    always @(posedge clock) begin
        if (mwren) begin
            ram[maddress] <= mdin;
        end
    end

endmodule