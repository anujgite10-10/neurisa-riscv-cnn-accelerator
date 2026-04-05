// ================================================================================
// NeurISA — CFU UVM Agent
// ================================================================================

`ifndef CFU_AGENT_SV
`define CFU_AGENT_SV

class cfu_agent extends uvm_agent;
  `uvm_component_utils(cfu_agent)

  cfu_driver    drv;
  cfu_monitor   mon;
  uvm_sequencer #(cfu_seq_item) sqr;

  function new(string name = "cfu_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = cfu_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      drv = cfu_driver::type_id::create("drv", this);
      sqr = uvm_sequencer#(cfu_seq_item)::type_id::create("sqr", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass : cfu_agent

`endif
