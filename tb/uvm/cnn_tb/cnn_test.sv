// ================================================================================
// NeurISA — CNN UVM Tests
// ================================================================================

`ifndef CNN_TEST_SV
`define CNN_TEST_SV

class cnn_base_test extends uvm_test;
  `uvm_component_utils(cnn_base_test)
  cnn_env env;

  function new(string name = "cnn_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = cnn_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    cnn_config_test_seq   cfg_seq;
    cnn_reg_readback_seq  rb_seq;
    cnn_start_test_seq    start_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "========================================", UVM_LOW)
    `uvm_info("TEST", " NeurISA CNN Accelerator — Test Suite   ", UVM_LOW)
    `uvm_info("TEST", "========================================", UVM_LOW)

    cfg_seq = cnn_config_test_seq::type_id::create("cfg_seq");
    cfg_seq.start(env.agent.sqr);

    rb_seq = cnn_reg_readback_seq::type_id::create("rb_seq");
    rb_seq.start(env.agent.sqr);

    start_seq = cnn_start_test_seq::type_id::create("start_seq");
    start_seq.start(env.agent.sqr);

    #1000;
    phase.drop_objection(this);
  endtask
endclass

`endif
