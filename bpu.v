module bpu#(
    parameter DATA_WIDTH    = 32,
    parameter PHYS_REGS     = 64,
    parameter ARCH_REGS     = 32,
    parameter TAG_WIDTH     = 6,
    parameter ROB_DEPTH     = 16,
    parameter ROB_IDX_WIDTH = 4,
    parameter TABEL_SIZE    = 8,
    parameter RS_DEPTH      = 8
)(
    input clk,
    input rst,

    // 
    input [DATA_WIDTH - 1:0] fetch_pc,
    output pred_taken,
    output [DATA_WIDTH - 1:0] pred_target,

    // after exectution 
    input ex_branch,
    input ex_taken,
    input [DATA_WIDTH - 1:0] ex_actual_target,
    input [DATA_WIDTH - 1:0] ex_pc
);
localparam BTB_ENTRIES = 16;
localparam PHT_ENTRIES = 32;

// pht > bht 

localparam BTB_IDX = $clog2(BTB_ENTRIES);
localparam PHT_IDX = $clog2(PHT_ENTRIES);
localparam SN = 2'b00;  // Strongly Not Taken
localparam WN = 2'b01;  // Weakly   Not Taken
localparam WT = 2'b10;  // Weakly   Taken
localparam ST = 2'b11;  // Strongly Taken

// BTB -- branch target buffer
// internal tabel should look like 
// valid | tag | target

reg                    btb_valid  [0:BTB_ENTRIES-1];
reg [DATA_WIDTH - 1:0] btb_tag    [0:BTB_ENTRIES-1];
reg [DATA_WIDTH - 1:0] btb_target [0:BTB_ENTRIES-1];

// indexing for knowing - which row we are looking at

wire [BTB_IDX - 1:0] btb_read_idx  = fetch_pc[BTB_IDX + 1:2];
wire [BTB_IDX - 1:0] btb_write_idx = ex_pc[BTB_IDX + 1:2]; 
// we did +1 to 2 bcz last 2 bits of 
// pc are always 0 so we remove them 

wire btb_hit = btb_valid[btb_read_idx] && (btb_tag[btb_read_idx] == fetch_pc);

// pht -- pattern histrory tabel
reg [1:0] pht [0:PHT_ENTRIES-1];

wire [PHT_IDX - 1:0] pht_read_idx  = fetch_pc[PHT_IDX + 1:2];
wire [PHT_IDX - 1:0] pht_write_idx = ex_pc[PHT_IDX + 1:2]; 

wire [1:0] counter = pht[pht_read_idx];

assign pred_taken  = btb_hit && counter[1];
assign pred_target = btb_target[btb_read_idx];

integer i;
always @(posedge clk or posedge rst)
begin 
    if(rst)
    begin 
        for(i=0; i < BTB_ENTRIES; i = i + 1)
        begin 
            btb_valid[i]  <= 1'b0;
            btb_tag[i]    <= {DATA_WIDTH{1'b0}};
            btb_target[i] <= {DATA_WIDTH{1'b0}};
        end

        for(i=0; i < PHT_ENTRIES; i = i + 1)
        begin 
            pht[i] <= WN;
        end
    end
    else 
    begin 
        if(ex_branch)
        begin 
            case(pht[pht_write_idx])
                SN: pht[pht_write_idx] <= ex_taken ? WN : SN;
                WN: pht[pht_write_idx] <= ex_taken ? WT : SN;
                WT: pht[pht_write_idx] <= ex_taken ? ST : WN;
                ST: pht[pht_write_idx] <= ex_taken ? ST : WT;
            endcase

            if(ex_taken)
            begin 
                btb_valid[btb_write_idx]  <= 1'b1;
                btb_tag[btb_write_idx]    <= ex_pc;
                btb_target[btb_write_idx] <= ex_actual_target;
            end
        end
    end
end
endmodule