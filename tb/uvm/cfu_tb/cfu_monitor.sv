// ================================================================================
// NeurISA — CFU UVM Monitor
// ================================================================================

`ifndef CFU_MONITOR_SV
`define CFU_MONITOR_SV

class cfu_monitor extends uvm_monitor;
  `uvm_component_utils(cfu_monitor)

  virtual cfu_if.monitor vif;
  uvm_analysis_port #(cfu_seq_item) ap;

  function new(string name = "cfu_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual cfu_if.monitor)::get(this, "", "vif", vif))
      `uvm_fatal("CFU_MON", "Could not get virtual interface")
  endfunction

  task run_phase(uvm_phase phase);
    cfu_seq_item item;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.start) begin
        item = cfu_seq_item::type_id::create("item");
        item.instr_type = vif.mon_cb.instr_type;
        item.funct3     = vif.mon_cb.funct3;
        item.funct7     = vif.mon_cb.funct7;
        item.imm12      = vif.mon_cb.imm12;
        item.rs1        = vif.mon_cb.rs1;
        item.rs2        = vif.mon_cb.rs2;

        // Wait for valid
        while (!vif.mon_cb.valid) @(vif.mon_cb);
        item.result = vif.mon_cb.result;
        item.valid  = vif.mon_cb.valid;

        ap.write(item);
        `uvm_info("CFU_MON", $sformatf("Observed: %s", item.convert2string()), UVM_HIGH)
      end
    end
  endtask

endclass : cfu_monitor

`endif
