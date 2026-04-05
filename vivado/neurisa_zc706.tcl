# ================================================================================
# NeurISA — Vivado Project Creation Script for Zynq-7000 ZC-706
# ================================================================================
# Usage: vivado -mode tcl -source vivado/neurisa_zc706.tcl
# ================================================================================

# Project settings
set project_name "neurisa_zc706"
set project_dir  "./vivado/${project_name}"
set part         "xc7z045ffg900-2"
set board        "xilinx.com:zc706:part0:1.4"

# Create project
create_project ${project_name} ${project_dir} -part ${part} -force
set_property board_part ${board} [current_project]

# ============================================================
# Add NEORV32 core sources
# ============================================================
set neorv32_rtl_dir "./rtl/neorv32/rtl"

# Add all NEORV32 core VHDL files
add_files -fileset sources_1 [glob ${neorv32_rtl_dir}/core/*.vhd]

# Add NEORV32 library property
set_property library neorv32 [get_files [glob ${neorv32_rtl_dir}/core/*.vhd]]

# ============================================================
# Add NeurISA custom RTL sources
# ============================================================
add_files -fileset sources_1 {
  ./rtl/neurisa/neorv32_cpu_alu_cfu.vhd
  ./rtl/neurisa/cnn_conv_engine.vhd
  ./rtl/neurisa/cnn_pool_engine.vhd
  ./rtl/neurisa/cnn_activation.vhd
  ./rtl/neurisa/cnn_controller.vhd
  ./rtl/neurisa/neorv32_cfs_cnn.vhd
}

# Set NeurISA CFU to override the default NEORV32 one (same entity name)

# Add top-level
add_files -fileset sources_1 ./rtl/top/neurisa_top.vhd

# Set top module
set_property top neurisa_top [current_fileset]

# ============================================================
# CRITICAL: Set ALL VHDL files to VHDL-2008
# NEORV32 and NeurISA use VHDL-2008 features:
#   process(all), generate-local signals, etc.
# ============================================================
set_property file_type {VHDL 2008} [get_files *.vhd]

# ============================================================
# Add constraints
# ============================================================
add_files -fileset constrs_1 ./vivado/constraints/zc706.xdc

# ============================================================
# Synthesis settings
# ============================================================
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING on [get_runs synth_1]

# ============================================================
# Implementation settings
# ============================================================
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

# ============================================================
# Run synthesis
# ============================================================
puts "============================================"
puts " NeurISA: Starting Synthesis..."
puts "============================================"
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "Synthesis complete!"

# Check for errors
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  puts "ERROR: Synthesis failed!"
  exit 1
}

# ============================================================
# Run implementation
# ============================================================
puts "============================================"
puts " NeurISA: Starting Implementation..."
puts "============================================"
launch_runs impl_1 -jobs 4
wait_on_run impl_1
puts "Implementation complete!"

# ============================================================
# Generate bitstream
# ============================================================
puts "============================================"
puts " NeurISA: Generating Bitstream..."
puts "============================================"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "Bitstream generated!"

# ============================================================
# Reports
# ============================================================
open_run impl_1
file mkdir "${project_dir}/reports"

# Utilization report
report_utilization -file "${project_dir}/reports/utilization.rpt"
puts "Utilization report saved."

# Timing report
report_timing_summary -file "${project_dir}/reports/timing.rpt"
puts "Timing report saved."

# Power report
report_power -file "${project_dir}/reports/power.rpt"
puts "Power report saved."

puts ""
puts "============================================"
puts " NeurISA BUILD COMPLETE!"
puts " Bitstream: ${project_dir}/${project_name}.runs/impl_1/neurisa_top.bit"
puts " Reports:   ${project_dir}/reports/"
puts "============================================"
