module decoder (
    input  [31:0] instruction,

    output [6:0]      instr_opcode,
    output [2:0]      funct3,
    output            funct7_5,

    output reg [4:0]  rs1,
    output reg [4:0]  rs2,
    output reg [4:0]  rd,

    output reg [31:0] imm,
    output reg        is_imm,

    output reg        is_alu,
    output reg        is_branch,
    output reg        is_lsu,
    output reg        is_store
);

wire [6:0] funct7;

assign instr_opcode = instruction[6:0];
assign funct3       = instruction[14:12];
assign funct7       = instruction[31:25];
assign funct7_5     = funct7[5];

always @(*) begin
    rs1       = instruction[19:15];
    rs2       = instruction[24:20];
    rd        = instruction[11:7];
    imm       = 32'b0;
    is_imm    = 1'b0;
    is_alu    = 1'b0;
    is_branch = 1'b0;
    is_lsu    = 1'b0;
    is_store  = 1'b0;

    case (instr_opcode)
        // R-Type
        7'b0110011: begin
            is_alu = 1'b1;
        end

        // I-Type ALU
        7'b0010011: begin
            is_alu = 1'b1;
            is_imm = 1'b1;
            rs2    = 5'b0;
            imm    = {{20{instruction[31]}}, instruction[31:20]};
        end

        // B-Type
        7'b1100011: begin
            is_branch = 1'b1;
            rd        = 5'b0;
            imm       = {{20{instruction[31]}}, instruction[7], instruction[30:25], instruction[11:8], 1'b0};
        end

        // JAL
        7'b1101111: begin
            is_branch = 1'b1;
            rs1       = 5'b0;
            rs2       = 5'b0;
            imm       = {{12{instruction[31]}}, instruction[19:12], instruction[20], instruction[30:21], 1'b0};
        end

        // JALR
        7'b1100111: begin
            is_branch = 1'b1;
            rs2       = 5'b0;
            imm       = {{20{instruction[31]}}, instruction[31:20]};
        end

        // Loads
        7'b0000011: begin
            is_lsu = 1'b1;
            is_imm = 1'b1;
            rs2    = 5'b0;
            imm    = {{20{instruction[31]}}, instruction[31:20]};
        end

        // Stores
        7'b0100011: begin
            is_lsu   = 1'b1;
            is_imm   = 1'b1;
            is_store = 1'b1;
            rd       = 5'b0;
            imm      = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
        end

        // LUI
        7'b0110111: begin
            is_alu = 1'b1;
            is_imm = 1'b1;
            rs1    = 5'b0;
            rs2    = 5'b0;
            imm    = {instruction[31:12], 12'b0};
        end

        // AUIPC
        7'b0010111: begin
            is_alu = 1'b1;
            is_imm = 1'b1;
            rs1    = 5'b0;
            rs2    = 5'b0;
            imm    = {instruction[31:12], 12'b0};
        end

        default: begin
            imm    = 32'b0;
            is_imm = 1'b0;
        end
    endcase
end

endmodule