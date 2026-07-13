module freelist #(
    parameter PHYS_REGS  = 64,
    parameter ARCH_REGS  = 32,
    parameter DATA_WIDTH = 32,
    parameter TAG_WIDTH  = 6
)(
    input clk, rst, flush,

    input                alloc_req,
    output [TAG_WIDTH-1:0] alloc_tag,
    output               alloc_valid,

    input                free_en,
    input [TAG_WIDTH-1:0] free_tag
);

localparam DEPTH = PHYS_REGS - ARCH_REGS; // 32

reg [DATA_WIDTH-1:0] fifo     [0:DEPTH-1];
reg [$clog2(DEPTH)-1:0] head, tail;
reg [$clog2(DEPTH):0]   count;

// Checkpoint registers for flush recovery
reg [DATA_WIDTH-1:0]    chk_fifo  [0:DEPTH-1];
reg [$clog2(DEPTH)-1:0] chk_head, chk_tail;
reg [$clog2(DEPTH):0]   chk_count;

assign alloc_valid = (count != 0);
assign alloc_tag   = fifo[head];

integer i;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < ARCH_REGS; i = i + 1)
            fifo[i] <= ARCH_REGS + i;
        count    <= 32;
        head     <= 0;
        tail     <= 0;
        for (i = 0; i < DEPTH; i = i + 1)
            chk_fifo[i] <= ARCH_REGS + i;
        chk_count <= 32;
        chk_head  <= 0;
        chk_tail  <= 0;
    end else if (flush) begin
        for (i = 0; i < DEPTH; i = i + 1)
            fifo[i] <= chk_fifo[i];
        count <= chk_count;
        head  <= chk_head;
        tail  <= chk_tail;
    end else begin
        if (free_en) begin
            fifo[tail] <= free_tag;
            tail       <= (tail == DEPTH-1) ? 0 : tail + 1;
        end
        if (alloc_req && (count != 0))
            head <= (head == DEPTH-1) ? 0 : head + 1;

        case ({(alloc_req && (count != 0)), free_en})
            2'b10: count <= count - 1;
            2'b01: count <= count + 1;
            default: count <= count;
        endcase

        // Update checkpoint on commit (free)
        if (free_en) begin
            for (i = 0; i < DEPTH; i = i + 1)
                if (i == tail) chk_fifo[i] <= free_tag;
                else           chk_fifo[i] <= fifo[i];
            chk_tail  <= (tail == DEPTH-1) ? 0 : tail + 1;
            chk_head  <= (alloc_req && (count != 0)) ? ((head == DEPTH-1) ? 0 : head + 1) : head;
            case ({(alloc_req && (count != 0)), free_en})
                2'b10: chk_count <= count - 1;
                2'b01: chk_count <= count + 1;
                default: chk_count <= count;
            endcase
        end
    end
end

endmodule