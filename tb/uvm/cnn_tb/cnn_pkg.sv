// ================================================================================
// NeurISA — CNN Accelerator UVM Testbench Package
// ================================================================================
// Comprehensive UVM testbench for the CNN accelerator CFS engine.
// Tests convolution, activation, pooling, and full pipeline operations.
// ================================================================================

`ifndef CNN_PKG_SV
`define CNN_PKG_SV

package cnn_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ============================================================
  // CNN Configuration Parameters
  // ============================================================
  typedef struct packed {
    bit [7:0]  input_h;
    bit [7:0]  input_w;
    bit [7:0]  input_ch;
    bit [7:0]  output_ch;
    bit [1:0]  stride;
    bit        padding;
    bit [1:0]  act_mode;     // 00=ReLU, 01=LeakyReLU, 10=bypass
    bit        pool_en;
    bit        pool_mode;    // 0=max, 1=avg
  } cnn_config_t;

  // CFS Register offsets
  typedef enum int unsigned {
    REG_CTRL       = 6'h00,
    REG_STATUS     = 6'h04,
    REG_CFG_IH     = 6'h08,
    REG_CFG_IW     = 6'h0C,
    REG_CFG_IC     = 6'h10,
    REG_CFG_OC     = 6'h14,
    REG_CFG_KS     = 6'h18,
    REG_CFG_STRIDE = 6'h1C,
    REG_PERF_CYC   = 6'h20,
    REG_PERF_OPS   = 6'h24,
    REG_WDATA      = 6'h28,
    REG_FDATA      = 6'h2C,
    REG_RESULT     = 6'h30,
    REG_RADDR      = 6'h34
  } cnn_reg_addr_e;

  // ============================================================
  // Golden Model: 3×3 INT8 Convolution
  // ============================================================
  function automatic int golden_conv3x3(
    byte kernel[9],
    byte patch[9]
  );
    int result = 0;
    for (int i = 0; i < 9; i++)
      result += int'(kernel[i]) * int'(patch[i]);
    return result;
  endfunction

  // Golden Model: ReLU
  function automatic int golden_relu(int val);
    return (val >= 0) ? val : 0;
  endfunction

  // Golden Model: Leaky ReLU (x/8)
  function automatic int golden_leaky_relu(int val);
    return (val >= 0) ? val : (val >>> 3);
  endfunction

  // Golden Model: Max-Pool 2×2
  function automatic byte golden_maxpool(byte vals[4]);
    byte max_val = vals[0];
    for (int i = 1; i < 4; i++)
      if (vals[i] > max_val) max_val = vals[i];
    return max_val;
  endfunction

  `include "cnn_seq_item.sv"
  `include "cnn_driver.sv"
  `include "cnn_monitor.sv"
  `include "cnn_scoreboard.sv"
  `include "cnn_agent.sv"
  `include "cnn_env.sv"
  `include "cnn_sequences.sv"
  `include "cnn_test.sv"

endpackage : cnn_pkg

`endif
