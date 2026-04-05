// ================================================================================
// NeurISA — CFU UVM Top-Level Test
// ================================================================================

`ifndef CFU_TEST_SV
`define CFU_TEST_SV

// ============================================================
// Base test — runs all directed sequences
// ============================================================
class cfu_base_test extends uvm_test;
  `uvm_component_utils(cfu_base_test)

  cfu_env env;

  function new(string name = "cfu_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = cfu_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    vmac_basic_seq     vmac_seq;
    vrelu_boundary_seq vrelu_seq;
    vpool_seq          pool_s;
    vadd_sub_seq       vadd_s;
    vmul_seq           mul_s;
    vabs_seq           abs_s;

    phase.raise_objection(this);

    `uvm_info("TEST", "========================================", UVM_LOW)
    `uvm_info("TEST", " NeurISA CFU — Directed Test Suite      ", UVM_LOW)
    `uvm_info("TEST", "========================================", UVM_LOW)

    // Run all directed test sequences
    vmac_seq = vmac_basic_seq::type_id::create("vmac_seq");
    vmac_seq.start(env.agent.sqr);

    vrelu_seq = vrelu_boundary_seq::type_id::create("vrelu_seq");
    vrelu_seq.start(env.agent.sqr);

    pool_s = vpool_seq::type_id::create("pool_s");
    pool_s.start(env.agent.sqr);

    vadd_s = vadd_sub_seq::type_id::create("vadd_s");
    vadd_s.start(env.agent.sqr);

    mul_s = vmul_seq::type_id::create("mul_s");
    mul_s.start(env.agent.sqr);

    abs_s = vabs_seq::type_id::create("abs_s");
    abs_s.start(env.agent.sqr);

    #100;
    phase.drop_objection(this);
  endtask

endclass

// ============================================================
// Stress test — 10K+ randomized transactions
// ============================================================
class cfu_stress_test extends uvm_test;
  `uvm_component_utils(cfu_stress_test)

  cfu_env env;

  function new(string name = "cfu_stress_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = cfu_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    random_stress_seq stress_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "========================================", UVM_LOW)
    `uvm_info("TEST", " NeurISA CFU — Stress Test (10K txn)    ", UVM_LOW)
    `uvm_info("TEST", "========================================", UVM_LOW)

    stress_seq = random_stress_seq::type_id::create("stress_seq");
    stress_seq.start(env.agent.sqr);

    #100;
    phase.drop_objection(this);
  endtask
endclass

// ============================================================
// Coverage test — hit all cross-coverage bins
// ============================================================
class cfu_coverage_test extends uvm_test;
  `uvm_component_utils(cfu_coverage_test)

  cfu_env env;

  function new(string name = "cfu_coverage_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = cfu_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    coverage_driven_seq cov_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "========================================", UVM_LOW)
    `uvm_info("TEST", " NeurISA CFU — Coverage-Driven Test     ", UVM_LOW)
    `uvm_info("TEST", "========================================", UVM_LOW)

    cov_seq = coverage_driven_seq::type_id::create("cov_seq");
    cov_seq.start(env.agent.sqr);

    #100;
    phase.drop_objection(this);
  endtask
endclass

// ============================================================
// Full regression — directed + stress + coverage
// ============================================================
class cfu_full_regression_test extends uvm_test;
  `uvm_component_utils(cfu_full_regression_test)

  cfu_env env;

  function new(string name = "cfu_full_regression_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = cfu_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    vmac_basic_seq     vmac_seq;
    vrelu_boundary_seq vrelu_seq;
    vpool_seq          pool_s;
    vadd_sub_seq       vadd_s;
    vmul_seq           mul_s;
    vabs_seq           abs_s;
    random_stress_seq  stress_seq;
    coverage_driven_seq cov_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "========================================", UVM_LOW)
    `uvm_info("TEST", " NeurISA CFU — Full Regression Suite    ", UVM_LOW)
    `uvm_info("TEST", "========================================", UVM_LOW)

    // Phase 1: Directed tests
    `uvm_info("TEST", "--- Phase 1: Directed Tests ---", UVM_LOW)
    vmac_seq = vmac_basic_seq::type_id::create("vmac_seq");
    vmac_seq.start(env.agent.sqr);
    vrelu_seq = vrelu_boundary_seq::type_id::create("vrelu_seq");
    vrelu_seq.start(env.agent.sqr);
    pool_s = vpool_seq::type_id::create("pool_s");
    pool_s.start(env.agent.sqr);
    vadd_s = vadd_sub_seq::type_id::create("vadd_s");
    vadd_s.start(env.agent.sqr);
    mul_s = vmul_seq::type_id::create("mul_s");
    mul_s.start(env.agent.sqr);
    abs_s = vabs_seq::type_id::create("abs_s");
    abs_s.start(env.agent.sqr);

    // Phase 2: Coverage-driven
    `uvm_info("TEST", "--- Phase 2: Coverage-Driven Tests ---", UVM_LOW)
    cov_seq = coverage_driven_seq::type_id::create("cov_seq");
    cov_seq.start(env.agent.sqr);

    // Phase 3: Stress test
    `uvm_info("TEST", "--- Phase 3: Stress Test ---", UVM_LOW)
    stress_seq = random_stress_seq::type_id::create("stress_seq");
    stress_seq.start(env.agent.sqr);

    #100;
    phase.drop_objection(this);
  endtask
endclass

`endif
