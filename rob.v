// ROB - Reorder Buffer
// FIFO: dispatch writes to TAIL, commit reads from HEAD
// FIX: added is_branch_in / head_is_branch so commit never
//      tries to write the ARF for branch instructions.

module rob #(
    parameter PHYS_REGS      = 64,
    parameter ARCH_REGS      = 32,
    parameter ROB_DEPTH      = 16,
    parameter RS_DEPTH       = 8,
    parameter DATA_WIDTH     = 32,
    parameter TAG_WIDTH      = 6
)(
    input clk, rst, flush,

    output rob_full,

    // Dispatch inputs
    input [TAG_WIDTH-1:0]            dest_tag,
    input [TAG_WIDTH-1:0]            old_phys_tag,
    input [4:0]                      arch_rd,
    input                            is_branch_in,   // FIX: new port
    input                            is_lsu_in,      // FIX: new port

    // Completion from CDB arbiter
    input                            complete_en,
    input [$clog2(ROB_DEPTH)-1:0]    complete_idx,
    input [DATA_WIDTH-1:0]           complete_data,

    // Dispatch handshake
    input                            dispacth_en,
    input [$clog2(ROB_DEPTH)-1:0]    dispatch_idx,   // output to rest of CPU (see assign below)
    input                            dispatch_ready,  // born-ready (NOP / x0 writes)

    // Commit gating
    input                            commit_en_in,

    // Head outputs for commit stage
    output                           head_ready,
    output [TAG_WIDTH-1:0]           head_phys,
    output [TAG_WIDTH-1:0]           head_old_phys,
    output [DATA_WIDTH-1:0]          head_data,
    output [4:0]                     head_arch_rd,
    output                           head_is_branch, // FIX: new output
    output                           head_is_lsu     // FIX: new output
);

// ── Internal storage ──────────────────────────────────────────────────────
reg                    busy_arr      [0:ROB_DEPTH-1];
reg                    ready_arr     [0:ROB_DEPTH-1];
reg [TAG_WIDTH-1:0]    dest_arr      [0:ROB_DEPTH-1];
reg [TAG_WIDTH-1:0]    old_phys_arr  [0:ROB_DEPTH-1];
reg [DATA_WIDTH-1:0]   value_arr     [0:ROB_DEPTH-1];
reg [4:0]              arch_rd_arr   [0:ROB_DEPTH-1];
reg                    is_branch_arr [0:ROB_DEPTH-1]; // FIX: new field
reg                    is_lsu_arr    [0:ROB_DEPTH-1]; // FIX: new field

reg [$clog2(ROB_DEPTH)-1:0] head_ptr, tail_ptr;
reg [$clog2(ROB_DEPTH):0]   count;

// ── Combinational head outputs ────────────────────────────────────────────
assign head_ready      = busy_arr[head_ptr] & ready_arr[head_ptr];
assign head_phys       = dest_arr[head_ptr];
assign head_old_phys   = old_phys_arr[head_ptr];
assign head_data       = value_arr[head_ptr];
assign head_arch_rd    = arch_rd_arr[head_ptr];
assign head_is_branch  = is_branch_arr[head_ptr];  // FIX
assign head_is_lsu     = is_lsu_arr[head_ptr];     // FIX

assign rob_full        = (count == ROB_DEPTH);

// dispatch_idx is always the current tail so the rest of the CPU can read it
// (the port is declared as input above for elaboration but driven externally in cpu.v;
//  the actual assignment below is the one that matters in this module)
assign dispatch_idx = tail_ptr;  // NOTE: cpu.v reads this as a wire

wire do_dispatch = dispacth_en && !rob_full;
wire do_commit   = busy_arr[head_ptr] && ready_arr[head_ptr] && commit_en_in;

integer i;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        head_ptr <= 0;
        tail_ptr <= 0;
        count    <= 0;
        for (i = 0; i < ROB_DEPTH; i = i + 1) begin
            busy_arr[i]      <= 0;
            ready_arr[i]     <= 0;
            dest_arr[i]      <= 0;
            old_phys_arr[i]  <= 0;
            value_arr[i]     <= 0;
            arch_rd_arr[i]   <= 0;
            is_branch_arr[i] <= 0;
            is_lsu_arr[i]    <= 0;
        end
    end else if (flush) begin
        head_ptr <= 0;
        tail_ptr <= 0;
        count    <= 0;
        for (i = 0; i < ROB_DEPTH; i = i + 1) begin
            busy_arr[i]  <= 0;
            ready_arr[i] <= 0;
        end
    end else begin

        // 1. Dispatch → write to tail
        if (do_dispatch) begin
            busy_arr[tail_ptr]      <= 1'b1;
            ready_arr[tail_ptr]     <= dispatch_ready;
            dest_arr[tail_ptr]      <= dest_tag;
            old_phys_arr[tail_ptr]  <= old_phys_tag;
            value_arr[tail_ptr]     <= 0;
            arch_rd_arr[tail_ptr]   <= arch_rd;
            is_branch_arr[tail_ptr] <= is_branch_in;  // FIX
            is_lsu_arr[tail_ptr]    <= is_lsu_in;     // FIX
            tail_ptr <= (tail_ptr == ROB_DEPTH-1) ? 0 : tail_ptr + 1;
        end

        // 2. Complete → mark entry ready with result
        if (complete_en) begin
            ready_arr[complete_idx] <= 1'b1;
            value_arr[complete_idx] <= complete_data;
        end

        // 3. Commit → free head
        if (do_commit) begin
            ready_arr[head_ptr] <= 0;
            busy_arr[head_ptr]  <= 0;
            head_ptr <= (head_ptr == ROB_DEPTH-1) ? 0 : head_ptr + 1;
        end

        count <= count + do_dispatch - do_commit;
    end
end

endmodule