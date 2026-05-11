# -----------------------------------------------------------------------------
# GateMate Makefile for current RISC-V SoC
# -----------------------------------------------------------------------------

TOP       = riscv_soc_gatemate
NETLIST   = $(TOP).json

# Local GateMate wrapper/core sources in this workspace.
CORE_DIR  ?= $(CURDIR)/RiscVTest.srcs/sources_1/new

GHDLFLAGS = --std=08 --ieee=synopsys --work=work
GHDLGEN   ?=
SYNFLAGS  = -luttree -nomx8

YOSYS     = yosys
PR        = nextpnr-himbaechel
BIT       = gmpack
OFL       = openFPGALoader
GHDL      = ghdl

# -----------------------------------------------------------------------------
# RISC-V software toolchain
# -----------------------------------------------------------------------------
RISCV_PREFIX ?= riscv64-unknown-elf

CC      = $(RISCV_PREFIX)-gcc
OBJCOPY = $(RISCV_PREFIX)-objcopy
OBJDUMP = $(RISCV_PREFIX)-objdump

CFLAGS  = -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os -msmall-data-limit=0
ASMFLAGS = -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles -Wl,--no-relax
LDFLAGS = -T link.ld -nostdlib

# optional if not in PATH
# TOOLBIN  = /home/krischan-ledwig/Documents/NanoSat/OpenSourceRiscV/cc-toolchain-linux/workspace/oss-cad-suite/bin
# YOSYS    = $(TOOLBIN)/yosys
# PR       = $(TOOLBIN)/nextpnr-himbaechel
# BIT      = $(TOOLBIN)/gmpack
# OFL      = $(TOOLBIN)/openFPGALoader

VHDL_SRC = \
	alu.vhd \
	csr_file.vhd \
	decoder.vhd \
	dmem.vhd \
	imem_dp_ram.vhd \
	regfile.vhd \
	cpu.vhd \
	riscv_soc_boot.vhd \
	simple_timer.vhd \
	uart_rx.vhd \
	uart_tx.vhd \
	riscv_soc_gatemate.vhd

CCF = $(TOP).ccf
BITFILE = $(TOP).bit
ASCFILE = $(TOP).txt

.PHONY: all clean synth impl bitstream jtag info sw asm baseline pc_tmr_only state_tmr_only rf_tmr_only full_hardening sim-fault-build fault-compare fault-campaign-large

all: clean synth impl bitstream

info:
	$(YOSYS) -V
	$(PR) --version || true
	$(CC) --version || true

# -----------------------------------------------------------------------------
# FPGA flow
# -----------------------------------------------------------------------------
synth:
	cd "$(CORE_DIR)" && $(YOSYS) -m ghdl -ql "$(CURDIR)/synth.log" -p "\
		ghdl $(GHDLFLAGS) $(GHDLGEN) $(VHDL_SRC) -e $(TOP); \
		synth_gatemate -top $(TOP) $(SYNFLAGS); \
		write_json $(CURDIR)/$(NETLIST); \
	"

baseline:
	$(MAKE) synth GHDLGEN='-gG_FAULT_INJECT=false -gG_PC_TMR=false -gG_STATE_TMR=false -gG_RF_TMR=false -gG_RF_SELF_HEAL=false -gG_IMEM_ECC=false -gG_DMEM_ECC=false'

pc_tmr_only:
	$(MAKE) synth GHDLGEN='-gG_FAULT_INJECT=false -gG_PC_TMR=true -gG_STATE_TMR=false -gG_RF_TMR=false -gG_RF_SELF_HEAL=false -gG_IMEM_ECC=false -gG_DMEM_ECC=false'

state_tmr_only:
	$(MAKE) synth GHDLGEN='-gG_FAULT_INJECT=false -gG_PC_TMR=false -gG_STATE_TMR=true -gG_RF_TMR=false -gG_RF_SELF_HEAL=false -gG_IMEM_ECC=false -gG_DMEM_ECC=false'

rf_tmr_only:
	$(MAKE) synth GHDLGEN='-gG_FAULT_INJECT=false -gG_PC_TMR=false -gG_STATE_TMR=false -gG_RF_TMR=true -gG_RF_SELF_HEAL=true -gG_IMEM_ECC=false -gG_DMEM_ECC=false'

full_hardening:
	$(MAKE) synth GHDLGEN='-gG_FAULT_INJECT=false -gG_PC_TMR=true -gG_STATE_TMR=true -gG_RF_TMR=true -gG_RF_SELF_HEAL=true -gG_IMEM_ECC=true -gG_DMEM_ECC=true'

impl:
	$(PR) \
		--device CCGM1A1 \
		--json $(NETLIST) \
		--router router2 \
		--vopt ccf=$(CCF) \
		--vopt out=$(ASCFILE) \
		> impl.log

bitstream:
	$(BIT) $(ASCFILE) $(BITFILE)

jtag:
	$(OFL) -b gatemate_evb_jtag $(BITFILE)

# -----------------------------------------------------------------------------
# Software flow
# -----------------------------------------------------------------------------

# Default software target example:
# make sw PROG=hello_uart
sw: $(PROG).boot.bin

# Simple assembly-only target:
# make asm PROG=smoke
asm: $(PROG).boot.bin

%.elf: %.c uart.c print.c start.S link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S uart.c print.c $<

%.elf: %.S link.ld
	$(CC) $(ASMFLAGS) $(LDFLAGS) -o $@ $<

%.lst: %.elf
	$(OBJDUMP) -d $< > $@

%.text.bin: %.elf
	$(OBJCOPY) --dump-section .text=$@ $<

%.rodata.bin: %.elf
	@if $(OBJCOPY) --dump-section .rodata=$@ $< 2>/dev/null; then \
		:; \
	else \
		rm -f $@; \
		touch $@; \
	fi

%.data.bin: %.elf
	@if $(OBJCOPY) --dump-section .data=$@ $< 2>/dev/null; then \
		:; \
	else \
		rm -f $@; \
		touch $@; \
	fi

%.imem.bin: %.text.bin
	cp $< $@

%.dmem.bin: %.rodata.bin %.data.bin
	cat $^ > $@

%.boot.bin: %.imem.bin %.dmem.bin
	python3 -c "import struct,sys; imem=open(sys.argv[1],'rb').read(); dmem=open(sys.argv[2],'rb').read(); open(sys.argv[3],'wb').write(b'\x55\xAA'+struct.pack('<I',len(imem))+struct.pack('<I',len(dmem))+imem+dmem)" $^ $@

%.boot.hex: %.boot.bin
	od -An -tx1 -v $< | tr -s ' ' '\n' | sed '/^$$/d' > $@

sim-fault-build: fault_campaign.boot.hex branch_fsm_campaign.boot.hex
	$(GHDL) -a --std=08 \
		RiscVTest.srcs/sources_1/new/alu.vhd \
		RiscVTest.srcs/sources_1/new/csr_file.vhd \
		RiscVTest.srcs/sources_1/new/decoder.vhd \
		RiscVTest.srcs/sources_1/new/dmem.vhd \
		RiscVTest.srcs/sources_1/new/imem_dp_ram.vhd \
		RiscVTest.srcs/sources_1/new/regfile.vhd \
		RiscVTest.srcs/sources_1/new/cpu.vhd \
		RiscVTest.srcs/sources_1/new/simple_timer.vhd \
		RiscVTest.srcs/sources_1/new/uart_rx.vhd \
		RiscVTest.srcs/sources_1/new/uart_tx.vhd \
		RiscVTest.srcs/sources_1/new/riscv_soc_boot.vhd \
		tb_fault_compare.vhd
	$(GHDL) -e --std=08 tb_fault_compare

fault-compare: sim-fault-build
	python3 scripts/fault_compare.py

fault-campaign-large: sim-fault-build
	python3 scripts/fault_campaign_batch.py
# Optional disassembly
%.lst: %.elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -f *.json *.log *.txt *.bit *.config *.history *.rpt
	rm -f *.elf *.bin *.boot.bin *.lst *.imem.bin *.dmem.bin *.text.bin *.rodata.bin *.data.bin
