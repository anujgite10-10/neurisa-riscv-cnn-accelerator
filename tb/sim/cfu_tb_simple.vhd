-- ================================================================================
-- NeurISA - Simple CFU Testbench for Vivado XSim
-- ================================================================================
-- Tests: VRELU, VADD, VMAC, VPOOL, VSUB, VMUL, VABS
-- Run in Vivado: add to sim_1 fileset, set as top, run behavioral simulation
-- ================================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;

entity cfu_tb_simple is
end cfu_tb_simple;

architecture sim of cfu_tb_simple is
  signal clk    : std_ulogic := '0';
  signal rstn   : std_ulogic := '0';
  signal start  : std_ulogic := '0';
  signal type_s : std_ulogic := '0';
  signal funct3 : std_ulogic_vector(2 downto 0) := "000";
  signal funct7 : std_ulogic_vector(6 downto 0) := "0000000";
  signal imm12  : std_ulogic_vector(11 downto 0) := (others => '0');
  signal rs1    : std_ulogic_vector(31 downto 0) := (others => '0');
  signal rs2    : std_ulogic_vector(31 downto 0) := (others => '0');
  signal result : std_ulogic_vector(31 downto 0);
  signal valid  : std_ulogic;

  signal test_pass : integer := 0;
  signal test_fail : integer := 0;
begin
  -- Clock: 10ns period (100 MHz)
  clk <= not clk after 5 ns;

  -- DUT
  dut: entity neorv32.neorv32_cpu_alu_cfu
    port map (
      clk_i    => clk,
      rstn_i   => rstn,
      start_i  => start,
      type_i   => type_s,
      funct3_i => funct3,
      funct7_i => funct7,
      imm12_i  => imm12,
      rs1_i    => rs1,
      rs2_i    => rs2,
      result_o => result,
      valid_o  => valid
    );

  -- Stimulus
  process
    variable expected : std_ulogic_vector(31 downto 0);
  begin
    rstn <= '0'; wait for 20 ns;
    rstn <= '1'; wait for 10 ns;

    report "========================================";
    report " NeurISA CFU - Testbench";
    report "========================================";

    -- ======================================================================
    -- TEST 1: VRELU - max(0, x) for each packed INT8
    -- Input:  [-5, 10, -128, 127] = 0x7F800AFB
    -- Expect: [0,  10,  0,   127] = 0x7F000A00
    -- ======================================================================
    report "TEST 1: VRELU";
    type_s <= '0'; funct3 <= "010"; funct7 <= "0000000";
    rs1 <= x"7F80" & x"0AFB";  -- [127, -128, 10, -5]
    start <= '1'; wait for 10 ns; start <= '0'; wait for 10 ns;
    assert valid = '1' report "VRELU: valid not asserted!" severity error;
    expected := x"7F000A00";
    if result = expected then
      report "VRELU: PASS (result=" & to_hstring(result) & ")";
      test_pass <= test_pass + 1;
    else
      report "VRELU: FAIL (got=" & to_hstring(result) & " exp=" & to_hstring(expected) & ")" severity error;
      test_fail <= test_fail + 1;
    end if;

    -- ======================================================================
    -- TEST 2: VADD - saturating packed INT8 add
    -- Input:  [4,3,2,1] + [1,1,1,1] = [5,4,3,2]
    -- ======================================================================
    report "TEST 2: VADD";
    type_s <= '0'; funct3 <= "101"; funct7 <= "0000000";
    rs1 <= x"04030201"; rs2 <= x"01010101";
    start <= '1'; wait for 10 ns; start <= '0'; wait for 10 ns;
    expected := x"05040302";
    if result = expected then
      report "VADD: PASS (result=" & to_hstring(result) & ")";
      test_pass <= test_pass + 1;
    else
      report "VADD: FAIL (got=" & to_hstring(result) & " exp=" & to_hstring(expected) & ")" severity error;
      test_fail <= test_fail + 1;
    end if;

    -- ======================================================================
    -- TEST 3: VADD saturation - [120,1,1,1] + [30,1,1,1] = [127,2,2,2]
    -- ======================================================================
    report "TEST 3: VADD Saturation";
    type_s <= '0'; funct3 <= "101"; funct7 <= "0000000";
    rs1 <= x"01010178"; rs2 <= x"0101011E";
    start <= '1'; wait for 10 ns; start <= '0'; wait for 10 ns;
    expected := x"0202027F";
    if result = expected then
      report "VADD SAT: PASS (result=" & to_hstring(result) & ")";
      test_pass <= test_pass + 1;
    else
      report "VADD SAT: FAIL (got=" & to_hstring(result) & " exp=" & to_hstring(expected) & ")" severity error;
      test_fail <= test_fail + 1;
    end if;

    -- ======================================================================
    -- TEST 4: VSUB - saturating packed INT8 subtract
    -- Input:  [4,3,2,1] - [1,1,1,1] = [3,2,1,0]
    -- ======================================================================
    report "TEST 4: VSUB";
    type_s <= '0'; funct3 <= "101"; funct7 <= "0000001";  -- funct7 ALT = SUB
    rs1 <= x"04030201"; rs2 <= x"01010101";
    start <= '1'; wait for 10 ns; start <= '0'; wait for 10 ns;
    expected := x"03020100";
    if result = expected then
      report "VSUB: PASS (result=" & to_hstring(result) & ")";
      test_pass <= test_pass + 1;
    else
      report "VSUB: FAIL (got=" & to_hstring(result) & " exp=" & to_hstring(expected) & ")" severity error;
      test_fail <= test_fail + 1;
    end if;

    -- ======================================================================
    -- TEST 5: VMAC - 4xINT8 multiply-accumulate
    -- [1,2,3,4] * [1,1,1,1] = 1+2+3+4 = 10
    -- ======================================================================
    report "TEST 5: VMAC";
    type_s <= '0'; funct3 <= "000"; funct7 <= "0000000";
    rs1 <= x"04030201"; rs2 <= x"01010101";
    start <= '1'; wait for 10 ns; start <= '0';
    wait for 30 ns;  -- 2-cycle pipeline latency
    report "VMAC result: " & to_hstring(result);
    expected := x"0000000A";  -- 10
    if result = expected then
      report "VMAC: PASS";
      test_pass <= test_pass + 1;
    else
      report "VMAC: FAIL (got=" & to_hstring(result) & " exp=" & to_hstring(expected) & ")" severity warning;
      test_fail <= test_fail + 1;
    end if;

    -- ======================================================================
    -- TEST 6: VPOOL - max across 4 packed bytes
    -- [4,3,2,1] -> max = 4
    -- ======================================================================
    report "TEST 6: VPOOL";
    type_s <= '0'; funct3 <= "011"; funct7 <= "0000000";
    rs1 <= x"04030201";
    start <= '1'; wait for 10 ns; start <= '0'; wait for 10 ns;
    expected := x"00000004";
    if result = expected then
      report "VPOOL: PASS (result=" & to_hstring(result) & ")";
      test_pass <= test_pass + 1;
    else
      report "VPOOL: FAIL (got=" & to_hstring(result) & " exp=" & to_hstring(expected) & ")" severity error;
      test_fail <= test_fail + 1;
    end if;

    -- ======================================================================
    -- TEST 7: VMUL - packed element-wise multiply (low 8 bits)
    -- [2,3,4,5] * [3,2,2,2] = [6,6,8,10]
    -- ======================================================================
    report "TEST 7: VMUL";
    type_s <= '0'; funct3 <= "110"; funct7 <= "0000000";
    rs1 <= x"05040302"; rs2 <= x"02020203";
    start <= '1'; wait for 10 ns; start <= '0'; wait for 10 ns;
    expected := x"0A080606";
    if result = expected then
      report "VMUL: PASS (result=" & to_hstring(result) & ")";
      test_pass <= test_pass + 1;
    else
      report "VMUL: FAIL (got=" & to_hstring(result) & " exp=" & to_hstring(expected) & ")" severity error;
      test_fail <= test_fail + 1;
    end if;

    -- ======================================================================
    -- TEST 8: VABS - packed absolute value
    -- [-5, 10, -128, 127] -> [5, 10, 127, 127]
    -- Note: -128 saturates to 127
    -- ======================================================================
    report "TEST 8: VABS";
    type_s <= '0'; funct3 <= "111"; funct7 <= "0000000";
    rs1 <= x"7F800AFB";  -- [127, -128, 10, -5]
    start <= '1'; wait for 10 ns; start <= '0'; wait for 10 ns;
    expected := x"7F7F0A05";
    if result = expected then
      report "VABS: PASS (result=" & to_hstring(result) & ")";
      test_pass <= test_pass + 1;
    else
      report "VABS: FAIL (got=" & to_hstring(result) & " exp=" & to_hstring(expected) & ")" severity error;
      test_fail <= test_fail + 1;
    end if;

    -- ======================================================================
    -- Summary
    -- ======================================================================
    wait for 10 ns;  -- let signals settle
    report "========================================";
    report " RESULTS: " & integer'image(test_pass) & " PASS, " & integer'image(test_fail) & " FAIL";
    report "========================================";

    if test_fail > 0 then
      report "SOME TESTS FAILED!" severity error;
    else
      report "ALL TESTS PASSED!" severity note;
    end if;

    wait for 100 ns;
    std.env.stop;
  end process;
end sim;
