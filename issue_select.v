module issue_select #(
    parameter RS_SIZE = 8
)(
    input [RS_SIZE - 1:0] entry_ready,
    
    output reg issue_valid,
    output reg [2:0] issue_idx
);

integer i;
// This synthesizes into a priority encoder:
always @(*)
begin 
    
    issue_valid = 1'b0;
    issue_idx = 3'b000;
    
    for(i = 0; i < RS_SIZE; i = i + 1)
    begin 
        
        if(entry_ready[i] && !issue_valid)
        begin 
            issue_valid = 1'b1;
            issue_idx = i;
        end
    end 
end
endmodule