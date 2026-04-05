// ================================================================================
// NeurISA — MNIST Digit Recognition Demo Application
// ================================================================================
// Demonstrates CNN inference on NEORV32 with NeurISA custom ISA extensions.
// Uses a quantized LeNet-5 model for MNIST digit classification.
//
// Architecture: Input(28×28×1) → Conv(5×5,6) → ReLU → Pool(2×2) →
//               Conv(5×5,16) → ReLU → Pool(2×2) → FC(120) → FC(84) → FC(10)
//
// Runs inference in 3 modes and compares performance:
//   1. SOFTWARE — pure C baseline
//   2. ISA_ACCEL — VMAC/VRELU/VPOOL custom instructions
//   3. CFS_ACCEL — hardware CNN accelerator engine
// ================================================================================

#include <neorv32.h>
#include "neurisa_cnn.h"
#include "neurisa_intrinsics.h"

// ============================================================
// Quantized LeNet-5 Weights (INT8)
// ============================================================
// In production: #include "lenet5_weights.h"
// For demo: use small representative test weights

// Conv1: 6 filters × 1 channel × 5×5 = 150 weights
static const int8_t conv1_weights[150] = {
   1, -2,  3, -1,  2,  0,  1, -3,  2,  1,  -1,  2,  0,  1, -2,
   3, -1,  0,  2, -2,  1,  0, -1,  3, -2,   1, -1,  2,  0,  1,
  -2,  3,  1, -1,  0,  2, -3,  1,  0, -1,   2,  1, -2,  0,  3,
  -1,  2,  0,  1, -2,  3, -1,  0,  2, -2,   1,  0, -1,  3, -2,
   1,  2, -1,  0,  3, -2,  1, -3,  2,  0,  -1,  1,  2, -2,  0,
   3, -1,  0,  2, -2,  1,  0, -1,  3, -2,   1,  2, -1,  0,  3,
  -2,  1, -3,  2,  0, -1,  1,  2, -2,  0,   3, -1,  0,  2, -2,
   1,  0, -1,  3, -2,  1,  2, -1,  0,  3,  -2,  1, -3,  2,  0,
  -1,  1,  2, -2,  0,  3, -1,  0,  2, -2,   1,  0, -1,  3, -2,
   1,  2, -1,  0,  3, -2,  1, -3,  2,  0,  -1,  1,  2, -2,  0
};
static const int32_t conv1_bias[6] = {0, 0, 0, 0, 0, 0};

// Conv2: 16 filters × 6 channels × 5×5 = 2400 weights (truncated for demo)
static const int8_t conv2_weights[2400] = {0}; // Zero-initialized placeholder
static const int32_t conv2_bias[16] = {0};

// FC1: 400→120 = 48000 weights (too large for IMEM - use simplified version)
static const int8_t fc1_weights[4800] = {0}; // Simplified 40→120
static const int32_t fc1_bias[120] = {0};

// FC2: 120→84
static const int8_t fc2_weights[10080] = {0};
static const int32_t fc2_bias[84] = {0};

// FC3: 84→10
static const int8_t fc3_weights[840] = {0};
static const int32_t fc3_bias[10] = {0};

// ============================================================
// Test Image: Handwritten "7" (28×28 INT8)
// ============================================================
static const int8_t test_image_7[784] = {
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,84,127,127,127,127,127,127,127,84,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,42,84,84,84,84,84,127,127,84,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,84,127,84,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,84,127,42,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,42,127,127,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,84,127,84,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,84,127,42,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,42,127,127,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,84,127,84,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,84,127,42,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,42,127,127,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,84,127,84,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,84,127,42,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,42,127,127,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,84,127,84,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,84,127,42,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};

// ============================================================
// Buffers for intermediate layer outputs
// ============================================================
static int8_t buf_a[6*24*24];   // Conv1 output: 6×24×24
static int8_t buf_b[6*12*12];   // Pool1 output: 6×12×12
static int8_t buf_c[16*8*8];    // Conv2 output: 16×8×8
static int8_t buf_d[16*4*4];    // Pool2 output: 16×4×4
static int8_t buf_fc1[120];     // FC1 output
static int8_t buf_fc2[84];      // FC2 output
static int8_t buf_fc3[10];      // FC3 output (logits)
static float  softmax_out[10];  // Softmax probabilities

// ============================================================
// Network Definition
// ============================================================
static neurisa_network_t lenet5 = {
  .num_layers = 5,
  .layers = {
    {.input_h=28, .input_w=28, .input_ch=1,  .output_ch=6,  .kernel_size=5, .stride=1, .padding=0, .act_mode=0, .pool_en=1, .pool_mode=0},
    {.input_h=12, .input_w=12, .input_ch=6,  .output_ch=16, .kernel_size=5, .stride=1, .padding=0, .act_mode=0, .pool_en=1, .pool_mode=0},
    {.input_h=1,  .input_w=1,  .input_ch=256,.output_ch=120, .kernel_size=1, .stride=1, .padding=0, .act_mode=0, .pool_en=0, .pool_mode=0},
    {.input_h=1,  .input_w=1,  .input_ch=120,.output_ch=84,  .kernel_size=1, .stride=1, .padding=0, .act_mode=0, .pool_en=0, .pool_mode=0},
    {.input_h=1,  .input_w=1,  .input_ch=84, .output_ch=10,  .kernel_size=1, .stride=1, .padding=0, .act_mode=2, .pool_en=0, .pool_mode=0},
  },
  .weights = {conv1_weights, conv2_weights, fc1_weights, fc2_weights, fc3_weights},
  .biases  = {conv1_bias, conv2_bias, fc1_bias, fc2_bias, fc3_bias},
};

// ============================================================
// Run Single Inference
// ============================================================
static int run_inference(const int8_t *input, neurisa_exec_mode_t mode) {
  // Layer 1: Conv1(5×5, 6) + ReLU + MaxPool(2×2)
  neurisa_conv2d(input, buf_a, conv1_weights, conv1_bias, &lenet5.layers[0], mode);
  neurisa_relu(buf_a, 6*24*24, mode);
  neurisa_maxpool2x2(buf_a, buf_b, 24, 24, 6, mode);

  // Layer 2: Conv2(5×5, 16) + ReLU + MaxPool(2×2)
  neurisa_conv2d(buf_b, buf_c, conv2_weights, conv2_bias, &lenet5.layers[1], mode);
  neurisa_relu(buf_c, 16*8*8, mode);
  neurisa_maxpool2x2(buf_c, buf_d, 8, 8, 16, mode);

  // Layer 3: FC1(256→120)
  neurisa_dense(buf_d, buf_fc1, fc1_weights, fc1_bias, 256, 120, 8, mode);
  neurisa_relu(buf_fc1, 120, mode);

  // Layer 4: FC2(120→84)
  neurisa_dense(buf_fc1, buf_fc2, fc2_weights, fc2_bias, 120, 84, 8, mode);
  neurisa_relu(buf_fc2, 84, mode);

  // Layer 5: FC3(84→10)
  neurisa_dense(buf_fc2, buf_fc3, fc3_weights, fc3_bias, 84, 10, 8, mode);

  // Softmax
  neurisa_softmax(buf_fc3, softmax_out, 10);

  // Find class
  int max_idx = 0;
  for (int i = 1; i < 10; i++) {
    if (softmax_out[i] > softmax_out[max_idx]) max_idx = i;
  }
  return max_idx;
}

// ============================================================
// Main Entry Point
// ============================================================
int main(void) {
  // Initialize NEORV32 UART
  neorv32_uart0_setup(19200, 0);

  // Initialize NeurISA runtime
  neurisa_init();

  // Print banner
  neorv32_uart0_printf("\n\n");
  neorv32_uart0_printf("╔══════════════════════════════════════════════════════════╗\n");
  neorv32_uart0_printf("║                                                        ║\n");
  neorv32_uart0_printf("║   ███╗   ██╗███████╗██╗   ██╗██████╗ ██╗███████╗ █████╗║\n");
  neorv32_uart0_printf("║   ████╗  ██║██╔════╝██║   ██║██╔══██╗██║██╔════╝██╔══██║\n");
  neorv32_uart0_printf("║   ██╔██╗ ██║█████╗  ██║   ██║██████╔╝██║███████╗███████║\n");
  neorv32_uart0_printf("║   ██║╚██╗██║██╔══╝  ██║   ██║██╔══██╗██║╚════██║██╔══██║\n");
  neorv32_uart0_printf("║   ██║ ╚████║███████╗╚██████╔╝██║  ██║██║███████║██║  ██║\n");
  neorv32_uart0_printf("║   ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═╝║\n");
  neorv32_uart0_printf("║                                                        ║\n");
  neorv32_uart0_printf("║   RISC-V Custom ISA Extensions for CNN Acceleration    ║\n");
  neorv32_uart0_printf("║   NEORV32 on Zynq-7000 ZC-706                         ║\n");
  neorv32_uart0_printf("║   Track C: RISC-V + ISA Extensions                    ║\n");
  neorv32_uart0_printf("╚══════════════════════════════════════════════════════════╝\n");

  // Check for CFU availability
  if (neorv32_cfu_available() == 0) {
    neorv32_uart0_printf("[ERROR] CFU not available! Enable RISCV_ISA_Xcfu.\n");
    return 1;
  }
  neorv32_uart0_printf("[OK] NeurISA CFU detected (Xcfu ISA extension)\n");

  // Quick instruction test
  neorv32_uart0_printf("\n=== NeurISA Instruction Self-Test ===\n");

  // Test VMAC
  uint32_t a = NEURISA_PACK_I8(1, 2, 3, 4);
  uint32_t b = NEURISA_PACK_I8(1, 1, 1, 1);
  uint32_t vmac_result = NEURISA_VMAC(a, b);
  neorv32_uart0_printf("VMAC([1,2,3,4]*[1,1,1,1]) = %d (expected: 10)\n", (int32_t)vmac_result);

  // Test VRELU
  uint32_t relu_in = NEURISA_PACK_I8(-5, 10, -128, 127);
  uint32_t relu_out = NEURISA_VRELU(relu_in);
  neorv32_uart0_printf("VRELU([-5,10,-128,127]) = [%d,%d,%d,%d] (exp: [0,10,0,127])\n",
    NEURISA_UNPACK_I8(relu_out, 0), NEURISA_UNPACK_I8(relu_out, 1),
    NEURISA_UNPACK_I8(relu_out, 2), NEURISA_UNPACK_I8(relu_out, 3));

  // Test VADD with saturation
  uint32_t add_a = NEURISA_PACK_I8(100, -100, 50, -50);
  uint32_t add_b = NEURISA_PACK_I8(100, -100, 50, -50);
  uint32_t add_out = NEURISA_VADD(add_a, add_b);
  neorv32_uart0_printf("VADD([100,-100,50,-50]+[100,-100,50,-50]) = [%d,%d,%d,%d] (exp: [127,-128,100,-100])\n",
    NEURISA_UNPACK_I8(add_out, 0), NEURISA_UNPACK_I8(add_out, 1),
    NEURISA_UNPACK_I8(add_out, 2), NEURISA_UNPACK_I8(add_out, 3));

  // Test VPOOL
  uint32_t pool_in = NEURISA_PACK_I8(10, 50, 30, 20);
  uint32_t pool_out = NEURISA_VPOOL(pool_in);
  neorv32_uart0_printf("VPOOL([10,50,30,20]) = %d (expected: 50)\n",
    NEURISA_UNPACK_I8(pool_out, 0));

  neorv32_uart0_printf("\n=== MNIST Digit Recognition Demo ===\n");
  neorv32_uart0_printf("Test image: digit '7' (28x28 INT8)\n");
  neorv32_uart0_printf("Model: Quantized LeNet-5\n\n");

  // ============================================================
  // Run inference in all 3 modes with timing
  // ============================================================
  uint32_t t0, t1;
  int prediction;

  neorv32_uart0_printf("╔════════════════════════════════════════════════╗\n");
  neorv32_uart0_printf("║          Inference Performance Results        ║\n");
  neorv32_uart0_printf("╠═════════════╦═══════════╦═══════╦═════════════╣\n");
  neorv32_uart0_printf("║ Mode        ║ Cycles    ║ Pred  ║ Speedup     ║\n");
  neorv32_uart0_printf("╠═════════════╬═══════════╬═══════╬═════════════╣\n");

  // Mode 1: Software
  t0 = neurisa_get_cycles();
  prediction = run_inference(test_image_7, NEURISA_MODE_SOFTWARE);
  t1 = neurisa_get_cycles();
  uint32_t sw_cycles = t1 - t0;
  neorv32_uart0_printf("║ SOFTWARE    ║ %9u ║   %d   ║   1.0x      ║\n", sw_cycles, prediction);

  // Mode 2: ISA Accelerated
  t0 = neurisa_get_cycles();
  prediction = run_inference(test_image_7, NEURISA_MODE_ISA_ACCEL);
  t1 = neurisa_get_cycles();
  uint32_t isa_cycles = t1 - t0;
  uint32_t isa_speedup_x10 = (sw_cycles * 10) / (isa_cycles > 0 ? isa_cycles : 1);
  neorv32_uart0_printf("║ ISA_ACCEL   ║ %9u ║   %d   ║   %u.%ux      ║\n",
    isa_cycles, prediction, isa_speedup_x10/10, isa_speedup_x10%10);

  // Mode 3: CFS Accelerated
  t0 = neurisa_get_cycles();
  prediction = run_inference(test_image_7, NEURISA_MODE_CFS_ACCEL);
  t1 = neurisa_get_cycles();
  uint32_t cfs_cycles = t1 - t0;
  uint32_t cfs_speedup_x10 = (sw_cycles * 10) / (cfs_cycles > 0 ? cfs_cycles : 1);
  neorv32_uart0_printf("║ CFS_ACCEL   ║ %9u ║   %d   ║   %u.%ux      ║\n",
    cfs_cycles, prediction, cfs_speedup_x10/10, cfs_speedup_x10%10);

  neorv32_uart0_printf("╠═════════════╩═══════════╩═══════╩═════════════╣\n");

  // Softmax probabilities
  neorv32_uart0_printf("║                                               ║\n");
  neorv32_uart0_printf("║ Class Probabilities (final softmax):          ║\n");
  for (int i = 0; i < 10; i++) {
    int prob_pct = (int)(softmax_out[i] * 100);
    neorv32_uart0_printf("║   Digit %d: %3d%%", i, prob_pct);
    // Bar chart
    int bars = prob_pct / 5;
    neorv32_uart0_printf(" ");
    for (int b = 0; b < bars && b < 20; b++) neorv32_uart0_printf("█");
    for (int b = bars; b < 20; b++) neorv32_uart0_printf(" ");
    neorv32_uart0_printf("║\n");
  }

  neorv32_uart0_printf("╚═══════════════════════════════════════════════╝\n\n");

  // CFS Performance counters
  neurisa_perf_t cfs_perf;
  neurisa_cfs_read_perf(&cfs_perf);
  neorv32_uart0_printf("CFS Engine: %u cycles, %u MAC ops\n", cfs_perf.cycles, cfs_perf.ops);

  // Summary
  neorv32_uart0_printf("\n=== NeurISA ISA Extension Summary ===\n");
  neorv32_uart0_printf("Custom Instructions: VMAC, VDOT, VRELU, VPOOL,\n");
  neorv32_uart0_printf("  VQUANT, VDEQUANT, VADD, VSUB, VMUL, VABS,\n");
  neorv32_uart0_printf("  VSCALE, VSHIFT, CNN_CFG, CNN_STATUS\n");
  neorv32_uart0_printf("CNN Accelerator: 3x3 Conv + ReLU + MaxPool\n");
  neorv32_uart0_printf("Target: NEORV32 on Zynq-7000 ZC-706\n");
  neorv32_uart0_printf("Data Format: INT8 quantized (4-wide SIMD)\n\n");

  neorv32_uart0_printf("[DEMO COMPLETE]\n");

  return 0;
}
