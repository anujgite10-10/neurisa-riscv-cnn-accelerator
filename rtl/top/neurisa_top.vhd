-- ================================================================================
-- NeurISA - Top-Level Wrapper for Zynq-7000 ZC-706
-- ================================================================================
-- Instantiates NEORV32 processor with NeurISA custom CFU and CNN CFS.
-- Uses MMCM to derive 50 MHz system clock from 200 MHz LVDS SYSCLK.
-- UART routed through PMOD1 connector (no PL UART bridge on ZC-706).
-- ================================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

library unisim;
use unisim.vcomponents.all;

entity neurisa_top is
  generic (
    IMEM_SIZE : natural := 64*1024;  -- 64KB IMEM
    DMEM_SIZE : natural := 64*1024   -- 64KB DMEM
  );
  port (
    -- 200 MHz LVDS System Clock --
    clk_p       : in  std_logic;     -- SYSCLK_P (H9)
    clk_n       : in  std_logic;     -- SYSCLK_N (G9)
    -- Active-high Reset --
    rstn_i      : in  std_ulogic;    -- GPIO_SW_CENTER (active-high on ZC-706)
    -- UART via PMOD1 (J58) --
    uart0_txd_o : out std_ulogic;    -- PMOD1_0_LS (AJ21)
    uart0_rxd_i : in  std_ulogic;    -- PMOD1_1_LS (AK21)
    -- LEDs --
    gpio_led_left   : out std_ulogic;  -- Y21 (HR bank 11)
    gpio_led_right  : out std_ulogic;  -- W21 (HR bank 11)
    gpio_led_center : out std_ulogic;  -- G2  (HP bank 33)
    gpio_led_0      : out std_ulogic;  -- A17 (HP bank 35)
    -- DIP Switches --
    gpio_dip_sw     : in  std_ulogic_vector(3 downto 0)  -- AB17, AC16, AC17, AJ13
  );
end neurisa_top;

architecture rtl of neurisa_top is

  -- Clock signals
  signal clk_ibuf   : std_logic;
  signal clk_mmcm   : std_logic;
  signal clk_50mhz  : std_logic;
  signal mmcm_fb    : std_logic;
  signal mmcm_locked : std_logic;

  -- System reset (active-low for NEORV32)
  signal sys_rstn   : std_ulogic;

  -- NEORV32 GPIO
  signal con_gpio_out : std_ulogic_vector(31 downto 0);
  signal con_gpio_in  : std_ulogic_vector(31 downto 0);

  -- Debug heartbeat counter
  signal heartbeat_cnt : unsigned(25 downto 0) := (others => '0');

begin

  -- ============================================================
  -- Clock Infrastructure: 200 MHz LVDS -> 50 MHz single-ended
  -- ============================================================

  ibufds_inst: IBUFDS
    generic map (
      DIFF_TERM  => TRUE,
      IOSTANDARD => "LVDS"
    )
    port map (
      I  => clk_p,
      IB => clk_n,
      O  => clk_ibuf
    );

  mmcm_inst: MMCME2_BASE
    generic map (
      CLKIN1_PERIOD   => 5.0,
      CLKFBOUT_MULT_F => 5.0,
      CLKOUT0_DIVIDE_F => 20.0,
      STARTUP_WAIT    => TRUE
    )
    port map (
      CLKIN1    => clk_ibuf,
      CLKFBIN   => mmcm_fb,
      CLKFBOUT  => mmcm_fb,
      CLKOUT0   => clk_mmcm,
      LOCKED    => mmcm_locked,
      PWRDWN    => '0',
      RST       => '0',
      CLKOUT0B  => open, CLKOUT1  => open, CLKOUT1B => open,
      CLKOUT2   => open, CLKOUT2B => open, CLKOUT3  => open,
      CLKOUT3B  => open, CLKOUT4  => open, CLKOUT5  => open,
      CLKOUT6   => open, CLKFBOUTB => open
    );

  bufg_inst: BUFG
    port map (I => clk_mmcm, O => clk_50mhz);

  -- ============================================================
  -- Reset + Heartbeat
  -- ============================================================
  sys_rstn <= mmcm_locked and (not rstn_i);

  process(clk_50mhz)
  begin
    if rising_edge(clk_50mhz) then
      heartbeat_cnt <= heartbeat_cnt + 1;
    end if;
  end process;

  -- ============================================================
  -- NEORV32 Processor Instance
  -- ============================================================
  neorv32_inst: entity neorv32.neorv32_top
    generic map (
      CLOCK_FREQUENCY  => 50_000_000,
      BOOT_MODE_SELECT => 0,
      IMEM_EN          => true,
      IMEM_SIZE        => IMEM_SIZE,
      DMEM_EN          => true,
      DMEM_SIZE        => DMEM_SIZE,
      RISCV_ISA_C      => true,
      RISCV_ISA_M      => true,
      RISCV_ISA_U      => false,
      RISCV_ISA_Zicntr => true,
      RISCV_ISA_Zihpm  => true,
      RISCV_ISA_Xcfu   => true,
      IO_GPIO_NUM      => 8,
      IO_UART0_EN      => true,
      IO_CFS_EN        => true
    )
    port map (
      clk_i       => std_ulogic(clk_50mhz),
      rstn_i      => sys_rstn,
      gpio_o      => con_gpio_out,
      gpio_i      => con_gpio_in,
      uart0_txd_o => uart0_txd_o,
      uart0_rxd_i => uart0_rxd_i
    );

  -- ============================================================
  -- LED Mapping (Debug + NEORV32)
  -- ============================================================
  gpio_led_left   <= std_ulogic(heartbeat_cnt(25));  -- Heartbeat (~1.3s)
  gpio_led_right  <= std_ulogic(mmcm_locked);        -- MMCM lock status
  gpio_led_center <= con_gpio_out(0);                 -- NEORV32 GPIO[0]
  gpio_led_0      <= con_gpio_out(1);                 -- NEORV32 GPIO[1]

  con_gpio_in <= x"0000000" & gpio_dip_sw;

end rtl;
