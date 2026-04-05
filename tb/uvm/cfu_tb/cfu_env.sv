// ================================================================================
// NeurISA — CFU UVM Environment
// ================================================================================

`ifndef CFU_ENV_SV
`define CFU_ENV_SV

class cfu_env extends uvm_env;
  `uvm_component_utils(cfu_env)

  cfu_agent      agent;
  cfu_scoreboard sb;

  function new(string name = "cfu_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = cfu_agent::type_id::create("agent", this);
    sb    = cfu_scoreboard::type_id::create("sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap.connect(sb.ap);
  endfunction

endclass : cfu_env

`endif
