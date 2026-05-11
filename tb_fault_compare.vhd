library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_fault_compare is
  generic(
    G_PROGRAM_FILE             : string  := "fault_campaign.boot.hex";
    G_EXPECTED_SIGNATURE_HEX   : string  := "D146879D";
    G_CLK_FREQ_HZ              : integer := 50_000_000;
    G_BAUD                     : integer := 1_000_000;
    G_IMEM_WORDS               : integer := 4096;
    G_TIMEOUT_CYCLES           : integer := 2_000_000;
    G_PC_TMR                   : boolean := false;
    G_STATE_TMR                : boolean := false;
    G_RF_TMR                   : boolean := false;
    G_RF_SELF_HEAL             : boolean := false;
    G_IMEM_ECC                 : boolean := false;
    G_DMEM_ECC                 : boolean := false;
    G_FAULT_KIND               : integer := 0;
    G_INJECT_AFTER_BOOT_CYCLES : integer := 64
  );
end entity;

architecture sim of tb_fault_compare is
  constant CLK_PERIOD        : time := 20 ns;
  constant BIT_TIME          : time := 1 sec / G_BAUD;
  constant MAX_BYTES         : integer := 65536;
  constant RESULT_ADDR       : std_logic_vector(31 downto 0) := x"00000FF8";
  constant STATUS_ADDR       : std_logic_vector(31 downto 0) := x"00000FFC";

  type byte_mem_t is array (0 to MAX_BYTES - 1) of std_logic_vector(7 downto 0);

  signal clk       : std_logic := '0';
  signal reset     : std_logic := '1';
  signal uart_rx_i : std_logic := '1';
  signal uart_tx_o : std_logic;
  signal led0_o    : std_logic;

  signal boot_done_o  : std_logic;
  signal prog_we_o    : std_logic;
  signal prog_addr_o  : std_logic_vector(31 downto 0);
  signal prog_wdata_o : std_logic_vector(31 downto 0);
  signal imem_pc_o    : std_logic_vector(31 downto 0);
  signal dmem_we_o    : std_logic;
  signal dmem_addr_o  : std_logic_vector(31 downto 0);
  signal dmem_wdata_o : std_logic_vector(31 downto 0);
  signal pc_tmr_error_o       : std_logic;
  signal state_tmr_error_o    : std_logic;
  signal regfile_tmr_error_o  : std_logic;
  signal dmem_ecc_single_error_o : std_logic;
  signal dmem_ecc_double_error_o : std_logic;

  signal fi_pc_mask_i      : std_logic_vector(31 downto 0) := (others => '0');
  signal fi_pc_target_i    : std_logic_vector(1 downto 0)  := "00";
  signal fi_pc_strobe_i    : std_logic := '0';
  signal fi_state_mask_i   : std_logic_vector(3 downto 0)  := (others => '0');
  signal fi_state_target_i : std_logic_vector(1 downto 0)  := "00";
  signal fi_state_strobe_i : std_logic := '0';
  signal fi_dmem_mask_i    : std_logic_vector(38 downto 0) := (others => '0');
  signal fi_dmem_addr_i    : std_logic_vector(9 downto 0)  := (others => '0');
  signal fi_dmem_strobe_i  : std_logic := '0';
  signal fi_rf_mask_i      : std_logic_vector(31 downto 0) := (others => '0');
  signal fi_rf_addr_i      : std_logic_vector(4 downto 0)  := (others => '0');
  signal fi_rf_target_i    : std_logic_vector(1 downto 0)  := "00";
  signal fi_rf_strobe_i    : std_logic := '0';
  signal fi_imem_mask_i    : std_logic_vector(38 downto 0) := (others => '0');
  signal fi_imem_addr_i    : std_logic_vector(11 downto 0) := (others => '0');
  signal fi_imem_strobe_i  : std_logic := '0';

  signal result_seen      : std_logic := '0';
  signal result_signature : std_logic_vector(31 downto 0) := (others => '0');
  signal status_seen      : std_logic := '0';
  signal status_value     : std_logic_vector(31 downto 0) := (others => '0');
  signal pc_error_seen       : std_logic := '0';
  signal state_error_seen    : std_logic := '0';
  signal regfile_error_seen  : std_logic := '0';
  signal dmem_single_seen    : std_logic := '0';
  signal dmem_double_seen    : std_logic := '0';

  function hex_char_to_slv4(c : character) return std_logic_vector is
  begin
    case c is
      when '0' => return "0000";
      when '1' => return "0001";
      when '2' => return "0010";
      when '3' => return "0011";
      when '4' => return "0100";
      when '5' => return "0101";
      when '6' => return "0110";
      when '7' => return "0111";
      when '8' => return "1000";
      when '9' => return "1001";
      when 'a' | 'A' => return "1010";
      when 'b' | 'B' => return "1011";
      when 'c' | 'C' => return "1100";
      when 'd' | 'D' => return "1101";
      when 'e' | 'E' => return "1110";
      when others => return "1111";
    end case;
  end function;

  function hex_string_to_slv32(s : string) return std_logic_vector is
    variable r : std_logic_vector(31 downto 0) := (others => '0');
    variable idx : integer := 31;
  begin
    for i in s'range loop
      exit when idx < 3;
      r(idx downto idx - 3) := hex_char_to_slv4(s(i));
      idx := idx - 4;
    end loop;
    return r;
  end function;

  constant EXPECTED_SIGNATURE : std_logic_vector(31 downto 0) := hex_string_to_slv32(G_EXPECTED_SIGNATURE_HEX);

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
    end if;
    return std_logic_vector(to_unsigned(v, 8));
  end function;

  procedure load_hex_byte_file(
    constant filename : in string;
    variable mem      : inout byte_mem_t;
    variable size_out : out integer
  ) is
    file f       : text;
    variable l   : line;
    variable idx : integer := 0;
    variable s   : string(1 to 256);
    variable len : integer;
  begin
    file_open(f, filename, read_mode);
    while not endfile(f) loop
      readline(f, l);
      len := l'length;
      if len >= 2 and idx <= mem'high then
        s := (others => ' ');
        for i in 1 to len loop
          s(i) := l.all(i);
        end loop;
        mem(idx) := hex_byte_from_string(s(1 to 2));
        idx := idx + 1;
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
  clk <= not clk after CLK_PERIOD / 2;

  uut : entity work.riscv_soc_boot
    generic map(
      CLK_FREQ_HZ    => G_CLK_FREQ_HZ,
      BAUD           => G_BAUD,
      IMEM_WORDS     => G_IMEM_WORDS,
      G_FAULT_INJECT => G_FAULT_KIND /= 0,
      G_PC_TMR       => G_PC_TMR,
      G_STATE_TMR    => G_STATE_TMR,
      G_RF_TMR       => G_RF_TMR,
      G_RF_SELF_HEAL => G_RF_SELF_HEAL,
      G_IMEM_ECC     => G_IMEM_ECC,
      G_DMEM_ECC     => G_DMEM_ECC
    )
    port map(
      clk              => clk,
      reset            => reset,
      uart_rx_i        => uart_rx_i,
      uart_tx_o        => uart_tx_o,
      led0_o           => led0_o,
      boot_done_o      => boot_done_o,
      prog_we_o        => prog_we_o,
      prog_addr_o      => prog_addr_o,
      prog_wdata_o     => prog_wdata_o,
      imem_pc_o        => imem_pc_o,
      dmem_we_o        => dmem_we_o,
      dmem_addr_o      => dmem_addr_o,
      dmem_wdata_o     => dmem_wdata_o,
      pc_tmr_error_o   => pc_tmr_error_o,
      state_tmr_error_o => state_tmr_error_o,
      regfile_tmr_error_o => regfile_tmr_error_o,
      dmem_ecc_single_error_o => dmem_ecc_single_error_o,
      dmem_ecc_double_error_o => dmem_ecc_double_error_o,
      fi_pc_mask_i     => fi_pc_mask_i,
      fi_pc_target_i   => fi_pc_target_i,
      fi_pc_strobe_i   => fi_pc_strobe_i,
      fi_state_mask_i  => fi_state_mask_i,
      fi_state_target_i=> fi_state_target_i,
      fi_state_strobe_i=> fi_state_strobe_i,
      fi_dmem_mask_i   => fi_dmem_mask_i,
      fi_dmem_addr_i   => fi_dmem_addr_i,
      fi_dmem_strobe_i => fi_dmem_strobe_i,
      fi_rf_mask_i     => fi_rf_mask_i,
      fi_rf_addr_i     => fi_rf_addr_i,
      fi_rf_target_i   => fi_rf_target_i,
      fi_rf_strobe_i   => fi_rf_strobe_i,
      fi_imem_mask_i   => fi_imem_mask_i,
      fi_imem_addr_i   => fi_imem_addr_i,
      fi_imem_strobe_i => fi_imem_strobe_i
    );

  stim_proc : process
    variable size_v          : integer := 0;
    variable program_bytes_v : byte_mem_t := (others => (others => '0'));
  begin
    uart_rx_i <= '1';
    load_hex_byte_file(G_PROGRAM_FILE, program_bytes_v, size_v);

    reset <= '1';
    wait for 500 ns;
    wait until rising_edge(clk);
    reset <= '0';

    wait for 20 * BIT_TIME;
    for i in 0 to size_v - 1 loop
      uart_send_byte(uart_rx_i, program_bytes_v(i));
    end loop;
    uart_rx_i <= '1';
    wait;
  end process;

  fault_proc : process
    variable strobe_cycles_v : integer := 1;
  begin
    wait until boot_done_o = '1';

    for i in 0 to G_INJECT_AFTER_BOOT_CYCLES - 1 loop
      wait until rising_edge(clk);
    end loop;

    case G_FAULT_KIND is
      when 1 =>
        fi_pc_mask_i   <= x"00000400";
        fi_pc_target_i <= "00";
        fi_pc_strobe_i <= '1';
        strobe_cycles_v := 3;
      when 2 =>
        fi_state_mask_i   <= "0001";
        fi_state_target_i <= "00";
        fi_state_strobe_i <= '1';
        strobe_cycles_v := 3;
      when 3 =>
        fi_rf_mask_i   <= x"00000001";
        fi_rf_addr_i   <= "11101";
        fi_rf_target_i <= "00";
        fi_rf_strobe_i <= '1';
        strobe_cycles_v := 3;
      when 4 =>
        fi_imem_mask_i   <= (0 => '1', others => '0');
        fi_imem_addr_i   <= std_logic_vector(to_unsigned(14, fi_imem_addr_i'length));
        fi_imem_strobe_i <= '1';
        strobe_cycles_v := 1;
      when 5 =>
        fi_dmem_mask_i   <= (0 => '1', others => '0');
        fi_dmem_addr_i   <= std_logic_vector(to_unsigned(16#100# / 4, fi_dmem_addr_i'length));
        fi_dmem_strobe_i <= '1';
        strobe_cycles_v := 1;
      when 6 =>
        fi_pc_mask_i   <= x"00000020";
        fi_pc_target_i <= "00";
        fi_pc_strobe_i <= '1';
        strobe_cycles_v := 8;
      when 7 =>
        fi_state_mask_i   <= "1100";
        fi_state_target_i <= "00";
        fi_state_strobe_i <= '1';
        strobe_cycles_v := 4;
      when 8 =>
        fi_rf_mask_i   <= x"FFFFFFFF";
        fi_rf_addr_i   <= "01010";
        fi_rf_target_i <= "00";
        fi_rf_strobe_i <= '1';
        strobe_cycles_v := 3;
      when others =>
        null;
        strobe_cycles_v := 1;
    end case;

    for i in 1 to strobe_cycles_v loop
      wait until rising_edge(clk);
    end loop;

    fi_pc_strobe_i    <= '0';
    fi_state_strobe_i <= '0';
    fi_rf_strobe_i    <= '0';
    fi_imem_strobe_i  <= '0';
    fi_dmem_strobe_i  <= '0';
    wait;
  end process;

  result_mon_proc : process(clk)
  begin
    if rising_edge(clk) then
      if pc_tmr_error_o = '1' then
        pc_error_seen <= '1';
      end if;
      if state_tmr_error_o = '1' then
        state_error_seen <= '1';
      end if;
      if regfile_tmr_error_o = '1' then
        regfile_error_seen <= '1';
      end if;
      if dmem_ecc_single_error_o = '1' then
        dmem_single_seen <= '1';
      end if;
      if dmem_ecc_double_error_o = '1' then
        dmem_double_seen <= '1';
      end if;

      if dmem_we_o = '1' then
        if dmem_addr_o = RESULT_ADDR then
          result_seen      <= '1';
          result_signature <= dmem_wdata_o;
        elsif dmem_addr_o = STATUS_ADDR then
          status_seen  <= '1';
          status_value <= dmem_wdata_o;
        end if;
      end if;
    end if;
  end process;

  finish_proc : process
    variable cycles : integer := 0;
    variable class_v : string(1 to 16);
  begin
    wait until reset = '0';
    loop
      wait until rising_edge(clk);
      cycles := cycles + 1;

      if status_seen = '1' then
        if status_value = x"00000001" and result_seen = '1' and result_signature = EXPECTED_SIGNATURE then
          class_v := "masked          ";
          case G_FAULT_KIND is
            when 1 =>
              if pc_error_seen = '1' then
                class_v := "corrected       ";
              end if;
            when 2 =>
              if state_error_seen = '1' then
                class_v := "corrected       ";
              end if;
            when 3 =>
              if regfile_error_seen = '1' then
                class_v := "corrected       ";
              end if;
            when 5 =>
              if dmem_single_seen = '1' then
                class_v := "corrected       ";
              end if;
              if dmem_double_seen = '1' then
                class_v := "uncorrectable   ";
              end if;
            when others =>
              null;
          end case;
          report "RESULT PASS class=" & class_v & " signature=" & to_hstring(result_signature) severity note;
          finish(0);
        else
          report "RESULT FAIL status=" & to_hstring(status_value) &
                 " signature=" & to_hstring(result_signature) severity error;
          finish(1);
        end if;
      end if;

      if cycles >= G_TIMEOUT_CYCLES then
        report "RESULT TIMEOUT pc=" & to_hstring(imem_pc_o) severity error;
        finish(1);
      end if;
    end loop;
  end process;
end architecture;
