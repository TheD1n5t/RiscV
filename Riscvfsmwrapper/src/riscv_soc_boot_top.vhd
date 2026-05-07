library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity riscv_soc_boot_top is
  port(
    clk       : in  std_logic;
    reset     : in  std_logic;
    uart_rx_i : in  std_logic;
    uart_tx_o : out std_logic;
    led0_o    : out std_logic
  );
end entity;

architecture rtl of riscv_soc_boot_top is
begin

  u_soc : entity work.riscv_soc_boot
    generic map(
      CLK_FREQ_HZ => 100_000_000,
      BAUD        => 115200,
      IMEM_WORDS  => 4096
    )
    port map(
      clk       => clk,
      reset     => reset,
      uart_rx_i => uart_rx_i,
      uart_tx_o => uart_tx_o,
      led0_o    => led0_o,

      -- debug ports not used on hardware
      boot_done_o  => open,
      prog_we_o    => open,
      prog_addr_o  => open,
      prog_wdata_o => open,
      imem_pc_o    => open,
      dmem_we_o    => open,
      dmem_addr_o  => open,
      dmem_wdata_o => open,

      -- fault injection disabled on hardware
      fi_pc_mask_i      => (others => '0'),
      fi_pc_target_i    => (others => '0'),
      fi_pc_strobe_i    => '0',
      fi_state_mask_i   => (others => '0'),
      fi_state_target_i => (others => '0'),
      fi_state_strobe_i => '0',

      fi_dmem_mask_i    => (others => '0'),
      fi_dmem_addr_i    => (others => '0'),
      fi_dmem_strobe_i  => '0',

      fi_rf_mask_i      => (others => '0'),
      fi_rf_addr_i      => (others => '0'),
      fi_rf_target_i    => (others => '0'),
      fi_rf_strobe_i    => '0',

      fi_imem_mask_i    => (others => '0'),
      fi_imem_addr_i    => (others => '0'),
      fi_imem_strobe_i  => '0'
    );

end rtl;