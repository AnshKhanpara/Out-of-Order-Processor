// =============================================================
// tb_cpu.v  -  Comprehensive LSQ Stress Test & Verification
// -------------------------------------------------------------
// This testbench verifies:
//   1. LSQ gets full (stalling dispatch).
//   2. 2x Store-to-Load forwarding cases (x3, x4).
//   3. 2x Age-based dependence stalling cases (Load stalls on older store
//      with unknown address, and Load stalls on older store with known
//      address but unknown data).
//   4. 2+ Normal loads from committed memory (x5, x6, x7, x8).
//   5. Stores successfully commit to DMEM at ROB commit time.
// =============================================================

`timescale 1ns/1ps

module tb_cpu;

    parameter NUM_PROG_WORDS = 22;
    parameter ACTIVE_CYCLES  = 250;

    // -------------------------------------------------------
    // Clock and reset
    // -------------------------------------------------------
    reg clk;
    reg rst;

    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    cpu #(
        .PROG_WORDS(NUM_PROG_WORDS)
    ) dut (
        .clk (clk),
        .rst (rst)
    );

    // -------------------------------------------------------
    // Reset & Memory Initialization
    // -------------------------------------------------------
    initial begin
        rst = 1'b1;
        repeat(3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        $display("=== Reset released at time %0t ns ===", $time);

        // Preload Data Memory with initial reference values
        dut.dmem_inst.memory[0]   = 32'd80;   // Base offset read by LSU 1 (lw x10, 0(x0))
        dut.dmem_inst.memory[26]  = 32'd5555; // Normal Load 1 (lw x5, 8(x14)) -> 96 + 8 = 104 -> word 26
        dut.dmem_inst.memory[27]  = 32'd6666; // Normal Load 2 (lw x6, 12(x14)) -> 96 + 12 = 108 -> word 27
        dut.dmem_inst.memory[28]  = 32'd7777; // Normal Load 3 (lw x7, 16(x14)) -> 96 + 16 = 112 -> word 28
        dut.dmem_inst.memory[29]  = 32'd8888; // Normal Load 4 (lw x8, 20(x14)) -> 96 + 20 = 116 -> word 29
        dut.dmem_inst.memory[30]  = 32'd9999; // Normal Load 5 (lw x9, 24(x14)) -> 96 + 24 = 120 -> word 30
    end

    // -------------------------------------------------------
    // Performance & State Monitors
    // -------------------------------------------------------
    integer commit_count = 0;
    integer cycle = 0;
    reg lsq_had_full = 1'b0;

    always @(posedge clk) begin
        if (!rst) begin
            cycle = cycle + 1;

            if (dut.lsq_full) begin
                lsq_had_full <= 1'b1;
            end

            $display("---[ Cycle %0d | Time %0t ]---", cycle, $time);

            // Fetch & Decode
            $display("  FETCH/DECODE: PC=0x%04h  instr=0x%08h  is_lsu=%0b  is_store=%0b",
                     dut.pc, dut.instruction, dut.is_lsu, dut.is_store);

            // Dispatch
            $display("  DISPATCH:     en=%0b  lsq_en=%0b  rob_full=%0b  lsq_full=%0b",
                     dut.dispatch_en, dut.lsq_dispatch_en, dut.rob_full, dut.lsq_full);

            // LSQ status
            $display("  LSQ state:    head=%0d  tail=%0d  count=%0d  full=%0b  lsq_head_ready=%0b",
                     dut.lsq_inst.head, dut.lsq_inst.tail, dut.lsq_inst.count, dut.lsq_full, dut.lsq_head_ready);
            
            // CDB Arbiter
            $display("  CDB:          wb_en=%0b  wb_tag=p%0d  wb_data=%0d",
                     dut.wb_en, dut.wb_tag, $signed(dut.wb_data));

            // Commit
            if (dut.commit_en) begin
                $display("  COMMIT:       #%0d  dest_phys=p%0d  value=%0d  arch_rd=x%0d  is_lsu=%0b",
                         commit_count,
                         dut.head_dest_phys,
                         $signed(dut.head_value),
                         dut.head_arch_rd,
                         dut.head_is_lsu);
                commit_count = commit_count + 1;
            end

            // DMEM
            if (dut.dmem_wr_en)
                $display("  DMEM_WR:      addr=0x%04h  data=%0d", dut.dmem_wr_addr, $signed(dut.dmem_wr_data));

            $display("");
        end
    end

    // -------------------------------------------------------
    // Self-checking Verification
    // -------------------------------------------------------
    integer j;
    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        #((3 + ACTIVE_CYCLES) * 10 + 5);

        $display("=================================================");
        $display("  COMPREHENSIVE LSQ STRESS TEST RESULTS");
        $display("=================================================");
        $display("");

        // Print Architectural Register File state
        $display("  ARF (Architectural Register File) state:");
        for (j = 0; j < 32; j = j + 1) begin
            if (j == 1 || j == 2 || j == 3 || j == 4 || j == 5 || j == 6 || j == 7 || j == 8 || j == 9 || j == 10 || j == 14 || j == 15 || j == 18 || j == 19)
                $display("    x%0d = %0d", j, $signed(dut.arf_inst.regs[j]));
        end
        $display("");

        // 1. Verify LSQ got full
        if (lsq_had_full) begin
            $display("    [PASS] LSQ Full state was successfully reached!");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] LSQ Full state was never reached!");
            fail_count = fail_count + 1;
        end

        // 2. Verify Store-to-Load Forwarding (Case 1 & 2)
        if (dut.arf_inst.regs[3] == 32'd111) begin
            $display("    [PASS] x3 = 111 (Forwarding Case 1 from Store 1)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] x3 = %0d (expected 111) *** FORWARDING BUG ***", $signed(dut.arf_inst.regs[3]));
            fail_count = fail_count + 1;
        end

        if (dut.arf_inst.regs[4] == 32'd222) begin
            $display("    [PASS] x4 = 222 (Forwarding Case 2 from Store 2)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] x4 = %0d (expected 222) *** FORWARDING BUG ***", $signed(dut.arf_inst.regs[4]));
            fail_count = fail_count + 1;
        end

        // 3. Verify Store-to-Load Forwarding with Unready Data (Case 3 / Age dependence 2)
        if (dut.arf_inst.regs[18] == 32'd80) begin
            $display("    [PASS] x18 = 80 (Forwarding Case 3 with unready data/age dependency resolved correctly)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] x18 = %0d (expected 80) *** AGE DEP / DATA WAKEUP BUG ***", $signed(dut.arf_inst.regs[18]));
            fail_count = fail_count + 1;
        end

        // 4. Verify Normal Loads from memory
        if (dut.arf_inst.regs[5] == 32'd5555) begin
            $display("    [PASS] x5 = 5555 (Normal Load 1)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] x5 = %0d (expected 5555) *** NORMAL LOAD BUG ***", $signed(dut.arf_inst.regs[5]));
            fail_count = fail_count + 1;
        end

        if (dut.arf_inst.regs[6] == 32'd6666) begin
            $display("    [PASS] x6 = 6666 (Normal Load 2)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] x6 = %0d (expected 6666) *** NORMAL LOAD BUG ***", $signed(dut.arf_inst.regs[6]));
            fail_count = fail_count + 1;
        end

        if (dut.arf_inst.regs[7] == 32'd7777) begin
            $display("    [PASS] x7 = 7777 (Normal Load 3)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] x7 = %0d (expected 7777) *** NORMAL LOAD BUG ***", $signed(dut.arf_inst.regs[7]));
            fail_count = fail_count + 1;
        end

        if (dut.arf_inst.regs[8] == 32'd8888) begin
            $display("    [PASS] x8 = 8888 (Normal Load 4)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] x8 = %0d (expected 8888) *** NORMAL LOAD BUG ***", $signed(dut.arf_inst.regs[8]));
            fail_count = fail_count + 1;
        end

        if (dut.arf_inst.regs[9] == 32'd9999) begin
            $display("    [PASS] x9 = 9999 (Normal Load 5 after stall dispatch)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] x9 = %0d (expected 9999) *** STALL DISPATCH LOAD BUG ***", $signed(dut.arf_inst.regs[9]));
            fail_count = fail_count + 1;
        end

        // 5. Verify Stores committed to DMEM
        $display("");
        $display("  Data Memory state:");
        $display("    mem[0x14] (word index 20) = %0d (Store 3)", $signed(dut.dmem_inst.memory[20]));
        $display("    mem[0x18] (word index 24) = %0d (Store 1)", $signed(dut.dmem_inst.memory[24]));
        $display("    mem[0x19] (word index 25) = %0d (Store 2)", $signed(dut.dmem_inst.memory[25]));
        $display("");

        if (dut.dmem_inst.memory[20] == 32'd80) begin
            $display("    [PASS] mem[0x14] = 80 (Store 3 committed correctly)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] mem[0x14] = %0d (expected 80) *** COMMIT TO DMEM BUG ***", $signed(dut.dmem_inst.memory[20]));
            fail_count = fail_count + 1;
        end

        if (dut.dmem_inst.memory[24] == 32'd111) begin
            $display("    [PASS] mem[0x18] = 111 (Store 1 committed correctly)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] mem[0x18] = %0d (expected 111) *** COMMIT TO DMEM BUG ***", $signed(dut.dmem_inst.memory[24]));
            fail_count = fail_count + 1;
        end

        if (dut.dmem_inst.memory[25] == 32'd222) begin
            $display("    [PASS] mem[0x19] = 222 (Store 2 committed correctly)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] mem[0x19] = %0d (expected 222) *** COMMIT TO DMEM BUG ***", $signed(dut.dmem_inst.memory[25]));
            fail_count = fail_count + 1;
        end

        // 6. Verify ALU dependent result
        if (dut.arf_inst.regs[19] == 32'd121) begin
            $display("    [PASS] x19 = 121 (ALU instruction dependent on OoO load output)");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] x19 = %0d (expected 121) *** DEPENDENT ALU BUG ***", $signed(dut.arf_inst.regs[19]));
            fail_count = fail_count + 1;
        end

        $display("");
        $display("=================================================");
        if (fail_count == 0)
            $display("  ALL %0d TESTS PASSED!", pass_count);
        else
            $display("  %0d PASSED  %0d FAILED", pass_count, fail_count);
        $display("=================================================");

        $finish;
    end

    // -------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------
    initial begin
        $dumpfile("tb_cpu.vcd");
        $dumpvars(0, tb_cpu);
    end

endmodule