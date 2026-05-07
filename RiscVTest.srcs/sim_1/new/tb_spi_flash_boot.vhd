library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_spi_flash_boot is
end entity;

architecture sim of tb_spi_flash_boot is
  constant CLK_PERIOD : time := 10 ns;

  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';
  signal start : std_logic := '0';

  signal sck  : std_logic;
  signal cs_n : std_logic;
  signal mosi : std_logic;
  signal miso : std_logic := '0';

  signal imem_we    : std_logic;
  signal imem_addr  : std_logic_vector(31 downto 0);
  signal imem_wdata : std_logic_vector(31 downto 0);
  signal dmem_we    : std_logic;
  signal dmem_addr  : std_logic_vector(31 downto 0);
  signal dmem_wdata : std_logic_vector(31 downto 0);
  signal done       : std_logic;
  signal error      : std_logic;
  signal imem_write_count : integer := 0;
  signal imem_addr0       : std_logic_vector(31 downto 0) := (others => '0');
  signal imem_wdata0      : std_logic_vector(31 downto 0) := (others => '0');
  signal imem_addr1       : std_logic_vector(31 downto 0) := (others => '0');
  signal imem_wdata1      : std_logic_vector(31 downto 0) := (others => '0');

  type flash_mem_t is array(0 to 31) of std_logic_vector(7 downto 0);
  constant flash_mem : flash_mem_t := (
    0  => x"55",
    1  => x"AA",
    2  => x"08",
    3  => x"00",
    4  => x"00",
    5  => x"00",
    6  => x"00",
    7  => x"00",
    8  => x"00",
    9  => x"00",
    10 => x"13",
    11 => x"00",
    12 => x"00",
    13 => x"00",
    14 => x"93",
    15 => x"00",
    16 => x"10",
    17 => x"00",
    others => x"00"
  );

  signal bit_count : integer := 0;
  signal rd_byte   : integer := 0;
  signal rd_bit    : integer range 0 to 7 := 7;

begin
  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.spi_flash_boot
    generic map(
      CLK_DIV => 2
    )
    port map(
      clk               => clk,
      reset             => reset,
      start             => start,
      spi_sck_o         => sck,
      spi_cs_n_o        => cs_n,
      spi_mosi_o        => mosi,
      spi_miso_i        => miso,
      imem_prog_we_o    => imem_we,
      imem_prog_addr_o  => imem_addr,
      imem_prog_wdata_o => imem_wdata,
      dmem_prog_we_o    => dmem_we,
      dmem_prog_addr_o  => dmem_addr,
      dmem_prog_wdata_o => dmem_wdata,
      done_o            => done,
      error_o           => error
    );

  flash_model : process(sck, cs_n)
  begin
    if cs_n = '1' then
      bit_count <= 0;
      rd_byte   <= 0;
      rd_bit    <= 7;
      miso      <= '0';
    elsif falling_edge(sck) then
      if bit_count >= 31 then
        miso <= flash_mem(rd_byte)(rd_bit);

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

  monitor_writes : process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        imem_write_count <= 0;
        imem_addr0       <= (others => '0');
        imem_wdata0      <= (others => '0');
        imem_addr1       <= (others => '0');
        imem_wdata1      <= (others => '0');
      elsif imem_we = '1' then
        if imem_write_count = 0 then
          imem_addr0  <= imem_addr;
          imem_wdata0 <= imem_wdata;
        elsif imem_write_count = 1 then
          imem_addr1  <= imem_addr;
          imem_wdata1 <= imem_wdata;
        end if;

        imem_write_count <= imem_write_count + 1;
      end if;
    end if;
  end process;

  stim : process
  begin
    wait for 100 ns;
    reset <= '0';
    start <= '1';

    wait until done = '1' or error = '1';
    assert error = '0' report "SPI boot reported an error" severity failure;

    wait until rising_edge(clk);
    assert imem_write_count = 2 report "Unexpected IMEM write count" severity failure;
    assert imem_addr0 = x"00000000" report "Unexpected first IMEM write address" severity failure;
    assert imem_wdata0 = x"00000013" report "Unexpected first IMEM boot word" severity failure;
    assert imem_addr1 = x"00000004" report "Unexpected second IMEM write address" severity failure;
    assert imem_wdata1 = x"00100093" report "Unexpected second IMEM boot word" severity failure;
    assert dmem_we = '0' report "Unexpected DMEM write" severity failure;

    report "SPI flash boot test passed" severity note;
    wait;
  end process;

end architecture;
