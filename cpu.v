// =============================================================
// cpu.v  -  Single-Issue Out-of-Order RISC-V CPU (Tomasulo)
// =============================================================
// Supported instructions:
//   R-type : ADD SUB AND OR XOR SLT SLTU SLL SRL SRA
//   I-type : ADDI
//   B-type : BEQ BNE BLT BGE BLTU BGEU
//   J-type : JAL JALR
//
// Pipeline stages
//   Fetch  -> Decode -> Rename/Dispatch -> (OoO) -> Issue -> Execute -> Writeback -> Commit
//
// Dual Reservation Stations:
//   - ALU RS (for R-type and I-type)
//   - Branch RS (for B-type, JAL, JALR)
//   - Both issue independently. Execute unit handles CDB arbitration.
//
// Commit:
//   On commit, values are written to the ARF (Architectural
//   Register File) for non-branch instructions with rd != x0.
// =============================================================

module cpu(
    input clk,
    input rst
);

    // ===========================================================
    // PARAMETERS
    // ===========================================================
    parameter DATA_WIDTH    = 32;
    parameter PHYS_REGS     = 64;
    parameter ARCH_REGS     = 32;
    parameter TAG_WIDTH     = 6;
    parameter ROB_SIZE      = 16;
    parameter ROB_IDX_WIDTH = 4;   // ceil(log2(ROB_SIZE))
    parameter RS_SIZE       = 8;

    // ===========================================================
    // INSTRUCTION MEMORY  (256 x 32-bit words)
    // ===========================================================
    reg [31:0] imem [0:255];

    initial begin
        $readmemh("program.mem", imem);
    end

    // ===========================================================
    // WIRES - FETCH
    // ===========================================================
    wire [31:0] pc;
    wire [31:0] instruction;

    // Instruction is read combinationally from imem using the current PC
    assign instruction = imem[pc[9:2]];

    // ===========================================================
    // WIRES - DECODE
    // ===========================================================
    wire [6:0]  instr_opcode; // full 7-bit RISC-V opcode
    wire [2:0]  funct3;       // function field
    wire        funct7_5;     // bit 5 of funct7
    wire [4:0]  rs1;          // architectural source register 1
    wire [4:0]  rs2;          // architectural source register 2
    wire [4:0]  rd;           // architectural destination register
    wire [31:0] imm;          // sign-extended immediate
    wire        is_imm;       // 1 = I-type: use imm instead of rs2
    wire        is_alu;       // instruction is ALU type
    wire        is_branch;    // instruction is branch type (B/JAL/JALR)
    wire        is_lsu;       // instruction is load/store (unused for now)
    wire        is_store;     // instruction is store (unused for now)

    // ===========================================================
    // WIRES - FREE LIST
    // ===========================================================
    wire [TAG_WIDTH-1:0] alloc_tag;   // physical tag allocated for rd
    wire                 alloc_valid; // free list is non-empty

    // ===========================================================
    // WIRES - RAT
    // ===========================================================
    wire [TAG_WIDTH-1:0] src1_tag;     // physical tag for rs1
    wire [TAG_WIDTH-1:0] src2_tag;     // physical tag for rs2
    wire [TAG_WIDTH-1:0] dest_tag;     // physical tag for rd (= alloc_tag)
    wire [TAG_WIDTH-1:0] old_dest_tag; // previous physical tag of rd (for ROB)

    // ===========================================================
    // WIRES - PHYSICAL REGISTER FILE
    // ===========================================================
    wire [DATA_WIDTH-1:0] src1_value; // value of physical src1 register
    wire [DATA_WIDTH-1:0] src2_value; // value of physical src2 register
    wire                  src1_ready; // src1 has a valid value
    wire                  src2_ready; // src2 has a valid value

    // ===========================================================
    // WIRES - IMMEDIATE MUX
    // ===========================================================
    wire [DATA_WIDTH-1:0] dispatch_src2_value; // src2 sent to RS
    wire                  dispatch_src2_ready; // src2 ready bit sent to RS

    assign dispatch_src2_value = is_imm ? imm       : src2_value;
    assign dispatch_src2_ready = is_imm ? 1'b1      : src2_ready;

    // ===========================================================
    // WIRES - ROB
    // ===========================================================
    wire [ROB_IDX_WIDTH-1:0] dispatch_idx;  // ROB slot for this dispatch
    wire                     rob_full;       // ROB is full - stall dispatch
    wire                     head_ready;     // ROB head instruction is complete
    wire [TAG_WIDTH-1:0]     head_dest_phys; // physical dest of head entry
    wire [TAG_WIDTH-1:0]     head_old_phys;  // old physical dest of head entry
    wire [DATA_WIDTH-1:0]    head_value;     // result value at head
    wire [4:0]               head_arch_rd;   // architectural rd at head
    wire                     head_is_branch; // head is a branch (no ARF write)
    wire                     head_is_lsu;    // head is a load/store (pop LSQ)

    // ===========================================================
    // WIRES - RESERVATION STATIONS
    // ===========================================================
    wire [RS_SIZE-1:0]    alu_entry_busy;
    wire [RS_SIZE-1:0]    alu_entry_ready;
    wire [RS_SIZE-1:0]    branch_entry_busy;
    wire [RS_SIZE-1:0]    branch_entry_ready;

    // ALU issue packet
    wire [6:0]            alu_issue_instr_opcode;
    wire [2:0]            alu_issue_funct3;
    wire                  alu_issue_funct7_5;
    wire [DATA_WIDTH-1:0] alu_issue_src1_value;
    wire [DATA_WIDTH-1:0] alu_issue_src2_value;
    wire [TAG_WIDTH-1:0]  alu_issue_dest_phys_tag;
    wire [ROB_IDX_WIDTH-1:0] alu_issue_rob_idx;

    // Branch issue packet
    wire [6:0]            branch_issue_instr_opcode;
    wire [2:0]            branch_issue_funct3;
    wire [DATA_WIDTH-1:0] branch_issue_pc;
    wire [DATA_WIDTH-1:0] branch_issue_imm;
    wire [4:0]            branch_issue_arch_rd;
    wire [DATA_WIDTH-1:0] branch_issue_src1_value;
    wire [DATA_WIDTH-1:0] branch_issue_src2_value;
    wire [TAG_WIDTH-1:0]  branch_issue_dest_phys_tag;
    wire [ROB_IDX_WIDTH-1:0] branch_issue_rob_idx;

    // ===========================================================
    // WIRES - ISSUE SELECT
    // ===========================================================
    wire        alu_issue_valid;
    wire [2:0]  alu_issue_idx;
    
    wire        branch_issue_valid;
    wire [2:0]  branch_issue_idx;

    // ===========================================================
    // WIRES - EXECUTE / WRITEBACK
    // ===========================================================
    wire        wb_en;           // writeback enable (physical register file)
    wire [TAG_WIDTH-1:0]  wb_tag;   // physical tag being written back
    wire [DATA_WIDTH-1:0] wb_data;  // writeback value

    wire        complete_en;        // mark ROB entry as complete
    wire [ROB_IDX_WIDTH-1:0] complete_idx;   // which ROB entry is complete
    wire [DATA_WIDTH-1:0]    complete_value; // result value written to ROB

    wire        branch_taken;
    wire [31:0] branch_target_pc;

    wire        alu_exec_busy;
    wire        branch_exec_busy;

    wire        jal_wr_en;
    wire [4:0]  jal_arch_rd;
    wire [DATA_WIDTH-1:0] jal_wr_data;

    // Issue grants back to RS
    wire        alu_issue_grant;
    assign alu_issue_grant = alu_issue_valid & ~alu_exec_busy;

    wire        branch_issue_grant;
    assign branch_issue_grant = branch_issue_valid & ~branch_exec_busy;

    // ===========================================================
    // WIRES - LSQ & DMEM
    // ===========================================================
    wire lsq_full;
    wire lsq_head_ready;
    wire lsq_dispatch_en = dispatch_en & is_lsu;

    wire lsq_cdb_req;
    wire [TAG_WIDTH-1:0] lsq_cdb_tag;
    wire [DATA_WIDTH-1:0] lsq_cdb_data;
    wire [ROB_IDX_WIDTH-1:0] lsq_cdb_rob_idx;
    wire lsq_cdb_grant;

    wire dmem_rd_en;
    wire [DATA_WIDTH-1:0] dmem_rd_addr;
    wire [DATA_WIDTH-1:0] dmem_rd_data;
    
    wire dmem_wr_en;
    wire [DATA_WIDTH-1:0] dmem_wr_addr;
    wire [DATA_WIDTH-1:0] dmem_wr_data;

    wire commit_pop = commit_en & head_is_lsu;

    // ===========================================================
    // WIRES - COMMIT
    // ===========================================================
    wire commit_en; // ROB head is being committed this cycle
    wire free_en;   // old physical register is being returned to free list
    wire [TAG_WIDTH-1:0] free_tag; // which physical register to free

    // ===========================================================
    // WIRES - ARF (Architectural Register File)
    // ===========================================================
    wire arf_wr_en;
    wire [4:0] arf_wr_addr;
    wire [DATA_WIDTH-1:0] arf_wr_data;

    assign arf_wr_en   = (commit_en & (head_arch_rd != 5'd0)) | jal_wr_en;
    assign arf_wr_addr = jal_wr_en ? jal_arch_rd : head_arch_rd;
    assign arf_wr_data = jal_wr_en ? jal_wr_data : head_value;

    // ===========================================================
    // FLUSH SIGNAL
    // ===========================================================
    wire flush;
    assign flush = branch_taken;

    // ===========================================================
    // DISPATCH ENABLE
    // ===========================================================
    parameter PROG_WORDS = 20;

    wire need_alloc = (rd != 5'd0);

    // Track full status of the two RS independently
    wire alu_rs_full    = (&alu_entry_busy);
    wire branch_rs_full = (&branch_entry_busy);

    // A dispatch stalls if the RS it needs is full
    wire rs_stall = (is_alu & alu_rs_full) | (is_branch & branch_rs_full) | (is_lsu & lsq_full);

    wire program_done = (pc[9:2] >= PROG_WORDS);

    wire dispatch_en = ~program_done
                     & ~flush
                     & (~need_alloc | alloc_valid)
                     & ~rob_full
                     & ~rs_stall;

    wire alu_dispatch_en    = dispatch_en & is_alu;
    wire branch_dispatch_en = dispatch_en & is_branch;

    // ===========================================================
    // MODULE INSTANTIATIONS
    // ===========================================================

    fetch fetch_inst(
        .clk              (clk),
        .rst              (rst),
        .dispatch_en      (dispatch_en),
        .flush            (flush),
        .branch_target_pc (branch_target_pc),
        .pc               (pc)
    );

    decoder decoder_inst(
        .instruction  (instruction),
        .instr_opcode (instr_opcode),
        .funct3       (funct3),
        .funct7_5     (funct7_5),
        .rs1          (rs1),
        .rs2          (rs2),
        .rd           (rd),
        .imm          (imm),
        .is_imm       (is_imm),
        .is_alu       (is_alu),
        .is_branch    (is_branch),
        .is_lsu       (is_lsu),
        .is_store     (is_store)
    );

    freelist #(
        .PHYS_REGS (PHYS_REGS),
        .ARCH_REGS (ARCH_REGS),
        .TAG_WIDTH (TAG_WIDTH)
    ) freelist_inst(
        .clk        (clk),
        .rst        (rst),
        .flush      (flush),
        .alloc_req  (dispatch_en & need_alloc),
        .alloc_tag  (alloc_tag),
        .alloc_valid(alloc_valid),
        .free_en    (free_en),
        .free_tag   (free_tag)
    );

    rat #(
        .DATA_WIDTH (DATA_WIDTH),
        .PHYS_REGS  (PHYS_REGS),
        .ARCH_REGS  (ARCH_REGS),
        .TAG_WIDTH  (TAG_WIDTH)
    ) rat_inst(
        .clk         (clk),
        .rst         (rst),
        .flush       (flush),
        .rs1         (rs1),
        .rs2         (rs2),
        .rd          (rd),
        .rename_en   (dispatch_en),
        .alloc_tag   (alloc_tag),
        .src1_tag    (src1_tag),
        .src2_tag    (src2_tag),
        .dest_tag    (dest_tag),
        .old_dest_tag(old_dest_tag)
    );

    prf #(
        .DATA_WIDTH (DATA_WIDTH),
        .PHYS_REGS  (PHYS_REGS),
        .TAG_WIDTH  (TAG_WIDTH)
    ) prf_inst(
        .clk        (clk),
        .rst        (rst),
        .flush      (flush),
        .src1_tag   (src1_tag),
        .src1_data  (src1_value),
        .src1_ready (src1_ready),
        .src2_tag   (src2_tag),
        .src2_data  (src2_value),
        .src2_ready (src2_ready),
        .alloc_tag  (alloc_tag),
        .alloc_en   (dispatch_en),
        .wb_tag     (wb_tag),
        .wb_data    (wb_data),
        .wb_en      (wb_en),
        .commit_en  (commit_en),
        .commit_tag (head_dest_phys)
    );

    rob #(
        .DATA_WIDTH    (DATA_WIDTH),
        .PHYS_REGS     (PHYS_REGS),
        .ARCH_REGS     (ARCH_REGS),
        .TAG_WIDTH     (TAG_WIDTH),
        .ROB_DEPTH     (ROB_SIZE),
        .RS_DEPTH      (RS_SIZE)
    ) rob_inst(
        .clk            (clk),
        .rst            (rst),
        .flush          (flush),
        .dispacth_en    (dispatch_en),
        .dest_tag       (dest_tag),
        .old_phys_tag   (old_dest_tag),
        .arch_rd        (rd),
        .is_branch_in   (is_branch),
        .is_lsu_in      (is_lsu),
        .dispatch_idx   (dispatch_idx),
        .dispatch_ready (~(is_alu | is_branch | (is_lsu & ~is_store))),  // Stores are born-ready (no CDB needed)
        .rob_full       (rob_full),
        .complete_en    (complete_en),
        .complete_idx   (complete_idx),
        .complete_data  (complete_value),
        .commit_en_in   (commit_en),
        .head_ready     (head_ready),
        .head_phys      (head_dest_phys),
        .head_old_phys  (head_old_phys),
        .head_data      (head_value),
        .head_arch_rd   (head_arch_rd),
        .head_is_branch (head_is_branch),
        .head_is_lsu    (head_is_lsu)
    );

    // -----------------------------------------------------------
    // RS 1: ALU
    // -----------------------------------------------------------
    reservation_station #(
        .RS_SIZE       (RS_SIZE),
        .DATA_WIDTH    (DATA_WIDTH),
        .TAG_WIDTH     (TAG_WIDTH),
        .ROB_IDX_WIDTH (ROB_IDX_WIDTH)
    ) rs_alu(
        .clk              (clk),
        .rst              (rst),
        .flush            (flush),

        .dispatch_en      (alu_dispatch_en),
        .instr_opcode     (instr_opcode),
        .funct3           (funct3),
        .funct7_5         (funct7_5),
        .pc               (32'b0),
        .imm              (32'b0),
        .arch_rd          (5'b0),

        .src1_value       (src1_value),
        .src2_value       (dispatch_src2_value),
        .src1_ready       (src1_ready),
        .src2_ready       (dispatch_src2_ready),
        .src1_tag         (src1_tag),
        .src2_tag         (src2_tag),
        .dest_phys_tag    (dest_tag),
        .rob_idx          (dispatch_idx),

        .wb_en            (wb_en),
        .wb_tag           (wb_tag),
        .wb_data          (wb_data),

        .issue_grant      (alu_issue_grant),
        .issue_idx        (alu_issue_idx),

        .entry_busy       (alu_entry_busy),
        .entry_ready      (alu_entry_ready),

        .issue_src1_value (alu_issue_src1_value),
        .issue_src2_value (alu_issue_src2_value),
        .issue_dest_phys_tag(alu_issue_dest_phys_tag),
        .issue_rob_idx    (alu_issue_rob_idx),
        
        .issue_instr_opcode(alu_issue_instr_opcode),
        .issue_funct3     (alu_issue_funct3),
        .issue_funct7_5   (alu_issue_funct7_5),
        .issue_pc         (),
        .issue_imm        (),
        .issue_arch_rd    ()
    );

    // -----------------------------------------------------------
    // RS 2: Branch
    // -----------------------------------------------------------
    reservation_station #(
        .RS_SIZE       (RS_SIZE),
        .DATA_WIDTH    (DATA_WIDTH),
        .TAG_WIDTH     (TAG_WIDTH),
        .ROB_IDX_WIDTH (ROB_IDX_WIDTH)
    ) rs_branch(
        .clk              (clk),
        .rst              (rst),
        .flush            (flush),

        .dispatch_en      (branch_dispatch_en),
        .instr_opcode     (instr_opcode),
        .funct3           (funct3),
        .funct7_5         (funct7_5),
        .pc               (pc),
        .imm              (imm),
        .arch_rd          (rd),

        .src1_value       (src1_value),
        .src2_value       (dispatch_src2_value),
        .src1_ready       (src1_ready),
        .src2_ready       (dispatch_src2_ready),
        .src1_tag         (src1_tag),
        .src2_tag         (src2_tag),
        .dest_phys_tag    (dest_tag),
        .rob_idx          (dispatch_idx),

        .wb_en            (wb_en),
        .wb_tag           (wb_tag),
        .wb_data          (wb_data),

        .issue_grant      (branch_issue_grant),
        .issue_idx        (branch_issue_idx),

        .entry_busy       (branch_entry_busy),
        .entry_ready      (branch_entry_ready),

        .issue_src1_value (branch_issue_src1_value),
        .issue_src2_value (branch_issue_src2_value),
        .issue_dest_phys_tag(branch_issue_dest_phys_tag),
        .issue_rob_idx    (branch_issue_rob_idx),

        .issue_instr_opcode(branch_issue_instr_opcode),
        .issue_funct3     (branch_issue_funct3),
        .issue_funct7_5   (),
        .issue_pc         (branch_issue_pc),
        .issue_imm        (branch_issue_imm),
        .issue_arch_rd    (branch_issue_arch_rd)
    );

    // -----------------------------------------------------------
    // ISSUE SELECT: Independent for ALU and Branch
    // -----------------------------------------------------------
    issue_select #(
        .RS_SIZE (RS_SIZE)
    ) issue_select_alu(
        .entry_ready (alu_entry_ready),
        .issue_valid (alu_issue_valid),
        .issue_idx   (alu_issue_idx)
    );

    issue_select #(
        .RS_SIZE (RS_SIZE)
    ) issue_select_branch(
        .entry_ready (branch_entry_ready),
        .issue_valid (branch_issue_valid),
        .issue_idx   (branch_issue_idx)
    );

    // -----------------------------------------------------------
    // EXECUTE: Handles both ALU and Branch issues. Absorbs CDB arbitration.
    // -----------------------------------------------------------
    execute #(
        .DATA_WIDTH    (DATA_WIDTH),
        .TAG_WIDTH     (TAG_WIDTH),
        .ROB_IDX_WIDTH (ROB_IDX_WIDTH)
    ) execute_inst(
        .clk                 (clk),
        .rst                 (rst),
        .flush               (flush),

        // ALU RS Packet
        .alu_issue_valid         (alu_issue_valid),
        .alu_issue_instr_opcode  (alu_issue_instr_opcode),
        .alu_issue_funct3        (alu_issue_funct3),
        .alu_issue_funct7_5      (alu_issue_funct7_5),
        .alu_issue_src1_value    (alu_issue_src1_value),
        .alu_issue_src2_value    (alu_issue_src2_value),
        .alu_issue_dest_phys_tag (alu_issue_dest_phys_tag),
        .alu_issue_rob_idx       (alu_issue_rob_idx),

        // Branch RS Packet
        .branch_issue_valid         (branch_issue_valid),
        .branch_issue_instr_opcode  (branch_issue_instr_opcode),
        .branch_issue_funct3        (branch_issue_funct3),
        .branch_issue_pc            (branch_issue_pc),
        .branch_issue_imm           (branch_issue_imm),
        .branch_issue_arch_rd       (branch_issue_arch_rd),
        .branch_issue_src1_value    (branch_issue_src1_value),
        .branch_issue_src2_value    (branch_issue_src2_value),
        .branch_issue_dest_phys_tag (branch_issue_dest_phys_tag),
        .branch_issue_rob_idx       (branch_issue_rob_idx),

        // LSQ CDB Packet
        .lsq_cdb_req         (lsq_cdb_req),
        .lsq_cdb_tag         (lsq_cdb_tag),
        .lsq_cdb_data        (lsq_cdb_data),
        .lsq_cdb_rob_idx     (lsq_cdb_rob_idx),
        .lsq_cdb_grant       (lsq_cdb_grant),

        // Busy signals to stall respective issues
        .alu_exec_busy       (alu_exec_busy),
        .branch_exec_busy    (branch_exec_busy),

        // Writeback + complete
        .wb_en               (wb_en),
        .wb_tag              (wb_tag),
        .wb_data             (wb_data),
        .complete_en         (complete_en),
        .complete_idx        (complete_idx),
        .complete_value      (complete_value),

        // Branch resolution
        .branch_taken        (branch_taken),
        .branch_target_pc    (branch_target_pc),

        // JAL/JALR ARF direct write
        .jal_wr_en           (jal_wr_en),
        .jal_arch_rd         (jal_arch_rd),
        .jal_wr_data         (jal_wr_data)
    );

    // -----------------------------------------------------------
    // COMMIT: fires when the ROB head is ready
    // -----------------------------------------------------------
    wire head_ready_gated = head_ready & (~head_is_lsu | lsq_head_ready);

    commit #(
        .TAG_WIDTH (TAG_WIDTH)
    ) commit_inst(
        .head_ready   (head_ready_gated),
        .head_old_phys(head_old_phys),
        .commit_en    (commit_en),
        .free_en      (free_en),
        .free_tag     (free_tag)
    );

    // -----------------------------------------------------------
    // ARF: Architectural Register File
    // -----------------------------------------------------------
    arf #(
        .ARCH_REGS (ARCH_REGS),
        .DATA_WIDTH(DATA_WIDTH)
    ) arf_inst(
        .clk         (clk),
        .rst         (rst),
        .rs1         (rs1),
        .rs2         (rs2),
        .arf_src1_data(),
        .arf_src2_data(),
        .arf_wr_en   (arf_wr_en),
        .arf_wr_addr (arf_wr_addr),
        .arf_wr_data (arf_wr_data)
    );

    // -----------------------------------------------------------
    // LSQ and Data Memory
    // -----------------------------------------------------------
    try_lsq #(
        .LSQ_SIZE       (RS_SIZE),
        .DATA_WIDTH     (DATA_WIDTH),
        .TAG_WIDTH      (TAG_WIDTH),
        .ROB_IDX_WIDTH  (ROB_IDX_WIDTH)
    ) lsq_inst(
        .clk                 (clk),
        .rst                 (rst),
        .flush               (flush),

        .dispatch_en         (lsq_dispatch_en),
        .dispatch_is_store   (is_store),
        .dispatch_src1_data  (src1_value),
        .dispatch_src2_data  (src2_value),
        .dispatch_src1_ready (src1_ready),
        .dispatch_src2_ready (src2_ready),
        .dispatch_src1_tag   (src1_tag),
        .dispatch_src2_tag   (src2_tag),
        .dispatch_imm        (imm),
        .dispatch_dest_tag   (dest_tag),
        .dispatch_rob_idx    (dispatch_idx),

        .lsq_full            (lsq_full),
        .lsq_head_ready      (lsq_head_ready),

        .wb_en               (wb_en),
        .wb_tag              (wb_tag),
        .wb_data             (wb_data),

        .cdb_req             (lsq_cdb_req),
        .cdb_tag             (lsq_cdb_tag),
        .cdb_data            (lsq_cdb_data),
        .cdb_rob_idx         (lsq_cdb_rob_idx),
        .cdb_grant           (lsq_cdb_grant),

        .dmem_rd_en          (dmem_rd_en),
        .dmem_rd_addr        (dmem_rd_addr),
        .dmem_rd_data        (dmem_rd_data),

        .commit_pop          (commit_pop),
        .dmem_wr_en          (dmem_wr_en),
        .dmem_wr_addr        (dmem_wr_addr),
        .dmem_wr_data        (dmem_wr_data)
    );

    dmem #(
        .DATA_WIDTH (DATA_WIDTH)
    ) dmem_inst(
        .clk        (clk),
        
        .read_en    (dmem_rd_en),
        .read_addr  (dmem_rd_addr),
        .read_data  (dmem_rd_data),

        .write_en   (dmem_wr_en),
        .write_addr (dmem_wr_addr),
        .write_data (dmem_wr_data)
    );

endmodule