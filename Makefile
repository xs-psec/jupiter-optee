SHELL := /bin/bash

PYTHON3 ?= python3

ROOT := $(CURDIR)

OPTEE_OS_PATH       := $(ROOT)/optee_os
OPTEE_FTPM_PATH     := $(ROOT)/optee_ftpm
FTPM_BENCH_TA_PATH  := $(ROOT)/optee_examples/ftpm_bench/ta
MS_TPM_20_REF_PATH  := $(ROOT)/ms-tpm-20-ref

OPTEE_OS_OUT        := $(OPTEE_OS_PATH)/out/riscv

CROSS_COMPILE       ?= riscv64-unknown-linux-gnu-

CCACHE              := $(shell which ccache 2>/dev/null)

ARCH                := riscv
COMPILE_S_USER      := 64
COMPILE_S_KERNEL    := 64

OPTEE_OS_TA_DEV_KIT_DIR := $(OPTEE_OS_OUT)/export-ta_rv64

OPTEE_OS_BIN        := $(OPTEE_OS_OUT)/core/tee.bin

FTPM_TA_UUID        := bc50d971-d4c9-42c4-82cb-343fb7f37896
FTPM_BENCH_TA_UUID  := a7b8c9d0-e1f2-4a5b-8c6d-7e8f9a0b1c2d
OPTEE_FTPM_TA_ELF   := $(OPTEE_FTPM_PATH)/out/$(FTPM_TA_UUID).stripped.elf
FTPM_BENCH_TA_ELF   := $(FTPM_BENCH_TA_PATH)/out/$(FTPM_BENCH_TA_UUID).stripped.elf

OPTEE_OS_PLATFORM   ?= jupiter

DEBUG               ?= 0

MEASURED_BOOT_FTPM  ?= y

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

CFG_IN_TREE_EARLY_TAS := trusted_keys/f04a0fe7-1f5d-4b9b-abf7-619b85b4ce8c

FTPM_FLAGS := \
	CROSS_COMPILE="$(CCACHE)$(CROSS_COMPILE)" \
	TA_DEV_KIT_DIR=$(OPTEE_OS_TA_DEV_KIT_DIR) \
	CFG_MS_TPM_20_REF=$(MS_TPM_20_REF_PATH) \
	CFG_TA_MEASURED_BOOT=y \
	$(if $(filter 1,$(DEBUG)),CFG_TA_DEBUG=y) \
	O=out

FTPM_BENCH_TA_FLAGS := \
	CROSS_COMPILE="$(CCACHE)$(CROSS_COMPILE)" \
	TA_DEV_KIT_DIR=$(OPTEE_OS_TA_DEV_KIT_DIR) \
	PYTHON3=$(PYTHON3) \
	O=out

.PHONY: all clean optee-os optee-os-devkit ftpm ftpm-bench-ta \
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

ifeq ($(MEASURED_BOOT_FTPM),y)
OPTEE_OS_EARLY_TA_FLAGS := EARLY_TA_PATHS="$(OPTEE_FTPM_TA_ELF) $(FTPM_BENCH_TA_ELF)"

optee-os: ftpm ftpm-bench-ta
	@echo "Building OP-TEE OS with fTPM and ftpm_bench as early TA..."
	$(MAKE) -C $(OPTEE_OS_PATH) \
		$(OPTEE_OS_COMMON_FLAGS) \
		$(OPTEE_OS_PLATFORM_FLAGS) \
		$(OPTEE_OS_EARLY_TA_FLAGS) \
		CFG_IN_TREE_EARLY_TAS="$(CFG_IN_TREE_EARLY_TAS)"
	@echo "OP-TEE OS build complete: $(OPTEE_OS_BIN)"
else
optee-os:
	@echo "Building OP-TEE OS without fTPM..."
	$(MAKE) -C $(OPTEE_OS_PATH) \
		$(OPTEE_OS_COMMON_FLAGS) \
		$(OPTEE_OS_PLATFORM_FLAGS) \
		CFG_IN_TREE_EARLY_TAS="$(CFG_IN_TREE_EARLY_TAS)"
	@echo "OP-TEE OS build complete: $(OPTEE_OS_BIN)"
endif

optee-os-devkit: check-python-deps
	@echo "Building OP-TEE OS TA development kit..."
	$(MAKE) -C $(OPTEE_OS_PATH) \
		$(OPTEE_OS_COMMON_FLAGS) \
		$(OPTEE_OS_PLATFORM_FLAGS) \
		CFG_IN_TREE_EARLY_TAS="$(CFG_IN_TREE_EARLY_TAS)" \
		ta_dev_kit
	@echo "TA dev kit built: $(OPTEE_OS_TA_DEV_KIT_DIR)"

ftpm: optee-os-devkit
ifeq ($(MEASURED_BOOT_FTPM),y)
	@echo "Building fTPM TA..."
	$(MAKE) -C $(OPTEE_FTPM_PATH) $(FTPM_FLAGS)
	@echo "fTPM TA built: $(OPTEE_FTPM_TA_ELF)"
else
	@echo "fTPM is disabled (MEASURED_BOOT_FTPM != y)"
endif

ftpm-bench-ta: optee-os-devkit
ifeq ($(MEASURED_BOOT_FTPM),y)
	@echo "Building ftpm_bench TA for early TA embedding..."
	$(MAKE) -C $(FTPM_BENCH_TA_PATH) $(FTPM_BENCH_TA_FLAGS)
	@echo "ftpm_bench TA built: $(FTPM_BENCH_TA_ELF)"
else
	@echo "ftpm_bench early TA is disabled (MEASURED_BOOT_FTPM != y)"
endif

clean: optee-os-clean ftpm-clean ftpm-bench-ta-clean

optee-os-clean:
	$(MAKE) -C $(OPTEE_OS_PATH) $(OPTEE_OS_COMMON_FLAGS) clean || true
	rm -rf $(OPTEE_OS_OUT)

ftpm-clean:
ifeq ($(MEASURED_BOOT_FTPM),y)
	$(MAKE) -C $(OPTEE_FTPM_PATH) $(FTPM_FLAGS) clean || true
	rm -rf $(OPTEE_FTPM_PATH)/out
endif

ftpm-bench-ta-clean:
	rm -rf $(FTPM_BENCH_TA_PATH)/out
