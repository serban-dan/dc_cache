`default_nettype none
`timescale 1ns/1ps

module cache_way #(
    parameter N_SETS = 256,
    parameter INDEX_WIDTH = 8,
    parameter TAG_WIDTH = 10,
    parameter BLOCK_SIZE = 256
)(
    input  wire                   clock,
    input  wire                   rst_n,
    
    // Read/Lookup Ports
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire [TAG_WIDTH-1:0]   tag_in,
    
    // Write Ports
    input  wire [BLOCK_SIZE-1:0]  data_in,
    input  wire                   write_en,
    input  wire                   dirty_in, // 1 for CPU write, 0 for RAM fill
    
    // Outputs
    output wire                   hit,
    output wire [BLOCK_SIZE-1:0]  data_out,
    output wire [TAG_WIDTH-1:0]   tag_out,
    output wire                   dirty_out,
    output wire                   valid_out
);

    //Physical Arrays
    reg                   valid_array [0:N_SETS-1];
    reg                   dirty_array [0:N_SETS-1];
    reg [TAG_WIDTH-1:0]   tag_array   [0:N_SETS-1];
    reg [BLOCK_SIZE-1:0]  data_array  [0:N_SETS-1];

    integer i;

    //Continuous Read Logic
    assign valid_out = valid_array[index];
    assign dirty_out = dirty_array[index];
    assign tag_out   = tag_array[index];
    assign data_out  = data_array[index];

    //Internal Hit Detection
    assign hit = valid_out && (tag_out == tag_in);

    //Sequential Write & Reset Logic
    always @(posedge clock) begin
        if (!rst_n) begin
            // Only reset valid bits
            for (i = 0; i < N_SETS; i = i + 1) begin
                valid_array[i] <= 1'b0;
                dirty_array[i] <= 1'b0;
            end
        end else begin
            if (write_en) begin
                data_array[index]  <= data_in;
                tag_array[index]   <= tag_in;
                valid_array[index] <= 1'b1;
                dirty_array[index] <= dirty_in;
            end
        end
    end

endmodule