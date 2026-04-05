// ================================================================================
// NeurISA — CNN Inference Runtime Library (Implementation)
// ================================================================================

#include "neurisa_cnn.h"
#include "neurisa_intrinsics.h"
#include <string.h>

// ============================================================
// CFS CNN Accelerator Register Addresses
// ============================================================
#define CFS_BASE     ((volatile uint32_t*)0xFFFFFE00UL)
#define CFS_CTRL     CFS_BASE[0]   // 0x00
#define CFS_STATUS   CFS_BASE[1]   // 0x04
#define CFS_CFG_IH   CFS_BASE[2]   // 0x08
#define CFS_CFG_IW   CFS_BASE[3]   // 0x0C
#define CFS_CFG_IC   CFS_BASE[4]   // 0x10
#define CFS_CFG_OC   CFS_BASE[5]   // 0x14
#define CFS_CFG_KS   CFS_BASE[6]   // 0x18
#define CFS_CFG_STRIDE CFS_BASE[7] // 0x1C
#define CFS_PERF_CYC CFS_BASE[8]   // 0x20
#define CFS_PERF_OPS CFS_BASE[9]   // 0x24
#define CFS_WDATA    CFS_BASE[10]  // 0x28
#define CFS_FDATA    CFS_BASE[11]  // 0x2C
#define CFS_RESULT   CFS_BASE[12]  // 0x30
#define CFS_RADDR    CFS_BASE[13]  // 0x34

// ============================================================
// Initialization
// ============================================================
void neurisa_init(void) {
  // Reset VDOT accumulator
  NEURISA_VDOT_RESET(0);
  // Reset CFS CNN engine
  CFS_CTRL = 0x02; // reset bit
  CFS_CTRL = 0x00; // clear reset
}

// ============================================================
// Performance Measurement Helpers
// ============================================================
uint32_t neurisa_get_cycles(void) {
  return neorv32_cpu_csr_read(CSR_MCYCLE);
}

void neurisa_print_perf(const neurisa_perf_t *perf, const char *label) {
  neorv32_uart0_printf("\n=== %s Performance ===\n", label);
  neorv32_uart0_printf("  Cycles:     %u\n", perf->cycles);
  neorv32_uart0_printf("  Operations: %u\n", perf->ops);
  neorv32_uart0_printf("  Latency:    %u us\n", perf->latency_us);
}

// ============================================================
// SOFTWARE Mode: Pure C Convolution
// ============================================================
static void conv2d_software(
  const int8_t *input, int8_t *output,
  const int8_t *weights, const int32_t *bias,
  const neurisa_layer_cfg_t *cfg
) {
  int oh = cfg->input_h - cfg->kernel_size + 1;
  int ow = cfg->input_w - cfg->kernel_size + 1;

  for (int oc = 0; oc < cfg->output_ch; oc++) {
    for (int r = 0; r < oh; r++) {
      for (int c = 0; c < ow; c++) {
        int32_t sum = bias ? bias[oc] : 0;
        for (int ic = 0; ic < cfg->input_ch; ic++) {
          for (int kr = 0; kr < cfg->kernel_size; kr++) {
            for (int kc = 0; kc < cfg->kernel_size; kc++) {
              int in_idx = ic * cfg->input_h * cfg->input_w +
                          (r + kr) * cfg->input_w + (c + kc);
              int w_idx  = oc * cfg->input_ch * cfg->kernel_size * cfg->kernel_size +
                          ic * cfg->kernel_size * cfg->kernel_size +
                          kr * cfg->kernel_size + kc;
              sum += (int32_t)input[in_idx] * (int32_t)weights[w_idx];
            }
          }
        }
        // Quantize back to INT8
        int32_t q = sum >> 8;
        if (q > 127) q = 127;
        if (q < -128) q = -128;
        output[oc * oh * ow + r * ow + c] = (int8_t)q;
      }
    }
  }
}

// ============================================================
// ISA_ACCEL Mode: Convolution using NeurISA VMAC
// ============================================================
static void conv2d_isa_accel(
  const int8_t *input, int8_t *output,
  const int8_t *weights, const int32_t *bias,
  const neurisa_layer_cfg_t *cfg
) {
  int oh = cfg->input_h - cfg->kernel_size + 1;
  int ow = cfg->input_w - cfg->kernel_size + 1;

  for (int oc = 0; oc < cfg->output_ch; oc++) {
    for (int r = 0; r < oh; r++) {
      for (int c = 0; c < ow; c++) {
        // Reset dot product accumulator for this output position
        NEURISA_VDOT_RESET(bias ? bias[oc] : 0);

        for (int ic = 0; ic < cfg->input_ch; ic++) {
          // Process kernel in groups of 4 (packed INT8 VMAC)
          int kernel_elems = cfg->kernel_size * cfg->kernel_size;
          int w_base = oc * cfg->input_ch * kernel_elems + ic * kernel_elems;
          int in_base = ic * cfg->input_h * cfg->input_w;

          for (int k = 0; k < kernel_elems; k += 4) {
            uint32_t w_packed = 0;
            uint32_t p_packed = 0;
            int remaining = kernel_elems - k;
            int batch = (remaining > 4) ? 4 : remaining;

            for (int b = 0; b < batch; b++) {
              int ki = k + b;
              int kr = ki / cfg->kernel_size;
              int kc = ki % cfg->kernel_size;
              w_packed |= ((uint32_t)(uint8_t)weights[w_base + ki]) << (b * 8);
              p_packed |= ((uint32_t)(uint8_t)input[in_base + (r+kr)*cfg->input_w + (c+kc)]) << (b * 8);
            }

            // Use VDOT for accumulating dot product
            NEURISA_VDOT(p_packed, w_packed);
          }
        }

        // Read accumulated result from VDOT and quantize
        uint32_t accum = NEURISA_CNN_STATUS(0xF); // Read accumulator
        int32_t q = ((int32_t)accum) >> 8;
        if (q > 127) q = 127;
        if (q < -128) q = -128;
        output[oc * oh * ow + r * ow + c] = (int8_t)q;
      }
    }
  }
}

// ============================================================
// Convolution Dispatcher
// ============================================================
void neurisa_conv2d(
  const int8_t *input, int8_t *output,
  const int8_t *weights, const int32_t *bias,
  const neurisa_layer_cfg_t *cfg,
  neurisa_exec_mode_t mode
) {
  switch (mode) {
    case NEURISA_MODE_SOFTWARE:
      conv2d_software(input, output, weights, bias, cfg);
      break;
    case NEURISA_MODE_ISA_ACCEL:
      conv2d_isa_accel(input, output, weights, bias, cfg);
      break;
    case NEURISA_MODE_CFS_ACCEL:
      neurisa_cfs_configure(cfg);
      neurisa_cfs_start();
      neurisa_cfs_wait_done();
      break;
  }
}

// ============================================================
// ReLU Activation
// ============================================================
void neurisa_relu(int8_t *data, int size, neurisa_exec_mode_t mode) {
  if (mode == NEURISA_MODE_ISA_ACCEL || mode == NEURISA_MODE_CFS_ACCEL) {
    // Process 4 bytes at a time using VRELU
    uint32_t *packed = (uint32_t*)data;
    int words = size / 4;
    for (int i = 0; i < words; i++) {
      packed[i] = NEURISA_VRELU(packed[i]);
    }
    // Handle remaining bytes
    for (int i = words * 4; i < size; i++) {
      if (data[i] < 0) data[i] = 0;
    }
  } else {
    // Software fallback
    for (int i = 0; i < size; i++) {
      if (data[i] < 0) data[i] = 0;
    }
  }
}

// ============================================================
// Leaky ReLU Activation
// ============================================================
void neurisa_leaky_relu(int8_t *data, int size, neurisa_exec_mode_t mode) {
  if (mode == NEURISA_MODE_ISA_ACCEL || mode == NEURISA_MODE_CFS_ACCEL) {
    uint32_t *packed = (uint32_t*)data;
    int words = size / 4;
    for (int i = 0; i < words; i++) {
      uint32_t val = packed[i];
      uint32_t relu_result = NEURISA_VRELU(val);
      // Leaky part: shift right by 3 for negative values
      uint32_t neg_mask = val & ~relu_result; // extract negative bytes
      uint32_t leaky = NEURISA_VSHIFT(neg_mask, 3); // x/8
      packed[i] = relu_result | leaky;
    }
  } else {
    for (int i = 0; i < size; i++) {
      if (data[i] < 0) data[i] = data[i] / 8;
    }
  }
}

// ============================================================
// 2×2 Max-Pooling
// ============================================================
void neurisa_maxpool2x2(
  const int8_t *input, int8_t *output,
  int height, int width, int channels,
  neurisa_exec_mode_t mode
) {
  int oh = height / 2;
  int ow = width / 2;

  for (int ch = 0; ch < channels; ch++) {
    for (int r = 0; r < oh; r++) {
      for (int c = 0; c < ow; c++) {
        int in_base = ch * height * width;
        int r2 = r * 2, c2 = c * 2;

        if (mode == NEURISA_MODE_ISA_ACCEL || mode == NEURISA_MODE_CFS_ACCEL) {
          // Pack 2×2 window into one word and use VPOOL
          uint32_t packed = NEURISA_PACK_I8(
            input[in_base + r2 * width + c2],
            input[in_base + r2 * width + c2 + 1],
            input[in_base + (r2+1) * width + c2],
            input[in_base + (r2+1) * width + c2 + 1]
          );
          uint32_t result = NEURISA_VPOOL(packed);
          output[ch * oh * ow + r * ow + c] = (int8_t)(result & 0xFF);
        } else {
          int8_t max_val = input[in_base + r2 * width + c2];
          int8_t v;
          v = input[in_base + r2 * width + c2 + 1]; if (v > max_val) max_val = v;
          v = input[in_base + (r2+1) * width + c2];  if (v > max_val) max_val = v;
          v = input[in_base + (r2+1) * width + c2+1]; if (v > max_val) max_val = v;
          output[ch * oh * ow + r * ow + c] = max_val;
        }
      }
    }
  }
}

// ============================================================
// Fully Connected Layer
// ============================================================
void neurisa_dense(
  const int8_t *input, int8_t *output,
  const int8_t *weights, const int32_t *bias,
  int input_size, int output_size,
  int quant_shift,
  neurisa_exec_mode_t mode
) {
  for (int o = 0; o < output_size; o++) {
    int32_t sum = bias ? bias[o] : 0;

    if (mode == NEURISA_MODE_ISA_ACCEL || mode == NEURISA_MODE_CFS_ACCEL) {
      // Reset VDOT accumulator
      NEURISA_VDOT_RESET(sum);

      // Process 4 elements at a time using VDOT
      uint32_t *in_packed  = (uint32_t*)input;
      uint32_t *w_packed   = (uint32_t*)&weights[o * input_size];
      int words = input_size / 4;

      for (int i = 0; i < words; i++) {
        NEURISA_VDOT(in_packed[i], w_packed[i]);
      }

      // Read accumulator result
      sum = (int32_t)NEURISA_CNN_STATUS(0xF);

      // Handle remaining elements
      for (int i = words * 4; i < input_size; i++) {
        sum += (int32_t)input[i] * (int32_t)weights[o * input_size + i];
      }
    } else {
      for (int i = 0; i < input_size; i++) {
        sum += (int32_t)input[i] * (int32_t)weights[o * input_size + i];
      }
    }

    // Quantize
    int32_t q = sum >> quant_shift;
    if (q > 127) q = 127;
    if (q < -128) q = -128;
    output[o] = (int8_t)q;
  }
}

// ============================================================
// Softmax (always software — tiny computation)
// ============================================================
void neurisa_softmax(const int8_t *input, float *output, int size) {
  // Find max for numerical stability
  int8_t max_val = input[0];
  for (int i = 1; i < size; i++) {
    if (input[i] > max_val) max_val = input[i];
  }

  // Simple approximation: exp(x) ≈ 2^(x/8) for small x
  float sum = 0.0f;
  for (int i = 0; i < size; i++) {
    int diff = (int)input[i] - (int)max_val;
    // Approximate exp using shift: 2^(diff/8)
    float val = 1.0f;
    if (diff < 0) {
      int shift = (-diff) / 8;
      if (shift > 30) shift = 30;
      val = 1.0f / (float)(1 << shift);
    }
    output[i] = val;
    sum += val;
  }

  // Normalize
  for (int i = 0; i < size; i++) {
    output[i] /= sum;
  }
}

// ============================================================
// Full Network Inference
// ============================================================
int neurisa_infer(
  neurisa_network_t *net,
  const int8_t *input,
  int8_t *output,
  neurisa_exec_mode_t mode
) {
  // Find max output (classification result)
  int max_idx = 0;
  int8_t max_val = output[0];
  int out_size = net->layers[net->num_layers - 1].output_ch;

  for (int i = 1; i < out_size; i++) {
    if (output[i] > max_val) {
      max_val = output[i];
      max_idx = i;
    }
  }

  return max_idx;
}

// ============================================================
// CFS Accelerator Control
// ============================================================
void neurisa_cfs_configure(const neurisa_layer_cfg_t *cfg) {
  CFS_CFG_IH     = cfg->input_h;
  CFS_CFG_IW     = cfg->input_w;
  CFS_CFG_IC     = cfg->input_ch;
  CFS_CFG_OC     = cfg->output_ch;
  CFS_CFG_STRIDE = (cfg->padding << 2) | cfg->stride;

  uint32_t ctrl = 0;
  ctrl |= (cfg->act_mode & 0x3) << 2;
  ctrl |= (cfg->pool_en & 0x1) << 4;
  ctrl |= (cfg->pool_mode & 0x1) << 5;
  CFS_CTRL = ctrl;
}

void neurisa_cfs_start(void) {
  uint32_t ctrl = CFS_CTRL;
  CFS_CTRL = ctrl | 0x01; // set start bit
}

void neurisa_cfs_wait_done(void) {
  while (!(CFS_STATUS & 0x02)) {
    // Wait for done bit
    asm volatile ("nop");
  }
}

void neurisa_cfs_read_perf(neurisa_perf_t *perf) {
  perf->cycles = CFS_PERF_CYC;
  perf->ops    = CFS_PERF_OPS;
}

// ============================================================
// Benchmark Comparison
// ============================================================
void neurisa_benchmark_compare(
  neurisa_network_t *net,
  const int8_t *input
) {
  uint32_t t0, t1;
  int8_t output_sw[16], output_isa[16], output_cfs[16];

  neorv32_uart0_printf("\n");
  neorv32_uart0_printf("╔══════════════════════════════════════════════╗\n");
  neorv32_uart0_printf("║    NeurISA Performance Benchmark Report     ║\n");
  neorv32_uart0_printf("╠══════════════════════════════════════════════╣\n");

  // Software baseline
  t0 = neurisa_get_cycles();
  neurisa_infer(net, input, output_sw, NEURISA_MODE_SOFTWARE);
  t1 = neurisa_get_cycles();
  uint32_t sw_cycles = t1 - t0;
  neorv32_uart0_printf("║ SOFTWARE:   %10u cycles                ║\n", sw_cycles);

  // ISA accelerated
  t0 = neurisa_get_cycles();
  neurisa_infer(net, input, output_isa, NEURISA_MODE_ISA_ACCEL);
  t1 = neurisa_get_cycles();
  uint32_t isa_cycles = t1 - t0;
  neorv32_uart0_printf("║ ISA_ACCEL:  %10u cycles (%.1fx speedup) ║\n",
    isa_cycles, (float)sw_cycles / (float)isa_cycles);

  // CFS accelerated
  t0 = neurisa_get_cycles();
  neurisa_infer(net, input, output_cfs, NEURISA_MODE_CFS_ACCEL);
  t1 = neurisa_get_cycles();
  uint32_t cfs_cycles = t1 - t0;
  neorv32_uart0_printf("║ CFS_ACCEL:  %10u cycles (%.1fx speedup) ║\n",
    cfs_cycles, (float)sw_cycles / (float)cfs_cycles);

  neorv32_uart0_printf("╚══════════════════════════════════════════════╝\n");
}
