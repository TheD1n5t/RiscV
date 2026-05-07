import os

from migen import *

from litex import get_data_mod
from litex.gen import *
from litex.soc.interconnect import wishbone
from litex.soc.cores.cpu import CPU, CPU_GCC_TRIPLE_RISCV32


CPU_VARIANTS = {
    "standard": "RiscVFSM",
}


class RiscVFSM(CPU):
    category             = "softcore"
    family               = "riscv"
    name                 = "riscvfsm"
    human_name           = "RiscVFSM"
    variants             = CPU_VARIANTS
    data_width           = 32
    endianness           = "little"
    gcc_triple           = CPU_GCC_TRIPLE_RISCV32
    linker_output_format = "elf32-littleriscv"
    nop                  = "nop"
    io_regions           = {0x8000_0000: 0x8000_0000}

    @property
    def mem_map(self):
        return {
            "rom"     : 0x0000_0000,
            "sram"    : 0x1000_0000,
            "main_ram": 0x4000_0000,
            "csr"     : 0xf000_0000,
        }

    @property
    def gcc_flags(self):
        flags  = "-march=rv32im_zicsr -mabi=ilp32 "
        flags += "-D__riscvfsm__"
        return flags

    def __init__(self, platform, variant="standard"):
        self.platform         = platform
        self.variant          = variant
        self.reset            = Signal()
        self.interrupt        = Signal(32)
        self.ibus             = wishbone.Interface(data_width=32, address_width=32, addressing="byte")
        self.dbus             = wishbone.Interface(data_width=32, address_width=32, addressing="byte")
        self.periph_buses     = [self.ibus, self.dbus]
        self.memory_buses     = []
        self.state_dbg        = Signal(4)

        self.cpu_params = dict(
            i_clk       = ClockSignal("sys"),
            i_reset     = ResetSignal("sys") | self.reset,
            i_irq_timer_i = self.interrupt[7],

            o_iwb_adr_o = self.ibus.adr,
            i_iwb_dat_i = self.ibus.dat_r,
            o_iwb_sel_o = self.ibus.sel,
            o_iwb_cyc_o = self.ibus.cyc,
            o_iwb_stb_o = self.ibus.stb,
            o_iwb_we_o  = self.ibus.we,
            i_iwb_ack_i = self.ibus.ack,
            i_iwb_err_i = self.ibus.err,

            o_dwb_adr_o = self.dbus.adr,
            o_dwb_dat_o = self.dbus.dat_w,
            i_dwb_dat_i = self.dbus.dat_r,
            o_dwb_sel_o = self.dbus.sel,
            o_dwb_cyc_o = self.dbus.cyc,
            o_dwb_stb_o = self.dbus.stb,
            o_dwb_we_o  = self.dbus.we,
            i_dwb_ack_i = self.dbus.ack,
            i_dwb_err_i = self.dbus.err,

            o_state_dbg_o = self.state_dbg,
        )

    def set_reset_address(self, reset_address):
        self.reset_address = reset_address
        if reset_address != 0x00000000:
            raise ValueError("RiscVFSM currently has a fixed reset vector at 0x00000000.")

    @staticmethod
    def add_sources(platform):
        vdir = get_data_mod("cpu", "riscvfsm").data_location
        platform.add_source(os.path.join(vdir, "cpu_litex.vhd"))
        platform.add_source(os.path.join(vdir, "riscv_core_wishbone.vhd"))
        for name in ["alu.vhd", "csr_file.vhd", "decoder.vhd", "regfile.vhd"]:
            platform.add_source(os.path.join(vdir, name))

    def do_finalize(self):
        assert hasattr(self, "reset_address")
        self.add_sources(self.platform)
        self.specials += Instance("riscv_core_wishbone", **self.cpu_params)
