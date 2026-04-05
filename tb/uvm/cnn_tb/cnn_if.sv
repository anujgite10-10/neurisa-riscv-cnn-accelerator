// ================================================================================
// NeurISA — CNN CFS Bus Interface
// ================================================================================

`ifndef CNN_IF_SV
`define CNN_IF_SV

interface cnn_if(input logic clk, input logic rstn);

  // CFS bus interface
  logic        bus_req;
  logic        bus_we;
  logic [5:0]  bus_addr;
  logic [31:0] bus_wdata;
  logic [31:0] bus_rdata;
  logic        bus_ack;
  logic        irq;

  // Driver clocking block
  clocking drv_cb @(posedge clk);
    output bus_req, bus_we, bus_addr, bus_wdata;
    input  bus_rdata, bus_ack, irq;
  endclocking

  // Monitor clocking block
  clocking mon_cb @(posedge clk);
    input bus_req, bus_we, bus_addr, bus_wdata;
    input bus_rdata, bus_ack, irq;
  endclocking

  modport driver(clocking drv_cb, input clk, rstn);
  modport monitor(clocking mon_cb, input clk, rstn);

endinterface : cnn_if

`endif
