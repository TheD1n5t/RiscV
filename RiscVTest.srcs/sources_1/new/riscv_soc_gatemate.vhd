library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity riscv_soc_gatemate is
  port (
    clk_i        : in  std_logic; -- 10 MHz board clock
    rstn_i       : in  std_logic; -- low active button
    rxd_i        : in  std_logic; -- UART RX from PMOD/USB-UART
    txd_o        : out std_logic; -- UART TX to PMOD/USB-UART
    led_o        : out std_logic; -- board LED
    boot_mode_i  : in  std_logic;
    qspi_sck_o   : out std_logic;
    qspi_cs_n_o  : out std_logic;
    qspi_io0_o   : out std_logic;
    qspi_io1_i   : in  std_logic;
    qspi_io2_o   : out std_logic;
    qspi_io3_o   : out std_logic
  );
end entity;

architecture rtl of riscv_soc_gatemate is
begin

  u_soc : entity work.riscv_soc_boot
    generic map(
      CLK_FREQ_HZ => 10_000_000,
      BAUD        => 115200,
      IMEM_WORDS  => 4096,
      SPI_CLK_DIV => 10
    )
    port map(
      clk              => clk_i,
      reset            => not rstn_i,
      uart_rx_i        => rxd_i,
      uart_tx_o        => txd_o,
      led0_o           => led_o,
      boot_mode_i      => boot_mode_i,
      qspi_sck_o       => qspi_sck_o,
      qspi_cs_n_o      => qspi_cs_n_o,
      qspi_io0_o       => qspi_io0_o,
      qspi_io1_i       => qspi_io1_i,
      qspi_io2_o       => qspi_io2_o,
      qspi_io3_o       => qspi_io3_o,

      -- debug outputs left open for hardware build
      boot_done_o      => open,
      boot_error_o     => open,
      prog_we_o        => open,
      prog_addr_o      => open,
      prog_wdata_o     => open,
      imem_pc_o        => open,
      dmem_we_o        => open,
      dmem_addr_o      => open,
      dmem_wdata_o     => open
    );

end architecture;
