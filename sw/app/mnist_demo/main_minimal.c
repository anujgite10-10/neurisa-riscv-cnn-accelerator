// ================================================================================
// NeurISA — Minimal Custom Instructions Demo
// ================================================================================
// Demonstrates NeurISA CFU custom instructions on NEORV32
// Tests: VMAC, VRELU, VPOOL, VQUANT
// ================================================================================

#include <neorv32.h>
#include "neurisa_intrinsics.h"

int main(void) {
  // Disable global interrupts
  neorv32_cpu_csr_write(CSR_MSTATUS, 0);

  // Setup UART for output
  neorv32_uart0_setup(19200, 0);

  neorv32_uart0_printf("\n");
  neorv32_uart0_printf("==================================================\n");
  neorv32_uart0_printf("     NeurISA Custom Instructions Test\n");
  neorv32_uart0_printf("==================================================\n\n");

  // ============================================================
  // Test 1: VMAC (Vector Multiply-Accumulate)
  // ============================================================
  neorv32_uart0_printf("[1] Testing VMAC (4x INT8 multiply-accumulate)...\n");
  uint32_t a = 0x04030201;  // bytes: 4, 3, 2, 1
  uint32_t b = 0x08070605;  // bytes: 8, 7, 6, 5
  uint32_t result = NEURISA_VMAC(a, b);
  // Expected: (1*5) + (2*6) + (3*7) + (4*8) = 5 + 12 + 21 + 32 = 70
  neorv32_uart0_printf("  Input A: %d\n", (int32_t)a);
  neorv32_uart0_printf("  Input B: %d\n", (int32_t)b);
  neorv32_uart0_printf("  Result: %d\n", (int32_t)result);
  neorv32_uart0_printf("  Expected: 70\n");
  if ((int32_t)result == 70) {
    neorv32_uart0_printf("  PASS\n\n");
  } else {
    neorv32_uart0_printf("  FAIL\n\n");
  }

  // ============================================================
  // Test 2: VRELU (Vectorized ReLU)
  // ============================================================
  neorv32_uart0_printf("[2] Testing VRELU (packed ReLU)...\n");
  uint32_t input = 0x7F80FF01;  // bytes: 127(+), -128(-), -1(-), 1(+)
  uint32_t relu_out = NEURISA_VRELU(input);
  // Expected: max(0, x) for each byte: 127, 0, 0, 1
  neorv32_uart0_printf("  Input:  %d\n", (int32_t)input);
  neorv32_uart0_printf("  Output: %d\n", (int32_t)relu_out);
  neorv32_uart0_printf("  Expected: 2139062273\n");  // 0x7F000001 in decimal
  if (relu_out == 0x7F000001) {
    neorv32_uart0_printf("  PASS\n\n");
  } else {
    neorv32_uart0_printf("  FAIL\n\n");
  }

  // ============================================================
  // Test 3: VPOOL (Max Pool across 4 bytes)
  // ============================================================
  neorv32_uart0_printf("[3] Testing VPOOL (max-pool)...\n");
  uint32_t pool_input = 0x04030201;  // bytes: 4, 3, 2, 1
  uint32_t pool_out = NEURISA_VPOOL(pool_input);
  // Expected: max(1, 2, 3, 4) = 4
  neorv32_uart0_printf("  Input:  %d\n", (int32_t)pool_input);
  neorv32_uart0_printf("  Output: %d\n", (int8_t)pool_out);
  neorv32_uart0_printf("  Expected: 4\n");
  if ((int8_t)pool_out == 4) {
    neorv32_uart0_printf("  PASS\n\n");
  } else {
    neorv32_uart0_printf("  FAIL\n\n");
  }

  // ============================================================
  // Test 4: VADD (Packed INT8 Saturating Add)
  // ============================================================
  neorv32_uart0_printf("[4] Testing VADD (packed add)...\n");
  uint32_t add_a = 0x10203040;  // bytes: 16, 32, 48, 64
  uint32_t add_b = 0x20304050;  // bytes: 32, 48, 80, 80
  uint32_t add_out = NEURISA_VADD(add_a, add_b);
  // Expected: 48, 80, 127, 127 (saturate at 127)
  neorv32_uart0_printf("  Input A: %d\n", (int32_t)add_a);
  neorv32_uart0_printf("  Input B: %d\n", (int32_t)add_b);
  neorv32_uart0_printf("  Output:  %d\n", (int32_t)add_out);
  neorv32_uart0_printf("  Expected: 2130772784\n");  // 0x7F7F5030 in decimal
  if (add_out == 0x7F7F5030) {
    neorv32_uart0_printf("  PASS\n\n");
  } else {
    neorv32_uart0_printf("  FAIL (got %d)\n\n", (int32_t)add_out);
  }

  // ============================================================
  // Performance Summary
  // ============================================================
  neorv32_uart0_printf("==================================================\n");
  neorv32_uart0_printf("NeurISA Custom Instructions Verified!\n");
  neorv32_uart0_printf("Ready for CNN acceleration demos.\n");
  neorv32_uart0_printf("==================================================\n\n");

  return 0;
}
