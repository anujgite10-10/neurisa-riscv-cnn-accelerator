// ================================================================================
// NeurISA — CFU Sequence Item
// ================================================================================

`ifndef CFU_SEQ_ITEM_SV
`define CFU_SEQ_ITEM_SV

class cfu_seq_item extends uvm_sequence_item;
  `uvm_object_utils(cfu_seq_item)

  // Stimulus fields
  rand bit        instr_type;  // 0=R, 1=I
  rand bit [2:0]  funct3;
  rand bit [6:0]  funct7;
  rand bit [11:0] imm12;
  rand bit [31:0] rs1;
  rand bit [31:0] rs2;

  // Response fields
  logic [31:0] result;
  logic        valid;

  // Expected result (from golden model)
  logic [31:0] expected_result;

  // ============================================================
  // Constraints
  // ============================================================

  // Limit funct7 to valid values for cleaner coverage
  constraint c_funct7 {
    funct7 inside {7'b0000000, 7'b0000001};
  }

  // For R-type instructions, all funct3 values are valid
  constraint c_rtype {
    if (instr_type == 0) {
      funct3 inside {[0:7]};
    }
  }

  // For I-type instructions, limit funct3
  constraint c_itype {
    if (instr_type == 1) {
      funct3 inside {[0:3]};
    }
  }

  // Distribution to stress edge cases
  constraint c_edge_cases {
    rs1 dist {
      32'h00000000 := 5,  // all zeros
      32'hFFFFFFFF := 5,  // all ones
      32'h7F7F7F7F := 5,  // max positive packed
      32'h80808080 := 5,  // min negative packed
      [32'h00000001:32'hFFFFFFFE] := 80  // normal range
    };
    rs2 dist {
      32'h00000000 := 5,
      32'hFFFFFFFF := 5,
      32'h7F7F7F7F := 5,
      32'h80808080 := 5,
      [32'h00000001:32'hFFFFFFFE] := 80
    };
  }

  function new(string name = "cfu_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("type=%s f3=%03b f7=%07b rs1=0x%08h rs2=0x%08h | result=0x%08h valid=%0b exp=0x%08h",
      instr_type ? "I" : "R", funct3, funct7, rs1, rs2, result, valid, expected_result);
  endfunction

endclass : cfu_seq_item

`endif
