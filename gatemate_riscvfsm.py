import os

from migen import *

from litex.gen import *

from litex_boards.platforms import colognechip_gatemate_evb
from litex.build.parser import LiteXArgumentParser

from litex.soc.integration.soc_core import SoCCore
from litex.soc.integration.builder import Builder

from litex.soc.cores.clock import CRG

from core import RISCVFSM


class BaseSoC(SoCCore):
    def __init__(self, sys_clk_freq=int(24e6), **kwargs):
        platform = colognechip_gatemate_evb.Platform()

        # WICHTIG: keine Standard-CPU von LiteX verwenden
        kwargs["cpu_type"] = None

        # Basis-SoC ohne LiteX-Standard-CPU
        SoCCore.__init__(
            self,
            platform,
            clk_freq=sys_clk_freq,
            ident="RISCVFSM on GateMate EVB",
            **kwargs
        )

        # Clock/Reset
        self.crg = CRG(platform.request("clk10"), rst=0)

        # Deine CPU instanzieren
        self.cpu = RISCVFSM(platform)

        # Instruction-/Datenbus an den SoC hängen
        self.bus.add_master(name="cpu_ibus", master=self.cpu.ibus)
        self.bus.add_master(name="cpu_dbus", master=self.cpu.dbus)


def main():
    parser = LiteXArgumentParser(platform=colognechip_gatemate_evb.Platform, description="RISCVFSM SoC on GateMate EVB")
    parser.add_target_argument("--sys-clk-freq", default=24e6, type=float)

    args = parser.parse_args()

    soc = BaseSoC(
        sys_clk_freq=int(args.sys_clk_freq),
        integrated_rom_size=0x8000,
        integrated_sram_size=0x8000,
        integrated_main_ram_size=0x4000,
        uart_name="crossover",
    )

    builder = Builder(soc)
    builder.build(run=args.build)


if __name__ == "__main__":
    main()