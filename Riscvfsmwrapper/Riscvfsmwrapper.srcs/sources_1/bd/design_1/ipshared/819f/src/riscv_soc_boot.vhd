library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity riscv_soc_boot is
  generic(
    CLK_FREQ_HZ : integer := 50_000_000;
    BAUD        : integer := 115200;
    IMEM_WORDS  : integer := 4096;
    SPI_CLK_DIV : integer := 50
  );
  port(
    clk       : in  std_logic;
    reset     : in  std_logic;
    uart_rx_i : in  std_logic;
    uart_tx_o : out std_logic;
    led0_o    : out std_logic;

    -- 0 = boot from external SPI flash, 1 = boot from UART
    boot_mode_i : in std_logic := '1';

    qspi_sck_o  : out std_logic;
    qspi_cs_n_o : out std_logic;
    qspi_io0_o  : out std_logic;
    qspi_io1_i  : in  std_logic := '1';
    qspi_io2_o  : out std_logic;
    qspi_io3_o  : out std_logic;

    -- Debug ports for testbench
    boot_done_o  : out std_logic;
    boot_error_o : out std_logic;
    prog_we_o    : out std_logic;
    prog_addr_o  : out std_logic_vector(31 downto 0);
    prog_wdata_o : out std_logic_vector(31 downto 0);
    imem_pc_o    : out std_logic_vector(31 downto 0);
    dmem_we_o    : out std_logic;
    dmem_addr_o  : out std_logic_vector(31 downto 0);
    dmem_wdata_o : out std_logic_vector(31 downto 0);

    -- External programming / AXI mode
    ext_prog_mode_i   : in std_logic := '0';
    ext_cpu_enable_i  : in std_logic := '0';
    ext_imem_we_i     : in std_logic := '0';
    ext_imem_addr_i   : in std_logic_vector(31 downto 0) := (others => '0');
    ext_imem_wdata_i  : in std_logic_vector(31 downto 0) := (others => '0');
    ext_dmem_we_i     : in std_logic := '0';
    ext_dmem_addr_i   : in std_logic_vector(31 downto 0) := (others => '0');
    ext_dmem_wdata_i  : in std_logic_vector(31 downto 0) := (others => '0')
  );
end entity;

architecture rtl of riscv_soc_boot is

  --------------------------------------------------------------------
  -- UART RX
  --------------------------------------------------------------------
  signal rx_byte  : std_logic_vector(7 downto 0);
  signal rx_valid : std_logic;

  --------------------------------------------------------------------
  -- UART TX MMIO
  --------------------------------------------------------------------
  signal uart_tx_start    : std_logic := '0';
  signal uart_tx_data     : std_logic_vector(7 downto 0) := (others => '0');
  signal uart_tx_busy     : std_logic;
  signal uart_tx_line     : std_logic;
  signal uart_tx_addr_sel : std_logic;
  signal uart_tx_we       : std_logic;
  signal uart_tx_rdata    : std_logic_vector(31 downto 0);

  --------------------------------------------------------------------
  -- UART boot path
  --------------------------------------------------------------------
  signal uart_prog_we      : std_logic;
  signal uart_prog_addr    : std_logic_vector(31 downto 0);
  signal uart_prog_wdata   : std_logic_vector(31 downto 0);
  signal uart_dmem_we      : std_logic;
  signal uart_dmem_addr    : std_logic_vector(31 downto 0);
  signal uart_dmem_wdata   : std_logic_vector(31 downto 0);
  signal uart_boot_done    : std_logic;

  -- Muxed programming interface (UART boot OR external AXI mode)
  signal prog_we_mux         : std_logic;
  signal prog_addr_mux       : std_logic_vector(31 downto 0);
  signal prog_wdata_mux      : std_logic_vector(31 downto 0);
  signal dmem_prog_we_mux    : std_logic;
  signal dmem_prog_addr_mux  : std_logic_vector(31 downto 0);
  signal dmem_prog_wdata_mux : std_logic_vector(31 downto 0);

  signal flash_start  : std_logic;
  signal flash_done   : std_logic;
  signal flash_error  : std_logic;

  signal flash_prog_we      : std_logic;
  signal flash_prog_addr    : std_logic_vector(31 downto 0);
  signal flash_prog_wdata   : std_logic_vector(31 downto 0);
  signal flash_dmem_we      : std_logic;
  signal flash_dmem_addr    : std_logic_vector(31 downto 0);
  signal flash_dmem_wdata   : std_logic_vector(31 downto 0);

  signal watchdog_reset         : std_logic := '0';
  signal watchdog_reset_stretch : unsigned(2 downto 0) := (others => '0');
  signal watchdog_reset_long    : std_logic := '0';
  signal cpu_reset_int          : std_logic;

  --------------------------------------------------------------------
  -- CPU / IMEM
  --------------------------------------------------------------------
  signal imem_pc    : std_logic_vector(31 downto 0);
  signal imem_instr : std_logic_vector(31 downto 0);

  --------------------------------------------------------------------
  -- CPU / DMEM
  --------------------------------------------------------------------
  signal dmem_we               : std_logic;
  signal dmem_be               : std_logic_vector(3 downto 0);
  signal dmem_addr             : std_logic_vector(31 downto 0);
  signal dmem_wdata            : std_logic_vector(31 downto 0);
  signal dmem_rdata            : std_logic_vector(31 downto 0);

  signal dmem_rdata_ram        : std_logic_vector(31 downto 0);
  signal dmem_we_ram           : std_logic;

  --------------------------------------------------------------------
  -- Timer MMIO
  --------------------------------------------------------------------
  signal irq_timer      : std_logic;
  signal timer_we       : std_logic;
  signal timer_addr     : std_logic_vector(31 downto 0);
  signal timer_rdata    : std_logic_vector(31 downto 0);
  signal timer_addr_sel : std_logic;

  --------------------------------------------------------------------
  -- Debug / keep-alive signals
  --------------------------------------------------------------------
  signal dbg_mix : std_logic_vector(31 downto 0);
  signal hb_cnt  : unsigned(25 downto 0) := (others => '0');
  signal led_reg : std_logic := '0';

  signal boot_done_eff : std_logic;

begin

  --------------------------------------------------------------------
  -- UART receiver
  --------------------------------------------------------------------
  u_rx : entity work.uart_rx
    generic map(
      CLK_FREQ_HZ => CLK_FREQ_HZ,
      BAUD        => BAUD
    )
    port map(
      clk      => clk,
      reset    => reset,
      rx       => uart_rx_i,
      rx_data  => rx_byte,
      rx_valid => rx_valid
    );

  --------------------------------------------------------------------
  -- UART boot path
  --------------------------------------------------------------------
  u_uart_boot : entity work.uart_boot_loader
    port map(
      clk               => clk,
      reset             => reset,
      rx_byte_i         => rx_byte,
      rx_valid_i        => rx_valid,
      imem_prog_we_o    => uart_prog_we,
      imem_prog_addr_o  => uart_prog_addr,
      imem_prog_wdata_o => uart_prog_wdata,
      dmem_prog_we_o    => uart_dmem_we,
      dmem_prog_addr_o  => uart_dmem_addr,
      dmem_prog_wdata_o => uart_dmem_wdata,
      done_o            => uart_boot_done
    );

  --------------------------------------------------------------------
  -- UART transmitter
  --------------------------------------------------------------------
  u_tx : entity work.uart_tx
    generic map(
      CLK_FREQ_HZ => CLK_FREQ_HZ,
      BAUD        => BAUD
    )
    port map(
      clk   => clk,
      reset => reset,
      start => uart_tx_start,
      data  => uart_tx_data,
      tx    => uart_tx_line,
      busy  => uart_tx_busy
    );

  --------------------------------------------------------------------
  -- External programming mux
  --------------------------------------------------------------------
  prog_we_mux         <= ext_imem_we_i    when ext_prog_mode_i = '1' else
                         flash_prog_we    when boot_mode_i = '0' else
                         uart_prog_we;
  prog_addr_mux       <= ext_imem_addr_i  when ext_prog_mode_i = '1' else
                         flash_prog_addr  when boot_mode_i = '0' else
                         uart_prog_addr;
  prog_wdata_mux      <= ext_imem_wdata_i when ext_prog_mode_i = '1' else
                         flash_prog_wdata when boot_mode_i = '0' else
                         uart_prog_wdata;

  dmem_prog_we_mux    <= ext_dmem_we_i    when ext_prog_mode_i = '1' else
                         flash_dmem_we    when boot_mode_i = '0' else
                         uart_dmem_we;
  dmem_prog_addr_mux  <= ext_dmem_addr_i  when ext_prog_mode_i = '1' else
                         flash_dmem_addr  when boot_mode_i = '0' else
                         uart_dmem_addr;
  dmem_prog_wdata_mux <= ext_dmem_wdata_i when ext_prog_mode_i = '1' else
                         flash_dmem_wdata when boot_mode_i = '0' else
                         uart_dmem_wdata;

  flash_start         <= '1' when (ext_prog_mode_i = '0' and boot_mode_i = '0') else '0';
  boot_done_eff       <= '1'        when ext_prog_mode_i = '1' else
                         flash_done when boot_mode_i = '0' else
                         uart_boot_done;

  -- Keep the flash side-band pins inactive in UART or AXI boot mode.
  qspi_io2_o <= '1';
  qspi_io3_o <= '1';

  --------------------------------------------------------------------
  -- SPI flash boot path
  --------------------------------------------------------------------
  u_flash_boot : entity work.spi_flash_boot
    generic map(
      CLK_DIV => SPI_CLK_DIV
    )
    port map(
      clk               => clk,
      reset             => reset,
      start             => flash_start,
      spi_sck_o         => qspi_sck_o,
      spi_cs_n_o        => qspi_cs_n_o,
      spi_mosi_o        => qspi_io0_o,
      spi_miso_i        => qspi_io1_i,
      imem_prog_we_o    => flash_prog_we,
      imem_prog_addr_o  => flash_prog_addr,
      imem_prog_wdata_o => flash_prog_wdata,
      dmem_prog_we_o    => flash_dmem_we,
      dmem_prog_addr_o  => flash_dmem_addr,
      dmem_prog_wdata_o => flash_dmem_wdata,
      done_o            => flash_done,
      error_o           => flash_error
    );

  --------------------------------------------------------------------
  -- Instruction memory
  --------------------------------------------------------------------
  u_imem : entity work.imem_dp_ram
    generic map(
      WORDS => IMEM_WORDS
    )
    port map(
      clk        => clk,
      pc         => imem_pc,
      instr_out  => imem_instr,
      prog_we    => prog_we_mux,
      prog_addr  => prog_addr_mux,
      prog_wdata => prog_wdata_mux
    );

  --------------------------------------------------------------------
  -- Data memory
  --------------------------------------------------------------------
  u_dmem : entity work.dmem
    port map(
      clk        => clk,
      we         => dmem_we_ram,
      be         => dmem_be,
      addr       => dmem_addr,
      data_in    => dmem_wdata,
      data_out   => dmem_rdata_ram,
      prog_we    => dmem_prog_we_mux,
      prog_addr  => dmem_prog_addr_mux,
      prog_wdata => dmem_prog_wdata_mux
    );

  --------------------------------------------------------------------
  -- Timer MMIO block
  --------------------------------------------------------------------
  u_timer : entity work.simple_timer
    port map(
      clk   => clk,
      rst   => reset,
      we    => timer_we,
      addr  => timer_addr(3 downto 0),
      wdata => dmem_wdata,
      rdata => timer_rdata,
      irq_o => irq_timer
    );

  --------------------------------------------------------------------
  -- MMIO address decode
  --------------------------------------------------------------------
  timer_addr_sel   <= '1' when dmem_addr(31 downto 12) = x"40001" else '0';
  uart_tx_addr_sel <= '1' when dmem_addr = x"40002000" else '0';

  timer_we   <= dmem_we and timer_addr_sel;
  uart_tx_we <= dmem_we and uart_tx_addr_sel;

  dmem_we_ram <= dmem_we and (not timer_addr_sel) and (not uart_tx_addr_sel);
  timer_addr  <= dmem_addr;

  uart_tx_rdata <= (31 downto 2 => '0') & (not uart_tx_busy) & uart_tx_busy;

  --------------------------------------------------------------------
  -- UART TX write pulse
  --------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        uart_tx_start <= '0';
        uart_tx_data  <= (others => '0');
      else
        uart_tx_start <= '0';

        if uart_tx_we = '1' and uart_tx_busy = '0' then
          uart_tx_data  <= dmem_wdata(7 downto 0);
          uart_tx_start <= '1';
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Watchdog reset stretcher
  --------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        watchdog_reset_stretch <= (others => '0');
      elsif watchdog_reset = '1' then
        watchdog_reset_stretch <= "111";
      elsif watchdog_reset_stretch /= 0 then
        watchdog_reset_stretch <= watchdog_reset_stretch - 1;
      end if;
    end if;
  end process;

  watchdog_reset_long <= '1' when watchdog_reset_stretch /= 0 else '0';

  --------------------------------------------------------------------
  -- CPU reset
  --------------------------------------------------------------------
  cpu_reset_int <= reset or watchdog_reset_long or
                 (not boot_done_eff) or
                 ((not ext_cpu_enable_i) and ext_prog_mode_i);

  --------------------------------------------------------------------
  -- DMEM read mux
  --------------------------------------------------------------------
  dmem_rdata <= timer_rdata   when timer_addr_sel = '1' else
                uart_tx_rdata when uart_tx_addr_sel = '1' else
                dmem_rdata_ram;

  --------------------------------------------------------------------
  -- CPU core
  --------------------------------------------------------------------
  u_cpu : entity work.riscv_core_memless
    port map(
      clk                     => clk,
      reset                   => cpu_reset_int,
      imem_pc                 => imem_pc,
      imem_instr              => imem_instr,
      dmem_we                 => dmem_we,
      dmem_be                 => dmem_be,
      dmem_addr               => dmem_addr,
      dmem_wdata              => dmem_wdata,
      dmem_rdata              => dmem_rdata,
      irq_timer_i             => irq_timer,
      watchdog_reset_o        => watchdog_reset
    );

  --------------------------------------------------------------------
  -- Debug mixing to keep internal signals alive
  --------------------------------------------------------------------
  dbg_mix <= imem_pc xor imem_instr xor dmem_addr xor dmem_wdata;

  --------------------------------------------------------------------
  -- LED behavior
  --------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        hb_cnt  <= (others => '0');
        led_reg <= '0';
      else
        hb_cnt <= hb_cnt + 1;

        if boot_done_eff = '0' then
          led_reg <= hb_cnt(hb_cnt'high);
        else
          led_reg <= dbg_mix(0) xor dbg_mix(5) xor dbg_mix(13) xor dbg_mix(21) xor dmem_we;
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Outputs
  --------------------------------------------------------------------
  uart_tx_o <= uart_tx_line;
  led0_o    <= led_reg;

  boot_done_o  <= boot_done_eff;
  boot_error_o <= flash_error when (ext_prog_mode_i = '0' and boot_mode_i = '0') else '0';
  prog_we_o    <= prog_we_mux;
  prog_addr_o  <= prog_addr_mux;
  prog_wdata_o <= prog_wdata_mux;
  imem_pc_o    <= imem_pc;

  -- expose only real RAM writes, not timer/UART MMIO writes
  dmem_we_o    <= dmem_we_ram;
  dmem_addr_o  <= dmem_addr;
  dmem_wdata_o <= dmem_wdata;

end rtl;
