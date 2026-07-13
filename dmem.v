// =============================================================
// dmem.v
// -------------------------------------------------------------
// Simple Data Memory (256 x 32-bit words).
// Word-addressable using addr[9:2].
// =============================================================

module dmem #(
    parameter DATA_WIDTH = 32
)(
    input clk,

    // Read Port (for LSQ Load Execution)
    input                       read_en,
    input      [DATA_WIDTH-1:0] read_addr,
    output reg [DATA_WIDTH-1:0] read_data,

    // Write Port (for Store Commits)
    input                       write_en,
    input      [DATA_WIDTH-1:0] write_addr,
    input      [DATA_WIDTH-1:0] write_data
);

    reg [DATA_WIDTH-1:0] memory [0:255];
    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1)
            memory[i] = 32'b0;
    end

    // Combinational Read (to keep LSQ load latency 1 cycle)
    // We can make it synchronous if needed, but combinational matches
    // the typical LSQ expectation where address calc and read happen quickly,
    // or address calc is cycle 1 and memory access is cycle 2. 
    // Since our execute phase is 1 cycle, combinational read is easiest.
    always @(*) begin
        if (read_en)
            read_data = memory[read_addr[9:2]];
        else
            read_data = 32'b0;
    end

    // Synchronous Write
    always @(posedge clk) begin
        if (write_en) begin
            memory[write_addr[9:2]] <= write_data;
            // $display("[DMEM] WRITE: mem[%0d] <- %0d", write_addr[9:2], $signed(write_data));
        end
    end

endmodule
