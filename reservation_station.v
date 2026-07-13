// =============================================================
// reservation_station.v
// -------------------------------------------------------------
// Fields: instr_opcode, funct3, funct7_5, pc, imm, arch_rd
//         src1/src2 values+tags+ready, dest_phys_tag, rob_idx
// =============================================================

module reservation_station #(
    parameter RS_SIZE       = 8,
    parameter DATA_WIDTH    = 32,
    parameter TAG_WIDTH     = 6,
    parameter ROB_IDX_WIDTH = 4
)(
    input clk,
    input rst,
    input flush,

    //-------------- dispatch --------------
    input dispatch_en,

    // Instruction fields
    input [6:0]            instr_opcode,
    input [2:0]            funct3,
    input                  funct7_5,
    input [DATA_WIDTH-1:0] pc,
    input [DATA_WIDTH-1:0] imm,
    input [4:0]            arch_rd,       

    input [DATA_WIDTH-1:0] src1_value,
    input [DATA_WIDTH-1:0] src2_value,

    input src1_ready,
    input src2_ready,

    input [TAG_WIDTH-1:0] src1_tag,
    input [TAG_WIDTH-1:0] src2_tag,

    input [TAG_WIDTH-1:0]     dest_phys_tag,
    input [ROB_IDX_WIDTH-1:0] rob_idx,

    //-------------- CDB writeback ----------
    input                     wb_en,
    input [TAG_WIDTH-1:0]     wb_tag,
    input [DATA_WIDTH-1:0]    wb_data,

    //-------------- issue ------------------
    input        issue_grant,
    input [2:0]  issue_idx,

    //-------------- status outputs ---------
    output [RS_SIZE-1:0] entry_busy,
    output [RS_SIZE-1:0] entry_ready,

    //-------------- issue packet -----------
    output [DATA_WIDTH-1:0]    issue_src1_value,
    output [DATA_WIDTH-1:0]    issue_src2_value,
    output [TAG_WIDTH-1:0]     issue_dest_phys_tag,
    output [ROB_IDX_WIDTH-1:0] issue_rob_idx,

    output [6:0]               issue_instr_opcode,
    output [2:0]               issue_funct3,
    output                     issue_funct7_5,
    output [DATA_WIDTH-1:0]    issue_pc,
    output [DATA_WIDTH-1:0]    issue_imm,
    output [4:0]               issue_arch_rd
);

// -------------- internal storage ---------------------
reg [RS_SIZE-1:0] busy;
reg [RS_SIZE-1:0] src1_ready_arr;
reg [RS_SIZE-1:0] src2_ready_arr;

reg [DATA_WIDTH-1:0] src1_value_arr  [0:RS_SIZE-1];
reg [DATA_WIDTH-1:0] src2_value_arr  [0:RS_SIZE-1];
reg [TAG_WIDTH-1:0]  src1_wait_tag_arr [0:RS_SIZE-1];
reg [TAG_WIDTH-1:0]  src2_wait_tag_arr [0:RS_SIZE-1];
reg [TAG_WIDTH-1:0]  dest_phys_tag_arr [0:RS_SIZE-1];
reg [ROB_IDX_WIDTH-1:0] rob_idx_arr  [0:RS_SIZE-1];

reg [6:0]            instr_opcode_arr [0:RS_SIZE-1];
reg [2:0]            funct3_arr       [0:RS_SIZE-1];
reg                  funct7_5_arr     [0:RS_SIZE-1];
reg [DATA_WIDTH-1:0] pc_arr           [0:RS_SIZE-1];
reg [DATA_WIDTH-1:0] imm_arr          [0:RS_SIZE-1];
reg [4:0]            arch_rd_arr      [0:RS_SIZE-1];

// -------------- combinational outputs ----------------
assign entry_busy  = busy;
assign entry_ready = busy & src1_ready_arr & src2_ready_arr;

assign issue_src1_value     = src1_value_arr[issue_idx];
assign issue_src2_value     = src2_value_arr[issue_idx];
assign issue_dest_phys_tag  = dest_phys_tag_arr[issue_idx];
assign issue_rob_idx        = rob_idx_arr[issue_idx];

assign issue_instr_opcode   = instr_opcode_arr[issue_idx];
assign issue_funct3         = funct3_arr[issue_idx];
assign issue_funct7_5       = funct7_5_arr[issue_idx];
assign issue_pc             = pc_arr[issue_idx];
assign issue_imm            = imm_arr[issue_idx];
assign issue_arch_rd        = arch_rd_arr[issue_idx];

// -------------- free slot priority encoder -----------
integer i;
reg found_slot;
reg [2:0] free_slot;

always @(*) begin
    found_slot = 1'b0;
    free_slot  = 3'b000;
    for (i = 0; i < RS_SIZE; i = i + 1) begin
        if (!busy[i] && !found_slot) begin
            found_slot = 1'b1;
            free_slot  = i[2:0];
        end
    end
end

// -------------- bypass wires -----------------
wire dispatch_src1_match = wb_en && !src1_ready && (src1_tag == wb_tag);
wire dispatch_src2_match = wb_en && !src2_ready && (src2_tag == wb_tag);

wire [DATA_WIDTH-1:0] dispatch_src1_val   = dispatch_src1_match ? wb_data : src1_value;
wire [DATA_WIDTH-1:0] dispatch_src2_val   = dispatch_src2_match ? wb_data : src2_value;
wire                  dispatch_src1_ready = src1_ready | dispatch_src1_match;
wire                  dispatch_src2_ready = src2_ready | dispatch_src2_match;

// -------------- sequential logic ---------------------
always @(posedge clk or posedge rst) begin
    if (rst || flush) begin
        busy           <= 0;
        src1_ready_arr <= 0;
        src2_ready_arr <= 0;
        for (i = 0; i < RS_SIZE; i = i + 1) begin
            src1_value_arr[i]    <= 0;
            src2_value_arr[i]    <= 0;
            src1_wait_tag_arr[i] <= 0;
            src2_wait_tag_arr[i] <= 0;
            dest_phys_tag_arr[i] <= 0;
            rob_idx_arr[i]       <= 0;
            instr_opcode_arr[i]  <= 0;
            funct3_arr[i]        <= 0;
            funct7_5_arr[i]      <= 0;
            pc_arr[i]            <= 0;
            imm_arr[i]           <= 0;
            arch_rd_arr[i]       <= 0;
        end
    end
    else begin

        // -------- wakeup: broadcast CDB to existing entries --------
        if (wb_en) begin
            for (i = 0; i < RS_SIZE; i = i + 1) begin
                if (busy[i]) begin
                    if (!src1_ready_arr[i] && src1_wait_tag_arr[i] == wb_tag) begin
                        src1_value_arr[i] <= wb_data;
                        src1_ready_arr[i] <= 1'b1;
                    end
                    if (!src2_ready_arr[i] && src2_wait_tag_arr[i] == wb_tag) begin
                        src2_value_arr[i] <= wb_data;
                        src2_ready_arr[i] <= 1'b1;
                    end
                end
            end
        end

        // -------- clear issued slot --------------------------------
        if (issue_grant)
            busy[issue_idx] <= 1'b0;

        // -------- dispatch new instruction -------------------------
        if (dispatch_en && found_slot) begin
            busy[free_slot]              <= 1'b1;
            src1_value_arr[free_slot]    <= dispatch_src1_val;
            src2_value_arr[free_slot]    <= dispatch_src2_val;
            src1_ready_arr[free_slot]    <= dispatch_src1_ready;
            src2_ready_arr[free_slot]    <= dispatch_src2_ready;
            src1_wait_tag_arr[free_slot] <= src1_tag;
            src2_wait_tag_arr[free_slot] <= src2_tag;
            dest_phys_tag_arr[free_slot] <= dest_phys_tag;
            rob_idx_arr[free_slot]       <= rob_idx;
            
            instr_opcode_arr[free_slot]  <= instr_opcode;
            funct3_arr[free_slot]        <= funct3;
            funct7_5_arr[free_slot]      <= funct7_5;
            pc_arr[free_slot]            <= pc;
            imm_arr[free_slot]           <= imm;
            arch_rd_arr[free_slot]       <= arch_rd;
        end

    end
end

endmodule