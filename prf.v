module prf #(
    parameter ARCH_REGS  = 32,
    parameter PHYS_REGS  = 64,
    parameter DATA_WIDTH = 32,
    parameter TAG_WIDTH  = 6
)(
    input clk, rst, flush,

    input [TAG_WIDTH-1:0]   alloc_tag,
    input                   alloc_en,

    input [TAG_WIDTH-1:0]   src1_tag, src2_tag,

    output                  src1_ready, src2_ready,
    output [DATA_WIDTH-1:0] src1_data,  src2_data,

    input                   wb_en,
    input [TAG_WIDTH-1:0]   wb_tag,
    input [DATA_WIDTH-1:0]  wb_data,

    input                   commit_en,
    input [TAG_WIDTH-1:0]   commit_tag
);

reg [DATA_WIDTH-1:0] preg           [0:PHYS_REGS-1];
reg                  ready          [0:PHYS_REGS-1];
reg                  committed_ready[0:PHYS_REGS-1];

assign src1_data  = preg[src1_tag];
assign src1_ready = ready[src1_tag];
assign src2_data  = preg[src2_tag];
assign src2_ready = ready[src2_tag];

integer i;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < ARCH_REGS; i = i + 1) begin
            ready[i]           <= 1;
            committed_ready[i] <= 1;
            preg[i]            <= 0;
        end
        // Pre-initialize registers for branch-only testing
        preg[1]  <= 32'd5;   // x1 = 5
        preg[2]  <= 32'd5;   // x2 = 5  (equal to x1 for BEQ test)
        preg[3]  <= 32'd10;  // x3 = 10
        preg[4]  <= 32'd3;   // x4 = 3  (not equal to x3 for BNE test)
        preg[11] <= 32'h4C;  // x11 = 0x4C (JALR target address)
        for (i = ARCH_REGS; i < PHYS_REGS; i = i + 1) begin
            ready[i]           <= 0;
            committed_ready[i] <= 0;
            preg[i]            <= 0;
        end
    end else begin

        // 1. Flush: restore ready bits to committed state
        if (flush) begin
            for (i = 0; i < PHYS_REGS; i = i + 1)
                ready[i] <= committed_ready[i];
        end

        // 2. Writeback: applies EVEN during flush cycle.
        //    For JAL/JALR, wb_tag is the identity-mapped physical reg
        //    (= arch_rd), so this write survives flush + RAT reset.
        //    The last NBA to ready[wb_tag] wins: wb_en's '1' overrides
        //    flush's committed_ready[wb_tag] value.
        if (wb_en) begin
            preg[wb_tag]  <= wb_data;
            ready[wb_tag] <= 1;
            preg[0]       <= 0;
            ready[0]      <= 1;
        end

        // 3. Alloc: mark new tag as not-ready (skip during flush)
        if (alloc_en && !flush) begin
            if (!(wb_en && wb_tag == alloc_tag))
                ready[alloc_tag] <= 0;
            preg[0]  <= 0;
            ready[0] <= 1;
        end

        // 4. Commit tracking
        if (commit_en && !flush) begin
            committed_ready[commit_tag] <= 1;
            committed_ready[0]          <= 1;
        end
    end
end

endmodule