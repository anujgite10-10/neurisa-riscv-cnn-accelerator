// ================================================================================
// NeurISA — Custom RISC-V Instruction Intrinsics for NEORV32
// ================================================================================
// C-language intrinsics wrapping NEORV32's CFU instruction encoding.
// Uses NEORV32's built-in neorv32_cfu_r_instr() and neorv32_cfu_i_instr()
// macros — NO toolchain modification required.
//
// All instructions operate on packed INT8 (4 × 8-bit signed) in 32-bit regs.
// ================================================================================
// Target: NEORV32 Xcfu ISA Extension on Zynq-7000 ZC-706
// Author: NeurISA Team — Track C: RISC-V + ISA Extensions
// ================================================================================

#ifndef NEURISA_INTRINSICS_H
#define NEURISA_INTRINSICS_H

#include <neorv32.h>
#include <neorv32_cfu.h>

// ============================================================
// R-Type Instructions (custom-0 opcode: 0001011)
// ============================================================

// -----------------------------------------------------------
// VMAC: Vector Multiply-Accumulate (4 × INT8)
// rd = Σ(rs1[i] * rs2[i]) for i=0..3
// Latency: 2 cycles
// -----------------------------------------------------------
#define NEURISA_VMAC(rs1, rs2) \
  neorv32_cfu_r_instr(0b0000000, 0b000, (uint32_t)(rs1), (uint32_t)(rs2))

// -----------------------------------------------------------
// VDOT: Vector Dot Product with Accumulate
// accum += Σ(rs1[i] * rs2[i]) for i=0..3
// Accumulator persists across calls; reset via CNN_CFG(0xF, val)
// Latency: 2 cycles
// -----------------------------------------------------------
#define NEURISA_VDOT(rs1, rs2) \
  neorv32_cfu_r_instr(0b0000000, 0b001, (uint32_t)(rs1), (uint32_t)(rs2))

// -----------------------------------------------------------
// VRELU: Packed Vectorized ReLU
// rd[i] = max(0, rs1[i]) for each INT8 byte
// Latency: 1 cycle (combinatorial)
// -----------------------------------------------------------
#define NEURISA_VRELU(rs1) \
  neorv32_cfu_r_instr(0b0000000, 0b010, (uint32_t)(rs1), 0)

// -----------------------------------------------------------
// VPOOL: Packed Max-Pool
// rd = max(rs1[0], rs1[1], rs1[2], rs1[3])
// Returns max byte in lowest byte position
// Latency: 1 cycle (combinatorial)
// -----------------------------------------------------------
#define NEURISA_VPOOL(rs1) \
  neorv32_cfu_r_instr(0b0000000, 0b011, (uint32_t)(rs1), 0)

// -----------------------------------------------------------
// VQUANT: Quantize INT32 → INT8
// rd = saturate_i8(rs1 >> rs2[4:0])
// Latency: 1 cycle (combinatorial)
// -----------------------------------------------------------
#define NEURISA_VQUANT(rs1, scale) \
  neorv32_cfu_r_instr(0b0000000, 0b100, (uint32_t)(rs1), (uint32_t)(scale))

// -----------------------------------------------------------
// VDEQUANT: Dequantize INT8 → INT32
// rd = sign_extend(rs1[7:0]) << rs2[4:0]
// Latency: 1 cycle (combinatorial)
// -----------------------------------------------------------
#define NEURISA_VDEQUANT(rs1, scale) \
  neorv32_cfu_r_instr(0b0000001, 0b100, (uint32_t)(rs1), (uint32_t)(scale))

// -----------------------------------------------------------
// VADD: Packed INT8 Saturating Add
// rd[i] = sat_add(rs1[i], rs2[i]) for each byte
// Latency: 1 cycle (combinatorial)
// -----------------------------------------------------------
#define NEURISA_VADD(rs1, rs2) \
  neorv32_cfu_r_instr(0b0000000, 0b101, (uint32_t)(rs1), (uint32_t)(rs2))

// -----------------------------------------------------------
// VSUB: Packed INT8 Saturating Subtract
// rd[i] = sat_sub(rs1[i], rs2[i]) for each byte
// Latency: 1 cycle (combinatorial)
// -----------------------------------------------------------
#define NEURISA_VSUB(rs1, rs2) \
  neorv32_cfu_r_instr(0b0000001, 0b101, (uint32_t)(rs1), (uint32_t)(rs2))

// -----------------------------------------------------------
// VMUL: Packed INT8 Element-wise Multiply (low byte)
// rd[i] = (rs1[i] * rs2[i])[7:0] for each byte
// Latency: 1 cycle (combinatorial)
// -----------------------------------------------------------
#define NEURISA_VMUL(rs1, rs2) \
  neorv32_cfu_r_instr(0b0000000, 0b110, (uint32_t)(rs1), (uint32_t)(rs2))

// -----------------------------------------------------------
// VABS: Packed INT8 Absolute Value
// rd[i] = |rs1[i]| for each byte (-128 saturates to 127)
// Latency: 1 cycle (combinatorial)
// -----------------------------------------------------------
#define NEURISA_VABS(rs1) \
  neorv32_cfu_r_instr(0b0000000, 0b111, (uint32_t)(rs1), 0)

// ============================================================
// I-Type Instructions (custom-1 opcode: 0101011)
// ============================================================
// NOTE: imm12 must be a compile-time constant (raw integer literal)
// because NEORV32's CUSTOM_INSTR_I_TYPE embeds it as assembly immediate.
// rs1 can be a variable (goes through a register).

// -----------------------------------------------------------
// CNN_CFG: Write CNN configuration register
// Writes rs1 to CNN config register at address imm12[3:0]
// Special: imm12=0xF writes to VDOT accumulator reset register
// -----------------------------------------------------------
#define NEURISA_CNN_CFG(addr, data) \
  neorv32_cfu_i_instr(0b000, addr, (uint32_t)(data))

// -----------------------------------------------------------
// CNN_STATUS: Read CNN configuration/status register
// Returns contents of register at imm12[3:0]
// -----------------------------------------------------------
#define NEURISA_CNN_STATUS(addr) \
  neorv32_cfu_i_instr(0b001, addr, 0)

// -----------------------------------------------------------
// VSCALE: Packed INT8 Scale by Immediate
// rd[i] = (rs1[i] * imm12[7:0]) >> 8
// Useful for batch normalization scaling
// Latency: 1 cycle (combinatorial)
// -----------------------------------------------------------
#define NEURISA_VSCALE(rs1, scale) \
  neorv32_cfu_i_instr(0b010, scale, (uint32_t)(rs1))

// -----------------------------------------------------------
// VSHIFT: Packed INT8 Arithmetic Right Shift
// rd[i] = rs1[i] >>> imm12[2:0]
// Latency: 1 cycle (combinatorial)
// -----------------------------------------------------------
#define NEURISA_VSHIFT(rs1, shamt) \
  neorv32_cfu_i_instr(0b011, shamt, (uint32_t)(rs1))

// ============================================================
// Convenience Macros
// ============================================================

// Reset VDOT accumulator to a specific value
#define NEURISA_VDOT_RESET(val) NEURISA_CNN_CFG(0xF, (val))

// Pack 4 INT8 values into a 32-bit word
#define NEURISA_PACK_I8(b3, b2, b1, b0) \
  ((uint32_t)(((uint8_t)(b3) << 24) | ((uint8_t)(b2) << 16) | \
               ((uint8_t)(b1) << 8) | (uint8_t)(b0)))

// Extract byte i from packed word
#define NEURISA_UNPACK_I8(word, i) \
  ((int8_t)(((uint32_t)(word) >> ((i) * 8)) & 0xFF))

#endif // NEURISA_INTRINSICS_H
