# 🚀 Out-of-Order RISC-V CPU (Tomasulo)

A **single-issue Out-of-Order (OoO) RISC-V processor** implemented in **Verilog**, based on **Tomasulo's algorithm**. The processor supports dynamic scheduling, register renaming, speculative execution, and in-order commit using a Reorder Buffer (ROB).

This project was developed from scratch as an educational implementation of modern CPU microarchitecture concepts.

---

## Features

- RV32I subset implementation
- Single-issue out-of-order execution
- Tomasulo-based dynamic scheduling
- Register renaming using RAT and Physical Register File
- 16-entry Reorder Buffer (ROB)
- Reservation Stations for ALU and Branch instructions
- Branch Prediction (BTB + 2-bit Saturating Counter)
- Common Data Bus (CDB) for result broadcast
- Load/Store Queue (LSQ)
- Precise exceptions through in-order commit
- Pipeline flush and recovery on branch misprediction

---

## Processor Pipeline

```
Fetch
   │
Decode
   │
Rename / Dispatch
   │
Issue
   │
Execute
   │
Writeback
   │
Commit
```

---

## Microarchitecture

```
                +-------------+
                |    Fetch    |
                +------+------+
                       |
                +------+------+
                |   Decode    |
                +------+------+
                       |
                +------+------+
                | Rename/ROB  |
                +------+------+
                       |
          +------------+-------------+
          |                          |
   +------+-------+          +-------+------+
   |  ALU RS       |          | Branch RS    |
   +------+-------+          +-------+------+
          |                          |
      +---+---+                  +---+---+
      |  ALU  |                  |Branch |
      +---+---+                  +---+---+
           \                      /
            \                    /
             +--------+---------+
                      |
                Common Data Bus
                      |
                +-----+------+
                |    ROB     |
                +-----+------+
                      |
                  Commit Stage
```

---

## Supported Instructions

### R-Type

- ADD
- SUB
- AND
- OR
- XOR
- SLL
- SRL
- SRA
- SLT
- SLTU

### I-Type

- ADDI

### Branch Instructions

- BEQ
- BNE
- BLT
- BGE
- BLTU
- BGEU

### Jump Instructions

- JAL
- JALR

---

## Project Structure

```
.
├── cpu.v
├── fetch.v
├── decode.v
├── rat.v
├── free_list.v
├── prf.v
├── arf.v
├── reservation_station.v
├── issue_select.v
├── execute.v
├── alu.v
├── branch_fn.v
├── rob.v
├── lsq.v
├── bpu.v
├── commit.v
├── dmem.v
├── program.mem
├── tb_cpu.v
└── README.md
```

---

## Simulation

### Requirements

- Icarus Verilog
- GTKWave (Optional)

### Run Simulation

```bash
iverilog -o cpu_sim *.v
vvp cpu_sim
gtkwave dump.vcd
```

---

## Configuration

| Parameter | Value |
|-----------|------:|
| Data Width | 32-bit |
| Physical Registers | 64 |
| Architectural Registers | 32 |
| ROB Entries | 16 |
| Reservation Station Entries | 8 |
| Branch Predictor | BTB + 2-bit Saturating Counter |

---

## Future Improvements

- Multi-issue (Superscalar) execution
- Instruction and Data Cache
- Return Address Stack (RAS)
- Tournament Branch Predictor
- FPGA implementation
- ASIC synthesis support

---

## License

This project is released for academic and educational purposes.

---

## Acknowledgements

This project is inspired by the **Tomasulo Algorithm** and modern out-of-order processor microarchitectures used in contemporary RISC-V and x86 processors.
