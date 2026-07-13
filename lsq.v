module try_lsq#(
    parameter DATA_WIDTH    = 32,
    parameter PHYS_REGS     = 64,
    parameter ARCH_REGS     = 32,
    parameter TAG_WIDTH     = 6,
    parameter ROB_DEPTH     = 16,
    parameter ROB_IDX_WIDTH = 4,
    parameter LSQ_SIZE      = 8,
    parameter RS_DEPTH      = 8
)(
    input clk,
    input rst,
    input flush,

    input dispatch_en,

    // signals from decoder 
    input                       dispatch_is_store,
    input      [DATA_WIDTH-1:0] dispatch_src1_data,
    input      [DATA_WIDTH-1:0] dispatch_src2_data,
    input                       dispatch_src1_ready,
    input                       dispatch_src2_ready,
    input      [TAG_WIDTH-1:0]  dispatch_src1_tag,
    input      [TAG_WIDTH-1:0]  dispatch_src2_tag,
    input      [DATA_WIDTH-1:0] dispatch_imm,
    input      [TAG_WIDTH-1:0]  dispatch_dest_tag,
    input   [ROB_IDX_WIDTH-1:0] dispatch_rob_idx,

    // signal from ROB for letting us know that store instr in being committed
    input commit_pop,

    // signlas form wb 

    input wb_en,
    input [TAG_WIDTH - 1:0] wb_tag,
    input [DATA_WIDTH - 1:0] wb_data,
    
    output lsq_full,
    output lsq_head_ready,

    // CDB Arbiter Interface
    output                      cdb_req,
    output      [TAG_WIDTH-1:0] cdb_tag,
    output     [DATA_WIDTH-1:0] cdb_data,
    output  [ROB_IDX_WIDTH-1:0] cdb_rob_idx,
    input                       cdb_grant,

    // Data Memory Interface (Read for Loads)
    output                      dmem_rd_en,
    output     [DATA_WIDTH-1:0] dmem_rd_addr,
    input      [DATA_WIDTH-1:0] dmem_rd_data,

    // Data Memory Interface (Write for Store Commits)
    output                      dmem_wr_en,
    output     [DATA_WIDTH-1:0] dmem_wr_addr,
    output     [DATA_WIDTH-1:0] dmem_wr_data
);

// internal tabel of arrays 

// some vectors 
reg [LSQ_SIZE - 1:0] valid;
reg [LSQ_SIZE - 1:0] is_store_arr;
reg [LSQ_SIZE - 1:0] src1_ready_arr;
reg [LSQ_SIZE - 1:0] src2_ready_arr;
reg [LSQ_SIZE - 1:0] completed;

// some arrays
// reg [DATA_WIDTH - 1:0] dispatch_is_store_arr [0:LSQ_SIZE - 1];
reg [DATA_WIDTH - 1:0] dispatch_src1_data_arr [0:LSQ_SIZE - 1];
reg [DATA_WIDTH - 1:0] dispatch_src2_data_arr [0:LSQ_SIZE - 1];
reg [TAG_WIDTH - 1:0]  dispatch_src1_tag_arr [0:LSQ_SIZE - 1];
reg [TAG_WIDTH - 1:0]  dispatch_src2_tag_arr [0:LSQ_SIZE - 1];
reg [DATA_WIDTH - 1:0] dispatch_imm_arr [0:LSQ_SIZE - 1];
reg [TAG_WIDTH - 1:0]  dispatch_dest_tag_arr [0:LSQ_SIZE - 1];
reg [ROB_IDX_WIDTH - 1:0] dispatch_rob_idx_arr [0:LSQ_SIZE - 1];


localparam LSQ_WIDTH = 3;

reg [LSQ_WIDTH - 1:0] head,tail;
reg [LSQ_WIDTH : 0] count;

// comb logic
assign lsq_full = (count == LSQ_SIZE);

wire [DATA_WIDTH - 1:0] addr [0:LSQ_SIZE - 1];
wire addr_ready [0:LSQ_SIZE-1];

genvar j;

generate
    for(j=0; j<LSQ_SIZE;j=j+1)
    begin : genrate_address
        assign addr_ready[j] = valid[j] & src1_ready_arr[j];
        assign addr[j] = dispatch_src1_data_arr[j] + dispatch_imm_arr[j]; 
    end 
endgenerate

integer i;
// seq logic
always @(posedge clk or posedge rst)
begin 
    if(rst)
    begin
        valid <= 0;
        is_store_arr <= 0;
        src1_ready_arr <= 0;
        src2_ready_arr <= 0;
        completed <= 0;

        for (i = 0; i < LSQ_SIZE; i = i + 1) 
        begin 
            dispatch_src1_data_arr[i]   <= 32'b0;
            dispatch_src2_data_arr[i]   <= 32'b0;
            dispatch_src1_tag_arr[i]    <= 4'b0;
            dispatch_src2_tag_arr[i]    <= 4'b0;
            dispatch_imm_arr[i]         <= 32'b0;
            dispatch_dest_tag_arr[i]    <= 4'b0;
            dispatch_rob_idx_arr[i]     <= 4'b0;
        end
        
        head <= 0;
        tail <= 0;
        count <= 0;
    end
    else if (flush)
    begin
        valid <= 0;
        is_store_arr <= 0;
        src1_ready_arr <= 0;
        src2_ready_arr <= 0;
        completed <= 0;
        
        head <= 0;
        tail <= 0;
        count <= 0;
    end
    else 
    begin 

        for(i=0;i<LSQ_SIZE;i = i + 1)
        begin 
            if(valid[i])
            begin 
                if(wb_en && !src1_ready_arr[i] && dispatch_src1_tag_arr[i] == wb_tag)
                begin 
                    src1_ready_arr[i] <= 1'b1;
                    dispatch_src1_data_arr[i] <= wb_data;
                end

                if(wb_en && !src2_ready_arr[i] && dispatch_src2_tag_arr[i] == wb_tag)
                begin 
                    src2_ready_arr[i] <= 1'b1;
                    dispatch_src2_data_arr[i] <= wb_data;
                end
            end
        end

        if (cdb_req && cdb_grant) begin
            completed[issue_idx] <= 1'b1;
        end

        if (dispatch_en && !lsq_full) 
        begin 
            valid[tail] <= 1'b1;
            is_store_arr[tail] <= dispatch_is_store;
            completed[tail] <= 1'b0;

            // Same-cycle CDB forwarding for src1
            if (wb_en && !dispatch_src1_ready && dispatch_src1_tag == wb_tag) begin
                src1_ready_arr[tail] <= 1'b1;
                dispatch_src1_data_arr[tail] <= wb_data;
            end else begin
                src1_ready_arr[tail] <= dispatch_src1_ready;
                dispatch_src1_data_arr[tail] <= dispatch_src1_data;
            end

            // Same-cycle CDB forwarding for src2
            if (wb_en && !dispatch_src2_ready && dispatch_src2_tag == wb_tag) begin
                src2_ready_arr[tail] <= 1'b1;
                dispatch_src2_data_arr[tail] <= wb_data;
            end else begin
                src2_ready_arr[tail] <= dispatch_src2_ready;
                dispatch_src2_data_arr[tail] <= dispatch_src2_data;
            end

            dispatch_src1_tag_arr[tail] <= dispatch_src1_tag;
            dispatch_src2_tag_arr[tail] <= dispatch_src2_tag;
            dispatch_imm_arr[tail] <= dispatch_imm;
            dispatch_dest_tag_arr[tail] <= dispatch_dest_tag;
            dispatch_rob_idx_arr[tail] <= dispatch_rob_idx;

            tail <= tail + 1;
        end

        if (commit_pop && count > 0) 
        begin
            valid[head] <= 0;
            completed[head] <= 1'b0;
            head <= head + 1; 
        end

        case({(dispatch_en && !lsq_full),(commit_pop && count > 0)})
            2'b10:  count <= count + 1;    
            2'b01:  count <= count - 1;
            default: count <= count;
        endcase
    end
end


// we need to mkae logic on frowarding of the lw if it matches the address in sw queue
// and it should be combinational logic 

reg [LSQ_SIZE-1:0] load_can_issue;
reg [LSQ_SIZE-1:0] load_do_forward;
reg [DATA_WIDTH-1:0] load_forward_data [0:LSQ_SIZE-1];

integer k;

reg issue_ok;
reg match_found;
reg match_src2_ready;
reg [DATA_WIDTH-1:0] match_src2_data;
reg [LSQ_WIDTH - 1:0] age_i;
reg [LSQ_WIDTH - 1:0] age_k;

always @(*) 
begin 
    for(i=0; i<LSQ_SIZE; i=i+1)
    begin 
        load_can_issue[i] = 1'b0;
        load_do_forward[i] = 1'b0;

        if(valid[i] && !is_store_arr[i] && addr_ready[i] && !completed[i])
        begin 
            issue_ok = 1'b1;
            match_found = 1'b0;
            match_src2_ready = 1'b0;
            match_src2_data = 32'b0;

            for(k=0; k<LSQ_SIZE; k=k+1)
            begin 
                if(valid[k] && is_store_arr[k])
                begin
                    age_i = i[LSQ_WIDTH - 1:0] - head;
                    age_k = k[LSQ_WIDTH - 1:0] - head;
                    
                    if(age_k < age_i)
                    begin 
                        if(addr_ready[k] == 0)
                        begin 
                            issue_ok = 1'b0;
                        end
                        else if(addr[k] == addr[i])
                        begin 
                            match_found = 1'b1;
                            match_src2_ready = src2_ready_arr[k];
                            match_src2_data = dispatch_src2_data_arr[k];
                        end
                    end
                end
            end

            if(match_found)
            begin 
                if(!match_src2_ready)
                begin 
                    issue_ok = 1'b0;
                end
                else
                begin
                    load_do_forward[i] = 1'b1;
                    load_forward_data[i] = match_src2_data;
                end
            end

            load_can_issue[i] = issue_ok;
        end
    end
end

// =========================================================
// Step 5: Issue Selection & Outputs
// =========================================================
reg issue_req;
reg [LSQ_WIDTH-1:0] issue_idx;
integer curr_age;
reg [LSQ_WIDTH-1:0] curr_idx;

always @(*) 
begin
    issue_req = 1'b0;
    issue_idx = 0;
    
    for (curr_age = 0; curr_age < LSQ_SIZE; curr_age = curr_age + 1) begin
        curr_idx = head + curr_age;
            
        if (!issue_req && valid[curr_idx]) begin
            // Only LOADS issue to the CDB. Stores commit via ROB.
            if (!is_store_arr[curr_idx] && load_can_issue[curr_idx]) begin
                issue_req = 1'b1;
                issue_idx = curr_idx;
            end
        end
    end
end


wire issue_is_store = is_store_arr[issue_idx];
wire issue_do_forward = load_do_forward[issue_idx];

// 1. Data Memory Read
assign dmem_rd_en   = issue_req & !issue_is_store & !issue_do_forward;
assign dmem_rd_addr = addr[issue_idx];

// 2. CDB Outputs
assign cdb_req      = issue_req;
assign cdb_tag      = dispatch_dest_tag_arr[issue_idx];
assign cdb_rob_idx  = dispatch_rob_idx_arr[issue_idx];
assign cdb_data     = issue_do_forward ? load_forward_data[issue_idx] : dmem_rd_data;

// 3. Commit Write (to dmem.v)
assign dmem_wr_en   = commit_pop & is_store_arr[head];
assign dmem_wr_addr = addr[head];
assign dmem_wr_data = dispatch_src2_data_arr[head];

// 4. Commit Readiness
assign lsq_head_ready = valid[head] ? (is_store_arr[head] ? (src1_ready_arr[head] & src2_ready_arr[head]) : completed[head]) : 1'b0;

endmodule