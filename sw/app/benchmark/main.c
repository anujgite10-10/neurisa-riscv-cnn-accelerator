// ================================================================================
// NeurISA — Performance Benchmark Suite
// ================================================================================
// Measures and compares instruction-level and layer-level performance across
// all three execution modes (Software, ISA, CFS).
// ================================================================================

#include <neorv32.h>
#include "neurisa_cnn.h"
#include "neurisa_intrinsics.h"

// ============================================================
// Benchmark Utilities
// ============================================================
#define BENCH_ITERATIONS 100

static uint32_t bench_start, bench_end;
#define BENCH_BEGIN() bench_start = neurisa_get_cycles()
#define BENCH_END()   bench_end = neurisa_get_cycles()
#define BENCH_CYCLES() (bench_end - bench_start)

// ============================================================
// Instruction-Level Benchmarks
// ============================================================
static void bench_instructions(void) {
  volatile uint32_t result;
  uint32_t a = 0x01020304;
  uint32_t b = 0x05060708;

  neorv32_uart0_printf("\n╔═══════════════════════════════════════════╗\n");
  neorv32_uart0_printf("║   Instruction-Level Benchmarks            ║\n");
  neorv32_uart0_printf("╠═══════════════╦═══════════╦═══════════════╣\n");
  neorv32_uart0_printf("║ Instruction   ║ Cycles    ║ Throughput    ║\n");
  neorv32_uart0_printf("╠═══════════════╬═══════════╬═══════════════╣\n");

  // VMAC
  BENCH_BEGIN();
  for (int i = 0; i < BENCH_ITERATIONS; i++) result = NEURISA_VMAC(a, b);
  BENCH_END();
  neorv32_uart0_printf("║ VMAC          ║ %4u/iter ║ %4u MAC/cyc  ║\n",
    BENCH_CYCLES()/BENCH_ITERATIONS, 4*BENCH_ITERATIONS*100/BENCH_CYCLES());

  // VRELU
  BENCH_BEGIN();
  for (int i = 0; i < BENCH_ITERATIONS; i++) result = NEURISA_VRELU(a);
  BENCH_END();
  neorv32_uart0_printf("║ VRELU         ║ %4u/iter ║ %4u ops/cyc  ║\n",
    BENCH_CYCLES()/BENCH_ITERATIONS, 4*BENCH_ITERATIONS*100/BENCH_CYCLES());

  // VPOOL
  BENCH_BEGIN();
  for (int i = 0; i < BENCH_ITERATIONS; i++) result = NEURISA_VPOOL(a);
  BENCH_END();
  neorv32_uart0_printf("║ VPOOL         ║ %4u/iter ║ %4u ops/cyc  ║\n",
    BENCH_CYCLES()/BENCH_ITERATIONS, 4*BENCH_ITERATIONS*100/BENCH_CYCLES());

  // VADD
  BENCH_BEGIN();
  for (int i = 0; i < BENCH_ITERATIONS; i++) result = NEURISA_VADD(a, b);
  BENCH_END();
  neorv32_uart0_printf("║ VADD          ║ %4u/iter ║ %4u ops/cyc  ║\n",
    BENCH_CYCLES()/BENCH_ITERATIONS, 4*BENCH_ITERATIONS*100/BENCH_CYCLES());

  // VSUB
  BENCH_BEGIN();
  for (int i = 0; i < BENCH_ITERATIONS; i++) result = NEURISA_VSUB(a, b);
  BENCH_END();
  neorv32_uart0_printf("║ VSUB          ║ %4u/iter ║ %4u ops/cyc  ║\n",
    BENCH_CYCLES()/BENCH_ITERATIONS, 4*BENCH_ITERATIONS*100/BENCH_CYCLES());

  // VMUL
  BENCH_BEGIN();
  for (int i = 0; i < BENCH_ITERATIONS; i++) result = NEURISA_VMUL(a, b);
  BENCH_END();
  neorv32_uart0_printf("║ VMUL          ║ %4u/iter ║ %4u ops/cyc  ║\n",
    BENCH_CYCLES()/BENCH_ITERATIONS, 4*BENCH_ITERATIONS*100/BENCH_CYCLES());

  // VABS
  BENCH_BEGIN();
  for (int i = 0; i < BENCH_ITERATIONS; i++) result = NEURISA_VABS(a);
  BENCH_END();
  neorv32_uart0_printf("║ VABS          ║ %4u/iter ║ %4u ops/cyc  ║\n",
    BENCH_CYCLES()/BENCH_ITERATIONS, 4*BENCH_ITERATIONS*100/BENCH_CYCLES());

  // Software MAC comparison
  BENCH_BEGIN();
  for (int i = 0; i < BENCH_ITERATIONS; i++) {
    volatile int32_t sw_result = 0;
    int8_t *pa = (int8_t*)&a;
    int8_t *pb = (int8_t*)&b;
    for (int j = 0; j < 4; j++) sw_result += (int32_t)pa[j] * (int32_t)pb[j];
    result = sw_result;
  }
  BENCH_END();
  neorv32_uart0_printf("║ SW MAC (ref)  ║ %4u/iter ║ %4u MAC/cyc  ║\n",
    BENCH_CYCLES()/BENCH_ITERATIONS, 4*BENCH_ITERATIONS*100/BENCH_CYCLES());

  neorv32_uart0_printf("╚═══════════════╩═══════════╩═══════════════╝\n");
  (void)result;
}

// ============================================================
// Layer-Level Benchmarks
// ============================================================
static int8_t bench_input[1*8*8];
static int8_t bench_output[1*6*6];
static int8_t bench_weights[9];
static int32_t bench_bias[1] = {0};

static void bench_layers(void) {
  // Initialize test data
  for (int i = 0; i < 64; i++) bench_input[i] = (int8_t)(i & 0x7F);
  for (int i = 0; i < 9; i++) bench_weights[i] = (int8_t)(i - 4);

  neurisa_layer_cfg_t cfg = {
    .input_h = 8, .input_w = 8, .input_ch = 1, .output_ch = 1,
    .kernel_size = 3, .stride = 1, .padding = 0,
    .act_mode = 0, .pool_en = 0, .pool_mode = 0
  };

  neorv32_uart0_printf("\n╔═══════════════════════════════════════════╗\n");
  neorv32_uart0_printf("║   Layer-Level Benchmarks (8x8x1 Conv3x3) ║\n");
  neorv32_uart0_printf("╠═══════════════╦═══════════╦═══════════════╣\n");
  neorv32_uart0_printf("║ Mode          ║ Cycles    ║ Speedup       ║\n");
  neorv32_uart0_printf("╠═══════════════╬═══════════╬═══════════════╣\n");

  // Software
  BENCH_BEGIN();
  neurisa_conv2d(bench_input, bench_output, bench_weights, bench_bias, &cfg, NEURISA_MODE_SOFTWARE);
  BENCH_END();
  uint32_t sw = BENCH_CYCLES();
  neorv32_uart0_printf("║ SOFTWARE      ║ %9u ║   1.0x        ║\n", sw);

  // ISA Accelerated
  BENCH_BEGIN();
  neurisa_conv2d(bench_input, bench_output, bench_weights, bench_bias, &cfg, NEURISA_MODE_ISA_ACCEL);
  BENCH_END();
  uint32_t isa = BENCH_CYCLES();
  neorv32_uart0_printf("║ ISA_ACCEL     ║ %9u ║   %u.%ux        ║\n",
    isa, (sw*10/isa)/10, (sw*10/isa)%10);

  // ReLU benchmark
  int8_t relu_data[64];
  for (int i = 0; i < 64; i++) relu_data[i] = (int8_t)(i - 32);

  BENCH_BEGIN();
  neurisa_relu(relu_data, 64, NEURISA_MODE_SOFTWARE);
  BENCH_END();
  uint32_t relu_sw = BENCH_CYCLES();

  for (int i = 0; i < 64; i++) relu_data[i] = (int8_t)(i - 32);
  BENCH_BEGIN();
  neurisa_relu(relu_data, 64, NEURISA_MODE_ISA_ACCEL);
  BENCH_END();
  uint32_t relu_isa = BENCH_CYCLES();

  neorv32_uart0_printf("╠═══════════════╬═══════════╬═══════════════╣\n");
  neorv32_uart0_printf("║ ReLU SW       ║ %9u ║   1.0x        ║\n", relu_sw);
  neorv32_uart0_printf("║ ReLU ISA      ║ %9u ║   %u.%ux        ║\n",
    relu_isa, (relu_sw*10/relu_isa)/10, (relu_sw*10/relu_isa)%10);

  neorv32_uart0_printf("╚═══════════════╩═══════════╩═══════════════╝\n");
}

// ============================================================
// Main
// ============================================================
int main(void) {
  neorv32_uart0_setup(19200, 0);
  neurisa_init();

  neorv32_uart0_printf("\n╔══════════════════════════════════════════════════╗\n");
  neorv32_uart0_printf("║      NeurISA Performance Benchmark Suite        ║\n");
  neorv32_uart0_printf("║      NEORV32 on Zynq-7000 ZC-706               ║\n");
  neorv32_uart0_printf("╚══════════════════════════════════════════════════╝\n");

  bench_instructions();
  bench_layers();

  neorv32_uart0_printf("\n[BENCHMARK COMPLETE]\n");
  return 0;
}
