// =============================================================
// fetch.v  (with branch redirect support)
// -------------------------------------------------------------
// Manages the Program Counter (PC) register.
//
// On reset      : PC <- 0
// On flush      : PC <- branch_target_pc (redirect)
// On dispatch_en: PC <- PC + 4
// Otherwise     : hold PC (stall)
// =============================================================

module fetch(
    input  clk,
    input  rst,

    // Stall signal from cpu.v: hold PC when pipeline cannot accept
    input  dispatch_en,

    // Branch redirect
    input         flush,
    input  [31:0] branch_target_pc,

    // Current PC driven out to cpu.v for imem indexing
    output reg [31:0] pc
);

    always @(posedge clk or posedge rst) begin
        if (rst)
            pc <= 32'b0;
        else if (flush)
            pc <= branch_target_pc;   // redirect on taken branch
        else if (dispatch_en)
            pc <= pc + 32'd4;
        // else: hold PC (stall) - RS/ROB/freelist full
    end

endmodule
