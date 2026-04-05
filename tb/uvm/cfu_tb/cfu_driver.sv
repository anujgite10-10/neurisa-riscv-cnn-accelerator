// ================================================================================
// NeurISA — CFU UVM Driver
// ================================================================================

`ifndef CFU_DRIVER_SV
`define CFU_DRIVER_SV

class cfu_driver extends uvm_driver #(cfu_seq_item);
  `uvm_component_utils(cfu_driver)

  virtual cfu_if.driver vif;

  function new(string name = "cfu_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual cfu_if.driver)::get(this, "", "vif", vif))
      `uvm_fatal("CFU_DRV", "Could not get virtual interface")
  endfunction

  task run_phase(uvm_phase phase);
    cfu_seq_item item;
    forever begin
      seq_item_port.get_next_item(item);
      drive_item(item);
      seq_item_port.item_done();
    end
  endtask

  task drive_item(cfu_seq_item item);
    // Wait for reset de-assertion
    while (!vif.rstn) @(vif.drv_cb);

    // Drive inputs
    @(vif.drv_cb);
    vif.drv_cb.instr_type <= item.instr_type;
    vif.drv_cb.funct3     <= item.funct3;
    vif.drv_cb.funct7     <= item.funct7;
    vif.drv_cb.imm12      <= item.imm12;
    vif.drv_cb.rs1        <= item.rs1;
    vif.drv_cb.rs2        <= item.rs2;
    vif.drv_cb.start      <= 1'b1;

    // Hold start for one cycle
    @(vif.drv_cb);
    vif.drv_cb.start <= 1'b0;

    // Wait for valid response (with timeout)
    fork
      begin
        int timeout_cnt = 0;
        while (!vif.drv_cb.valid && timeout_cnt < 1000) begin
          @(vif.drv_cb);
          timeout_cnt++;
        end
        if (timeout_cnt >= 1000)
          `uvm_error("CFU_DRV", "Timeout waiting for valid response")
      end
    join

    // Capture result
    item.result = vif.drv_cb.result;
    item.valid  = vif.drv_cb.valid;

    // Inter-instruction gap
    @(vif.drv_cb);
  endtask

endclass : cfu_driver

`endif
