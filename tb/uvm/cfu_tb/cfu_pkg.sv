// ================================================================================
// NeurISA — CFU UVM Testbench Package
// ================================================================================
// Defines types, parameters, and utility functions for testing the NeurISA CFU
// custom RISC-V instructions.
// ================================================================================

`ifndef CFU_PKG_SV
`define CFU_PKG_SV

package cfu_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ============================================================
  // Instruction Type Constants
  // ============================================================
  typedef enum bit {
    R_TYPE = 1'b0,
    I_TYPE = 1'b1
  } cfu_instr_type_e;

  // R-type funct3 opcodes
  typedef enum bit [2:0] {
    VMAC_F3   = 3'b000,
    VDOT_F3   = 3'b001,
    VRELU_F3  = 3'b010,
    VPOOL_F3  = 3'b011,
    VQUANT_F3 = 3'b100,
    VADD_F3   = 3'b101,
    VMUL_F3   = 3'b110,
    VABS_F3   = 3'b111
  } rtype_funct3_e;

  // I-type funct3 opcodes
  typedef enum bit [2:0] {
    CNN_CFG_F3    = 3'b000,
    CNN_STATUS_F3 = 3'b001,
    VSCALE_F3     = 3'b010,
    VSHIFT_F3     = 3'b011
  } itype_funct3_e;

  // funct7 sub-selectors
  typedef enum bit [6:0] {
    F7_DEFAULT = 7'b0000000,
    F7_ALT     = 7'b0000001
  } funct7_e;

  // ============================================================
  // Golden Model Functions
  // ============================================================

  // INT8 saturating add
  function automatic byte sat_add_i8(byte a, byte b);
    int sum = int'(a) + int'(b);
    if (sum > 127)  return 8'sd127;
    if (sum < -128) return -8'sd128;
    return byte'(sum);
  endfunction

  // INT8 saturating subtract
  function automatic byte sat_sub_i8(byte a, byte b);
    int diff = int'(a) - int'(b);
    if (diff > 127)  return 8'sd127;
    if (diff < -128) return -8'sd128;
    return byte'(diff);
  endfunction

  // Packed VMAC golden model
  function automatic logic [31:0] golden_vmac(logic [31:0] rs1, logic [31:0] rs2);
    int result = 0;
    for (int i = 0; i < 4; i++) begin
      byte a = rs1[i*8 +: 8];
      byte b = rs2[i*8 +: 8];
      result += int'(a) * int'(b);
    end
    return result;
  endfunction

  // Packed VRELU golden model
  function automatic logic [31:0] golden_vrelu(logic [31:0] rs1);
    logic [31:0] result;
    for (int i = 0; i < 4; i++) begin
      byte val = rs1[i*8 +: 8];
      result[i*8 +: 8] = (val >= 0) ? val : 8'd0;
    end
    return result;
  endfunction

  // Packed VPOOL golden model (max of 4 bytes)
  function automatic logic [31:0] golden_vpool(logic [31:0] rs1);
    byte max_val = rs1[7:0];
    for (int i = 1; i < 4; i++) begin
      byte val = rs1[i*8 +: 8];
      if (val > max_val) max_val = val;
    end
    return {24'd0, max_val};
  endfunction

  // Packed VADD golden model
  function automatic logic [31:0] golden_vadd(logic [31:0] rs1, logic [31:0] rs2);
    logic [31:0] result;
    for (int i = 0; i < 4; i++)
      result[i*8 +: 8] = sat_add_i8(rs1[i*8 +: 8], rs2[i*8 +: 8]);
    return result;
  endfunction

  // Packed VSUB golden model
  function automatic logic [31:0] golden_vsub(logic [31:0] rs1, logic [31:0] rs2);
    logic [31:0] result;
    for (int i = 0; i < 4; i++)
      result[i*8 +: 8] = sat_sub_i8(rs1[i*8 +: 8], rs2[i*8 +: 8]);
    return result;
  endfunction

  // Packed VMUL golden model (low byte of each product)
  function automatic logic [31:0] golden_vmul(logic [31:0] rs1, logic [31:0] rs2);
    logic [31:0] result;
    for (int i = 0; i < 4; i++) begin
      shortint prod = shortint'(signed'(rs1[i*8 +: 8])) * shortint'(signed'(rs2[i*8 +: 8]));
      result[i*8 +: 8] = prod[7:0];
    end
    return result;
  endfunction

  // Packed VABS golden model
  function automatic logic [31:0] golden_vabs(logic [31:0] rs1);
    logic [31:0] result;
    for (int i = 0; i < 4; i++) begin
      byte val = rs1[i*8 +: 8];
      if (val == -128) result[i*8 +: 8] = 8'd127; // saturate
      else if (val < 0) result[i*8 +: 8] = -val;
      else result[i*8 +: 8] = val;
    end
    return result;
  endfunction

  // Include all testbench components
  `include "cfu_seq_item.sv"
  `include "cfu_driver.sv"
  `include "cfu_monitor.sv"
  `include "cfu_scoreboard.sv"
  `include "cfu_agent.sv"
  `include "cfu_env.sv"
  `include "cfu_sequences.sv"
  `include "cfu_test.sv"

endpackage : cfu_pkg

`endif
