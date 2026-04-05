// ================================================================================
// NeurISA — CNN Inference Runtime Library (Header)
// ================================================================================
// Provides high-level CNN layer functions using NeurISA custom instructions
// and the CFS CNN accelerator engine.
//
// Supports three execution modes:
//   1. SOFTWARE: Pure C implementation (baseline)
//   2. ISA_ACCEL: Using NeurISA custom instructions (VMAC, VRELU, etc.)
//   3. CFS_ACCEL: Using the CFS CNN hardware accelerator engine
// ================================================================================

#ifndef NEURISA_CNN_H
#define NEURISA_CNN_H

#include <stdint.h>
#include <neorv32.h>

// ============================================================
// Execution Modes
// ============================================================
typedef enum {
  NEURISA_MODE_SOFTWARE  = 0, // Pure software
  NEURISA_MODE_ISA_ACCEL = 1, // Custom instruction accelerated
  NEURISA_MODE_CFS_ACCEL = 2  // CFS hardware accelerator
} neurisa_exec_mode_t;

// ============================================================
// Layer Configuration
// ============================================================
typedef struct {
  uint8_t input_h;
  uint8_t input_w;
  uint8_t input_ch;
  uint8_t output_ch;
  uint8_t kernel_size;  // 3 for 3×3
  uint8_t stride;
  uint8_t padding;      // 0=valid, 1=same
  uint8_t act_mode;     // 0=ReLU, 1=LeakyReLU, 2=none
  uint8_t pool_en;      // 1=enable 2×2 pooling
  uint8_t pool_mode;    // 0=max, 1=avg
} neurisa_layer_cfg_t;

// ============================================================
// Performance Metrics
// ============================================================
typedef struct {
  uint32_t cycles;
  uint32_t ops;
  uint32_t latency_us;
  float    throughput_gops;
  float    speedup;
} neurisa_perf_t;

// ============================================================
// Network Definition (for LeNet-5)
// ============================================================
#define NEURISA_MAX_LAYERS 10

typedef struct {
  int num_layers;
  neurisa_layer_cfg_t layers[NEURISA_MAX_LAYERS];
  const int8_t *weights[NEURISA_MAX_LAYERS]; // quantized INT8 weights
  const int32_t *biases[NEURISA_MAX_LAYERS]; // INT32 biases
  neurisa_perf_t perf[NEURISA_MAX_LAYERS];   // per-layer perf
  neurisa_perf_t total_perf;                  // total perf
} neurisa_network_t;

// ============================================================
// API Functions
// ============================================================

// Initialize the NeurISA runtime
void neurisa_init(void);

// --- Layer Operations ---

// 2D Convolution (dispatches to selected mode)
void neurisa_conv2d(
  const int8_t *input, int8_t *output,
  const int8_t *weights, const int32_t *bias,
  const neurisa_layer_cfg_t *cfg,
  neurisa_exec_mode_t mode
);

// ReLU activation (packed INT8)
void neurisa_relu(int8_t *data, int size, neurisa_exec_mode_t mode);

// Leaky ReLU activation (packed INT8)
void neurisa_leaky_relu(int8_t *data, int size, neurisa_exec_mode_t mode);

// 2×2 Max-Pooling
void neurisa_maxpool2x2(
  const int8_t *input, int8_t *output,
  int height, int width, int channels,
  neurisa_exec_mode_t mode
);

// Fully connected layer
void neurisa_dense(
  const int8_t *input, int8_t *output,
  const int8_t *weights, const int32_t *bias,
  int input_size, int output_size,
  int quant_shift,
  neurisa_exec_mode_t mode
);

// Softmax (always software — tiny computation)
void neurisa_softmax(const int8_t *input, float *output, int size);

// --- Full Network Inference ---

// Run complete network inference
int neurisa_infer(
  neurisa_network_t *net,
  const int8_t *input,
  int8_t *output,
  neurisa_exec_mode_t mode
);

// --- Performance ---

// Get cycle count
uint32_t neurisa_get_cycles(void);

// Print performance report
void neurisa_print_perf(const neurisa_perf_t *perf, const char *label);

// Compare performance across modes
void neurisa_benchmark_compare(
  neurisa_network_t *net,
  const int8_t *input
);

// --- CFS Accelerator Control ---

// Configure CFS CNN engine
void neurisa_cfs_configure(const neurisa_layer_cfg_t *cfg);

// Start CFS CNN engine
void neurisa_cfs_start(void);

// Wait for CFS CNN engine completion
void neurisa_cfs_wait_done(void);

// Read CFS performance counters
void neurisa_cfs_read_perf(neurisa_perf_t *perf);

#endif // NEURISA_CNN_H
