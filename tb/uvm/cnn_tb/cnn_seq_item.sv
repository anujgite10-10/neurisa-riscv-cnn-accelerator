// ================================================================================
// NeurISA — CNN Sequence Item, Driver, Monitor, Scoreboard, Agent, Env
// ================================================================================

// === CNN Sequence Item ===
`ifndef CNN_SEQ_ITEM_SV
`define CNN_SEQ_ITEM_SV
class cnn_seq_item extends uvm_sequence_item;
  `uvm_object_utils(cnn_seq_item)

  rand bit        is_write;
  rand bit [5:0]  reg_addr;
  rand bit [31:0] wdata;
  logic [31:0]    rdata;
  logic           ack;

  function new(string name = "cnn_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%s addr=0x%02h wdata=0x%08h rdata=0x%08h",
      is_write ? "WR" : "RD", reg_addr, wdata, rdata);
  endfunction
endclass
`endif

// === CNN Driver ===
`ifndef CNN_DRIVER_SV
`define CNN_DRIVER_SV
class cnn_driver extends uvm_driver #(cnn_seq_item);
  `uvm_component_utils(cnn_driver)
  virtual cnn_if.driver vif;

  function new(string name = "cnn_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual cnn_if.driver)::get(this, "", "vif", vif))
      `uvm_fatal("CNN_DRV", "Could not get vif")
  endfunction

  task run_phase(uvm_phase phase);
    cnn_seq_item item;
    forever begin
      seq_item_port.get_next_item(item);
      @(vif.drv_cb);
      vif.drv_cb.bus_req   <= 1'b1;
      vif.drv_cb.bus_we    <= item.is_write;
      vif.drv_cb.bus_addr  <= item.reg_addr;
      vif.drv_cb.bus_wdata <= item.wdata;
      @(vif.drv_cb);
      while (!vif.drv_cb.bus_ack) @(vif.drv_cb);
      item.rdata = vif.drv_cb.bus_rdata;
      item.ack   = vif.drv_cb.bus_ack;
      vif.drv_cb.bus_req <= 1'b0;
      @(vif.drv_cb);
      seq_item_port.item_done();
    end
  endtask
endclass
`endif

// === CNN Monitor ===
`ifndef CNN_MONITOR_SV
`define CNN_MONITOR_SV
class cnn_monitor extends uvm_monitor;
  `uvm_component_utils(cnn_monitor)
  virtual cnn_if.monitor vif;
  uvm_analysis_port #(cnn_seq_item) ap;

  function new(string name = "cnn_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual cnn_if.monitor)::get(this, "", "vif", vif))
      `uvm_fatal("CNN_MON", "Could not get vif")
  endfunction

  task run_phase(uvm_phase phase);
    cnn_seq_item item;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.bus_req && vif.mon_cb.bus_ack) begin
        item = cnn_seq_item::type_id::create("item");
        item.is_write = vif.mon_cb.bus_we;
        item.reg_addr = vif.mon_cb.bus_addr;
        item.wdata    = vif.mon_cb.bus_wdata;
        item.rdata    = vif.mon_cb.bus_rdata;
        ap.write(item);
      end
    end
  endtask
endclass
`endif

// === CNN Scoreboard ===
`ifndef CNN_SCOREBOARD_SV
`define CNN_SCOREBOARD_SV
class cnn_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(cnn_scoreboard)
  uvm_analysis_imp #(cnn_seq_item, cnn_scoreboard) ap;

  int unsigned total_txns = 0;
  int unsigned writes = 0;
  int unsigned reads = 0;

  // Shadow registers for tracking config
  logic [31:0] shadow_regs[16];

  covergroup cnn_cov with function sample(cnn_seq_item item);
    cp_rw: coverpoint item.is_write { bins wr = {1}; bins rd = {0}; }
    cp_addr: coverpoint item.reg_addr[5:2] {
      bins ctrl   = {0};  bins status = {1};
      bins cfg_ih = {2};  bins cfg_iw = {3};
      bins cfg_ic = {4};  bins cfg_oc = {5};
      bins perf[] = {[8:9]};
      bins data[] = {[10:13]};
    }
    cx_rw_addr: cross cp_rw, cp_addr;
  endgroup

  function new(string name = "cnn_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    cnn_cov = new();
    foreach (shadow_regs[i]) shadow_regs[i] = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  function void write(cnn_seq_item item);
    total_txns++;
    cnn_cov.sample(item);
    if (item.is_write) begin
      writes++;
      shadow_regs[item.reg_addr[5:2]] = item.wdata;
      `uvm_info("CNN_SB", $sformatf("Write: %s", item.convert2string()), UVM_HIGH)
    end else begin
      reads++;
      `uvm_info("CNN_SB", $sformatf("Read: %s", item.convert2string()), UVM_HIGH)
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("CNN_SB", "============================================", UVM_LOW)
    `uvm_info("CNN_SB", " NeurISA CNN Accelerator Test Report        ", UVM_LOW)
    `uvm_info("CNN_SB", "============================================", UVM_LOW)
    `uvm_info("CNN_SB", $sformatf("Total: %0d | Writes: %0d | Reads: %0d", total_txns, writes, reads), UVM_LOW)
    `uvm_info("CNN_SB", "============================================", UVM_LOW)
  endfunction
endclass
`endif

// === CNN Agent ===
`ifndef CNN_AGENT_SV
`define CNN_AGENT_SV
class cnn_agent extends uvm_agent;
  `uvm_component_utils(cnn_agent)
  cnn_driver   drv;
  cnn_monitor  mon;
  uvm_sequencer #(cnn_seq_item) sqr;

  function new(string name = "cnn_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = cnn_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      drv = cnn_driver::type_id::create("drv", this);
      sqr = uvm_sequencer#(cnn_seq_item)::type_id::create("sqr", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
`endif

// === CNN Environment ===
`ifndef CNN_ENV_SV
`define CNN_ENV_SV
class cnn_env extends uvm_env;
  `uvm_component_utils(cnn_env)
  cnn_agent      agent;
  cnn_scoreboard sb;

  function new(string name = "cnn_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = cnn_agent::type_id::create("agent", this);
    sb    = cnn_scoreboard::type_id::create("sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agent.mon.ap.connect(sb.ap);
  endfunction
endclass
`endif
