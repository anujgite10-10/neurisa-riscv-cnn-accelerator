# NeurISA — ISA Extension Specification

## 1. Overview

NeurISA defines custom RISC-V instructions for CNN/ML inference acceleration, implemented as the NEORV32 `Xcfu` ISA extension. All instructions use the RISC-V reserved `custom-0` and `custom-1` opcode spaces.

## 2. Instruction Encoding

### 2.1 R-Type (custom-0, opcode = `0001011`)

```
 31       25 24   20 19   15 14  12 11    7 6      0
┌──────────┬───────┬───────┬──────┬───────┬────────┐
│  funct7  │  rs2  │  rs1  │funct3│  rd   │0001011 │
│  [6:0]   │ [4:0] │ [4:0] │[2:0] │ [4:0] │        │
└──────────┴───────┴───────┴──────┴───────┴────────┘
```

### 2.2 I-Type (custom-1, opcode = `0101011`)

```
 31              20 19   15 14  12 11    7 6      0
┌─────────────────┬───────┬──────┬───────┬────────┐
│     imm[11:0]   │  rs1  │funct3│  rd   │0101011 │
│                 │ [4:0] │[2:0] │ [4:0] │        │
└─────────────────┴───────┴──────┴───────┴────────┘
```

## 3. R-Type Instructions

### 3.1 VMAC — Vector Multiply-Accumulate
- **funct3**: `000`, **funct7**: `0000000`
- **Operation**: `rd = Σ(rs1[i] * rs2[i])` for i=0..3 (INT8 packed)
- **Latency**: 2 cycles (pipelined)
- **Description**: Performs 4 parallel INT8 multiplications on packed bytes, then sums all products into a 32-bit result.

### 3.2 VDOT — Vector Dot Product with Accumulate
- **funct3**: `001`, **funct7**: `0000000`
- **Operation**: `accum += Σ(rs1[i] * rs2[i])`; `rd = accum`
- **Latency**: 2 cycles
- **Description**: Like VMAC but accumulates into persistent register.

### 3.3 VRELU — Packed ReLU Activation
- **funct3**: `010`, **funct7**: `0000000`
- **Operation**: `rd[i] = max(0, rs1[i])` for each packed INT8 byte
- **Latency**: 1 cycle (combinatorial)

### 3.4 VPOOL — Packed Max-Pool
- **funct3**: `011`, **funct7**: `0000000`
- **Operation**: `rd = max(rs1[byte0..3])`
- **Latency**: 1 cycle (combinatorial)

### 3.5 VQUANT — Quantize INT32→INT8
- **funct3**: `100`, **funct7**: `0000000`
- **Operation**: `rd = sat_i8(rs1 >> rs2[4:0])`
- **Latency**: 1 cycle

### 3.6 VDEQUANT — Dequantize INT8→INT32
- **funct3**: `100`, **funct7**: `0000001`
- **Operation**: `rd = sign_extend(rs1[7:0]) << rs2[4:0]`
- **Latency**: 1 cycle

### 3.7 VADD — Packed Saturating Add
- **funct3**: `101`, **funct7**: `0000000`
- **Operation**: `rd[i] = sat_add(rs1[i], rs2[i])`
- **Latency**: 1 cycle

### 3.8 VSUB — Packed Saturating Subtract
- **funct3**: `101`, **funct7**: `0000001`
- **Operation**: `rd[i] = sat_sub(rs1[i], rs2[i])`
- **Latency**: 1 cycle

### 3.9 VMUL — Packed Element-wise Multiply
- **funct3**: `110`, **funct7**: `0000000`
- **Operation**: `rd[i] = (rs1[i] * rs2[i])[7:0]`
- **Latency**: 1 cycle

### 3.10 VABS — Packed Absolute Value
- **funct3**: `111`, **funct7**: `0000000`
- **Operation**: `rd[i] = |rs1[i]|` (-128 saturates to 127)
- **Latency**: 1 cycle

## 4. I-Type Instructions

### 4.1 CNN_CFG — Configure CNN Engine
- **funct3**: `000`
- **Operation**: `cfg_reg[imm12[3:0]] = rs1`

### 4.2 CNN_STATUS — Read CNN Status
- **funct3**: `001`
- **Operation**: `rd = cfg_reg[imm12[3:0]]`

### 4.3 VSCALE — Packed Scale by Immediate
- **funct3**: `010`
- **Operation**: `rd[i] = (rs1[i] * imm12[7:0]) >> 8`

### 4.4 VSHIFT — Packed Arithmetic Right Shift
- **funct3**: `011`
- **Operation**: `rd[i] = rs1[i] >>> imm12[2:0]`

## 5. Data Format

All SIMD instructions operate on **packed INT8** format:
```
 31      24 23     16 15      8 7       0
┌─────────┬─────────┬─────────┬─────────┐
│ byte[3]  │ byte[2]  │ byte[1]  │ byte[0]  │
│  INT8    │  INT8    │  INT8    │  INT8    │
└─────────┴─────────┴─────────┴─────────┘
```

Signed INT8 range: -128 to +127. Saturation arithmetic prevents overflow.
