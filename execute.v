// =============================================================
// execute.v  (Dual RS + CDB Arbitration)
// -------------------------------------------------------------
// Wraps both ALU and branch_fn.
// Accepts independent issue packets from ALU RS and Branch RS.
//
// CDB Arbitration:
// - If both ALU and Branch want to writeback on the same cycle,
//   Branch gets priority.
// - If ALU loses arbitration, its result is buffered and 
//   alu_exec_busy is asserted to stall further ALU issues until
//   the buffer clears.
// =============================================================

module execute #(
    parameter DATA_WIDTH    = 32,
    parameter TAG_WIDTH     = 6,
    parameter ROB_IDX_WIDTH = 4
)(
    input clk,
    input rst,
    input flush,

    // -----------------------------------------------------
    // ALU Issue Packet (from rs_alu)
    // -----------------------------------------------------
    input alu_issue_valid,
    input [6:0] alu_issue_instr_opcode,
    input [2:0] alu_issue_funct3,
    input       alu_issue_funct7_5,
    input [DATA_WIDTH-1:0] alu_issue_src1_value,
    input [DATA_WIDTH-1:0] alu_issue_src2_value,
    input [TAG_WIDTH-1:0]  alu_issue_dest_phys_tag,
    input [ROB_IDX_WIDTH-1:0] alu_issue_rob_idx,

    // -----------------------------------------------------
    // Branch Issue Packet (from rs_branch)
    // -----------------------------------------------------        // Branch RS Packet
    input                           branch_issue_valid,
    input  [6:0]                    branch_issue_instr_opcode,
    input  [2:0]                    branch_issue_funct3,
    input  [DATA_WIDTH-1:0]         branch_issue_pc,
    input  [DATA_WIDTH-1:0]         branch_issue_imm,
    input  [4:0]                    branch_issue_arch_rd,
    input  [DATA_WIDTH-1:0]         branch_issue_src1_value,
    input  [DATA_WIDTH-1:0]         branch_issue_src2_value,
    input  [TAG_WIDTH-1:0]          branch_issue_dest_phys_tag,
    input  [ROB_IDX_WIDTH-1:0]      branch_issue_rob_idx,

    // LSQ CDB Packet
    input                           lsq_cdb_req,
    input  [TAG_WIDTH-1:0]          lsq_cdb_tag,
    input  [DATA_WIDTH-1:0]         lsq_cdb_data,
    input  [ROB_IDX_WIDTH-1:0]      lsq_cdb_rob_idx,
    output                          lsq_cdb_grant,

    // -----------------------------------------------------
    // Busy signals (to stall issue)
    // -----------------------------------------------------
    output alu_exec_busy,
    output branch_exec_busy,

    // -----------------------------------------------------
    // CDB Outputs
    // -----------------------------------------------------
    output wb_en,
    output [TAG_WIDTH-1:0] wb_tag,
    output [DATA_WIDTH-1:0] wb_data,

    output complete_en,
    output [ROB_IDX_WIDTH-1:0] complete_idx,
    output [DATA_WIDTH-1:0] complete_value,

    // Branch resolution outputs
    output branch_taken,
    output [DATA_WIDTH-1:0] branch_target_pc,

    // JAL/JALR link writeback info (for direct ARF write in cpu.v)
    output                  jal_wr_en,
    output [4:0]            jal_arch_rd,
    output [DATA_WIDTH-1:0] jal_wr_data
);

// =============================================================
// ALU UNIT (0-cycle latency)
// =============================================================
wire [DATA_WIDTH-1:0] alu_result;

alu alu_inst(
    .instr_opcode(alu_issue_instr_opcode),
    .funct3      (alu_issue_funct3),
    .funct7_5    (alu_issue_funct7_5),
    .src1_value  (alu_issue_src1_value),
    .src2_value  (alu_issue_src2_value),
    .result      (alu_result)
);

// Buffer for ALU result in case of arbitration loss
reg alu_buf_valid;
reg [TAG_WIDTH-1:0] alu_buf_tag;
reg [DATA_WIDTH-1:0] alu_buf_data;
reg [ROB_IDX_WIDTH-1:0] alu_buf_rob_idx;

wire alu_live_req = alu_issue_valid & ~alu_exec_busy;
wire alu_total_req = alu_buf_valid | alu_live_req;

// Busy signal: If buffer is full, we can't accept new issues
assign alu_exec_busy = alu_buf_valid;

// =============================================================
// BRANCH UNIT (1-cycle latency)
// =============================================================
wire                       br_cdb_req;
wire                       br_cdb_grant;
wire                       br_wb_en;
wire [TAG_WIDTH-1:0]       br_wb_tag;
wire [DATA_WIDTH-1:0]      br_wb_data;
wire [ROB_IDX_WIDTH-1:0]   br_wb_rob_idx;
wire                       br_branch_taken;
wire [DATA_WIDTH-1:0]      br_branch_target_pc;
wire [ROB_IDX_WIDTH-1:0]   br_branch_rob_idx;

// Detect instruction types to latch arch_rd for JAL/JALR bypass
wire is_b    = (branch_issue_instr_opcode == 7'b1100011);
wire is_jal  = (branch_issue_instr_opcode == 7'b1101111);
wire is_jalr = (branch_issue_instr_opcode == 7'b1100111);
wire is_branch_type = is_b | is_jal | is_jalr;

// branch_fn only takes 1 issue at a time. If it hasn't received a grant
// for its current request, it is busy and cannot accept new issues.
assign branch_exec_busy = br_cdb_req;

wire branch_live_issue = branch_issue_valid & ~branch_exec_busy & is_branch_type;

// Latch arch_rd for JAL/JALR
reg [4:0] latched_arch_rd;
always @(posedge clk or posedge rst) begin
    if (rst)
        latched_arch_rd <= 5'd0;
    else if (branch_live_issue)
        latched_arch_rd <= branch_issue_arch_rd;
end

branch_fn #(
    .DATA_WIDTH    (DATA_WIDTH),
    .TAG_WIDTH     (TAG_WIDTH),
    .ROB_IDX_WIDTH (ROB_IDX_WIDTH)
) branch_fn_inst (
    .clk             (clk),
    .rst             (rst),
    .flush           (flush),

    .issue_src1_data (branch_issue_src1_value),
    .issue_src2_data (branch_issue_src2_value),
    .issue_dest_tag  (branch_issue_dest_phys_tag),
    .issue_rob_idx   (branch_issue_rob_idx),
    .issue_opcode    (branch_issue_instr_opcode),
    .issue_funct3    (branch_issue_funct3),
    .issue_funct7_5  (1'b0),
    .issue_pc        (branch_issue_pc),
    .issue_imm       (branch_issue_imm),
    .issue_valid     (branch_live_issue),

    .cdb_grant       (br_cdb_grant),
    .cdb_req         (br_cdb_req),
    .wb_en           (br_wb_en),
    .wb_tag          (br_wb_tag),
    .wb_data         (br_wb_data),
    .wb_rob_idx      (br_wb_rob_idx),

    .branch_taken    (br_branch_taken),
    .branch_target_pc(br_branch_target_pc),
    .branch_rob_idx  (br_branch_rob_idx)
);

// =============================================================
// CDB ARBITRATION
// =============================================================
// Priority: ALU > Branch > LSQ

wire   alu_cdb_grant = alu_total_req;
assign br_cdb_grant  = br_cdb_req & ~alu_total_req;
assign lsq_cdb_grant = lsq_cdb_req & ~alu_total_req & ~br_cdb_req;

always @(posedge clk or posedge rst) begin
    if (rst || flush) begin
        alu_buf_valid <= 0;
    end else begin
        if (alu_live_req && !alu_cdb_grant) begin
            // ALU lost arbitration, buffer the result
            alu_buf_valid   <= 1;
            alu_buf_tag     <= alu_issue_dest_phys_tag;
            alu_buf_data    <= alu_result;
            alu_buf_rob_idx <= alu_issue_rob_idx;
        end else if (alu_buf_valid && alu_cdb_grant) begin
            // Buffered ALU won arbitration, clear buffer
            alu_buf_valid <= 0;
        end
    end
end

// Select ALU data source (buffer vs live)
wire [TAG_WIDTH-1:0]     alu_final_tag     = alu_buf_valid ? alu_buf_tag     : alu_issue_dest_phys_tag;
wire [DATA_WIDTH-1:0]    alu_final_data    = alu_buf_valid ? alu_buf_data    : alu_result;
wire [ROB_IDX_WIDTH-1:0] alu_final_rob_idx = alu_buf_valid ? alu_buf_rob_idx : alu_issue_rob_idx;

// JAL/JALR Identity Tag Override
wire jal_jalr_active = br_cdb_req & br_wb_en;
wire [TAG_WIDTH-1:0] identity_tag = {{(TAG_WIDTH-5){1'b0}}, latched_arch_rd};

wire [TAG_WIDTH-1:0] final_br_wb_tag = jal_jalr_active ? identity_tag : br_wb_tag;

// Output Mux (Branch > LSQ > ALU)
assign wb_en   = br_cdb_req ? br_wb_en    : (lsq_cdb_req ? 1'b1           : alu_cdb_grant);
assign wb_tag  = br_cdb_req ? final_br_wb_tag : (lsq_cdb_req ? lsq_cdb_tag    : alu_final_tag);
assign wb_data = br_cdb_req ? br_wb_data  : (lsq_cdb_req ? lsq_cdb_data   : alu_final_data);

assign complete_en    = br_cdb_req ? 1'b1          : (lsq_cdb_req ? 1'b1              : alu_cdb_grant);
assign complete_idx   = br_cdb_req ? br_wb_rob_idx : (lsq_cdb_req ? lsq_cdb_rob_idx   : alu_final_rob_idx);
assign complete_value = br_cdb_req ? br_wb_data    : (lsq_cdb_req ? lsq_cdb_data      : alu_final_data);

// Branch signals
assign branch_taken     = br_branch_taken;
assign branch_target_pc = br_branch_target_pc;

assign jal_wr_en   = jal_jalr_active;
assign jal_arch_rd = latched_arch_rd;
assign jal_wr_data = br_wb_data;

endmodule