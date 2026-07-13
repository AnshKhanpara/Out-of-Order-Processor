module commit #(
    parameter TAG_WIDTH = 6
)(
    input head_ready,
    input [TAG_WIDTH - 1:0] head_old_phys,

    output commit_en,

    output free_en,

    output [TAG_WIDTH - 1:0] free_tag

    
);

assign commit_en = head_ready;

assign free_en = head_ready;

assign free_tag = head_old_phys;
endmodule