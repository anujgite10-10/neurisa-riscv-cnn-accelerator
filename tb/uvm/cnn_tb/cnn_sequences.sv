// ================================================================================
// NeurISA — CNN UVM Test Sequences
// ================================================================================

`ifndef CNN_SEQUENCES_SV
`define CNN_SEQUENCES_SV

// ============================================================
// Helper: Write a CFS register
// ============================================================
class cnn_write_reg_seq extends uvm_sequence #(cnn_seq_item);
  `uvm_object_utils(cnn_write_reg_seq)
  bit [5:0]  addr;
  bit [31:0] data;

  function new(string name = "cnn_write_reg_seq");
    super.new(name);
  endfunction

  task body();
    cnn_seq_item item = cnn_seq_item::type_id::create("item");
    start_item(item);
    item.is_write = 1;
    item.reg_addr = addr;
    item.wdata    = data;
    finish_item(item);
  endtask
endclass

// ============================================================
// Helper: Read a CFS register
// ============================================================
class cnn_read_reg_seq extends uvm_sequence #(cnn_seq_item);
  `uvm_object_utils(cnn_read_reg_seq)
  bit [5:0]  addr;
  logic [31:0] rdata;

  function new(string name = "cnn_read_reg_seq");
    super.new(name);
  endfunction

  task body();
    cnn_seq_item item = cnn_seq_item::type_id::create("item");
    start_item(item);
    item.is_write = 0;
    item.reg_addr = addr;
    finish_item(item);
    rdata = item.rdata;
  endtask
endclass

// ============================================================
// Test: Configure CNN for a 4×4×1→2 convolution layer
// ============================================================
class cnn_config_test_seq extends uvm_sequence #(cnn_seq_item);
  `uvm_object_utils(cnn_config_test_seq)

  function new(string name = "cnn_config_test_seq");
    super.new(name);
  endfunction

  task body();
    cnn_write_reg_seq wr_seq;

    `uvm_info("CNN_CFG", "Configuring CNN: 4x4x1 -> 2 output channels", UVM_MEDIUM)

    // Configure layer dimensions
    wr_seq = cnn_write_reg_seq::type_id::create("wr_ih");
    wr_seq.addr = REG_CFG_IH; wr_seq.data = 32'd4;
    wr_seq.start(m_sequencer);

    wr_seq = cnn_write_reg_seq::type_id::create("wr_iw");
    wr_seq.addr = REG_CFG_IW; wr_seq.data = 32'd4;
    wr_seq.start(m_sequencer);

    wr_seq = cnn_write_reg_seq::type_id::create("wr_ic");
    wr_seq.addr = REG_CFG_IC; wr_seq.data = 32'd1;
    wr_seq.start(m_sequencer);

    wr_seq = cnn_write_reg_seq::type_id::create("wr_oc");
    wr_seq.addr = REG_CFG_OC; wr_seq.data = 32'd2;
    wr_seq.start(m_sequencer);

    // Stride=1, no padding
    wr_seq = cnn_write_reg_seq::type_id::create("wr_stride");
    wr_seq.addr = REG_CFG_STRIDE; wr_seq.data = 32'h01;
    wr_seq.start(m_sequencer);

    // Control: ReLU activation, no pooling
    wr_seq = cnn_write_reg_seq::type_id::create("wr_ctrl");
    wr_seq.addr = REG_CTRL; wr_seq.data = 32'h00; // don't start yet
    wr_seq.start(m_sequencer);

    `uvm_info("CNN_CFG", "Configuration complete", UVM_MEDIUM)
  endtask
endclass

// ============================================================
// Test: Verify register read-back
// ============================================================
class cnn_reg_readback_seq extends uvm_sequence #(cnn_seq_item);
  `uvm_object_utils(cnn_reg_readback_seq)

  function new(string name = "cnn_reg_readback_seq");
    super.new(name);
  endfunction

  task body();
    cnn_write_reg_seq wr_seq;
    cnn_read_reg_seq  rd_seq;

    `uvm_info("CNN_RB", "Testing register read-back", UVM_MEDIUM)

    // Write then read each config register
    wr_seq = cnn_write_reg_seq::type_id::create("wr");
    wr_seq.addr = REG_CFG_IH; wr_seq.data = 32'd28;
    wr_seq.start(m_sequencer);

    rd_seq = cnn_read_reg_seq::type_id::create("rd");
    rd_seq.addr = REG_CFG_IH;
    rd_seq.start(m_sequencer);

    if (rd_seq.rdata[7:0] !== 8'd28)
      `uvm_error("CNN_RB", $sformatf("IH readback mismatch: got %0d exp 28", rd_seq.rdata[7:0]))
    else
      `uvm_info("CNN_RB", "IH readback OK", UVM_MEDIUM)

    // Test kernel size (fixed 3)
    rd_seq = cnn_read_reg_seq::type_id::create("rd_ks");
    rd_seq.addr = REG_CFG_KS;
    rd_seq.start(m_sequencer);

    if (rd_seq.rdata !== 32'h3)
      `uvm_error("CNN_RB", $sformatf("KS readback mismatch: got %0h exp 3", rd_seq.rdata))
    else
      `uvm_info("CNN_RB", "KS readback OK (fixed=3)", UVM_MEDIUM)

    `uvm_info("CNN_RB", "Register read-back test complete", UVM_MEDIUM)
  endtask
endclass

// ============================================================
// Test: Start CNN and check status
// ============================================================
class cnn_start_test_seq extends uvm_sequence #(cnn_seq_item);
  `uvm_object_utils(cnn_start_test_seq)

  function new(string name = "cnn_start_test_seq");
    super.new(name);
  endfunction

  task body();
    cnn_write_reg_seq wr_seq;
    cnn_read_reg_seq  rd_seq;
    cnn_config_test_seq cfg_seq;

    // First configure
    cfg_seq = cnn_config_test_seq::type_id::create("cfg");
    cfg_seq.start(m_sequencer);

    // Start CNN
    `uvm_info("CNN_START", "Starting CNN engine", UVM_MEDIUM)
    wr_seq = cnn_write_reg_seq::type_id::create("start");
    wr_seq.addr = REG_CTRL; wr_seq.data = 32'h01; // start bit
    wr_seq.start(m_sequencer);

    // Check busy status
    rd_seq = cnn_read_reg_seq::type_id::create("rd_status");
    rd_seq.addr = REG_STATUS;
    rd_seq.start(m_sequencer);

    `uvm_info("CNN_START", $sformatf("Status after start: 0x%08h (busy=%0b)", rd_seq.rdata, rd_seq.rdata[0]), UVM_MEDIUM)

    // Read perf counters
    rd_seq = cnn_read_reg_seq::type_id::create("rd_perf");
    rd_seq.addr = REG_PERF_CYC;
    rd_seq.start(m_sequencer);
    `uvm_info("CNN_START", $sformatf("Cycles: %0d", rd_seq.rdata), UVM_MEDIUM)

    rd_seq = cnn_read_reg_seq::type_id::create("rd_ops");
    rd_seq.addr = REG_PERF_OPS;
    rd_seq.start(m_sequencer);
    `uvm_info("CNN_START", $sformatf("Ops: %0d", rd_seq.rdata), UVM_MEDIUM)
  endtask
endclass

`endif
