library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;
use std.env.all;
use ieee.std_logic_textio.all;

entity tb_riscv_soc_system is
  generic(
    TEST_ID : integer := 32
  );
end entity;

architecture sim of tb_riscv_soc_system is

  --------------------------------------------------------------------
  -- SIM SETTINGS
  --------------------------------------------------------------------
  constant CLK_FREQ_HZ : integer := 50_000_000;
  constant BAUD_SIM    : integer := 1_000_000;

  constant CLK_PERIOD  : time := 1 sec / CLK_FREQ_HZ;
  constant BIT_TIME    : time := 1 sec / BAUD_SIM;

  signal boot_seen : std_logic := '0';

  constant IMEM_WORDS  : integer := 4096;
  constant MAX_BYTES   : integer := IMEM_WORDS * 4;
  constant MAX_WORDS   : integer := IMEM_WORDS;

  constant MAX_STORES  : integer := 64;

  --------------------------------------------------------------------
  -- Payload files
  --------------------------------------------------------------------
  constant PAYLOAD_BASE_DIR : string :=
    "/home/krischan-ledwig/Documents/NanoSat/OpenSourceRiscV/cc-toolchain-linux/workspace/RiscVFSM/hex_files/";

  constant PAYLOAD_FILE_0  : string := PAYLOAD_BASE_DIR & "payload_store.hex";
  constant PAYLOAD_FILE_1  : string := PAYLOAD_BASE_DIR & "payload_beq_bne.hex";
  constant PAYLOAD_FILE_2  : string := PAYLOAD_BASE_DIR & "payload_branch.hex";
  constant PAYLOAD_FILE_3  : string := PAYLOAD_BASE_DIR & "payload_branch_not_taken.hex";
  constant PAYLOAD_FILE_4  : string := PAYLOAD_BASE_DIR & "payload_jalr.hex";
  constant PAYLOAD_FILE_5  : string := PAYLOAD_BASE_DIR & "payload_lb_lbu.hex";
  constant PAYLOAD_FILE_6  : string := PAYLOAD_BASE_DIR & "payload_mul.hex";
  constant PAYLOAD_FILE_7  : string := PAYLOAD_BASE_DIR & "payload_matmul.hex";
  constant PAYLOAD_FILE_8  : string := PAYLOAD_BASE_DIR & "payload_mytest.hex";
  constant PAYLOAD_FILE_9  : string := PAYLOAD_BASE_DIR & "payload_alu.hex";
  constant PAYLOAD_FILE_10 : string := PAYLOAD_BASE_DIR & "payload_bltu_bgeu.hex";
  constant PAYLOAD_FILE_11 : string := PAYLOAD_BASE_DIR & "payload_timer_mmio.hex";
  constant PAYLOAD_FILE_12 : string := PAYLOAD_BASE_DIR & "payload_regression.hex";
  constant PAYLOAD_FILE_13 : string := PAYLOAD_BASE_DIR & "payload_imm_logic.hex";
  constant PAYLOAD_FILE_14 : string := PAYLOAD_BASE_DIR & "payload_imm_shift_cmp.hex";
  constant PAYLOAD_FILE_15 : string := PAYLOAD_BASE_DIR & "payload_lui_auipc.hex";
  constant PAYLOAD_FILE_16 : string := PAYLOAD_BASE_DIR & "payload_beq_bne.hex";
  constant PAYLOAD_FILE_17 : string := PAYLOAD_BASE_DIR & "payload_blt_bge.hex";
  constant PAYLOAD_FILE_18 : string := PAYLOAD_BASE_DIR & "payload_jal.hex";
  constant PAYLOAD_FILE_19 : string := PAYLOAD_BASE_DIR & "payload_jalr.hex";
  constant PAYLOAD_FILE_20 : string := PAYLOAD_BASE_DIR & "payload_csr_rw.hex";
  constant PAYLOAD_FILE_21 : string := PAYLOAD_BASE_DIR & "payload_csr_imm.hex";
  constant PAYLOAD_FILE_22 : string := PAYLOAD_BASE_DIR & "payload_ecall.hex";
  constant PAYLOAD_FILE_23 : string := PAYLOAD_BASE_DIR & "payload_ebreak.hex";
  constant PAYLOAD_FILE_24 : string := PAYLOAD_BASE_DIR & "payload_illegal.hex";
  constant PAYLOAD_FILE_25 : string := PAYLOAD_BASE_DIR & "payload_mret.hex";
  constant PAYLOAD_FILE_26 : string := PAYLOAD_BASE_DIR & "payload_timer_irq_gated.hex";
  constant PAYLOAD_FILE_27 : string := PAYLOAD_BASE_DIR & "payload_trap_priority.hex";
  constant PAYLOAD_FILE_28 : string := PAYLOAD_BASE_DIR & "payload_big_regression.hex";
  constant PAYLOAD_FILE_29 : string := PAYLOAD_BASE_DIR & "payload_tmr_counter_readback.hex";
  constant PAYLOAD_FILE_30 : string := PAYLOAD_BASE_DIR & "payload_state_tmr_counter_readback.hex";
  constant PAYLOAD_FILE_31 : string := PAYLOAD_BASE_DIR & "payload_watchdog_timeout.hex";
  constant PAYLOAD_FILE_32 : string := PAYLOAD_BASE_DIR & "payload_dmem_ecc_single.hex";
  constant PAYLOAD_FILE_33 : string := PAYLOAD_BASE_DIR & "payload_dmem_ecc_double.hex";
  constant PAYLOAD_FILE_34 : string := PAYLOAD_BASE_DIR & "payload_regfile_tmr_counter_readback.hex";
  constant PAYLOAD_FILE_35 : string := PAYLOAD_BASE_DIR & "payload_regfile_tmr_double_fault.hex";
  constant PAYLOAD_FILE_36 : string := PAYLOAD_BASE_DIR & "payload_imem_ecc_single.hex";

  --------------------------------------------------------------------
  -- DUT I/O
  --------------------------------------------------------------------
  signal clk       : std_logic := '0';
  signal reset     : std_logic := '1';
  signal uart_rx_i : std_logic := '1';
  signal led0_o    : std_logic;

  signal boot_done_o  : std_logic;
  signal prog_we_o    : std_logic;
  signal prog_addr_o  : std_logic_vector(31 downto 0);
  signal prog_wdata_o : std_logic_vector(31 downto 0);

  signal imem_pc_o    : std_logic_vector(31 downto 0);
  signal dmem_we_o    : std_logic;
  signal dmem_addr_o  : std_logic_vector(31 downto 0);
  signal dmem_wdata_o : std_logic_vector(31 downto 0);

  --------------------------------------------------------------------
  -- Fault injection signals
  --------------------------------------------------------------------
  signal fi_pc_mask      : std_logic_vector(31 downto 0) := (others => '0');
  signal fi_pc_target    : std_logic_vector(1 downto 0)  := "00";
  signal fi_pc_strobe    : std_logic := '0';

  signal fi_state_mask   : std_logic_vector(3 downto 0)  := (others => '0');
  signal fi_state_target : std_logic_vector(1 downto 0)  := "00";
  signal fi_state_strobe : std_logic := '0';

  signal fi_dmem_mask    : std_logic_vector(38 downto 0) := (others => '0');
  signal fi_dmem_addr    : std_logic_vector(9 downto 0)  := (others => '0');
  signal fi_dmem_strobe  : std_logic := '0';

  signal fi_rf_mask      : std_logic_vector(31 downto 0) := (others => '0');
  signal fi_rf_addr      : std_logic_vector(4 downto 0)  := (others => '0');
  signal fi_rf_target    : std_logic_vector(1 downto 0)  := "00";
  signal fi_rf_strobe    : std_logic := '0';

  signal fi_imem_mask    : std_logic_vector(38 downto 0) := (others => '0');
  signal fi_imem_addr    : std_logic_vector(11 downto 0) := (others => '0');
  signal fi_imem_strobe  : std_logic := '0';

  --------------------------------------------------------------------
  -- Payload storage
  --------------------------------------------------------------------
  type byte_mem_t is array (0 to MAX_BYTES-1) of std_logic_vector(7 downto 0);
  type word_mem_t is array (0 to MAX_WORDS-1) of std_logic_vector(31 downto 0);

  signal expected_words  : word_mem_t;
  signal expected_nwords : integer := 0;

  --------------------------------------------------------------------
  -- Expected store sequence
  --------------------------------------------------------------------
  type slv32_arr_t is array (0 to MAX_STORES-1) of std_logic_vector(31 downto 0);

  signal exp_store_addr : slv32_arr_t := (others => (others => '0'));
  signal exp_store_data : slv32_arr_t := (others => (others => '0'));
  signal exp_nstores    : integer := 0;

  signal store_count           : integer := 0;
  signal marker_seen           : std_logic := '0';
  signal timer_mmio_store_seen : std_logic := '0';

  signal wd_reset_seen     : std_logic := '0';
  signal post_boot_started : std_logic := '0';

  --------------------------------------------------------------------
  -- UART helpers
  --------------------------------------------------------------------
  procedure uart_send_byte(signal line: out std_logic; b: std_logic_vector(7 downto 0)) is
  begin
    line <= '0';
    wait for BIT_TIME;
    for i in 0 to 7 loop
      line <= b(i);
      wait for BIT_TIME;
    end loop;
    line <= '1';
    wait for BIT_TIME;
  end procedure;

  procedure uart_send_u32_le(signal line: out std_logic; v: integer) is
    variable x : unsigned(31 downto 0);
  begin
    x := to_unsigned(v, 32);
    uart_send_byte(line, std_logic_vector(x(7 downto 0)));
    uart_send_byte(line, std_logic_vector(x(15 downto 8)));
    uart_send_byte(line, std_logic_vector(x(23 downto 16)));
    uart_send_byte(line, std_logic_vector(x(31 downto 24)));
  end procedure;

  --------------------------------------------------------------------
  -- Select payload file
  --------------------------------------------------------------------
  function select_payload_file(test_id : integer) return string is
  begin
    case test_id is
      when 0  => return PAYLOAD_FILE_0;
      when 1  => return PAYLOAD_FILE_1;
      when 2  => return PAYLOAD_FILE_2;
      when 3  => return PAYLOAD_FILE_3;
      when 4  => return PAYLOAD_FILE_4;
      when 5  => return PAYLOAD_FILE_5;
      when 6  => return PAYLOAD_FILE_6;
      when 7  => return PAYLOAD_FILE_7;
      when 8  => return PAYLOAD_FILE_8;
      when 9  => return PAYLOAD_FILE_9;
      when 10 => return PAYLOAD_FILE_10;
      when 11 => return PAYLOAD_FILE_11;
      when 12 => return PAYLOAD_FILE_12;
      when 13 => return PAYLOAD_FILE_13;
      when 14 => return PAYLOAD_FILE_14;
      when 15 => return PAYLOAD_FILE_15;
      when 16 => return PAYLOAD_FILE_16;
      when 17 => return PAYLOAD_FILE_17;
      when 18 => return PAYLOAD_FILE_18;
      when 19 => return PAYLOAD_FILE_19;
      when 20 => return PAYLOAD_FILE_20;
      when 21 => return PAYLOAD_FILE_21;
      when 22 => return PAYLOAD_FILE_22;
      when 23 => return PAYLOAD_FILE_23;
      when 24 => return PAYLOAD_FILE_24;
      when 25 => return PAYLOAD_FILE_25;
      when 26 => return PAYLOAD_FILE_26;
      when 27 => return PAYLOAD_FILE_27;
      when 28 => return PAYLOAD_FILE_28;
      when 29 => return PAYLOAD_FILE_29;
      when 30 => return PAYLOAD_FILE_30;
      when 31 => return PAYLOAD_FILE_31;
      when 32 => return PAYLOAD_FILE_32;
      when 33 => return PAYLOAD_FILE_33;
      when 34 => return PAYLOAD_FILE_34;
      when 35 => return PAYLOAD_FILE_35;
      when 36 => return PAYLOAD_FILE_36;
      when others =>
        assert false report "Unknown TEST_ID in select_payload_file" severity failure;
        return PAYLOAD_FILE_0;
    end case;
  end function;

  --------------------------------------------------------------------
  -- Load payload from file: one hex byte per line
  --------------------------------------------------------------------
  procedure load_payload_file(
    constant filename : in string;
    variable bytes    : out byte_mem_t;
    variable len      : out integer
  ) is
    file f           : text;
    variable fstatus : file_open_status;
    variable l       : line;
    variable b       : std_logic_vector(7 downto 0);
    variable i       : integer := 0;
  begin
    for k in 0 to MAX_BYTES-1 loop
      bytes(k) := (others => '0');
    end loop;

    file_open(fstatus, f, filename, read_mode);

    assert fstatus = open_ok
      report "Could not open payload file: " & filename
      severity failure;

    while not endfile(f) loop
      readline(f, l);
      if l'length = 0 then
        next;
      end if;

      hread(l, b);

      if i >= MAX_BYTES then
        assert false report "payload too large (MAX_BYTES exceeded)" severity failure;
      end if;

      bytes(i) := b;
      i := i + 1;
    end loop;

    file_close(f);
    len := i;
  end procedure;

  --------------------------------------------------------------------
  -- Build expected words from byte stream
  --------------------------------------------------------------------
  procedure build_expected_words(
    variable bytes   : in  byte_mem_t;
    constant len     : in  integer;
    variable words   : out word_mem_t;
    variable nwords  : out integer
  ) is
    variable w   : std_logic_vector(31 downto 0);
    variable idx : integer;
    variable nw  : integer;
  begin
    for j in 0 to MAX_WORDS-1 loop
      words(j) := (others => '0');
    end loop;

    nw := (len + 3) / 4;

    if nw > MAX_WORDS then
      assert false report "payload exceeds IMEM_WORDS" severity failure;
    end if;

    for j in 0 to nw-1 loop
      w := (others => '0');
      for k in 0 to 3 loop
        idx := j*4 + k;
        if idx < len then
          case k is
            when 0 => w(7 downto 0)        := bytes(idx);
            when 1 => w(15 downto 8)       := bytes(idx);
            when 2 => w(23 downto 16)      := bytes(idx);
            when others => w(31 downto 24) := bytes(idx);
          end case;
        end if;
      end loop;
      words(j) := w;
    end loop;

    nwords := nw;
  end procedure;

  function slv_to_hex(slv : std_logic_vector) return string is
    constant hexchars : string := "0123456789ABCDEF";
    variable padded   : std_logic_vector(((slv'length + 3)/4)*4 - 1 downto 0) := (others => '0');
    variable result   : string(1 to (slv'length + 3)/4);
    variable nibble   : std_logic_vector(3 downto 0);
    variable idx      : integer;
  begin
    padded(slv'length-1 downto 0) := slv;

    for i in 0 to result'length-1 loop
      nibble := padded(padded'length - 1 - i*4 downto padded'length - 4 - i*4);
      case nibble is
        when "0000" => idx := 0;
        when "0001" => idx := 1;
        when "0010" => idx := 2;
        when "0011" => idx := 3;
        when "0100" => idx := 4;
        when "0101" => idx := 5;
        when "0110" => idx := 6;
        when "0111" => idx := 7;
        when "1000" => idx := 8;
        when "1001" => idx := 9;
        when "1010" => idx := 10;
        when "1011" => idx := 11;
        when "1100" => idx := 12;
        when "1101" => idx := 13;
        when "1110" => idx := 14;
        when "1111" => idx := 15;
        when others => idx := 0;
      end case;
      result(i+1) := hexchars(idx+1);
    end loop;

    return result;
  end function;

begin

  --------------------------------------------------------------------
  -- Clock
  --------------------------------------------------------------------
  clk <= not clk after CLK_PERIOD/2;

  --------------------------------------------------------------------
  -- DUT
  --------------------------------------------------------------------
  uut: entity work.riscv_soc_boot
    generic map(
      CLK_FREQ_HZ => CLK_FREQ_HZ,
      BAUD        => BAUD_SIM,
      IMEM_WORDS  => IMEM_WORDS
    )
    port map(
      clk               => clk,
      reset             => reset,
      uart_rx_i         => uart_rx_i,
      led0_o            => led0_o,
      boot_done_o       => boot_done_o,
      boot_error_o      => open,
      prog_we_o         => prog_we_o,
      prog_addr_o       => prog_addr_o,
      prog_wdata_o      => prog_wdata_o,
      imem_pc_o         => imem_pc_o,
      dmem_we_o         => dmem_we_o,
      dmem_addr_o       => dmem_addr_o,
      dmem_wdata_o      => dmem_wdata_o,
      fi_pc_mask_i      => fi_pc_mask,
      fi_pc_target_i    => fi_pc_target,
      fi_pc_strobe_i    => fi_pc_strobe,
      fi_state_mask_i   => fi_state_mask,
      fi_state_target_i => fi_state_target,
      fi_state_strobe_i => fi_state_strobe,
      fi_dmem_mask_i    => fi_dmem_mask,
      fi_dmem_addr_i    => fi_dmem_addr,
      fi_dmem_strobe_i  => fi_dmem_strobe,
      fi_rf_mask_i      => fi_rf_mask,
      fi_rf_addr_i      => fi_rf_addr,
      fi_rf_target_i    => fi_rf_target,
      fi_rf_strobe_i    => fi_rf_strobe,
      fi_imem_mask_i    => fi_imem_mask,
      fi_imem_addr_i    => fi_imem_addr,
      fi_imem_strobe_i  => fi_imem_strobe
    );

  --------------------------------------------------------------------
  -- Fault injection: PC
  --------------------------------------------------------------------
  fault_inject_pc: process
  begin
    if TEST_ID /= 29 then
      wait;
    end if;

    wait until boot_done_o = '1';
    wait for 30 us;

    report "FAULT INJECTION: flipping PC voter input A" severity note;

    fi_pc_mask   <= x"00000004";
    fi_pc_target <= "00";
    fi_pc_strobe <= '1';

    wait for CLK_PERIOD;

    fi_pc_strobe <= '0';
    fi_pc_mask   <= (others => '0');
    fi_pc_target <= "00";

    wait;
  end process;

  --------------------------------------------------------------------
  -- Fault injection: STATE
  --------------------------------------------------------------------
  fault_inject_state: process
  begin
    if TEST_ID /= 30 then
      wait;
    end if;

    wait until boot_done_o = '1';
    wait for 30 us;

    report "FAULT INJECTION: flipping STATE voter input B" severity note;

    fi_state_mask   <= "0001";
    fi_state_target <= "01";
    fi_state_strobe <= '1';

    wait for CLK_PERIOD;

    fi_state_strobe <= '0';
    fi_state_mask   <= (others => '0');
    fi_state_target <= "00";

    wait;
  end process;

  --------------------------------------------------------------------
  -- Fault injection: REGFILE single-bank
  --------------------------------------------------------------------
  fault_inject_regfile: process
  begin
    if TEST_ID /= 34 then
      wait;
    end if;

    wait until rising_edge(clk) and dmem_we_o = '1' and dmem_addr_o = x"00000020";

    report "FAULT INJECTION: flipping REGFILE bank B, x5 bit 3" severity note;

    fi_rf_addr   <= "00101";
    fi_rf_mask   <= x"00000008";
    fi_rf_target <= "01";
    fi_rf_strobe <= '1';

    wait until rising_edge(clk);

    fi_rf_strobe <= '0';
    fi_rf_mask   <= (others => '0');
    fi_rf_addr   <= (others => '0');
    fi_rf_target <= "00";

    wait;
  end process;

  --------------------------------------------------------------------
  -- Fault injection: REGFILE double-bank
  --------------------------------------------------------------------
  fault_inject_regfile_double: process
  begin
    if TEST_ID /= 35 then
      wait;
    end if;

    wait until rising_edge(clk) and dmem_we_o = '1' and dmem_addr_o = x"00000020";

    report "FAULT INJECTION: flipping REGFILE bank A, x5 bit 3" severity note;

    fi_rf_addr   <= "00101";
    fi_rf_mask   <= x"00000008";
    fi_rf_target <= "00";
    fi_rf_strobe <= '1';

    wait until rising_edge(clk);

    fi_rf_strobe <= '0';
    fi_rf_mask   <= (others => '0');
    fi_rf_target <= "00";

    wait until rising_edge(clk);

    report "FAULT INJECTION: flipping REGFILE bank B, x5 bit 3" severity note;

    fi_rf_addr   <= "00101";
    fi_rf_mask   <= x"00000008";
    fi_rf_target <= "01";
    fi_rf_strobe <= '1';

    wait until rising_edge(clk);

    fi_rf_strobe <= '0';
    fi_rf_mask   <= (others => '0');
    fi_rf_addr   <= (others => '0');
    fi_rf_target <= "00";

    wait;
  end process;

  --------------------------------------------------------------------
  -- Fault injection: IMEM single-bit
  --------------------------------------------------------------------
  fault_inject_imem_single: process
    variable mask_v : std_logic_vector(38 downto 0);
  begin
    if TEST_ID /= 36 then
      wait;
    end if;

    wait until rising_edge(clk) and prog_we_o = '1' and prog_addr_o = x"00000008";

    report "FAULT INJECTION: flipping 1 bit in IMEM word 2" severity note;

    mask_v := (others => '0');
    mask_v(10) := '1';

    fi_imem_addr   <= std_logic_vector(to_unsigned(2, 12));
    fi_imem_mask   <= mask_v;
    fi_imem_strobe <= '1';

    wait until rising_edge(clk);

    fi_imem_strobe <= '0';
    fi_imem_mask   <= (others => '0');
    fi_imem_addr   <= (others => '0');

    wait;
  end process;

  --------------------------------------------------------------------
  -- Fault injection: DMEM single-bit
  --------------------------------------------------------------------
  fault_inject_dmem_single: process
      variable mask_v : std_logic_vector(38 downto 0);
    begin
      if TEST_ID /= 32 then
        wait;
      end if;
    
      wait until rising_edge(clk) and dmem_we_o = '1' and dmem_addr_o = x"00000000";
    
      report "FAULT INJECTION: flipping 1 bit in DMEM word 0" severity note;
    
      mask_v := (others => '0');
      mask_v(10) := '1';
    
      fi_dmem_addr   <= (others => '0');
      fi_dmem_mask   <= mask_v;
      fi_dmem_strobe <= '1';
    
      wait until rising_edge(clk);
    
      fi_dmem_strobe <= '0';
      fi_dmem_mask   <= (others => '0');
      fi_dmem_addr   <= (others => '0');
    
      wait;
    end process;

  --------------------------------------------------------------------
  -- Fault injection: DMEM double-bit
  --------------------------------------------------------------------
  fault_inject_dmem_double: process
  variable mask_v : std_logic_vector(38 downto 0);
begin
  if TEST_ID /= 33 then
    wait;
  end if;

  wait until rising_edge(clk) and dmem_we_o = '1' and dmem_addr_o = x"00000000";

  report "FAULT INJECTION: flipping 2 bits in DMEM word 0" severity note;

  mask_v := (others => '0');
  mask_v(10) := '1';
  mask_v(11) := '1';

  fi_dmem_addr   <= (others => '0');
  fi_dmem_mask   <= mask_v;
  fi_dmem_strobe <= '1';

  wait until rising_edge(clk);

  fi_dmem_strobe <= '0';
  fi_dmem_mask   <= (others => '0');
  fi_dmem_addr   <= (others => '0');

  wait;
end process;

  --------------------------------------------------------------------
  -- Watchdog reset monitor
  --------------------------------------------------------------------
  monitor_watchdog_reset: process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        wd_reset_seen     <= '0';
        post_boot_started <= '0';
      else
        if TEST_ID = 31 then
          if boot_done_o = '1' and unsigned(imem_pc_o) > 0 then
            post_boot_started <= '1';
          end if;

          if boot_done_o = '1' and post_boot_started = '1' and imem_pc_o = x"00000000" then
            wd_reset_seen <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- IMEM write verification
  --------------------------------------------------------------------
  monitor_imem: process(clk)
    variable write_count : integer := 0;
    variable addr_u      : unsigned(31 downto 0);
  begin
    if rising_edge(clk) then
      if reset = '1' then
        write_count := 0;
      else
        if prog_we_o = '1' then
          addr_u := unsigned(prog_addr_o);

          assert addr_u = to_unsigned(write_count * 4, 32)
            report "IMEM write addr mismatch"
            severity failure;

          assert prog_wdata_o = expected_words(write_count)
            report "IMEM write data mismatch"
            severity failure;

          write_count := write_count + 1;
        end if;

        if boot_done_o = '1' then
          assert write_count = expected_nwords
            report "boot_done but IMEM write_count != expected_nwords"
            severity failure;
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Store verification
  --------------------------------------------------------------------
  monitor_store: process(clk)
    variable idx : integer;
  begin
    if rising_edge(clk) then
      if reset = '1' then
        store_count           <= 0;
        marker_seen           <= '0';
        timer_mmio_store_seen <= '0';
        boot_seen             <= '0';
      else
        if boot_done_o = '1' then
          boot_seen <= '1';
        end if;

        if dmem_we_o = '1' and boot_seen = '1' then
          if TEST_ID = 8 then
            if dmem_addr_o = x"00000010" then
              assert dmem_wdata_o = x"CAFEBABE"
                report "TEST 8: Timer IRQ marker mismatch"
                severity failure;
              marker_seen <= '1';
            end if;

          elsif TEST_ID = 11 then
            if dmem_addr_o = x"40001000" or
               dmem_addr_o = x"40001004" or
               dmem_addr_o = x"40001008" or
               dmem_addr_o = x"4000100C" then
              timer_mmio_store_seen <= '1';
              assert false
                report "TEST 11: observed forbidden DMEM write to timer MMIO address"
                severity failure;
            else
              idx := store_count;
              assert idx < exp_nstores
                report "TEST 11: observed more stores than expected"
                severity failure;
              assert dmem_addr_o = exp_store_addr(idx)
                report "TEST 11: DMEM store addr mismatch"
                severity failure;
              assert dmem_wdata_o = exp_store_data(idx)
                report "TEST 11: DMEM store data mismatch"
                severity failure;
            end if;

          elsif TEST_ID = 29 then
            idx := store_count;

            report "STORE idx=" & integer'image(store_count) &
                   " addr=0x" & slv_to_hex(dmem_addr_o) &
                   " data=0x" & slv_to_hex(dmem_wdata_o)
              severity note;

            assert idx < exp_nstores
              report "TEST 29: observed more stores than expected"
              severity failure;

            assert dmem_addr_o = exp_store_addr(idx)
              report "TEST 29: DMEM store addr mismatch"
              severity failure;

            if idx = 0 then
              assert unsigned(dmem_wdata_o) >= 1
                report "TEST 29: PC TMR error counter did not increment"
                severity failure;
            else
              assert dmem_wdata_o = exp_store_data(idx)
                report "TEST 29: DMEM store data mismatch"
                severity failure;
            end if;

          elsif TEST_ID = 30 then
            idx := store_count;

            report "STORE idx=" & integer'image(store_count) &
                   " addr=0x" & slv_to_hex(dmem_addr_o) &
                   " data=0x" & slv_to_hex(dmem_wdata_o)
              severity note;

            assert idx < exp_nstores
              report "TEST 30: observed more stores than expected"
              severity failure;

            assert dmem_addr_o = exp_store_addr(idx)
              report "TEST 30: DMEM store addr mismatch"
              severity failure;

            if idx = 0 then
              assert unsigned(dmem_wdata_o) >= 1
                report "TEST 30: STATE TMR error counter did not increment"
                severity failure;
            else
              assert dmem_wdata_o = exp_store_data(idx)
                report "TEST 30: DMEM store data mismatch"
                severity failure;
            end if;

          elsif TEST_ID = 32 then
            idx := store_count;

            report "STORE idx=" & integer'image(store_count) &
                   " addr=0x" & slv_to_hex(dmem_addr_o) &
                   " data=0x" & slv_to_hex(dmem_wdata_o)
              severity note;

            assert idx < exp_nstores
              report "TEST 32: observed more stores than expected"
              severity failure;

            assert dmem_addr_o = exp_store_addr(idx)
              report "TEST 32: DMEM store addr mismatch"
              severity failure;

            case idx is
              when 0 =>
                assert dmem_wdata_o = x"00000011"
                  report "TEST 32: initial DMEM write mismatch"
                  severity failure;

              when 1 =>
                assert unsigned(dmem_wdata_o) >= 1
                  report "TEST 32: DMEM single ECC counter did not increment"
                  severity failure;

              when 2 =>
                assert dmem_wdata_o = x"0000007B"
                  report "TEST 32: final marker mismatch"
                  severity failure;

              when others =>
                assert false
                  report "TEST 32: unexpected extra store"
                  severity failure;
            end case;

          elsif TEST_ID = 33 then
            idx := store_count;

            report "STORE idx=" & integer'image(store_count) &
                   " addr=0x" & slv_to_hex(dmem_addr_o) &
                   " data=0x" & slv_to_hex(dmem_wdata_o)
              severity note;

            assert idx < exp_nstores
              report "TEST 33: observed more stores than expected"
              severity failure;

            assert dmem_addr_o = exp_store_addr(idx)
              report "TEST 33: DMEM store addr mismatch"
              severity failure;

            case idx is
              when 0 =>
                assert dmem_wdata_o = x"00000011"
                  report "TEST 33: initial DMEM write mismatch"
                  severity failure;

              when 1 =>
                assert unsigned(dmem_wdata_o) >= 1
                  report "TEST 33: DMEM double ECC counter did not increment"
                  severity failure;

              when 2 =>
                assert dmem_wdata_o = x"0000007B"
                  report "TEST 33: final marker mismatch"
                  severity failure;

              when others =>
                assert false
                  report "TEST 33: unexpected extra store"
                  severity failure;
            end case;

          elsif TEST_ID = 34 then
            idx := store_count;

            report "STORE idx=" & integer'image(store_count) &
                   " addr=0x" & slv_to_hex(dmem_addr_o) &
                   " data=0x" & slv_to_hex(dmem_wdata_o)
              severity note;

            assert idx < exp_nstores
              report "TEST 34: observed more stores than expected"
              severity failure;

            assert dmem_addr_o = exp_store_addr(idx)
              report "TEST 34: DMEM store addr mismatch"
              severity failure;

            case idx is
              when 0 =>
                assert dmem_wdata_o = x"0000000A"
                  report "TEST 34: marker store mismatch"
                  severity failure;

              when 1 =>
                assert dmem_wdata_o = x"0000000D"
                  report "TEST 34: functional result mismatch after regfile fault"
                  severity failure;

              when 2 =>
                assert unsigned(dmem_wdata_o) >= 1
                  report "TEST 34: REGFILE TMR counter did not increment"
                  severity failure;

              when 3 =>
                assert dmem_wdata_o = x"0000007B"
                  report "TEST 34: final marker mismatch"
                  severity failure;

              when others =>
                assert false
                  report "TEST 34: unexpected extra store"
                  severity failure;
            end case;

          elsif TEST_ID = 35 then
            idx := store_count;

            report "STORE idx=" & integer'image(store_count) &
                   " addr=0x" & slv_to_hex(dmem_addr_o) &
                   " data=0x" & slv_to_hex(dmem_wdata_o)
              severity note;

            assert idx < exp_nstores
              report "TEST 35: observed more stores than expected"
              severity failure;

            assert dmem_addr_o = exp_store_addr(idx)
              report "TEST 35: DMEM store addr mismatch"
              severity failure;

            case idx is
              when 0 =>
                assert dmem_wdata_o = x"0000000A"
                  report "TEST 35: marker store mismatch"
                  severity failure;

              when 1 =>
                assert dmem_wdata_o = x"00000005"
                  report "TEST 35: expected wrong functional result after double-bank upset"
                  severity failure;

              when 2 =>
                assert unsigned(dmem_wdata_o) >= 1
                  report "TEST 35: REGFILE TMR counter did not increment"
                  severity failure;

              when 3 =>
                assert dmem_wdata_o = x"0000007B"
                  report "TEST 35: final marker mismatch"
                  severity failure;

              when others =>
                assert false
                  report "TEST 35: unexpected extra store"
                  severity failure;
            end case;

          elsif TEST_ID = 36 then
            idx := store_count;

            report "STORE idx=" & integer'image(store_count) &
                   " addr=0x" & slv_to_hex(dmem_addr_o) &
                   " data=0x" & slv_to_hex(dmem_wdata_o)
              severity note;

            assert idx < exp_nstores
              report "TEST 36: observed more stores than expected"
              severity failure;

            assert dmem_addr_o = exp_store_addr(idx)
              report "TEST 36: DMEM store addr mismatch"
              severity failure;

            assert dmem_wdata_o = exp_store_data(idx)
              report "TEST 36: functional result mismatch after IMEM single-bit fault"
              severity failure;

          else
            idx := store_count;

            report "STORE idx=" & integer'image(store_count) &
                   " addr=0x" & slv_to_hex(dmem_addr_o) &
                   " data=0x" & slv_to_hex(dmem_wdata_o)
              severity note;

            assert idx < exp_nstores
              report "Observed more stores than expected"
              severity failure;

            if dmem_addr_o /= exp_store_addr(idx) then
              report "DMEM store addr mismatch at idx=" & integer'image(idx) &
                     " actual=0x" & slv_to_hex(dmem_addr_o) &
                     " expected=0x" & slv_to_hex(exp_store_addr(idx))
                severity failure;
            end if;

            if dmem_wdata_o /= exp_store_data(idx) then
              report "DMEM store data mismatch at idx=" & integer'image(idx) &
                     " addr=0x" & slv_to_hex(dmem_addr_o) &
                     " actual=0x" & slv_to_hex(dmem_wdata_o) &
                     " expected=0x" & slv_to_hex(exp_store_data(idx))
                severity failure;
            end if;
          end if;

          store_count <= store_count + 1;
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Stimulus
  --------------------------------------------------------------------
  stim: process
    variable bytes       : byte_mem_t;
    variable len         : integer;
    variable words       : word_mem_t;
    variable nwords      : integer;
    variable total_bytes : integer;
    variable timeout_t   : time;
  begin
    exp_store_addr <= (others => (others => '0'));
    exp_store_data <= (others => (others => '0'));
    exp_nstores    <= 0;

    if TEST_ID = 0 then
      exp_store_addr(0) <= x"00000000";
      exp_store_data(0) <= x"12345678";
      exp_nstores       <= 1;

    elsif TEST_ID = 1 then
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"000000AA";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"000000BB";
      exp_nstores       <= 2;

    elsif TEST_ID = 2 then
      exp_store_addr(0) <= x"00000004"; exp_store_data(0) <= x"00000001";
      exp_nstores       <= 1;

    elsif TEST_ID = 3 then
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"00000001";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"00000002";
      exp_nstores       <= 2;

    elsif TEST_ID = 4 then
      exp_store_addr(0) <= x"00000004"; exp_store_data(0) <= x"00000008";
      exp_nstores       <= 1;

    elsif TEST_ID = 5 then
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"807F01FF";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"FFFFFFFF";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"000000FF";
      exp_nstores       <= 3;

    elsif TEST_ID = 6 then
      exp_nstores <= 0;

    elsif TEST_ID = 7 then
      exp_nstores <= 13;
      exp_store_addr(0)  <= x"00000100"; exp_store_data(0)  <= x"00000001";
      exp_store_addr(1)  <= x"00000104"; exp_store_data(1)  <= x"00000002";
      exp_store_addr(2)  <= x"00000108"; exp_store_data(2)  <= x"00000003";
      exp_store_addr(3)  <= x"0000010C"; exp_store_data(3)  <= x"00000004";
      exp_store_addr(4)  <= x"00000120"; exp_store_data(4)  <= x"00000005";
      exp_store_addr(5)  <= x"00000124"; exp_store_data(5)  <= x"00000006";
      exp_store_addr(6)  <= x"00000128"; exp_store_data(6)  <= x"00000007";
      exp_store_addr(7)  <= x"0000012C"; exp_store_data(7)  <= x"00000008";
      exp_store_addr(8)  <= x"00000140"; exp_store_data(8)  <= x"00000013";
      exp_store_addr(9)  <= x"00000144"; exp_store_data(9)  <= x"00000016";
      exp_store_addr(10) <= x"00000148"; exp_store_data(10) <= x"0000002B";
      exp_store_addr(11) <= x"0000014C"; exp_store_data(11) <= x"00000032";
      exp_store_addr(12) <= x"00000000"; exp_store_data(12) <= x"DEADBEEF";

    elsif TEST_ID = 8 then
      exp_nstores <= 0;

    elsif TEST_ID = 9 then
      exp_nstores <= 8;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"00000000";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"FFFFFFFF";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"FFFFFFFF";
      exp_store_addr(3) <= x"0000000C"; exp_store_data(3) <= x"00000010";
      exp_store_addr(4) <= x"00000010"; exp_store_data(4) <= x"00000004";
      exp_store_addr(5) <= x"00000014"; exp_store_data(5) <= x"FFFFFFFC";
      exp_store_addr(6) <= x"00000018"; exp_store_data(6) <= x"00000001";
      exp_store_addr(7) <= x"0000001C"; exp_store_data(7) <= x"00000000";

    elsif TEST_ID = 10 then
      exp_nstores <= 2;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"000000AA";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"000000BB";

    elsif TEST_ID = 11 then
      exp_nstores <= 2;
      exp_store_addr(0) <= x"00000020"; exp_store_data(0) <= x"11111111";
      exp_store_addr(1) <= x"00000024"; exp_store_data(1) <= x"22222222";

    elsif TEST_ID = 12 then
      exp_nstores <= 8;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"00000030";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"FFFFFFF0";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"00000000";
      exp_store_addr(3) <= x"0000000C"; exp_store_data(3) <= x"00000030";
      exp_store_addr(4) <= x"00000010"; exp_store_data(4) <= x"00000030";
      exp_store_addr(5) <= x"00000014"; exp_store_data(5) <= x"00000010";
      exp_store_addr(6) <= x"00000018"; exp_store_data(6) <= x"00000004";
      exp_store_addr(7) <= x"0000001C"; exp_store_data(7) <= x"FFFFFFFC";

    elsif TEST_ID = 13 then
      exp_nstores <= 4;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"00000011";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"00000001";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"0000001F";
      exp_store_addr(3) <= x"0000000C"; exp_store_data(3) <= x"0000001E";

    elsif TEST_ID = 14 then
      exp_nstores <= 5;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"00000001";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"00000000";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"00000010";
      exp_store_addr(3) <= x"0000000C"; exp_store_data(3) <= x"00000004";
      exp_store_addr(4) <= x"00000010"; exp_store_data(4) <= x"FFFFFFFC";

    elsif TEST_ID = 15 then
      exp_nstores <= 2;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"12345000";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"00000008";

    elsif TEST_ID = 16 then
      exp_nstores <= 2;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"000000AA";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"000000BB";

    elsif TEST_ID = 17 then
      exp_nstores <= 2;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"000000AA";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"000000BB";

    elsif TEST_ID = 18 then
      exp_nstores <= 1;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"00000004";

    elsif TEST_ID = 19 then
      exp_nstores <= 1;
      exp_store_addr(0) <= x"00000004"; exp_store_data(0) <= x"00000008";

    elsif TEST_ID = 20 then
      exp_nstores <= 4;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"00000100";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"00000080";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"00000088";
      exp_store_addr(3) <= x"0000000C"; exp_store_data(3) <= x"00000080";

    elsif TEST_ID = 21 then
      exp_nstores <= 3;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"00000008";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"00000018";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"00000008";

    elsif TEST_ID = 22 then
      exp_nstores <= 3;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"0000000B";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"00000008";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"11111111";

    elsif TEST_ID = 23 then
      exp_nstores <= 3;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"00000003";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"00000008";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"22222222";

    elsif TEST_ID = 24 then
      exp_nstores <= 3;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"00000002";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"00000008";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"33333333";

    elsif TEST_ID = 25 then
      exp_nstores <= 4;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"0000000B";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"00000008";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"44444444";
      exp_store_addr(3) <= x"0000000C"; exp_store_data(3) <= x"55555555";

    elsif TEST_ID = 26 then
      exp_nstores <= 4;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"000000AA";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"80000007";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"00000038";
      exp_store_addr(3) <= x"0000000C"; exp_store_data(3) <= x"66666666";

    elsif TEST_ID = 27 then
      exp_nstores <= 3;
      exp_store_addr(0) <= x"00000000"; exp_store_data(0) <= x"00000002";
      exp_store_addr(1) <= x"00000004"; exp_store_data(1) <= x"00000030";
      exp_store_addr(2) <= x"00000008"; exp_store_data(2) <= x"77777777";

    elsif TEST_ID = 28 then
      exp_nstores <= 13;
      exp_store_addr(0)  <= x"00000000"; exp_store_data(0)  <= x"0000002A";
      exp_store_addr(1)  <= x"00000004"; exp_store_data(1)  <= x"12345678";
      exp_store_addr(2)  <= x"00000008"; exp_store_data(2)  <= x"12345678";
      exp_store_addr(3)  <= x"0000000C"; exp_store_data(3)  <= x"0000000C";
      exp_store_addr(4)  <= x"00000010"; exp_store_data(4)  <= x"00000111";
      exp_store_addr(5)  <= x"00000014"; exp_store_data(5)  <= x"00000040";
      exp_store_addr(6)  <= x"00000018"; exp_store_data(6)  <= x"00000050";
      exp_store_addr(7)  <= x"0000001C"; exp_store_data(7)  <= x"00000100";
      exp_store_addr(8)  <= x"00000020"; exp_store_data(8)  <= x"00000018";
      exp_store_addr(9)  <= x"00000024"; exp_store_data(9)  <= x"0000000B";
      exp_store_addr(10) <= x"00000028"; exp_store_data(10) <= x"00000444";
      exp_store_addr(11) <= x"00000030"; exp_store_data(11) <= x"00000002";
      exp_store_addr(12) <= x"00000034"; exp_store_data(12) <= x"00000777";

    elsif TEST_ID = 29 then
      exp_nstores <= 4;
      exp_store_addr(0) <= x"00000040"; exp_store_data(0) <= x"00000001";
      exp_store_addr(1) <= x"00000044"; exp_store_data(1) <= x"00000000";
      exp_store_addr(2) <= x"00000048"; exp_store_data(2) <= x"00000000";
      exp_store_addr(3) <= x"0000004C"; exp_store_data(3) <= x"0000007B";

    elsif TEST_ID = 30 then
      exp_nstores <= 3;
      exp_store_addr(0) <= x"00000040"; exp_store_data(0) <= x"00000001";
      exp_store_addr(1) <= x"00000044"; exp_store_data(1) <= x"00000000";
      exp_store_addr(2) <= x"00000048"; exp_store_data(2) <= x"0000007B";

    elsif TEST_ID = 31 then
      exp_nstores <= 0;

    elsif TEST_ID = 32 then
      exp_nstores <= 3;
      exp_store_addr(0) <= x"00000000";
      exp_store_data(0) <= x"00000011";
      exp_store_addr(1) <= x"00000040";
      exp_store_data(1) <= x"00000001";
      exp_store_addr(2) <= x"00000044";
      exp_store_data(2) <= x"0000007B";

    elsif TEST_ID = 33 then
      exp_nstores <= 3;
      exp_store_addr(0) <= x"00000000";
      exp_store_data(0) <= x"00000011";
      exp_store_addr(1) <= x"00000040";
      exp_store_data(1) <= x"00000001";
      exp_store_addr(2) <= x"00000044";
      exp_store_data(2) <= x"0000007B";

    elsif TEST_ID = 34 then
      exp_nstores <= 4;
      exp_store_addr(0) <= x"00000020"; exp_store_data(0) <= x"0000000A";
      exp_store_addr(1) <= x"00000000"; exp_store_data(1) <= x"0000000D";
      exp_store_addr(2) <= x"00000040"; exp_store_data(2) <= x"00000001";
      exp_store_addr(3) <= x"00000044"; exp_store_data(3) <= x"0000007B";

    elsif TEST_ID = 35 then
      exp_nstores <= 4;
      exp_store_addr(0) <= x"00000020"; exp_store_data(0) <= x"0000000A";
      exp_store_addr(1) <= x"00000000"; exp_store_data(1) <= x"00000005";
      exp_store_addr(2) <= x"00000040"; exp_store_data(2) <= x"00000001";
      exp_store_addr(3) <= x"00000044"; exp_store_data(3) <= x"0000007B";

    elsif TEST_ID = 36 then
      exp_nstores <= 1;
      exp_store_addr(0) <= x"00000000";
      exp_store_data(0) <= x"0000000D";

    else
      assert false report "Unknown TEST_ID" severity failure;
    end if;

    ------------------------------------------------------------------
    -- Load payload bytes
    ------------------------------------------------------------------
    load_payload_file(select_payload_file(TEST_ID), bytes, len);
    build_expected_words(bytes, len, words, nwords);

    expected_nwords <= nwords;
    for i in 0 to MAX_WORDS-1 loop
      expected_words(i) <= words(i);
    end loop;

    report "Loaded payload: file=" & select_payload_file(TEST_ID) &
           " len=" & integer'image(len) &
           " => nwords=" & integer'image(nwords) &
           " TEST_ID=" & integer'image(TEST_ID)
      severity note;

    ------------------------------------------------------------------
    -- Reset
    ------------------------------------------------------------------
    uart_rx_i <= '1';
    reset <= '1';
    wait for 50*CLK_PERIOD;
    reset <= '0';
    wait for 50*CLK_PERIOD;

    ------------------------------------------------------------------
    -- Send boot stream
    ------------------------------------------------------------------
    uart_send_byte(uart_rx_i, x"55");
    uart_send_byte(uart_rx_i, x"AA");
    uart_send_u32_le(uart_rx_i, len);

    for i in 0 to len-1 loop
      uart_send_byte(uart_rx_i, bytes(i));
    end loop;

    total_bytes := len + 6;
    timeout_t := (total_bytes * 10) * BIT_TIME + 2 ms;

    report "Waiting for boot_done (timeout " & time'image(timeout_t) & ")" severity note;

    wait for 1 us;
    if boot_done_o /= '1' then
      wait for timeout_t;
    end if;

    assert boot_done_o = '1'
      report "Timeout: boot_done_o did not assert"
      severity failure;

    report "OK: boot_done asserted and IMEM verified." severity note;

    ------------------------------------------------------------------
    -- Wait for expected stores / marker
    ------------------------------------------------------------------
    if TEST_ID = 8 then
      wait until marker_seen = '1' for 100000 us;
      assert marker_seen = '1'
        report "Timeout: did not observe Timer IRQ marker"
        severity failure;

    elsif TEST_ID = 11 then
      wait until store_count = exp_nstores for 100000 us;
      assert store_count = exp_nstores
        report "Timeout: did not observe expected RAM stores in TEST 11"
        severity failure;

      assert timer_mmio_store_seen = '0'
        report "TEST 11 failed: timer MMIO leaked onto debug RAM write path"
        severity failure;

    elsif TEST_ID = 31 then
      wait until wd_reset_seen = '1' for 100000 us;
      assert wd_reset_seen = '1'
        report "Timeout: watchdog reset was not observed"
        severity failure;

    elsif TEST_ID = 36 then
      wait until store_count = exp_nstores for 100000 us;
      assert store_count = exp_nstores
        report "Timeout: did not observe expected store sequence in TEST 36"
        severity failure;

      wait for 20*CLK_PERIOD;

    else
      wait until store_count = exp_nstores for 100000 us;
      assert store_count = exp_nstores
        report "Timeout: did not observe expected store sequence"
        severity failure;
    end if;

    report "Simulation finished successfully." severity note;
    finish;
    wait;
  end process;

end architecture;
