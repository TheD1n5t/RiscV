# -----------------------------------------------------------------------------
# GateMate Makefile for current RISC-V SoC
# -----------------------------------------------------------------------------

TOP       = riscv_soc_gatemate
NETLIST   = $(TOP).json

SRC_DIR   = /home/krischan-ledwig/Documents/NanoSat/OpenSourceRiscV/cc-toolchain-linux/workspace/RiscVFSM/RiscVTest.srcs/sources_1/new

GHDLFLAGS = --std=08 --ieee=synopsys --work=work
SYNFLAGS  = -luttree -nomx8

YOSYS     = yosys
PR        = nextpnr-himbaechel
BIT       = gmpack
OFL       = openFPGALoader

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
	$(SRC_DIR)/alu.vhd \
	$(SRC_DIR)/csr_file.vhd \
	$(SRC_DIR)/decoder.vhd \
	$(SRC_DIR)/dmem.vhd \
	$(SRC_DIR)/imem_dp_ram.vhd \
	$(SRC_DIR)/regfile.vhd \
	$(SRC_DIR)/cpu.vhd \
	$(SRC_DIR)/riscv_soc_boot.vhd \
	$(SRC_DIR)/simple_timer.vhd \
	$(SRC_DIR)/uart_rx.vhd \
	$(SRC_DIR)/uart_tx.vhd \
	$(SRC_DIR)/riscv_soc_gatemate.vhd

CCF = $(TOP).ccf
BITFILE = $(TOP).bit
ASCFILE = $(TOP).txt

.PHONY: all clean synth impl bitstream jtag info sw asm

all: clean synth impl bitstream

info:
	$(YOSYS) -V
	$(PR) --version || true
	$(CC) --version || true

# -----------------------------------------------------------------------------
# FPGA flow
# -----------------------------------------------------------------------------
synth:
	$(YOSYS) -m ghdl -ql synth.log -p "\
		ghdl $(GHDLFLAGS) $(VHDL_SRC) -e $(TOP); \
		synth_gatemate -top $(TOP) $(SYNFLAGS); \
		write_json $(NETLIST); \
	"

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
# Optional disassembly
%.lst: %.elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -f *.json *.log *.txt *.bit *.config *.history *.rpt
	rm -f *.elf *.bin *.boot.bin *.lst *.imem.bin *.dmem.bin *.text.bin *.rodata.bin *.data.bin
