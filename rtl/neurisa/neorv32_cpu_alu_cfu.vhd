-- ================================================================================
-- NeurISA — RISC-V Custom ISA Extensions for CNN/ML Acceleration
-- CFU (Custom Functions Unit) for NEORV32
-- ================================================================================
-- Implements packed INT8 SIMD instructions for neural network inference:
--   R-type (custom-0 / 0001011):
--     funct3=000: VMAC    — 4×INT8 packed multiply-accumulate
--     funct3=001: VDOT    — 4×INT8 dot product with saturating accumulate
--     funct3=010: VRELU   — packed vectorized ReLU (4×INT8)
--     funct3=011: VPOOL   — packed max-pool across 4 bytes
--     funct3=100: VQUANT  — quantize/dequantize (funct7 selects direction)
--     funct3=101: VADD/VSUB — packed INT8 saturating add/subtract
--     funct3=110: VMUL    — packed INT8 element-wise multiply (low bytes)
--     funct3=111: VABS    — packed INT8 absolute value
--   I-type (custom-1 / 0101011):
--     funct3=000: CNN_CFG    — write CNN config register
--     funct3=001: CNN_STATUS — read CNN status register
--     funct3=010: VSCALE     — packed INT8 scale by immediate
--     funct3=011: VSHIFT     — packed INT8 arithmetic right shift by imm
-- ================================================================================
-- Target: NEORV32 Xcfu ISA Extension on Zynq-7000 ZC-706
-- ================================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity neorv32_cpu_alu_cfu is
  port (
    -- global control --
    clk_i    : in  std_ulogic;                     -- global clock, rising edge
    rstn_i   : in  std_ulogic;                     -- global reset, low-active, async
    -- operation trigger --
    start_i  : in  std_ulogic;                     -- start trigger, single-shot
    -- operands --
    type_i   : in  std_ulogic;                     -- instruction type (0=R-type, 1=I-type)
    funct3_i : in  std_ulogic_vector(2 downto 0);  -- funct3 bit-field
    funct7_i : in  std_ulogic_vector(6 downto 0);  -- funct7 bit-field (R-type only)
    imm12_i  : in  std_ulogic_vector(11 downto 0); -- imm12 bit-field (I-type only)
    rs1_i    : in  std_ulogic_vector(31 downto 0);  -- source register 1
    rs2_i    : in  std_ulogic_vector(31 downto 0);  -- source register 2
    -- result and status --
    result_o : out std_ulogic_vector(31 downto 0);  -- operation result
    valid_o  : out std_ulogic                       -- operation done
  );
end neorv32_cpu_alu_cfu;

architecture neorv32_cpu_alu_cfu_rtl of neorv32_cpu_alu_cfu is

  -- instruction type identifiers --
  constant r_type_c : std_ulogic := '0';
  constant i_type_c : std_ulogic := '1';

  -- R-type funct3 identifiers --
  constant VMAC_F3   : std_ulogic_vector(2 downto 0) := "000";
  constant VDOT_F3   : std_ulogic_vector(2 downto 0) := "001";
  constant VRELU_F3  : std_ulogic_vector(2 downto 0) := "010";
  constant VPOOL_F3  : std_ulogic_vector(2 downto 0) := "011";
  constant VQUANT_F3 : std_ulogic_vector(2 downto 0) := "100";
  constant VADD_F3   : std_ulogic_vector(2 downto 0) := "101";
  constant VMUL_F3   : std_ulogic_vector(2 downto 0) := "110";
  constant VABS_F3   : std_ulogic_vector(2 downto 0) := "111";

  -- funct7 sub-selectors --
  constant F7_DEFAULT : std_ulogic_vector(6 downto 0) := "0000000";
  constant F7_ALT     : std_ulogic_vector(6 downto 0) := "0000001";

  -- I-type funct3 identifiers --
  constant CNN_CFG_F3    : std_ulogic_vector(2 downto 0) := "000";
  constant CNN_STATUS_F3 : std_ulogic_vector(2 downto 0) := "001";
  constant VSCALE_F3     : std_ulogic_vector(2 downto 0) := "010";
  constant VSHIFT_F3     : std_ulogic_vector(2 downto 0) := "011";

  -- ============================================================
  -- INT8 byte extraction helpers
  -- ============================================================
  -- rs1 packed as [byte3:byte2:byte1:byte0] (little-endian)
  signal a0, a1, a2, a3 : signed(7 downto 0);
  signal b0, b1, b2, b3 : signed(7 downto 0);

  -- ============================================================
  -- VMAC / VDOT signals — 4× parallel INT8 multiply + add tree
  -- ============================================================
  signal mul0, mul1, mul2, mul3 : signed(15 downto 0);
  signal mac_sum                : signed(31 downto 0);
  signal mac_result             : std_ulogic_vector(31 downto 0);

  -- Pipeline stage for MAC (2 cycle latency)
  type mac_pipe_t is record
    stage1_valid : std_ulogic;
    stage2_valid : std_ulogic;
    mul0_r       : signed(15 downto 0);
    mul1_r       : signed(15 downto 0);
    mul2_r       : signed(15 downto 0);
    mul3_r       : signed(15 downto 0);
    result       : signed(31 downto 0);
    is_dot       : std_ulogic; -- for VDOT accumulate mode
  end record;
  signal mac_pipe : mac_pipe_t;

  -- VDOT accumulator register
  signal dot_accum : signed(31 downto 0);

  -- ============================================================
  -- VRELU signals — packed byte-wise max(0, x)
  -- ============================================================
  signal relu_result : std_ulogic_vector(31 downto 0);

  -- ============================================================
  -- VPOOL signals — max across 4 packed bytes
  -- ============================================================
  signal pool_max01, pool_max23 : signed(7 downto 0);
  signal pool_result            : std_ulogic_vector(31 downto 0);

  -- ============================================================
  -- VQUANT / VDEQUANT signals
  -- ============================================================
  signal quant_result : std_ulogic_vector(31 downto 0);

  -- ============================================================
  -- VADD / VSUB signals — packed saturating arithmetic
  -- ============================================================
  signal add_result : std_ulogic_vector(31 downto 0);

  -- ============================================================
  -- VMUL signals — packed element-wise multiply (low byte)
  -- ============================================================
  signal emul_result : std_ulogic_vector(31 downto 0);

  -- ============================================================
  -- VABS signals — packed absolute value
  -- ============================================================
  signal abs_result : std_ulogic_vector(31 downto 0);

  -- ============================================================
  -- I-type: VSCALE / VSHIFT
  -- ============================================================
  signal scale_result : std_ulogic_vector(31 downto 0);
  signal shift_result : std_ulogic_vector(31 downto 0);

  -- ============================================================
  -- CNN config register file (accessible via I-type)
  -- ============================================================
  type cnn_cfg_mem_t is array (0 to 15) of std_ulogic_vector(31 downto 0);
  signal cnn_cfg_mem : cnn_cfg_mem_t;

  -- ============================================================
  -- Saturation helper functions
  -- ============================================================
  function sat_add_i8(a : signed(7 downto 0); b : signed(7 downto 0)) return signed is
    variable sum : signed(8 downto 0);
  begin
    sum := resize(a, 9) + resize(b, 9);
    if sum > 127 then
      return to_signed(127, 8);
    elsif sum < -128 then
      return to_signed(-128, 8);
    else
      return sum(7 downto 0);
    end if;
  end function;

  function sat_sub_i8(a : signed(7 downto 0); b : signed(7 downto 0)) return signed is
    variable diff : signed(8 downto 0);
  begin
    diff := resize(a, 9) - resize(b, 9);
    if diff > 127 then
      return to_signed(127, 8);
    elsif diff < -128 then
      return to_signed(-128, 8);
    else
      return diff(7 downto 0);
    end if;
  end function;

begin

  -- ============================================================
  -- Byte extraction from packed INT8 words
  -- ============================================================
  a0 <= signed(rs1_i( 7 downto  0));
  a1 <= signed(rs1_i(15 downto  8));
  a2 <= signed(rs1_i(23 downto 16));
  a3 <= signed(rs1_i(31 downto 24));

  b0 <= signed(rs2_i( 7 downto  0));
  b1 <= signed(rs2_i(15 downto  8));
  b2 <= signed(rs2_i(23 downto 16));
  b3 <= signed(rs2_i(31 downto 24));

  -- ============================================================
  -- VMAC / VDOT: 4× INT8 Multiply (combinatorial stage)
  -- ============================================================
  mul0 <= a0 * b0;
  mul1 <= a1 * b1;
  mul2 <= a2 * b2;
  mul3 <= a3 * b3;

  -- ============================================================
  -- VMAC / VDOT: Pipelined Multiply-Accumulate (2-cycle)
  -- ============================================================
  mac_pipeline: process(rstn_i, clk_i)
  begin
    if rstn_i = '0' then
      mac_pipe.stage1_valid <= '0';
      mac_pipe.stage2_valid <= '0';
      mac_pipe.mul0_r       <= (others => '0');
      mac_pipe.mul1_r       <= (others => '0');
      mac_pipe.mul2_r       <= (others => '0');
      mac_pipe.mul3_r       <= (others => '0');
      mac_pipe.result       <= (others => '0');
      mac_pipe.is_dot       <= '0';
      dot_accum             <= (others => '0');
    elsif rising_edge(clk_i) then
      -- Stage 1: Register multiply results
      mac_pipe.stage1_valid <= '0';
      mac_pipe.stage2_valid <= mac_pipe.stage1_valid;

      if (start_i = '1') and (type_i = r_type_c) and
         ((funct3_i = VMAC_F3) or (funct3_i = VDOT_F3)) then
        mac_pipe.mul0_r       <= mul0;
        mac_pipe.mul1_r       <= mul1;
        mac_pipe.mul2_r       <= mul2;
        mac_pipe.mul3_r       <= mul3;
        mac_pipe.stage1_valid <= '1';
        mac_pipe.is_dot       <= funct3_i(0); -- 0=VMAC, 1=VDOT
      end if;

      -- Stage 2: Add tree + accumulate
      if mac_pipe.stage1_valid = '1' then
        mac_sum <= resize(mac_pipe.mul0_r, 32) + resize(mac_pipe.mul1_r, 32) +
                   resize(mac_pipe.mul2_r, 32) + resize(mac_pipe.mul3_r, 32);
        if mac_pipe.is_dot = '1' then
          -- VDOT: accumulate with existing value
          mac_pipe.result <= dot_accum +
                            resize(mac_pipe.mul0_r, 32) + resize(mac_pipe.mul1_r, 32) +
                            resize(mac_pipe.mul2_r, 32) + resize(mac_pipe.mul3_r, 32);
          dot_accum <= dot_accum +
                       resize(mac_pipe.mul0_r, 32) + resize(mac_pipe.mul1_r, 32) +
                       resize(mac_pipe.mul2_r, 32) + resize(mac_pipe.mul3_r, 32);
        else
          -- VMAC: just sum products (no accumulate)
          mac_pipe.result <= resize(mac_pipe.mul0_r, 32) + resize(mac_pipe.mul1_r, 32) +
                            resize(mac_pipe.mul2_r, 32) + resize(mac_pipe.mul3_r, 32);
        end if;
      end if;

      -- Reset accumulator when writing CNN config register 0xF (dedicated reset)
      if (start_i = '1') and (type_i = i_type_c) and (funct3_i = CNN_CFG_F3) and
         (imm12_i(3 downto 0) = "1111") then
        dot_accum <= signed(rs1_i);
      end if;
    end if;
  end process mac_pipeline;

  mac_result <= std_ulogic_vector(mac_pipe.result);

  -- ============================================================
  -- VRELU: Packed byte-wise max(0, x) — pure combinatorial
  -- ============================================================
  vrelu_gen: for i in 0 to 3 generate
    signal byte_in  : signed(7 downto 0);
    signal byte_out : std_ulogic_vector(7 downto 0);
  begin
    byte_in  <= signed(rs1_i(i*8+7 downto i*8));
    byte_out <= rs1_i(i*8+7 downto i*8) when byte_in >= 0 else (others => '0');
    relu_result(i*8+7 downto i*8) <= byte_out;
  end generate;

  -- ============================================================
  -- VPOOL: Max across 4 packed INT8 bytes — pure combinatorial
  -- ============================================================
  pool_max01  <= a0 when a0 >= a1 else a1;
  pool_max23  <= a2 when a2 >= a3 else a3;
  pool_result <= x"000000" & std_ulogic_vector(pool_max01) when pool_max01 >= pool_max23
                 else x"000000" & std_ulogic_vector(pool_max23);

  -- ============================================================
  -- VQUANT: INT32 → 4×INT8 quantize (shift right by rs2[4:0] then saturate)
  -- VDEQUANT (funct7=ALT): 4×INT8 → INT32 sign-extend byte0
  -- Pure combinatorial
  -- ============================================================
  vquant_proc: process(all)
    variable shift_amt : natural range 0 to 31;
    variable shifted   : signed(31 downto 0);
    variable q_byte    : signed(7 downto 0);
  begin
    shift_amt := to_integer(unsigned(rs2_i(4 downto 0)));
    if funct7_i = F7_ALT then
      -- VDEQUANT: sign-extend byte0 of rs1 to 32-bit, shift left by rs2
      quant_result <= std_ulogic_vector(shift_left(resize(a0, 32), shift_amt));
    else
      -- VQUANT: shift rs1 right arithmetically, then saturate to INT8
      shifted := shift_right(signed(rs1_i), shift_amt);
      if shifted > 127 then
        q_byte := to_signed(127, 8);
      elsif shifted < -128 then
        q_byte := to_signed(-128, 8);
      else
        q_byte := shifted(7 downto 0);
      end if;
      quant_result <= x"000000" & std_ulogic_vector(q_byte);
    end if;
  end process vquant_proc;

  -- ============================================================
  -- VADD/VSUB: Packed INT8 saturating add/subtract
  -- funct7=0000000 → ADD, funct7=0000001 → SUB
  -- Pure combinatorial
  -- ============================================================
  vadd_sub_proc: process(all)
    variable r0, r1, r2, r3 : signed(7 downto 0);
  begin
    if funct7_i = F7_ALT then
      -- VSUB
      r0 := sat_sub_i8(a0, b0);
      r1 := sat_sub_i8(a1, b1);
      r2 := sat_sub_i8(a2, b2);
      r3 := sat_sub_i8(a3, b3);
    else
      -- VADD
      r0 := sat_add_i8(a0, b0);
      r1 := sat_add_i8(a1, b1);
      r2 := sat_add_i8(a2, b2);
      r3 := sat_add_i8(a3, b3);
    end if;
    add_result <= std_ulogic_vector(r3) & std_ulogic_vector(r2) &
                  std_ulogic_vector(r1) & std_ulogic_vector(r0);
  end process vadd_sub_proc;

  -- ============================================================
  -- VMUL: Packed INT8 element-wise multiply (keep low 8 bits)
  -- Pure combinatorial
  -- ============================================================
  vmul_proc: process(all)
    variable p0, p1, p2, p3 : signed(15 downto 0);
  begin
    p0 := a0 * b0;
    p1 := a1 * b1;
    p2 := a2 * b2;
    p3 := a3 * b3;
    emul_result <= std_ulogic_vector(p3(7 downto 0)) & std_ulogic_vector(p2(7 downto 0)) &
                   std_ulogic_vector(p1(7 downto 0)) & std_ulogic_vector(p0(7 downto 0));
  end process vmul_proc;

  -- ============================================================
  -- VABS: Packed INT8 absolute value — pure combinatorial
  -- ============================================================
  vabs_gen: for i in 0 to 3 generate
    signal byte_in  : signed(7 downto 0);
  begin
    byte_in <= signed(rs1_i(i*8+7 downto i*8));
    abs_result(i*8+7 downto i*8) <= rs1_i(i*8+7 downto i*8) when byte_in >= 0
                                    else std_ulogic_vector(-byte_in) when byte_in /= to_signed(-128, 8)
                                    else x"7F"; -- saturate -128 → 127
  end generate;

  -- ============================================================
  -- I-type: VSCALE — multiply each packed byte by imm12[7:0]
  -- Pure combinatorial
  -- ============================================================
  vscale_proc: process(all)
    variable scale_val    : signed(7 downto 0);
    variable p0, p1, p2, p3 : signed(15 downto 0);
  begin
    scale_val := signed(imm12_i(7 downto 0));
    p0 := a0 * scale_val;
    p1 := a1 * scale_val;
    p2 := a2 * scale_val;
    p3 := a3 * scale_val;
    -- Keep high byte (effectively multiply then shift right by 8)
    scale_result <= std_ulogic_vector(p3(15 downto 8)) & std_ulogic_vector(p2(15 downto 8)) &
                    std_ulogic_vector(p1(15 downto 8)) & std_ulogic_vector(p0(15 downto 8));
  end process vscale_proc;

  -- ============================================================
  -- I-type: VSHIFT — arithmetic right shift each packed byte
  -- Pure combinatorial
  -- ============================================================
  vshift_proc: process(all)
    variable shamt : natural range 0 to 7;
  begin
    shamt := to_integer(unsigned(imm12_i(2 downto 0)));
    for i in 0 to 3 loop
      shift_result(i*8+7 downto i*8) <=
        std_ulogic_vector(shift_right(signed(rs1_i(i*8+7 downto i*8)), shamt));
    end loop;
  end process vshift_proc;

  -- ============================================================
  -- CNN Config Register File (I-type read/write)
  -- ============================================================
  cnn_cfg_regs: process(rstn_i, clk_i)
  begin
    if rstn_i = '0' then
      cnn_cfg_mem <= (others => (others => '0'));
    elsif rising_edge(clk_i) then
      if (start_i = '1') and (type_i = i_type_c) and (funct3_i = CNN_CFG_F3) then
        cnn_cfg_mem(to_integer(unsigned(imm12_i(3 downto 0)))) <= rs1_i;
      end if;
    end if;
  end process cnn_cfg_regs;

  -- ============================================================
  -- Result Multiplexer & Valid Signal
  -- ============================================================
  result_mux: process(all)
  begin
    -- defaults
    result_o <= (others => '0');
    valid_o  <= '0';

    if type_i = r_type_c then
      case funct3_i is
        -- VMAC / VDOT — pipelined, 2-cycle latency
        when VMAC_F3 | VDOT_F3 =>
          result_o <= mac_result;
          valid_o  <= mac_pipe.stage2_valid;

        -- VRELU — combinatorial
        when VRELU_F3 =>
          result_o <= relu_result;
          valid_o  <= '1';

        -- VPOOL — combinatorial
        when VPOOL_F3 =>
          result_o <= pool_result;
          valid_o  <= '1';

        -- VQUANT / VDEQUANT — combinatorial
        when VQUANT_F3 =>
          result_o <= quant_result;
          valid_o  <= '1';

        -- VADD / VSUB — combinatorial
        when VADD_F3 =>
          result_o <= add_result;
          valid_o  <= '1';

        -- VMUL — combinatorial
        when VMUL_F3 =>
          result_o <= emul_result;
          valid_o  <= '1';

        -- VABS — combinatorial
        when VABS_F3 =>
          result_o <= abs_result;
          valid_o  <= '1';

        when others =>
          result_o <= (others => '0');
          valid_o  <= '0'; -- illegal instruction exception
      end case;

    else -- I-type instructions
      case funct3_i is
        -- CNN_CFG: write config (result is zero, operation is write side-effect)
        when CNN_CFG_F3 =>
          result_o <= (others => '0');
          valid_o  <= '1';

        -- CNN_STATUS: read config register
        when CNN_STATUS_F3 =>
          result_o <= cnn_cfg_mem(to_integer(unsigned(imm12_i(3 downto 0))));
          valid_o  <= '1';

        -- VSCALE: packed byte multiply by immediate
        when VSCALE_F3 =>
          result_o <= scale_result;
          valid_o  <= '1';

        -- VSHIFT: packed byte arithmetic right shift
        when VSHIFT_F3 =>
          result_o <= shift_result;
          valid_o  <= '1';

        when others =>
          result_o <= (others => '0');
          valid_o  <= '0'; -- illegal instruction exception
      end case;
    end if;
  end process result_mux;

end neorv32_cpu_alu_cfu_rtl;
