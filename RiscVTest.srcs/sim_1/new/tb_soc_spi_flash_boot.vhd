library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_soc_spi_flash_boot is
end entity;

architecture sim of tb_soc_spi_flash_boot is

  constant CLK_PERIOD : time := 20 ns;
  constant MAX_CYCLES : integer := 200000;

  signal clk       : std_logic := '0';
  signal reset     : std_logic := '1';
  signal uart_rx_i : std_logic := '1';
  signal uart_tx_o : std_logic;
  signal led0_o    : std_logic;

  signal boot_mode_i : std_logic := '0';
  signal qspi_sck_o  : std_logic;
  signal qspi_cs_n_o : std_logic;
  signal qspi_io0_o  : std_logic;
  signal qspi_io1_i  : std_logic := '0';
  signal qspi_io2_o  : std_logic;
  signal qspi_io3_o  : std_logic;

  signal boot_done_o  : std_logic;
  signal prog_we_o    : std_logic;
  signal prog_addr_o  : std_logic_vector(31 downto 0);
  signal prog_wdata_o : std_logic_vector(31 downto 0);
  signal imem_pc_o    : std_logic_vector(31 downto 0);
  signal dmem_we_o    : std_logic;
  signal dmem_addr_o  : std_logic_vector(31 downto 0);
  signal dmem_wdata_o : std_logic_vector(31 downto 0);

  signal sim_done : std_logic := '0';

  type flash_mem_t is array(0 to 63) of std_logic_vector(7 downto 0);
  constant flash_mem : flash_mem_t := (
    -- Header: magic 55 AA, IMEM length = 12 bytes, DMEM length = 0 bytes.
    0  => x"55",
    1  => x"AA",
    2  => x"0C",
    3  => x"00",
    4  => x"00",
    5  => x"00",
    6  => x"00",
    7  => x"00",
    8  => x"00",
    9  => x"00",

    -- addi x1, x0, 123
    10 => x"93",
    11 => x"00",
    12 => x"B0",
    13 => x"07",

    -- sw x1, 0(x0)
    14 => x"23",
    15 => x"20",
    16 => x"10",
    17 => x"00",

    -- jal x0, 0
    18 => x"6F",
    19 => x"00",
    20 => x"00",
    21 => x"00",

    others => x"00"
  );

  signal bit_count : integer := 0;
  signal rd_byte   : integer := 0;
  signal rd_bit    : integer range 0 to 7 := 7;

begin

  clk <= not clk after CLK_PERIOD / 2;

  uut : entity work.riscv_soc_boot
    generic map(
      CLK_FREQ_HZ => 50_000_000,
      BAUD        => 115200,
      IMEM_WORDS  => 4096,
      SPI_CLK_DIV => 2
    )
    port map(
      clk       => clk,
      reset     => reset,
      uart_rx_i => uart_rx_i,
      uart_tx_o => uart_tx_o,
      led0_o    => led0_o,

      boot_mode_i => boot_mode_i,
      qspi_sck_o  => qspi_sck_o,
      qspi_cs_n_o => qspi_cs_n_o,
      qspi_io0_o  => qspi_io0_o,
      qspi_io1_i  => qspi_io1_i,
      qspi_io2_o  => qspi_io2_o,
      qspi_io3_o  => qspi_io3_o,

      boot_done_o  => boot_done_o,
      boot_error_o => open,
      prog_we_o    => prog_we_o,
      prog_addr_o  => prog_addr_o,
      prog_wdata_o => prog_wdata_o,
      imem_pc_o    => imem_pc_o,
      dmem_we_o    => dmem_we_o,
      dmem_addr_o  => dmem_addr_o,
      dmem_wdata_o => dmem_wdata_o
    );

  flash_model : process(qspi_sck_o, qspi_cs_n_o)
  begin
    if qspi_cs_n_o = '1' then
      bit_count <= 0;
      rd_byte   <= 0;
      rd_bit    <= 7;
      qspi_io1_i <= '0';
    elsif falling_edge(qspi_sck_o) then
      if bit_count >= 31 then
        qspi_io1_i <= flash_mem(rd_byte)(rd_bit);

        if rd_bit = 0 then
          rd_bit  <= 7;
          rd_byte <= rd_byte + 1;
        else
          rd_bit <= rd_bit - 1;
        end if;
      end if;

      bit_count <= bit_count + 1;
    end if;
  end process;

  stim : process
  begin
    boot_mode_i <= '0';
    reset <= '1';
    wait for 200 ns;
    wait until rising_edge(clk);
    reset <= '0';

    wait;
  end process;

  monitor : process(clk)
    variable cycles : integer := 0;
  begin
    if rising_edge(clk) then
      if reset = '1' then
        cycles := 0;
        sim_done <= '0';
      elsif sim_done = '0' then
        cycles := cycles + 1;

        if boot_done_o = '1' and dmem_we_o = '1' then
          assert dmem_addr_o = x"00000000"
            report "Unexpected DMEM write address after SPI boot"
            severity failure;

          assert dmem_wdata_o = x"0000007B"
            report "Unexpected DMEM write data after SPI boot"
            severity failure;

          sim_done <= '1';
          report "SOC SPI flash boot test passed" severity note;
        end if;

        if cycles >= MAX_CYCLES then
          report "Timeout waiting for CPU DMEM write after SPI flash boot"
            severity failure;
        end if;
      end if;
    end if;
  end process;

end architecture;
