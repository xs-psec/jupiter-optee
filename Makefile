SHELL := /bin/bash

PYTHON3 ?= python3

ROOT := $(CURDIR)

OPTEE_OS_PATH       := $(ROOT)/optee_os
FTPM_BENCH_TA_PATH  := $(ROOT)/optee_examples/ftpm_bench/ta

OPTEE_OS_OUT        := $(OPTEE_OS_PATH)/out/riscv

CROSS_COMPILE       ?= riscv64-unknown-linux-gnu-

CCACHE              := $(shell which ccache 2>/dev/null)

ARCH                := riscv
COMPILE_S_USER      := 64
COMPILE_S_KERNEL    := 64

OPTEE_OS_TA_DEV_KIT_DIR := $(OPTEE_OS_OUT)/export-ta_rv64

OPTEE_OS_BIN        := $(OPTEE_OS_OUT)/core/tee.bin
FTPM_BENCH_TA_UUID  := d96a5b4c-e3f2-4817-a695-0b1c2d3e4f50
FTPM_BENCH_TA_ELF   := $(FTPM_BENCH_TA_PATH)/out/$(FTPM_BENCH_TA_UUID).stripped.elf

OPTEE_OS_PLATFORM   ?= jupiter

DEBUG               ?= 0


OPTEE_OS_COMMON_FLAGS := \
	ARCH=$(ARCH) \
	PLATFORM=$(OPTEE_OS_PLATFORM) \
	CROSS_COMPILE="$(CCACHE)$(CROSS_COMPILE)" \
	CROSS_COMPILE_core="$(CCACHE)$(CROSS_COMPILE)" \
	CROSS_COMPILE_ta_rv64="$(CCACHE)$(CROSS_COMPILE)" \
	CFG_RV64_core=y \
	CFG_USER_TA_TARGETS=ta_rv64 \
	CFG_TEE_CORE_LOG_LEVEL=0 \
	CFG_TEE_TA_LOG_LEVEL=0 \
	DEBUG=$(DEBUG) \
	O=out/riscv

OPTEE_OS_PLATFORM_FLAGS := \
	CFG_TEE_CORE_NB_CORE=8 \
	CFG_NUM_THREADS=8 \
	CFG_UNWIND=y \
	CFG_SEMIHOSTING_CONSOLE=n \
	CFG_16550_UART=y \
	CFG_UART0_BASE=0xD4017000 \
	CFG_RISCV_PLIC=n \
	CFG_RISCV_MTIME_RATE=24000000 \
	CFG_TDDRAM_START=0x38000000 \
	CFG_TDDRAM_SIZE=0x01000000

CFG_IN_TREE_EARLY_TAS :=
OPTEE_OS_EARLY_TA_FLAGS := EARLY_TA_PATHS="$(FTPM_BENCH_TA_ELF)"

FTPM_BENCH_TA_FLAGS := \
	CROSS_COMPILE="$(CCACHE)$(CROSS_COMPILE)" \
	TA_DEV_KIT_DIR=$(OPTEE_OS_TA_DEV_KIT_DIR) \
	PYTHON3=$(PYTHON3) \
	O=out


.PHONY: all clean optee-os optee-os-core optee-os-devkit ftpm-bench-ta \
	check-python-deps

all: optee-os

check-python-deps:
	@$(PYTHON3) -c "import cryptography" 2>/dev/null || \
		(echo "ERROR: Python 'cryptography' module is required but not installed." && \
		 echo "Please install it with: pip3 install cryptography" && \
		 exit 1)
	@$(PYTHON3) -c "import elftools" 2>/dev/null || \
		(echo "ERROR: Python 'pyelftools' module is required but not installed." && \
		 echo "Please install it with: pip3 install pyelftools" && \
		 exit 1)

optee-os: optee-os-core optee-os-devkit

optee-os-core: ftpm-bench-ta
	@echo "Building OP-TEE OS with ftpm_bench as early TA..."
	$(MAKE) -C $(OPTEE_OS_PATH) \
		$(OPTEE_OS_COMMON_FLAGS) \
		$(OPTEE_OS_PLATFORM_FLAGS) \
		$(OPTEE_OS_EARLY_TA_FLAGS) \
		CFG_IN_TREE_EARLY_TAS="$(CFG_IN_TREE_EARLY_TAS)"
	@echo "OP-TEE OS build complete: $(OPTEE_OS_BIN)"

optee-os-devkit: check-python-deps
	@echo "Building OP-TEE OS TA development kit..."
	$(MAKE) -C $(OPTEE_OS_PATH) \
		$(OPTEE_OS_COMMON_FLAGS) \
		$(OPTEE_OS_PLATFORM_FLAGS) \
		CFG_IN_TREE_EARLY_TAS="$(CFG_IN_TREE_EARLY_TAS)" \
		ta_dev_kit
	@echo "TA dev kit built: $(OPTEE_OS_TA_DEV_KIT_DIR)"

ftpm-bench-ta: optee-os-devkit
	@echo "Building ftpm_bench TA for early TA embedding..."
	$(MAKE) -C $(FTPM_BENCH_TA_PATH) $(FTPM_BENCH_TA_FLAGS)
	@echo "ftpm_bench TA built: $(FTPM_BENCH_TA_ELF)"

clean:
	$(MAKE) -C $(OPTEE_OS_PATH) $(OPTEE_OS_COMMON_FLAGS) clean || true
	rm -rf $(OPTEE_OS_OUT)
	rm -rf $(FTPM_BENCH_TA_PATH)/out
