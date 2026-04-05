// ================================================================================
// NeurISA — CFU UVM Sequences
// ================================================================================
// Collection of test sequences for comprehensive CFU verification:
//   1. vmac_basic_seq     — directed VMAC tests
//   2. vrelu_boundary_seq — ReLU boundary/edge cases
//   3. vpool_seq          — max-pool tests
//   4. vadd_sub_seq       — saturating add/subtract
//   5. vmul_seq           — element-wise multiply
//   6. vabs_seq           — absolute value tests
//   7. random_stress_seq  — constrained-random stress (10K+ items)
//   8. coverage_driven_seq— targets coverage holes
// ================================================================================

`ifndef CFU_SEQUENCES_SV
`define CFU_SEQUENCES_SV

// ============================================================
// 1. VMAC Basic Test Sequence
// ============================================================
class vmac_basic_seq extends uvm_sequence #(cfu_seq_item);
  `uvm_object_utils(vmac_basic_seq)

  function new(string name = "vmac_basic_seq");
    super.new(name);
  endfunction

  task body();
    cfu_seq_item item;

    `uvm_info("VMAC_SEQ", "Starting VMAC basic tests", UVM_MEDIUM)

    // Test 1: Simple multiply [1,2,3,4] * [1,1,1,1] = 1+2+3+4 = 10
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0; // R-type
    item.funct3 = VMAC_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h04030201;
    item.rs2 = 32'h01010101;
    finish_item(item);

    // Test 2: Zero vector
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VMAC_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h00000000;
    item.rs2 = 32'hFFFFFFFF;
    finish_item(item);

    // Test 3: Max positive * max positive
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VMAC_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h7F7F7F7F;
    item.rs2 = 32'h7F7F7F7F;
    finish_item(item);

    // Test 4: Negative values [-1,-1,-1,-1] * [1,1,1,1]
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VMAC_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'hFFFFFFFF;
    item.rs2 = 32'h01010101;
    finish_item(item);

    // Test 5: Mixed positive and negative
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VMAC_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h80FF8001; // [-128, -1, -128, 1]
    item.rs2 = 32'h01010101; // [1, 1, 1, 1]
    finish_item(item);

    `uvm_info("VMAC_SEQ", "VMAC basic tests complete", UVM_MEDIUM)
  endtask
endclass

// ============================================================
// 2. VRELU Boundary Test Sequence
// ============================================================
class vrelu_boundary_seq extends uvm_sequence #(cfu_seq_item);
  `uvm_object_utils(vrelu_boundary_seq)

  function new(string name = "vrelu_boundary_seq");
    super.new(name);
  endfunction

  task body();
    cfu_seq_item item;

    `uvm_info("VRELU_SEQ", "Starting VRELU boundary tests", UVM_MEDIUM)

    // All zeros
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VRELU_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h00000000;
    item.rs2 = 32'h00000000;
    finish_item(item);

    // All max positive (should pass through)
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VRELU_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h7F7F7F7F;
    item.rs2 = 32'h00000000;
    finish_item(item);

    // All negative (should become zero)
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VRELU_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h80808080;
    item.rs2 = 32'h00000000;
    finish_item(item);

    // Mixed positive and negative
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VRELU_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h807F80FF; // [-128, 127, -128, -1]
    item.rs2 = 32'h00000000;
    finish_item(item);

    // Boundary: -1 (0xFF) should become 0
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VRELU_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'hFFFFFFFF;
    item.rs2 = 32'h00000000;
    finish_item(item);

    `uvm_info("VRELU_SEQ", "VRELU boundary tests complete", UVM_MEDIUM)
  endtask
endclass

// ============================================================
// 3. VPOOL Test Sequence
// ============================================================
class vpool_seq extends uvm_sequence #(cfu_seq_item);
  `uvm_object_utils(vpool_seq)

  function new(string name = "vpool_seq");
    super.new(name);
  endfunction

  task body();
    cfu_seq_item item;

    `uvm_info("VPOOL_SEQ", "Starting VPOOL tests", UVM_MEDIUM)

    // Max is in byte0
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VPOOL_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h01020304; // [1,2,3,4] -> max=4
    item.rs2 = 32'h00000000;
    finish_item(item);

    // All same values
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VPOOL_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h05050505;
    item.rs2 = 32'h00000000;
    finish_item(item);

    // Negative values
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VPOOL_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'hFEFDFCFB; // [-2,-3,-4,-5] -> max=-2
    item.rs2 = 32'h00000000;
    finish_item(item);

    `uvm_info("VPOOL_SEQ", "VPOOL tests complete", UVM_MEDIUM)
  endtask
endclass

// ============================================================
// 4. VADD/VSUB Saturating Arithmetic Sequence
// ============================================================
class vadd_sub_seq extends uvm_sequence #(cfu_seq_item);
  `uvm_object_utils(vadd_sub_seq)

  function new(string name = "vadd_sub_seq");
    super.new(name);
  endfunction

  task body();
    cfu_seq_item item;

    `uvm_info("VADD_SEQ", "Starting VADD/VSUB saturation tests", UVM_MEDIUM)

    // Normal addition
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VADD_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h01020304;
    item.rs2 = 32'h01010101;
    finish_item(item);

    // Positive saturation: 127 + 1 -> 127
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VADD_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h7F7F7F7F;
    item.rs2 = 32'h01010101;
    finish_item(item);

    // Negative saturation: -128 - 1 -> -128
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VADD_F3;
    item.funct7 = F7_ALT; // VSUB
    item.rs1 = 32'h80808080;
    item.rs2 = 32'h01010101;
    finish_item(item);

    // Subtraction: normal case
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VADD_F3;
    item.funct7 = F7_ALT;
    item.rs1 = 32'h04030201;
    item.rs2 = 32'h01010101;
    finish_item(item);

    `uvm_info("VADD_SEQ", "VADD/VSUB saturation tests complete", UVM_MEDIUM)
  endtask
endclass

// ============================================================
// 5. VMUL Test Sequence
// ============================================================
class vmul_seq extends uvm_sequence #(cfu_seq_item);
  `uvm_object_utils(vmul_seq)

  function new(string name = "vmul_seq");
    super.new(name);
  endfunction

  task body();
    cfu_seq_item item;

    // Simple multiply
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VMUL_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h02020202;
    item.rs2 = 32'h03030303;
    finish_item(item);

    // Multiply by zero
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VMUL_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'hFFFFFFFF;
    item.rs2 = 32'h00000000;
    finish_item(item);
  endtask
endclass

// ============================================================
// 6. VABS Test Sequence
// ============================================================
class vabs_seq extends uvm_sequence #(cfu_seq_item);
  `uvm_object_utils(vabs_seq)

  function new(string name = "vabs_seq");
    super.new(name);
  endfunction

  task body();
    cfu_seq_item item;

    // Positive values (pass through)
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VABS_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'h01027F40;
    item.rs2 = 32'h00000000;
    finish_item(item);

    // Negative values
    item = cfu_seq_item::type_id::create("item");
    start_item(item);
    item.instr_type = 0;
    item.funct3 = VABS_F3;
    item.funct7 = F7_DEFAULT;
    item.rs1 = 32'hFFFeFC80; // [-1,-2,-4,-128]
    item.rs2 = 32'h00000000;
    finish_item(item);
  endtask
endclass

// ============================================================
// 7. Constrained-Random Stress Sequence (10K+ transactions)
// ============================================================
class random_stress_seq extends uvm_sequence #(cfu_seq_item);
  `uvm_object_utils(random_stress_seq)

  int unsigned num_transactions = 10000;

  function new(string name = "random_stress_seq");
    super.new(name);
  endfunction

  task body();
    cfu_seq_item item;

    `uvm_info("STRESS_SEQ", $sformatf("Starting random stress test: %0d transactions", num_transactions), UVM_MEDIUM)

    for (int i = 0; i < num_transactions; i++) begin
      item = cfu_seq_item::type_id::create($sformatf("item_%0d", i));
      start_item(item);
      if (!item.randomize() with {
        // Bias towards R-type for better instruction coverage
        instr_type dist {0 := 80, 1 := 20};
      }) begin
        `uvm_error("STRESS_SEQ", "Randomization failed")
      end
      finish_item(item);
    end

    `uvm_info("STRESS_SEQ", "Random stress test complete", UVM_MEDIUM)
  endtask
endclass

// ============================================================
// 8. Coverage-Driven Sequence
// ============================================================
class coverage_driven_seq extends uvm_sequence #(cfu_seq_item);
  `uvm_object_utils(coverage_driven_seq)

  function new(string name = "coverage_driven_seq");
    super.new(name);
  endfunction

  task body();
    cfu_seq_item item;

    `uvm_info("COV_SEQ", "Starting coverage-driven tests", UVM_MEDIUM)

    // Systematically hit all instruction × operand combinations
    for (int f3 = 0; f3 < 8; f3++) begin
      for (int f7 = 0; f7 < 2; f7++) begin
        // Edge case: zero operands
        item = cfu_seq_item::type_id::create("item");
        start_item(item);
        item.instr_type = 0;
        item.funct3 = f3;
        item.funct7 = f7 ? F7_ALT : F7_DEFAULT;
        item.rs1 = 32'h00000000;
        item.rs2 = 32'h00000000;
        finish_item(item);

        // Edge case: max positive
        item = cfu_seq_item::type_id::create("item");
        start_item(item);
        item.instr_type = 0;
        item.funct3 = f3;
        item.funct7 = f7 ? F7_ALT : F7_DEFAULT;
        item.rs1 = 32'h7F7F7F7F;
        item.rs2 = 32'h7F7F7F7F;
        finish_item(item);

        // Edge case: max negative
        item = cfu_seq_item::type_id::create("item");
        start_item(item);
        item.instr_type = 0;
        item.funct3 = f3;
        item.funct7 = f7 ? F7_ALT : F7_DEFAULT;
        item.rs1 = 32'h80808080;
        item.rs2 = 32'h80808080;
        finish_item(item);

        // Edge case: all ones
        item = cfu_seq_item::type_id::create("item");
        start_item(item);
        item.instr_type = 0;
        item.funct3 = f3;
        item.funct7 = f7 ? F7_ALT : F7_DEFAULT;
        item.rs1 = 32'hFFFFFFFF;
        item.rs2 = 32'hFFFFFFFF;
        finish_item(item);
      end
    end

    // I-type instructions
    for (int f3 = 0; f3 < 4; f3++) begin
      item = cfu_seq_item::type_id::create("item");
      start_item(item);
      item.instr_type = 1;
      item.funct3 = f3;
      item.imm12 = 12'h000;
      item.rs1 = 32'h12345678;
      finish_item(item);

      item = cfu_seq_item::type_id::create("item");
      start_item(item);
      item.instr_type = 1;
      item.funct3 = f3;
      item.imm12 = 12'hFFF;
      item.rs1 = 32'hDEADBEEF;
      finish_item(item);
    end

    `uvm_info("COV_SEQ", "Coverage-driven tests complete", UVM_MEDIUM)
  endtask
endclass

`endif
