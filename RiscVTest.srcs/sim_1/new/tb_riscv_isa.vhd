library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_riscv_isa is
  generic (
    PROGRAM_FILE_G : string := "D:/Documents/FAU/NanoSat/isa_hex/add.hex";
    TOHOST_ADDR_G  : std_logic_vector(31 downto 0) := x"00001000"
  );
end entity;

architecture sim of tb_riscv_isa is

  --------------------------------------------------------------------
  -- Configuration
  --------------------------------------------------------------------
  constant CLK_PERIOD : time    := 20 ns;
  constant IMEM_BYTES : integer := 65536;
  constant DMEM_BYTES : integer := 65536;
  constant MAX_CYCLES : integer := 200000;

  constant PROGRAM_FILE      : string := PROGRAM_FILE_G;
  constant TOHOST_ADDR       : std_logic_vector(31 downto 0) := TOHOST_ADDR_G;
  constant TOHOST_PLUS4_ADDR : std_logic_vector(31 downto 0) := std_logic_vector(unsigned(TOHOST_ADDR_G) + 4);

  --------------------------------------------------------------------
  -- Types
  --------------------------------------------------------------------
  type byte_mem_t is array (0 to IMEM_BYTES-1) of std_logic_vector(7 downto 0);
  type dmem_t     is array (0 to DMEM_BYTES-1) of std_logic_vector(7 downto 0);

  --------------------------------------------------------------------
  -- DUT signals
  --------------------------------------------------------------------
  signal clk         : std_logic := '0';
  signal reset       : std_logic := '1';
  signal irq_timer_i : std_logic := '0';

  -- Instruction Wishbone
  signal iwb_adr_o : std_logic_vector(31 downto 0);
  signal iwb_dat_i : std_logic_vector(31 downto 0) := (others => '0');
  signal iwb_sel_o : std_logic_vector(3 downto 0);
  signal iwb_cyc_o : std_logic;
  signal iwb_stb_o : std_logic;
  signal iwb_we_o  : std_logic;
  signal iwb_ack_i : std_logic := '0';
  signal iwb_err_i : std_logic := '0';

  -- Data Wishbone
  signal dwb_adr_o : std_logic_vector(31 downto 0);
  signal dwb_dat_o : std_logic_vector(31 downto 0);
  signal dwb_dat_i : std_logic_vector(31 downto 0) := (others => '0');
  signal dwb_sel_o : std_logic_vector(3 downto 0);
  signal dwb_cyc_o : std_logic;
  signal dwb_stb_o : std_logic;
  signal dwb_we_o  : std_logic;
  signal dwb_ack_i : std_logic := '0';
  signal dwb_err_i : std_logic := '0';

  signal state_dbg_o : std_logic_vector(3 downto 0);

  --------------------------------------------------------------------
  -- Memories
  --------------------------------------------------------------------
  shared variable imem : byte_mem_t := (others => (others => '0'));
  shared variable dmem : dmem_t     := (others => (others => '0'));

  --------------------------------------------------------------------
  -- Simulation control
  --------------------------------------------------------------------
  signal sim_done : std_logic := '0';
  signal sim_pass : std_logic := '0';

  --------------------------------------------------------------------
  -- Helper functions
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

  function nibble_to_hex_char(n : std_logic_vector(3 downto 0)) return character is
  begin
    case n is
      when "0000" => return '0';
      when "0001" => return '1';
      when "0010" => return '2';
      when "0011" => return '3';
      when "0100" => return '4';
      when "0101" => return '5';
      when "0110" => return '6';
      when "0111" => return '7';
      when "1000" => return '8';
      when "1001" => return '9';
      when "1010" => return 'A';
      when "1011" => return 'B';
      when "1100" => return 'C';
      when "1101" => return 'D';
      when "1110" => return 'E';
      when others => return 'F';
    end case;
  end function;

  function slv32_to_hex(x : std_logic_vector(31 downto 0)) return string is
    variable s : string(1 to 8);
  begin
    s(1) := nibble_to_hex_char(x(31 downto 28));
    s(2) := nibble_to_hex_char(x(27 downto 24));
    s(3) := nibble_to_hex_char(x(23 downto 20));
    s(4) := nibble_to_hex_char(x(19 downto 16));
    s(5) := nibble_to_hex_char(x(15 downto 12));
    s(6) := nibble_to_hex_char(x(11 downto 8));
    s(7) := nibble_to_hex_char(x(7 downto 4));
    s(8) := nibble_to_hex_char(x(3 downto 0));
    return s;
  end function;

  procedure load_byte_hex_file(
    constant filename : in string;
    variable mem      : inout byte_mem_t
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
    report "Loaded " & integer'image(idx) & " bytes from " & filename severity note;
  end procedure;

  function read_word_le_from_imem(
    mem  : byte_mem_t;
    addr : integer
  ) return std_logic_vector is
    variable w : std_logic_vector(31 downto 0);
  begin
    w(7 downto 0)   := mem(addr + 0);
    w(15 downto 8)  := mem(addr + 1);
    w(23 downto 16) := mem(addr + 2);
    w(31 downto 24) := mem(addr + 3);
    return w;
  end function;

  function read_word_le_from_dmem(
    mem  : dmem_t;
    addr : integer
  ) return std_logic_vector is
    variable w : std_logic_vector(31 downto 0);
  begin
    w(7 downto 0)   := mem(addr + 0);
    w(15 downto 8)  := mem(addr + 1);
    w(23 downto 16) := mem(addr + 2);
    w(31 downto 24) := mem(addr + 3);
    return w;
  end function;

begin

  --------------------------------------------------------------------
  -- Clock
  --------------------------------------------------------------------
  clk <= not clk after CLK_PERIOD/2;

  --------------------------------------------------------------------
  -- DUT
  --------------------------------------------------------------------
  uut : entity work.riscv_core_wishbone
    port map (
      clk         => clk,
      reset       => reset,
      irq_timer_i => irq_timer_i,

      iwb_adr_o   => iwb_adr_o,
      iwb_dat_i   => iwb_dat_i,
      iwb_sel_o   => iwb_sel_o,
      iwb_cyc_o   => iwb_cyc_o,
      iwb_stb_o   => iwb_stb_o,
      iwb_we_o    => iwb_we_o,
      iwb_ack_i   => iwb_ack_i,
      iwb_err_i   => iwb_err_i,

      dwb_adr_o   => dwb_adr_o,
      dwb_dat_o   => dwb_dat_o,
      dwb_dat_i   => dwb_dat_i,
      dwb_sel_o   => dwb_sel_o,
      dwb_cyc_o   => dwb_cyc_o,
      dwb_stb_o   => dwb_stb_o,
      dwb_we_o    => dwb_we_o,
      dwb_ack_i   => dwb_ack_i,
      dwb_err_i   => dwb_err_i,

      state_dbg_o => state_dbg_o
    );

  --------------------------------------------------------------------
  -- Stimulus / program loading
  --------------------------------------------------------------------
  stim_proc : process
  begin
    load_byte_hex_file(PROGRAM_FILE, imem);

    reset <= '1';
    wait for 200 ns;
    wait until rising_edge(clk);
    reset <= '0';

    wait;
  end process;

  --------------------------------------------------------------------
  -- Instruction Wishbone slave
  --------------------------------------------------------------------
  iwb_slave_proc : process(clk)
    variable addr_i : integer;
    variable instr  : std_logic_vector(31 downto 0);
    variable req_d  : std_logic := '0';
    variable addr_d : std_logic_vector(31 downto 0) := (others => '0');
  begin
    if rising_edge(clk) then
      iwb_ack_i <= '0';
      iwb_err_i <= '0';

      if req_d = '1' then
        addr_i := to_integer(unsigned(addr_d));

        if (addr_i >= 0) and (addr_i + 3 < IMEM_BYTES) then
          instr := read_word_le_from_imem(imem, addr_i);
          iwb_dat_i <= instr;
          iwb_ack_i <= '1';

          report "IFETCH ACK  addr=0x" &
                 slv32_to_hex(addr_d) &
                 " instr=0x" & slv32_to_hex(instr)
                 severity note;
        else
          iwb_dat_i <= (others => '0');
          iwb_err_i <= '1';
          report "IFETCH ERR out-of-range addr=0x" & slv32_to_hex(addr_d) severity error;
        end if;
      end if;

      req_d  := iwb_cyc_o and iwb_stb_o and (not iwb_we_o);
      addr_d := iwb_adr_o;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Data Wishbone slave
  --------------------------------------------------------------------
  dwb_slave_proc : process(clk)
    variable req_d     : std_logic := '0';
    variable we_d      : std_logic := '0';
    variable addr_d    : std_logic_vector(31 downto 0) := (others => '0');
    variable wdata_d   : std_logic_vector(31 downto 0) := (others => '0');
    variable sel_d     : std_logic_vector(3 downto 0)  := (others => '0');

    variable addr_i    : integer;
    variable rdata     : std_logic_vector(31 downto 0);
    variable write_hit : boolean;
  begin
    if rising_edge(clk) then
      dwb_ack_i <= '0';
      dwb_err_i <= '0';

      -- raw debug
      if dwb_cyc_o = '1' or dwb_stb_o = '1' then
        report "DWB RAW cyc=" & std_logic'image(dwb_cyc_o) &
               " stb=" & std_logic'image(dwb_stb_o) &
               " we="  & std_logic'image(dwb_we_o) &
               " addr=0x" & slv32_to_hex(dwb_adr_o) &
               " wdata=0x" & slv32_to_hex(dwb_dat_o)
               severity note;
      end if;

      if req_d = '1' then
        addr_i := to_integer(unsigned(addr_d));
        write_hit := false;

        report "DWB LATCHED we=" & std_logic'image(we_d) &
               " addr=0x" & slv32_to_hex(addr_d) &
               " wdata=0x" & slv32_to_hex(wdata_d)
               severity note;

        ----------------------------------------------------------------
        -- Official riscv-tests result channel
        -- tohost      : actual result
        -- tohost + 4  : clear/handshake write, ignore
        ----------------------------------------------------------------
        if we_d = '1' and addr_d = TOHOST_ADDR then
          dwb_ack_i <= '1';
          write_hit := true;

          report "TOHOST RESULT write detected. data=0x" & slv32_to_hex(wdata_d) severity note;

          if wdata_d = x"00000001" then
            sim_done <= '1';
            sim_pass <= '1';
            report "RISC-V TEST PASS" severity note;
          elsif wdata_d /= x"00000000" then
            sim_done <= '1';
            sim_pass <= '0';
            report "RISC-V TEST FAIL, tohost=0x" & slv32_to_hex(wdata_d) severity error;
          else
            report "Unexpected zero write to TOHOST result address" severity warning;
          end if;

        elsif we_d = '1' and addr_d = TOHOST_PLUS4_ADDR then
          dwb_ack_i <= '1';
          write_hit := true;

          report "TOHOST+4 write detected. data=0x" & slv32_to_hex(wdata_d) &
                 " (ignored handshake/clear write)" severity note;
        end if;

        if not write_hit then
          if (addr_i >= 0) and (addr_i + 3 < DMEM_BYTES) then
            if we_d = '1' then
              if sel_d(0) = '1' then
                dmem(addr_i + 0) := wdata_d(7 downto 0);
              end if;
              if sel_d(1) = '1' then
                dmem(addr_i + 1) := wdata_d(15 downto 8);
              end if;
              if sel_d(2) = '1' then
                dmem(addr_i + 2) := wdata_d(23 downto 16);
              end if;
              if sel_d(3) = '1' then
                dmem(addr_i + 3) := wdata_d(31 downto 24);
              end if;

              dwb_ack_i <= '1';

              report "DWRITE ACK addr=0x" & slv32_to_hex(addr_d) &
                     " data=0x" & slv32_to_hex(wdata_d)
                     severity note;
            else
              rdata := read_word_le_from_dmem(dmem, addr_i);
              dwb_dat_i <= rdata;
              dwb_ack_i <= '1';

              report "DREAD  ACK addr=0x" & slv32_to_hex(addr_d) &
                     " data=0x" & slv32_to_hex(rdata)
                     severity note;
            end if;
          else
            -- allow accesses outside DMEM so result regions do not deadlock
            if we_d = '1' then
              dwb_ack_i <= '1';
              report "DWRITE outside DMEM addr=0x" & slv32_to_hex(addr_d) &
                     " data=0x" & slv32_to_hex(wdata_d)
                     severity note;
            else
              dwb_dat_i <= (others => '0');
              dwb_ack_i <= '1';
              report "DREAD outside DMEM addr=0x" & slv32_to_hex(addr_d)
                     severity note;
            end if;
          end if;
        end if;
      end if;

      req_d   := dwb_cyc_o and dwb_stb_o;
      we_d    := dwb_we_o;
      addr_d  := dwb_adr_o;
      wdata_d := dwb_dat_o;
      sel_d   := dwb_sel_o;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Watchdog / simulation end
  --------------------------------------------------------------------
  watchdog_proc : process
    variable cycles : integer := 0;
  begin
    wait until reset = '0';

    while sim_done = '0' loop
      wait until rising_edge(clk);
      cycles := cycles + 1;

      if cycles >= MAX_CYCLES then
        report "WATCHDOG TIMEOUT after " & integer'image(cycles) & " cycles" severity failure;
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