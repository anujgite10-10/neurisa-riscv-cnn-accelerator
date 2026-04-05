## ZC-706 Pin Constraints for NeurISA
## Target: Zynq-7000 XC7Z045 FFG900-2 (ZC-706)
## Source: Official Xilinx ZC-706 Master XDC

# ============================================================
# System Clock - 200 MHz LVDS (Bank 34, HP)
# ============================================================
set_property PACKAGE_PIN H9 [get_ports clk_p]
set_property PACKAGE_PIN G9 [get_ports clk_n]
set_property IOSTANDARD LVDS [get_ports clk_p]
set_property IOSTANDARD LVDS [get_ports clk_n]
create_clock -period 5.000 -name sys_clk [get_ports clk_p]

# ============================================================
# Reset - GPIO_SW_CENTER push button (Bank 35, HP, Active-HIGH)
# ============================================================
set_property PACKAGE_PIN K15 [get_ports rstn_i]
set_property IOSTANDARD LVCMOS15 [get_ports rstn_i]

# ============================================================
# UART via PMOD1 Connector J58 (Bank 11, HR, LVCMOS25)
# Connect USB-UART adapter:
#   PMOD1_0 (pin 1) = FPGA TX -> Adapter RX
#   PMOD1_1 (pin 2) = FPGA RX <- Adapter TX
#   PMOD GND (pin 5) = Adapter GND
# ============================================================
set_property PACKAGE_PIN AJ21 [get_ports uart0_txd_o]
set_property IOSTANDARD LVCMOS25 [get_ports uart0_txd_o]
set_property PACKAGE_PIN AK21 [get_ports uart0_rxd_i]
set_property IOSTANDARD LVCMOS25 [get_ports uart0_rxd_i]

# ============================================================
# LEDs (Active-high)
# ============================================================
# GPIO_LED_LEFT  - Bank 11 HR
set_property PACKAGE_PIN Y21 [get_ports gpio_led_left]
set_property IOSTANDARD LVCMOS25 [get_ports gpio_led_left]
# GPIO_LED_RIGHT - Bank 11 HR
set_property PACKAGE_PIN W21 [get_ports gpio_led_right]
set_property IOSTANDARD LVCMOS25 [get_ports gpio_led_right]
# GPIO_LED_CENTER - Bank 33 HP (1.5V)
set_property PACKAGE_PIN G2 [get_ports gpio_led_center]
set_property IOSTANDARD LVCMOS15 [get_ports gpio_led_center]
# GPIO_LED_0 - Bank 35 HP (1.5V)
set_property PACKAGE_PIN A17 [get_ports gpio_led_0]
set_property IOSTANDARD LVCMOS15 [get_ports gpio_led_0]

# ============================================================
# DIP Switches (Bank 10, HR, LVCMOS25)
# ============================================================
set_property PACKAGE_PIN AB17 [get_ports {gpio_dip_sw[0]}]
set_property PACKAGE_PIN AC16 [get_ports {gpio_dip_sw[1]}]
set_property PACKAGE_PIN AC17 [get_ports {gpio_dip_sw[2]}]
set_property PACKAGE_PIN AJ13 [get_ports {gpio_dip_sw[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {gpio_dip_sw[*]}]

# ============================================================
# Timing Constraints
# ============================================================
set_false_path -from [get_ports rstn_i]
set_false_path -from [get_ports {gpio_dip_sw[*]}]
set_false_path -to   [get_ports gpio_led_left]
set_false_path -to   [get_ports gpio_led_right]
set_false_path -to   [get_ports gpio_led_center]
set_false_path -to   [get_ports gpio_led_0]
set_false_path -to   [get_ports uart0_txd_o]
set_false_path -from [get_ports uart0_rxd_i]
