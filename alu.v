// =============================================================
// alu.v
// -------------------------------------------------------------
// Computes result based on standard 7-bit RISC-V opcode,
// funct3, and funct7[5].
// =============================================================

module alu(
    input  [6:0]  instr_opcode,
    input  [2:0]  funct3,
    input         funct7_5,
    input  [31:0] src1_value,
    input  [31:0] src2_value,

    output reg [31:0] result
);

wire is_r_type = (instr_opcode == 7'b0110011);
wire is_i_type = (instr_opcode == 7'b0010011);

always @(*) begin
    result = 32'b0;
    if (is_r_type || is_i_type) begin
        case (funct3)
            3'b000: result = (is_r_type && funct7_5) ? (src1_value - src2_value) : (src1_value + src2_value); // ADD/SUB
            3'b001: result = src1_value << src2_value[4:0];                                     // SLL
            3'b010: result = ($signed(src1_value) < $signed(src2_value)) ? 32'b1 : 32'b0;       // SLT
            3'b011: result = (src1_value < src2_value) ? 32'b1 : 32'b0;                         // SLTU
            3'b100: result = src1_value ^ src2_value;                                           // XOR
            3'b101: result = funct7_5 ? ($signed(src1_value) >>> src2_value[4:0]) : (src1_value >> src2_value[4:0]); // SRA/SRL
            3'b110: result = src1_value | src2_value;                                           // OR
            3'b111: result = src1_value & src2_value;                                           // AND
        endcase
    end
end

endmodule