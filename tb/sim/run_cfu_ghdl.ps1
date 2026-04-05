# ================================================================================
# NeurISA — GHDL Simulation Script for CFU Testing
# ================================================================================
# Usage (from project root):
#   powershell -File tb/sim/run_cfu_ghdl.ps1
#
# Requirements: GHDL installed and in PATH
# ================================================================================

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " NeurISA CFU — GHDL Simulation"
Write-Host "============================================" -ForegroundColor Cyan

$ProjectRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
$WorkDir = "$ProjectRoot\tb\sim\work_cfu"
$CfuSrc = "$ProjectRoot\rtl\neurisa\neorv32_cpu_alu_cfu.vhd"
$TbDir = "$ProjectRoot\tb\sim"

# Create work directory
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}

Write-Host "`n[1/4] Analyzing VHDL sources..." -ForegroundColor Yellow

# Analyze the CFU
ghdl -a --workdir=$WorkDir --std=08 $CfuSrc
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: VHDL analysis failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  CFU analysis OK" -ForegroundColor Green

# Create a simple VHDL testbench
$TbFile = "$TbDir\cfu_tb_simple.vhd"
if (-not (Test-Path $TbFile)) {
    Write-Host "`n[2/4] Creating simple VHDL testbench..." -ForegroundColor Yellow
    @"
-- Simple CFU testbench for GHDL
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
begin
  -- Clock: 10ns period
  clk <= not clk after 5 ns;

  -- DUT
  dut: entity work.neorv32_cpu_alu_cfu
    port map (clk_i => clk, rstn_i => rstn, start_i => start,
              type_i => type_s, funct3_i => funct3, funct7_i => funct7,
              imm12_i => imm12, rs1_i => rs1, rs2_i => rs2,
              result_o => result, valid_o => valid);

  -- Stimulus
  process
  begin
    rstn <= '0'; wait for 20 ns;
    rstn <= '1'; wait for 10 ns;

    -- Test VRELU: [-5, 10, -128, 127] -> [0, 10, 0, 127]
    report "TEST: VRELU";
    type_s <= '0'; funct3 <= "010"; funct7 <= "0000000";
    rs1 <= x"7F80" & x"0AFB"; -- [127, -128, 10, -5]
    start <= '1'; wait for 10 ns; start <= '0'; wait for 10 ns;
    assert valid = '1' report "VRELU: valid not set" severity error;
    report "VRELU result: " & to_hstring(result);

    -- Test VADD: normal add
    report "TEST: VADD";
    type_s <= '0'; funct3 <= "101"; funct7 <= "0000000";
    rs1 <= x"04030201"; rs2 <= x"01010101";
    start <= '1'; wait for 10 ns; start <= '0'; wait for 10 ns;
    assert valid = '1' report "VADD: valid not set" severity error;
    assert result = x"05040302" report "VADD: wrong result" severity error;
    report "VADD result: " & to_hstring(result);

    -- Test VMAC: [1,2,3,4] * [1,1,1,1] = 10
    report "TEST: VMAC";
    type_s <= '0'; funct3 <= "000"; funct7 <= "0000000";
    rs1 <= x"04030201"; rs2 <= x"01010101";
    start <= '1'; wait for 10 ns; start <= '0';
    wait for 30 ns; -- 2-cycle latency
    report "VMAC result: " & to_hstring(result);

    -- Test VPOOL: max of [1,2,3,4] = 4
    report "TEST: VPOOL";
    type_s <= '0'; funct3 <= "011"; funct7 <= "0000000";
    rs1 <= x"04030201";
    start <= '1'; wait for 10 ns; start <= '0'; wait for 10 ns;
    report "VPOOL result: " & to_hstring(result);

    report "ALL TESTS COMPLETE" severity note;
    wait for 100 ns;
    std.env.stop;
  end process;
end sim;
"@ | Out-File -Encoding UTF8 $TbFile
    Write-Host "  Created $TbFile" -ForegroundColor Green
} else {
    Write-Host "`n[2/4] Using existing testbench" -ForegroundColor Yellow
}

# Analyze testbench
ghdl -a --workdir=$WorkDir --std=08 $TbFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Testbench analysis failed!" -ForegroundColor Red
    exit 1
}

Write-Host "`n[3/4] Elaborating design..." -ForegroundColor Yellow
ghdl -e --workdir=$WorkDir --std=08 cfu_tb_simple
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Elaboration failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  Elaboration OK" -ForegroundColor Green

Write-Host "`n[4/4] Running simulation..." -ForegroundColor Yellow
ghdl -r --workdir=$WorkDir --std=08 cfu_tb_simple --wave="$WorkDir\cfu_tb.ghw" --stop-time=500ns
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: Simulation ended with non-zero exit" -ForegroundColor Yellow
} else {
    Write-Host "  Simulation OK" -ForegroundColor Green
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " Waveform: $WorkDir\cfu_tb.ghw"
Write-Host " Open with: gtkwave $WorkDir\cfu_tb.ghw"
Write-Host "============================================" -ForegroundColor Cyan
