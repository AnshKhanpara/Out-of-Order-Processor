module rat #(
    parameter DATA_WIDTH = 32,
    parameter PHYS_REGS  = 64,
    parameter ARCH_REGS  = 32,
    parameter TAG_WIDTH  = 6
)(
    input clk, rst, flush,

    input [4:0] rs1, rs2, rd,

    input rename_en,
    input [TAG_WIDTH-1:0] alloc_tag,

    output [TAG_WIDTH-1:0] src1_tag,
    output [TAG_WIDTH-1:0] src2_tag,

    output src1_valid,
    output src2_valid,

    output [TAG_WIDTH-1:0] dest_tag,
    output [TAG_WIDTH-1:0] old_dest_tag
);

reg [TAG_WIDTH-1:0] rat   [0:31];
reg                 valid [0:31];

assign src1_tag   = rat[rs1];
assign src2_tag   = rat[rs2];
assign src1_valid = valid[rs1];
assign src2_valid = valid[rs2];
assign old_dest_tag = rat[rd];
assign dest_tag     = alloc_tag;

integer i;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < 32; i = i + 1) begin
            rat[i]   <= i;
            valid[i] <= 1'b0;
        end
    end else if (flush) begin
        for (i = 0; i < 32; i = i + 1) begin
            rat[i]   <= i[TAG_WIDTH-1:0];
            valid[i] <= 1'b0;
        end
    end else begin
        if (rename_en && (rd != 5'd0)) begin
            rat[rd]   <= alloc_tag;
            valid[rd] <= 1'b1;
        end
    end
end

endmodule