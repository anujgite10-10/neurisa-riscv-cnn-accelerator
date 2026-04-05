---
description: How to build, simulate, and run the NeurISA project
---

# NeurISA — Build & Run Workflow

## Prerequisites

Install the following tools:

1. **Xilinx Vivado 2023.2+** — for synthesis, implementation, and FPGA programming
2. **GHDL** (optional) — for open-source VHDL simulation: https://github.com/ghdl/ghdl/releases
3. **RISC-V GCC Toolchain** — for compiling software:
   - Download from: https://github.com/stnolting/riscv-gcc-prebuilt/releases
   - Or: `choco install riscv-gnu-toolchain` (if using Chocolatey)
4. **GTKWave** (optional) — for viewing waveforms: https://gtkwave.sourceforge.net/

---

## Step 1: Simulate the CFU (Custom Instructions)

### Option A: GHDL (Free, Open-Source)

```powershell
# From project root
powershell -ExecutionPolicy Bypass -File tb/sim/run_cfu_ghdl.ps1
```

This will:
- Analyze the CFU VHDL
- Create and run a testbench with VRELU, VADD, VMAC, VPOOL tests
- Generate waveform file at `tb/sim/work_cfu/cfu_tb.ghw`
- Open with: `gtkwave tb/sim/work_cfu/cfu_tb.ghw`

### Option B: Vivado Simulator (xsim)

```powershell
# From project root
cd vivado
vivado -mode tcl -source run_sim.tcl
```

### Option C: Questa/ModelSim (for UVM testbenches)

```powershell
# Compile UVM testbench
cd tb/uvm/cfu_tb
vlog -sv +incdir+. cfu_pkg.sv cfu_if.sv
# Run tests
vsim -c work.cfu_top +UVM_TESTNAME=cfu_full_regression_test -do "run -all; quit"
```

---

## Step 2: Synthesize for Zynq-7000 ZC-706

### Option A: Automated TCL Script

```powershell
# From project root — runs synthesis + implementation + bitstream
vivado -mode tcl -source vivado/neurisa_zc706.tcl
```

### Option B: Vivado GUI

1. Open Vivado
2. Create new project → RTL Project → Part: `xc7z045ffg900-2`
3. Add sources:
   - All files from `rtl/neorv32/rtl/core/*.vhd` (set library to `neorv32`)
   - All files from `rtl/neurisa/*.vhd`
   - `rtl/top/neurisa_top.vhd` (set as top)
4. Add constraints: `vivado/constraints/zc706.xdc`
5. Run Synthesis → Implementation → Generate Bitstream

---

## Step 3: Compile Software

```powershell
# Set up environment (adjust path to your RISC-V toolchain)
$env:NEORV32_HOME = "C:\Users\Anuj\ChipMonk\rtl\neorv32"

# Copy NeurISA libraries to NEORV32 software framework
Copy-Item sw/lib/neurisa_intrinsics.h rtl/neorv32/sw/lib/include/
Copy-Item sw/lib/neurisa_cnn.h rtl/neorv32/sw/lib/include/
Copy-Item sw/lib/neurisa_cnn.c rtl/neorv32/sw/lib/source/

# Build MNIST demo
cd sw/app/mnist_demo
make -C $env:NEORV32_HOME/sw/example/demo_cfu clean_all \
  APP_SRC="C:/Users/Anuj/ChipMonk/sw/app/mnist_demo/main.c" \
  APP_INC="-IC:/Users/Anuj/ChipMonk/sw/lib" exe

# Or build benchmark
cd sw/app/benchmark
make -C $env:NEORV32_HOME/sw/example/demo_cfu clean_all \
  APP_SRC="C:/Users/Anuj/ChipMonk/sw/app/benchmark/main.c" \
  APP_INC="-IC:/Users/Anuj/ChipMonk/sw/lib" exe
```

---

## Step 4: Program FPGA & Run Demo

// turbo-all

1. Connect ZC-706 via USB-JTAG and USB-UART (J17)

2. Program bitstream:
```powershell
# In Vivado TCL console
open_hw_manager
connect_hw_server
open_hw_target
set_property PROGRAM.FILE {vivado/neurisa_zc706/neurisa_zc706.runs/impl_1/neurisa_top.bit} [current_hw_device]
program_hw_devices
```

3. Open serial terminal (PuTTY, TeraTerm, or built-in):
   - Port: COMx (check Device Manager)
   - Baud: 19200
   - 8N1

4. In the NEORV32 bootloader menu, press 'u' to upload executable via UART

5. Send the compiled `.bin` file through the terminal

6. Watch the demo output with performance metrics!

---

## Step 5: Collect Results

After running, you'll see:
- **Instruction self-test results** (VMAC, VRELU, VADD, VPOOL)
- **Inference results** (predicted digit + confidence)
- **Performance comparison table** (Software vs ISA vs CFS cycles + speedup)
- **Vivado reports** (utilization, timing, power) in `vivado/neurisa_zc706/reports/`
