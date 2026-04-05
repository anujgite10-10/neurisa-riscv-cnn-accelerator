# ================================================================================
# NeurISA — Application Makefile
# ================================================================================
# Wraps the NEORV32 build system for NeurISA applications.
#
# Usage:
#   make demo    — Build MNIST demo
#   make bench   — Build benchmark suite
#   make clean   — Clean build artifacts
# ================================================================================

# Point to NEORV32 installation
NEORV32_HOME ?= $(CURDIR)/rtl/neorv32

# NEORV32 makefile
NEORV32_MK = $(NEORV32_HOME)/sw/common/common.mk

# NeurISA library paths
NEURISA_INC = -I$(CURDIR)/sw/lib
NEURISA_SRC = $(CURDIR)/sw/lib/neurisa_cnn.c

# Architecture flags for NeurISA (RV32IMAC + Zicsr + Zifencei)
# Note: Custom CFU instructions accessed via intrinsics, not compiler march flag
MARCH ?= rv32imac_zicsr_zifencei
MABI  ?= ilp32

# Default target
.PHONY: all demo bench clean help

all: demo

# ============================================================
# MNIST Demo Application
# ============================================================
demo:
	@echo "============================================"
	@echo " Building NeurISA MNIST Demo..."
	@echo "============================================"
	$(MAKE) -C $(NEORV32_HOME)/sw/example/demo_cfu \
		clean_all exe \
		NEORV32_HOME=$(NEORV32_HOME) \
		USER_FLAGS="$(NEURISA_INC)" \
		APP_SRC="$(CURDIR)/sw/app/mnist_demo/main.c $(NEURISA_SRC)" \
		MARCH=$(MARCH) MABI=$(MABI)
	@echo ""
	@echo "Binary: $(NEORV32_HOME)/sw/example/demo_cfu/main.bin"
	@echo "Upload via UART bootloader at 19200 baud"

# ============================================================
# Benchmark Suite
# ============================================================
bench:
	@echo "============================================"
	@echo " Building NeurISA Benchmark Suite..."
	@echo "============================================"
	$(MAKE) -C $(NEORV32_HOME)/sw/example/demo_cfu \
		clean_all exe \
		NEORV32_HOME=$(NEORV32_HOME) \
		USER_FLAGS="$(NEURISA_INC)" \
		APP_SRC="$(CURDIR)/sw/app/benchmark/main.c $(NEURISA_SRC)" \
		MARCH=$(MARCH) MABI=$(MABI)
	@echo ""
	@echo "Binary: $(NEORV32_HOME)/sw/example/demo_cfu/main.bin"

# ============================================================
# Clean
# ============================================================
clean:
	$(MAKE) -C $(NEORV32_HOME)/sw/example/demo_cfu clean_all \
		NEORV32_HOME=$(NEORV32_HOME)

# ============================================================
# Help
# ============================================================
help:
	@echo ""
	@echo "NeurISA Build System"
	@echo "===================="
	@echo "  make demo    - Build MNIST digit recognition demo"
	@echo "  make bench   - Build performance benchmark suite"
	@echo "  make clean   - Clean build artifacts"
	@echo "  make help    - Show this help"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - RISC-V GCC toolchain (riscv32-unknown-elf-gcc)"
	@echo "  - NEORV32_HOME set to rtl/neorv32 (default)"
	@echo ""
