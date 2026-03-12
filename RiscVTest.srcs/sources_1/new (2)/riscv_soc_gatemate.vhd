library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity riscv_soc_gatemate is
  port (
    clk_i  : in  std_logic; -- 10 MHz board clock
    rstn_i : in  std_logic; -- low active button
    rxd_i  : in  std_logic; -- UART RX from PMOD/USB-UART
    led_o  : out std_logic  -- board LED
  );
end entity;

architecture rtl of riscv_soc_gatemate is
begin

  u_soc : entity work.riscv_soc_boot
    generic map(
      CLK_FREQ_HZ => 10_000_000,
      BAUD        => 115200,
      IMEM_WORDS  => 4096
    )
    port map(
      clk              => clk_i,
      reset            => not rstn_i,
      uart_rx_i        => rxd_i,
      led0_o           => led_o,

      -- debug outputs left open for hardware build
      boot_done_o      => open,
      prog_we_o        => open,
      prog_addr_o      => open,
      prog_wdata_o     => open,
      imem_pc_o        => open,
      dmem_we_o        => open,
      dmem_addr_o      => open,
      dmem_wdata_o     => open,

      -- no external FI in hardware build
      fi_pc_mask_i      => (others => '0'),
      fi_pc_target_i    => (others => '0'),
      fi_pc_strobe_i    => '0',
      fi_state_mask_i   => (others => '0'),
      fi_state_target_i => (others => '0'),
      fi_state_strobe_i => '0',
      fi_dmem_mask_i    => (others => '0'),
      fi_dmem_addr_i    => (others => '0'),
      fi_dmem_strobe_i  => '0'
    );

end architecture;