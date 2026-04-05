// ================================================================================
// NeurISA — CFU Interface Definition
// ================================================================================

`ifndef CFU_IF_SV
`define CFU_IF_SV

interface cfu_if(input logic clk, input logic rstn);

  // Operation trigger
  logic        start;

  // Operands
  logic        instr_type;   // 0=R-type, 1=I-type
  logic [2:0]  funct3;
  logic [6:0]  funct7;
  logic [11:0] imm12;
  logic [31:0] rs1;
  logic [31:0] rs2;

  // Results
  logic [31:0] result;
  logic        valid;

  // Driver clocking block
  clocking drv_cb @(posedge clk);
    output start, instr_type, funct3, funct7, imm12, rs1, rs2;
    input  result, valid;
  endclocking

  // Monitor clocking block
  clocking mon_cb @(posedge clk);
    input start, instr_type, funct3, funct7, imm12, rs1, rs2;
    input result, valid;
  endclocking

  // Driver modport
  modport driver(clocking drv_cb, input clk, rstn);

  // Monitor modport
  modport monitor(clocking mon_cb, input clk, rstn);

endinterface : cfu_if

`endif
