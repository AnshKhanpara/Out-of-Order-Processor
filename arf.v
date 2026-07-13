module arf #(
    parameter ARCH_REGS  = 32,
    parameter DATA_WIDTH = 32
)(
    input clk, rst,

    input [4:0]          rs1,
    input [4:0]          rs2,
    output [DATA_WIDTH-1:0] arf_src1_data,
    output [DATA_WIDTH-1:0] arf_src2_data,

    input                arf_wr_en,
    input [4:0]          arf_wr_addr,
    input [DATA_WIDTH-1:0] arf_wr_data
);

reg [DATA_WIDTH-1:0] regs [0:ARCH_REGS-1];

assign arf_src1_data = regs[rs1];
assign arf_src2_data = regs[rs2];

integer i;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < ARCH_REGS; i = i + 1)
            regs[i] <= 0;
    end else begin
        if (arf_wr_en && arf_wr_addr != 5'd0)
            regs[arf_wr_addr] <= arf_wr_data;
    end
end

endmodule