// ================================================================================
// NeurISA - Full Demo: ISA Self-Test + Digit Classification
// ================================================================================
// Part 1: Verifies all NeurISA custom instructions on FPGA hardware
// Part 2: Classifies handwritten digits using VMAC-accelerated template matching
// ================================================================================

#include <neorv32.h>

// ============================================================
// NeurISA Intrinsics
// ============================================================
#define PACK_I8(b3, b2, b1, b0) \
  ((uint32_t)((uint8_t)(b0)) | ((uint32_t)((uint8_t)(b1)) << 8) | \
   ((uint32_t)((uint8_t)(b2)) << 16) | ((uint32_t)((uint8_t)(b3)) << 24))

static inline int8_t UNPACK_I8(uint32_t packed, int idx) {
  return (int8_t)((packed >> (idx * 8)) & 0xFF);
}

static inline uint32_t __cfu_r(uint32_t rs1, uint32_t rs2, uint32_t f3, uint32_t f7) {
  uint32_t result;
  asm volatile (".insn r 0x0B, %3, %4, %0, %1, %2"
    : "=r"(result) : "r"(rs1), "r"(rs2), "i"(f3), "i"(f7));
  return result;
}

#define VMAC(a, b)     __cfu_r((a), (b), 0, 0)
#define VRELU(a)       __cfu_r((a), 0, 2, 0)
#define VPOOL(a)       __cfu_r((a), 0, 3, 0)
#define VADD(a, b)     __cfu_r((a), (b), 5, 0)
#define VSUB(a, b)     __cfu_r((a), (b), 5, 1)
#define VMUL(a, b)     __cfu_r((a), (b), 6, 0)
#define VABS(a)        __cfu_r((a), 0, 7, 0)

// ============================================================
// Test tracking
// ============================================================
static int pass_count = 0;
static int fail_count = 0;

static void check(const char *name, uint32_t got, uint32_t expected) {
  if (got == expected) {
    neorv32_uart0_printf("  [PASS] %s = 0x%x\n", name, got);
    pass_count++;
  } else {
    neorv32_uart0_printf("  [FAIL] %s = 0x%x (exp 0x%x)\n", name, got, expected);
    fail_count++;
  }
}

static void check_byte(const char *name, uint32_t result, int idx, int8_t expected) {
  int8_t got = UNPACK_I8(result, idx);
  if (got == expected) { pass_count++; }
  else {
    neorv32_uart0_printf("  [FAIL] %s[%d]=%d (exp %d)\n", name, idx, got, expected);
    fail_count++;
  }
}

// ============================================================
// Digit images (8x8 INT8)
// ============================================================
static const int8_t image_7[64] = {
   0,  0,  0,  0,  0,  0,  0,  0,
   0,  0, 80,127,127,127, 80,  0,
   0,  0,  0,  0,  0,100,100,  0,
   0,  0,  0,  0, 80,120,  0,  0,
   0,  0,  0, 60,120,  0,  0,  0,
   0,  0, 60,120,  0,  0,  0,  0,
   0,  0,100, 80,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0 };
static const int8_t image_3[64] = {
   0,  0,  0,  0,  0,  0,  0,  0,
   0, 40,100,127,127, 80,  0,  0,
   0,  0,  0,  0, 60,120,  0,  0,
   0,  0, 40,100,120, 40,  0,  0,
   0,  0,  0,  0, 40,120,  0,  0,
   0,  0,  0,  0, 60,100,  0,  0,
   0, 40,100,127,120, 40,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0 };
static const int8_t image_1[64] = {
   0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0, 80,120,  0,  0,  0,
   0,  0, 60,127,120,  0,  0,  0,
   0,  0,  0, 80,120,  0,  0,  0,
   0,  0,  0, 80,120,  0,  0,  0,
   0,  0,  0, 80,120,  0,  0,  0,
   0,  0, 40,120,127, 80,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0 };

// ============================================================
// Digit templates (10 x 64 bytes = 640 bytes)
// ============================================================
static const int8_t templates[10][64] = {
  { 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 60,100,100, 60, 0, 0,  0, 60,100, 0, 0,100, 60, 0,
    0,100, 60, 0, 0, 60,100, 0,  0,100, 60, 0, 0, 60,100, 0,  0, 60,100, 0, 0,100, 60, 0,
    0, 0, 60,100,100, 60, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0 },
  { 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 80,120, 0, 0, 0,  0, 0, 60,120,120, 0, 0, 0,
    0, 0, 0, 80,120, 0, 0, 0,  0, 0, 0, 80,120, 0, 0, 0,  0, 0, 0, 80,120, 0, 0, 0,
    0, 0, 40,120,120, 80, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0 },
  { 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 60,100,100, 60, 0, 0,  0, 0, 0, 0, 60,100, 0, 0,
    0, 0, 0, 60,100, 0, 0, 0,  0, 0, 60,100, 0, 0, 0, 0,  0, 60,100, 0, 0, 0, 0, 0,
    0, 60,100,100,100,100, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0 },
  { 0, 0, 0, 0, 0, 0, 0, 0,  0, 40,100,120,120, 80, 0, 0,  0, 0, 0, 0, 60,100, 0, 0,
    0, 0, 40,100,100, 40, 0, 0,  0, 0, 0, 0, 60,100, 0, 0,  0, 0, 0, 0, 60,100, 0, 0,
    0, 40,100,120,100, 40, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0 },
  { 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 80, 0, 0, 80, 0, 0,  0, 0,100, 0, 0,100, 0, 0,
    0, 0,100, 0, 60,100, 0, 0,  0, 0,100,100,100,100, 0, 0,  0, 0, 0, 0, 0,100, 0, 0,
    0, 0, 0, 0, 0,100, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0 },
  { 0, 0, 0, 0, 0, 0, 0, 0,  0, 60,100,100,100, 60, 0, 0,  0, 60,100, 0, 0, 0, 0, 0,
    0, 60,100,100,100, 60, 0, 0,  0, 0, 0, 0, 0,100, 60, 0,  0, 0, 0, 0, 60,100, 0, 0,
    0, 60,100,100,100, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0 },
  { 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 60,100,100, 0, 0, 0,  0, 60,100, 0, 0, 0, 0, 0,
    0,100,100,100,100, 60, 0, 0,  0,100, 60, 0, 0,100, 0, 0,  0,100, 60, 0, 60,100, 0, 0,
    0, 0, 60,100,100, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0 },
  { 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 80,120,120,120, 80, 0,  0, 0, 0, 0, 0,100,100, 0,
    0, 0, 0, 0, 80,100, 0, 0,  0, 0, 0, 60,100, 0, 0, 0,  0, 0, 60,100, 0, 0, 0, 0,
    0, 0,100, 80, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0 },
  { 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 60,100,100, 60, 0, 0,  0, 60,100, 0, 0,100, 60, 0,
    0, 0, 60,100,100, 60, 0, 0,  0, 60,100, 0, 0,100, 60, 0,  0, 60,100, 0, 0,100, 60, 0,
    0, 0, 60,100,100, 60, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0 },
  { 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 60,100,100, 60, 0, 0,  0, 60,100, 0, 0,100, 0, 0,
    0, 60,100, 0, 60,100, 0, 0,  0, 0, 60,100,100,100, 0, 0,  0, 0, 0, 0, 60,100, 0, 0,
    0, 0, 60,100,100, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0 },
};

// ============================================================
// Dot product: SW and ISA versions
// ============================================================
static int32_t sw_dot(const int8_t *a, const int8_t *b, int n) {
  int32_t sum = 0;
  for (int i = 0; i < n; i++) sum += (int32_t)a[i] * (int32_t)b[i];
  return sum;
}

static int32_t isa_dot(const int8_t *a, const int8_t *b, int n) {
  int32_t sum = 0;
  for (int i = 0; i < n; i += 4) {
    uint32_t va = PACK_I8(a[i+3], a[i+2], a[i+1], a[i]);
    uint32_t vb = PACK_I8(b[i+3], b[i+2], b[i+1], b[i]);
    sum += (int32_t)VMAC(va, vb);
  }
  return sum;
}

static int classify(const int8_t *img, int use_isa) {
  int best = 0;
  int32_t best_score = use_isa ? isa_dot(img, templates[0], 64) : sw_dot(img, templates[0], 64);
  for (int d = 1; d < 10; d++) {
    int32_t s = use_isa ? isa_dot(img, templates[d], 64) : sw_dot(img, templates[d], 64);
    if (s > best_score) { best_score = s; best = d; }
  }
  return best;
}

static void print_image(const int8_t *img) {
  for (int r = 0; r < 8; r++) {
    neorv32_uart0_printf("    ");
    for (int c = 0; c < 8; c++) {
      if (img[r*8+c] > 80)       neorv32_uart0_printf("##");
      else if (img[r*8+c] > 30)  neorv32_uart0_printf("..");
      else                        neorv32_uart0_printf("  ");
    }
    neorv32_uart0_printf("\n");
  }
}

// ============================================================
// Main
// ============================================================
int main(void) {
  uint32_t a, b, r, t0, t1;

  neorv32_uart0_setup(19200, 0);

  neorv32_uart0_printf("\n\n");
  neorv32_uart0_printf("=========================================\n");
  neorv32_uart0_printf("  NeurISA - Full Hardware Demo\n");
  neorv32_uart0_printf("  NEORV32 on Zynq-7000 ZC-706\n");
  neorv32_uart0_printf("=========================================\n\n");

  if (neorv32_cfu_available() == 0) {
    neorv32_uart0_printf("[ERROR] CFU not found!\n");
    return 1;
  }
  neorv32_uart0_printf("[OK] NeurISA CFU detected\n\n");

  // ===========================
  // PART 1: ISA INSTRUCTION TESTS
  // ===========================
  neorv32_uart0_printf("========== PART 1: ISA SELF-TEST ==========\n\n");

  // TEST: VMAC
  neorv32_uart0_printf("--- VMAC (4x INT8 MAC) ---\n");
  a = PACK_I8(4, 3, 2, 1); b = PACK_I8(1, 1, 1, 1);
  check("VMAC([4,3,2,1]*[1,1,1,1])", VMAC(a, b), 10);
  a = PACK_I8(10, 20, 30, 40); b = PACK_I8(1, 2, 3, 4);
  check("VMAC([10,20,30,40]*[1,2,3,4])", VMAC(a, b), 300);

  // TEST: VRELU
  neorv32_uart0_printf("\n--- VRELU (Packed ReLU) ---\n");
  a = PACK_I8(127, -128, 10, -5);
  r = VRELU(a);
  check_byte("VRELU", r, 0, 0);    // -5 -> 0
  check_byte("VRELU", r, 1, 10);   // 10 -> 10
  check_byte("VRELU", r, 2, 0);    // -128 -> 0
  check_byte("VRELU", r, 3, 127);  // 127 -> 127
  neorv32_uart0_printf("  [INFO] VRELU(7F800AFB) = 0x%x\n", r);

  // TEST: VPOOL
  neorv32_uart0_printf("\n--- VPOOL (Max Pooling) ---\n");
  a = PACK_I8(4, 3, 2, 1);
  check("VPOOL([4,3,2,1])", VPOOL(a) & 0xFF, 4);
  a = PACK_I8(10, 50, 30, 20);
  check("VPOOL([10,50,30,20])", VPOOL(a) & 0xFF, 50);

  // TEST: VADD
  neorv32_uart0_printf("\n--- VADD (Saturating Add) ---\n");
  a = PACK_I8(4, 3, 2, 1); b = PACK_I8(1, 1, 1, 1);
  check("VADD([4,3,2,1]+[1,1,1,1])", VADD(a, b), PACK_I8(5, 4, 3, 2));
  a = PACK_I8(1, 1, 1, 120); b = PACK_I8(1, 1, 1, 30);
  r = VADD(a, b);
  check_byte("VADD_SAT(120+30)", r, 0, 127);

  // TEST: VSUB
  neorv32_uart0_printf("\n--- VSUB (Saturating Sub) ---\n");
  a = PACK_I8(4, 3, 2, 1); b = PACK_I8(1, 1, 1, 1);
  check("VSUB([4,3,2,1]-[1,1,1,1])", VSUB(a, b), PACK_I8(3, 2, 1, 0));

  // TEST: VMUL
  neorv32_uart0_printf("\n--- VMUL (Element Multiply) ---\n");
  a = PACK_I8(5, 4, 3, 2); b = PACK_I8(2, 2, 2, 3);
  check("VMUL([5,4,3,2]*[2,2,2,3])", VMUL(a, b), PACK_I8(10, 8, 6, 6));

  // TEST: VABS
  neorv32_uart0_printf("\n--- VABS (Absolute Value) ---\n");
  a = PACK_I8(127, -128, 10, -5);
  r = VABS(a);
  check_byte("VABS", r, 0, 5);
  check_byte("VABS", r, 1, 10);
  check_byte("VABS", r, 2, 127);
  check_byte("VABS", r, 3, 127);
  neorv32_uart0_printf("  [INFO] VABS(7F800AFB) = 0x%x\n", r);

  // TEST: CFS Registers
  neorv32_uart0_printf("\n--- CFS CNN Registers ---\n");
  if (neorv32_cfs_available()) {
    NEORV32_CFS->REG[2] = 28;
    NEORV32_CFS->REG[3] = 28;
    NEORV32_CFS->REG[4] = 1;
    NEORV32_CFS->REG[5] = 6;
    check("CFS IH", NEORV32_CFS->REG[2] & 0xFF, 28);
    check("CFS IW", NEORV32_CFS->REG[3] & 0xFF, 28);
    check("CFS IC", NEORV32_CFS->REG[4] & 0xFF, 1);
    check("CFS OC", NEORV32_CFS->REG[5] & 0xFF, 6);
    check("CFS KS", NEORV32_CFS->REG[6], 3);
  } else {
    neorv32_uart0_printf("  [SKIP] CFS not available\n");
  }

  // ISA test summary
  neorv32_uart0_printf("\n>> ISA Tests: %d PASS, %d FAIL\n", pass_count, fail_count);
  if (fail_count == 0) neorv32_uart0_printf(">> ALL ISA TESTS PASSED!\n");

  // Performance benchmark
  neorv32_uart0_printf("\n--- VMAC Throughput ---\n");
  a = PACK_I8(10, 20, 30, 40); b = PACK_I8(1, 2, 3, 4);
  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  volatile uint32_t sum = 0;
  for (int i = 0; i < 1000; i++) sum += VMAC(a, b);
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  neorv32_uart0_printf("  1000x VMAC: %u cycles\n", t1 - t0);
  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  volatile int32_t sw_s = 0;
  int8_t aa[4] = {10, 20, 30, 40}, bb[4] = {1, 2, 3, 4};
  for (int i = 0; i < 1000; i++)
    sw_s += aa[0]*bb[0] + aa[1]*bb[1] + aa[2]*bb[2] + aa[3]*bb[3];
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  neorv32_uart0_printf("  1000x SW MAC: %u cycles\n", t1 - t0);

  // ===========================
  // PART 2: DIGIT CLASSIFICATION
  // ===========================
  neorv32_uart0_printf("\n========== PART 2: DIGIT CLASSIFIER ==========\n");
  neorv32_uart0_printf("Method: Template matching (VMAC dot-product)\n\n");

  const int8_t *images[3] = { image_7, image_3, image_1 };
  const char *names[3]    = { "seven (7)", "three (3)", "one (1)" };
  uint32_t total_sw = 0, total_isa = 0;

  for (int t = 0; t < 3; t++) {
    neorv32_uart0_printf("--- Test: %s ---\n", names[t]);
    print_image(images[t]);

    t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
    int sw_pred = classify(images[t], 0);
    t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
    uint32_t sw_cyc = t1 - t0;
    total_sw += sw_cyc;

    t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
    int isa_pred = classify(images[t], 1);
    t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
    uint32_t isa_cyc = t1 - t0;
    total_isa += isa_cyc;

    uint32_t spd = (sw_cyc * 10) / (isa_cyc > 0 ? isa_cyc : 1);
    neorv32_uart0_printf("  SW  -> digit %d (%u cyc)\n", sw_pred, sw_cyc);
    neorv32_uart0_printf("  ISA -> digit %d (%u cyc)\n", isa_pred, isa_cyc);
    neorv32_uart0_printf("  Speedup: %u.%ux\n\n", spd/10, spd%10);
  }

  uint32_t tspd = (total_sw * 10) / (total_isa > 0 ? total_isa : 1);

  // ===========================
  // PART 3: PERFORMANCE BENCHMARKING
  // ===========================
  neorv32_uart0_printf("========== PART 3: PERF BENCHMARK ==========\n");
  neorv32_uart0_printf("(1000 iterations each, ISA vs SW baseline)\n\n");

  volatile uint32_t sink = 0;
  uint32_t sw_cycles, isa_cycles, spd;

  // --- VMAC benchmark ---
  a = PACK_I8(10, 20, 30, 40); b = PACK_I8(1, 2, 3, 4);
  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  for (int i = 0; i < 1000; i++) sink += VMAC(a, b);
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  isa_cycles = t1 - t0;

  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  { int8_t p[4]={10,20,30,40}, q[4]={1,2,3,4};
    for (int i = 0; i < 1000; i++)
      sink += p[0]*q[0] + p[1]*q[1] + p[2]*q[2] + p[3]*q[3]; }
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  sw_cycles = t1 - t0;
  spd = (sw_cycles * 10) / (isa_cycles > 0 ? isa_cycles : 1);
  neorv32_uart0_printf("  VMAC  : ISA %u | SW %u | %u.%ux\n",
    isa_cycles, sw_cycles, spd/10, spd%10);

  // --- VRELU benchmark ---
  a = PACK_I8(50, -30, 100, -5);
  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  for (int i = 0; i < 1000; i++) sink += VRELU(a);
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  isa_cycles = t1 - t0;

  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  { int8_t v[4] = {50, -30, 100, -5};
    for (int i = 0; i < 1000; i++) {
      int8_t r0 = v[0]>0?v[0]:0, r1 = v[1]>0?v[1]:0;
      int8_t r2 = v[2]>0?v[2]:0, r3 = v[3]>0?v[3]:0;
      sink += r0 + r1 + r2 + r3; } }
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  sw_cycles = t1 - t0;
  spd = (sw_cycles * 10) / (isa_cycles > 0 ? isa_cycles : 1);
  neorv32_uart0_printf("  VRELU : ISA %u | SW %u | %u.%ux\n",
    isa_cycles, sw_cycles, spd/10, spd%10);

  // --- VADD benchmark ---
  a = PACK_I8(10, 20, 30, 40); b = PACK_I8(5, 5, 5, 5);
  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  for (int i = 0; i < 1000; i++) sink += VADD(a, b);
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  isa_cycles = t1 - t0;

  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  { int8_t p[4]={10,20,30,40}, q[4]={5,5,5,5};
    for (int i = 0; i < 1000; i++) {
      int16_t s0=p[0]+q[0], s1=p[1]+q[1], s2=p[2]+q[2], s3=p[3]+q[3];
      if(s0>127)s0=127; if(s1>127)s1=127; if(s2>127)s2=127; if(s3>127)s3=127;
      sink += s0+s1+s2+s3; } }
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  sw_cycles = t1 - t0;
  spd = (sw_cycles * 10) / (isa_cycles > 0 ? isa_cycles : 1);
  neorv32_uart0_printf("  VADD  : ISA %u | SW %u | %u.%ux\n",
    isa_cycles, sw_cycles, spd/10, spd%10);

  // --- VMUL benchmark ---
  a = PACK_I8(5, 4, 3, 2); b = PACK_I8(2, 3, 4, 5);
  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  for (int i = 0; i < 1000; i++) sink += VMUL(a, b);
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  isa_cycles = t1 - t0;

  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  { int8_t p[4]={5,4,3,2}, q[4]={2,3,4,5};
    for (int i = 0; i < 1000; i++) {
      int8_t r0=(int8_t)(p[0]*q[0]), r1=(int8_t)(p[1]*q[1]);
      int8_t r2=(int8_t)(p[2]*q[2]), r3=(int8_t)(p[3]*q[3]);
      sink += r0+r1+r2+r3; } }
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  sw_cycles = t1 - t0;
  spd = (sw_cycles * 10) / (isa_cycles > 0 ? isa_cycles : 1);
  neorv32_uart0_printf("  VMUL  : ISA %u | SW %u | %u.%ux\n",
    isa_cycles, sw_cycles, spd/10, spd%10);

  // --- VABS benchmark ---
  a = PACK_I8(-50, 30, -100, 5);
  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  for (int i = 0; i < 1000; i++) sink += VABS(a);
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  isa_cycles = t1 - t0;

  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  { int8_t v[4] = {-50, 30, -100, 5};
    for (int i = 0; i < 1000; i++) {
      int8_t r0 = v[0]<0?-v[0]:v[0], r1 = v[1]<0?-v[1]:v[1];
      int8_t r2 = v[2]<0?-v[2]:v[2], r3 = v[3]<0?-v[3]:v[3];
      sink += r0+r1+r2+r3; } }
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  sw_cycles = t1 - t0;
  spd = (sw_cycles * 10) / (isa_cycles > 0 ? isa_cycles : 1);
  neorv32_uart0_printf("  VABS  : ISA %u | SW %u | %u.%ux\n",
    isa_cycles, sw_cycles, spd/10, spd%10);

  // --- Dot product benchmark (64-element, classifier workload) ---
  neorv32_uart0_printf("\n  64-elem dot product (classifier):\n");
  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  for (int i = 0; i < 100; i++) sink += sw_dot(image_7, templates[7], 64);
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  sw_cycles = t1 - t0;

  t0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  for (int i = 0; i < 100; i++) sink += isa_dot(image_7, templates[7], 64);
  t1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  isa_cycles = t1 - t0;
  spd = (sw_cycles * 10) / (isa_cycles > 0 ? isa_cycles : 1);
  neorv32_uart0_printf("  DOT64 : ISA %u | SW %u | %u.%ux\n",
    isa_cycles, sw_cycles, spd/10, spd%10);

  // ===========================
  // FINAL SUMMARY
  // ===========================
  neorv32_uart0_printf("\n=========================================\n");
  neorv32_uart0_printf("          NEURISA DEMO SUMMARY\n");
  neorv32_uart0_printf("=========================================\n");
  neorv32_uart0_printf("  ISA Tests:  %d PASS / %d FAIL\n", pass_count, fail_count);
  neorv32_uart0_printf("  Classifier: 3 images tested\n");
  neorv32_uart0_printf("  Total SW:   %u cycles\n", total_sw);
  neorv32_uart0_printf("  Total ISA:  %u cycles\n", total_isa);
  neorv32_uart0_printf("  Speedup:    %u.%ux\n", tspd/10, tspd%10);
  neorv32_uart0_printf("\n  Instructions: VMAC VRELU VPOOL\n");
  neorv32_uart0_printf("    VADD VSUB VMUL VABS\n");
  neorv32_uart0_printf("  CNN Accel:  3x3 Conv + ReLU + Pool\n");
  neorv32_uart0_printf("  Data fmt:   INT8 packed (4-wide SIMD)\n");
  neorv32_uart0_printf("=========================================\n");
  neorv32_uart0_printf("[DEMO COMPLETE]\n");

  return 0;
}

