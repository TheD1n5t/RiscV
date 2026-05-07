library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_riscv_soc_boot is
end entity;

architecture sim of tb_riscv_soc_boot is

  --------------------------------------------------------------------
  -- Configuration
  --------------------------------------------------------------------
  constant CLK_FREQ_HZ : integer := 50_000_000;
  constant BAUD : integer := 1000000;
  constant IMEM_WORDS  : integer := 4096;

  constant CLK_PERIOD  : time := 20 ns;
  constant BIT_TIME    : time := 1 sec / BAUD;

  constant MAX_CYCLES  : integer := 50_000_000;

  -- Change this path as needed
  constant PROGRAM_FILE : string :=
    "D:/Documents/FAU/NanoSat/isa_hex/xori.hex";

  -- For official riscv-tests:
  constant TOHOST_ADDR_A       : std_logic_vector(31 downto 0) := x"80001000";
  constant TOHOST_PLUS4_ADDR_A : std_logic_vector(31 downto 0) := x"80001004";
  constant TOHOST_ADDR_B       : std_logic_vector(31 downto 0) := x"00001000";
  constant TOHOST_PLUS4_ADDR_B : std_logic_vector(31 downto 0) := x"00001004";

  -- Split point for official riscv-tests unified image:
  -- 0x0000..0x1FFF -> IMEM, 0x2000.. -> DMEM
  constant DMEM_BASE_OFFSET : integer := 16#2000#;

  constant MAX_BYTES : integer := 65536;

  --------------------------------------------------------------------
  -- Types
  --------------------------------------------------------------------
  type byte_mem_t is array (0 to MAX_BYTES-1) of std_logic_vector(7 downto 0);

  --------------------------------------------------------------------
  -- DUT signals
  --------------------------------------------------------------------
  signal clk       : std_logic := '0';
  signal reset     : std_logic := '1';
  signal uart_rx_i : std_logic := '1';
  signal uart_tx_o : std_logic;
  signal led0_o    : std_logic;
  signal boot_mode_i : std_logic := '1';
  signal qspi_sck_o  : std_logic;
  signal qspi_cs_n_o : std_logic;
  signal qspi_io0_o  : std_logic;
  signal qspi_io1_i  : std_logic := '1';
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

  --------------------------------------------------------------------
  -- Simulation control
  --------------------------------------------------------------------
  shared variable program_bytes : byte_mem_t := (others => (others => '0'));

  signal program_size_bytes : integer := 0;
  signal sim_done           : std_logic := '0';
  signal sim_pass           : std_logic := '0';

  --------------------------------------------------------------------
  -- Helpers
  --------------------------------------------------------------------
  function hex_char_to_int(c : character) return integer is
  begin
    case c is
      when '0' => return 0;
      when '1' => return 1;
      when '2' => return 2;
      when '3' => return 3;
      when '4' => return 4;
      when '5' => return 5;
      when '6' => return 6;
      when '7' => return 7;
      when '8' => return 8;
      when '9' => return 9;
      when 'a' | 'A' => return 10;
      when 'b' | 'B' => return 11;
      when 'c' | 'C' => return 12;
      when 'd' | 'D' => return 13;
      when 'e' | 'E' => return 14;
      when 'f' | 'F' => return 15;
      when others => return 0;
    end case;
  end function;

  function hex_byte_from_string(s : string) return std_logic_vector is
    variable v : integer := 0;
  begin
    if s'length >= 2 then
      v := hex_char_to_int(s(s'low)) * 16 + hex_char_to_int(s(s'low + 1));
    elsif s'length = 1 then
      v := hex_char_to_int(s(s'low));
    else
      v := 0;
    end if;
    return std_logic_vector(to_unsigned(v, 8));
  end function;

  procedure load_byte_hex_file(
    constant filename : in string;
    variable mem      : inout byte_mem_t;
    variable size_out : out integer
  ) is
    file f       : text;
    variable l   : line;
    variable idx : integer := 0;
    variable s   : string(1 to 256);
    variable len : integer;
    variable tmp : std_logic_vector(7 downto 0);
  begin
    file_open(f, filename, read_mode);

    while not endfile(f) loop
      readline(f, l);
      len := l'length;

      if len >= 2 then
        s := (others => ' ');
        for i in 1 to len loop
          s(i) := l.all(i);
        end loop;

        if idx <= mem'high then
          tmp := hex_byte_from_string(s(1 to 2));
          mem(idx) := tmp;
          idx := idx + 1;
        end if;
      end if;
    end loop;

    file_close(f);
    size_out := idx;
  end procedure;

  procedure uart_send_byte(
  signal uart_line : out std_logic;
  constant b       : in  std_logic_vector(7 downto 0)
) is
begin
  uart_line <= '0';
  wait for BIT_TIME;

  for i in 0 to 7 loop
    uart_line <= b(i);
    wait for BIT_TIME;
  end loop;

  uart_line <= '1';
  wait for BIT_TIME;
end procedure;

begin

  --------------------------------------------------------------------
  -- Clock
  --------------------------------------------------------------------
  clk <= not clk after CLK_PERIOD/2;

  --------------------------------------------------------------------
  -- DUT
  --------------------------------------------------------------------
  uut : entity work.riscv_soc_boot
    generic map(
      CLK_FREQ_HZ => CLK_FREQ_HZ,
      BAUD        => BAUD,
      IMEM_WORDS  => IMEM_WORDS
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

  --------------------------------------------------------------------
  -- Stimulus: reset + boot packet over UART
  --------------------------------------------------------------------
  stim_proc : process
    variable size_v     : integer := 0;
    variable imem_bytes : integer := 0;
    variable dmem_bytes : integer := 0;
    variable imem_len_u : unsigned(31 downto 0);
    variable dmem_len_u : unsigned(31 downto 0);
  begin
    uart_rx_i <= '1';

    load_byte_hex_file(PROGRAM_FILE, program_bytes, size_v);
    program_size_bytes <= size_v;

    if size_v > DMEM_BASE_OFFSET then
      imem_bytes := DMEM_BASE_OFFSET;
      dmem_bytes := size_v - DMEM_BASE_OFFSET;
    else
      imem_bytes := size_v;
      dmem_bytes := 0;
    end if;

    reset <= '1';
    wait for 500 ns;
    wait until rising_edge(clk);
    reset <= '0';

    wait for 20 * BIT_TIME;

    imem_len_u := to_unsigned(imem_bytes, 32);
    dmem_len_u := to_unsigned(dmem_bytes, 32);

    -- Boot header
    uart_send_byte(uart_rx_i, x"55");
    uart_send_byte(uart_rx_i, x"AA");

    -- IMEM length, little endian
    uart_send_byte(uart_rx_i, std_logic_vector(imem_len_u(7 downto 0)));
    uart_send_byte(uart_rx_i, std_logic_vector(imem_len_u(15 downto 8)));
    uart_send_byte(uart_rx_i, std_logic_vector(imem_len_u(23 downto 16)));
    uart_send_byte(uart_rx_i, std_logic_vector(imem_len_u(31 downto 24)));

    -- DMEM length, little endian
    uart_send_byte(uart_rx_i, std_logic_vector(dmem_len_u(7 downto 0)));
    uart_send_byte(uart_rx_i, std_logic_vector(dmem_len_u(15 downto 8)));
    uart_send_byte(uart_rx_i, std_logic_vector(dmem_len_u(23 downto 16)));
    uart_send_byte(uart_rx_i, std_logic_vector(dmem_len_u(31 downto 24)));

    -- IMEM payload
    for i in 0 to imem_bytes - 1 loop
      uart_send_byte(uart_rx_i, program_bytes(i));
    end loop;

    -- DMEM payload
    for i in 0 to dmem_bytes - 1 loop
      uart_send_byte(uart_rx_i, program_bytes(DMEM_BASE_OFFSET + i));
    end loop;

    uart_rx_i <= '1';
    wait;
  end process;

  --------------------------------------------------------------------
  -- tohost monitor
  --------------------------------------------------------------------
  result_mon_proc : process(clk)
  begin
    if rising_edge(clk) then
      if dmem_we_o = '1' then
        if (dmem_addr_o = TOHOST_ADDR_A) or (dmem_addr_o = TOHOST_ADDR_B) then
          if dmem_wdata_o = x"00000001" then
            sim_done <= '1';
            sim_pass <= '1';
          elsif dmem_wdata_o /= x"00000000" then
            sim_done <= '1';
            sim_pass <= '0';
          end if;
        elsif (dmem_addr_o = TOHOST_PLUS4_ADDR_A) or (dmem_addr_o = TOHOST_PLUS4_ADDR_B) then
          null;
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Watchdog
  --------------------------------------------------------------------
  watchdog_proc : process
    variable cycles : integer := 0;
  begin
    wait until reset = '0';

    while sim_done = '0' loop
      wait until rising_edge(clk);
      cycles := cycles + 1;

      if cycles >= MAX_CYCLES then
        report "WATCHDOG TIMEOUT after " & integer'image(cycles) & " cycles"
               severity failure;
      end if;
    end loop;

    if sim_pass = '1' then
      report "SIMULATION PASSED" severity note;
      wait for 100 ns;
      report "END OF TEST" severity failure;
    else
      report "SIMULATION FAILED" severity failure;
    end if;
  end process;

end architecture;
