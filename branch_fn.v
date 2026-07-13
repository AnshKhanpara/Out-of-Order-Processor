// Branch Functional Unit
//
// FIX 1: B-type branches do NOT write the PRF (wb_en=0) but they MUST
//        still raise cdb_req so the CDB arbiter forwards their rob_idx
//        to the ROB's complete_idx port.  Without this the ROB entry
//        for a B-type branch stays ready=0 forever → deadlock.
//
// FIX 2: branch_taken is a registered single-cycle pulse.  It goes high
//        the cycle after issue_valid arrives and goes low the cycle
//        cdb_grant fires.  cpu.v wires flush ← branch_taken directly,
//        so the flush to fetch/RAT/RS/ROB is exactly one cycle wide.

module branch_fn #(
    parameter DATA_WIDTH    = 32,
    parameter PHYS_REGS     = 64,
    parameter ARCH_REGS     = 32,
    parameter TAG_WIDTH     = 6,
    parameter ROB_DEPTH     = 16,
    parameter ROB_IDX_WIDTH = 4,
    parameter RS_DEPTH      = 8
)(
    input clk, rst, flush,

    // From reservation station
    input [DATA_WIDTH-1:0]       issue_src1_data,
    input [DATA_WIDTH-1:0]       issue_src2_data,
    input [TAG_WIDTH-1:0]        issue_dest_tag,
    input [ROB_IDX_WIDTH-1:0]    issue_rob_idx,
    input [6:0]                  issue_opcode,
    input [2:0]                  issue_funct3,
    input                        issue_funct7_5,
    input [DATA_WIDTH-1:0]       issue_pc,
    input [DATA_WIDTH-1:0]       issue_imm,
    input                        issue_valid,

    // CDB handshake
    input  cdb_grant,
    output reg cdb_req,
    output reg wb_en,
    output reg [TAG_WIDTH-1:0]     wb_tag,
    output reg [DATA_WIDTH-1:0]    wb_data,
    output reg [ROB_IDX_WIDTH-1:0] wb_rob_idx,

    // Branch resolution outputs (go to cpu.v flush logic)
    output reg                   branch_taken,
    output reg [DATA_WIDTH-1:0]  branch_target_pc,
    output reg [ROB_IDX_WIDTH-1:0] branch_rob_idx
);

// ── Combinational resolve ─────────────────────────────────────────────────
wire zero   = (issue_src1_data == issue_src2_data);
wire less_u = (issue_src1_data <  issue_src2_data);
wire less   = ($signed(issue_src1_data) < $signed(issue_src2_data));

wire is_jal  = (issue_opcode == 7'b1101111);
wire is_jalr = (issue_opcode == 7'b1100111);
wire is_b    = (issue_opcode == 7'b1100011);

wire branch_condition =
    (issue_funct3 == 3'b000 &&  zero)   ||  // BEQ
    (issue_funct3 == 3'b001 && !zero)   ||  // BNE
    (issue_funct3 == 3'b100 &&  less)   ||  // BLT
    (issue_funct3 == 3'b101 && !less)   ||  // BGE
    (issue_funct3 == 3'b110 &&  less_u) ||  // BLTU
    (issue_funct3 == 3'b111 && !less_u);    // BGEU

wire is_taken = is_jal || is_jalr || (is_b && branch_condition);

// JALR clears bit 0 per RISC-V spec
wire [DATA_WIDTH-1:0] target_pc =
    is_jalr ? ((issue_src1_data + issue_imm) & ~32'd1)
            : (issue_pc + issue_imm);

// ── Sequential output latch ───────────────────────────────────────────────
always @(posedge clk or posedge rst) begin
    if (rst) begin
        cdb_req          <= 0;
        wb_en            <= 0;
        wb_tag           <= 0;
        wb_data          <= 0;
        wb_rob_idx       <= 0;
        branch_taken     <= 0;
        branch_target_pc <= 0;
        branch_rob_idx   <= 0;
    end else if (flush) begin
        cdb_req      <= 0;
        wb_en        <= 0;
        branch_taken <= 0;
    end else begin

        // Accept new instruction when we are free
        if (issue_valid && !cdb_req) begin

            // 1. Branch resolution
            branch_taken     <= is_taken;
            branch_target_pc <= target_pc;
            branch_rob_idx   <= issue_rob_idx;

            // 2. PRF writeback (JAL/JALR write PC+4; B-types write nothing)
            wb_data    <= issue_pc + 32'd4;
            wb_tag     <= issue_dest_tag;
            wb_rob_idx <= issue_rob_idx;
            wb_en      <= (is_jal || is_jalr);

            // 3. FIX: always request the CDB, even for B-type branches.
            //    The arbiter will forward rob_idx to ROB complete_idx so the
            //    ROB entry is marked done regardless of wb_en.
            cdb_req <= 1'b1;
        end

        // Release CDB once granted
        if (cdb_req && cdb_grant) begin
            cdb_req      <= 1'b0;
            branch_taken <= 1'b0; // single-cycle flush pulse ends here
        end
    end
end

endmodule