library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;

library std;
use std.textio.all;
use std.env.all;

entity tb_fault_campaign is
  generic(
    CAMPAIGN_RUNS   : integer := 12;
    PAYLOAD_FILE    : string :=
      "D:/Documents/FAU/NanoSat/riscv_radhart_coll/RiscVFSM/hex_files/payload_fault_campaign.hex";
    EXPECTED_FILE   : string :=
      "D:/Documents/FAU/NanoSat/riscv_radhart_coll/RiscVFSM/hex_files/payload_fault_campaign.expected";
    G_PC_TMR        : boolean := true;
    G_STATE_TMR     : boolean := true;
    G_RF_TMR        : boolean := true;
    G_RF_SELF_HEAL  : boolean := true;
    G_IMEM_ECC      : boolean := true;
    G_DMEM_ECC      : boolean := true;
    G_FAULT_INJECT  : boolean := true
  );
end entity;

architecture sim of tb_fault_campaign is
  constant CLK_FREQ_HZ : integer := 50_000_000;
  constant BAUD_SIM    : integer := 1_000_000;
  constant IMEM_WORDS  : integer := 4096;
  constant MAX_BYTES   : integer := IMEM_WORDS * 4;
  constant MAX_WORDS   : integer := IMEM_WORDS;
  constant MAX_CYCLES  : integer := 1500;
  constant CLEAR_WORDS : integer := 256;
  constant FINISH_GRACE_CYCLES : integer := 32;
  constant MAX_EXPECTED_STORES : integer := 256;
  constant CLK_PERIOD  : time := 1 sec / CLK_FREQ_HZ;

  type byte_mem_t is array (0 to MAX_BYTES-1) of std_logic_vector(7 downto 0);
  type word_mem_t is array (0 to MAX_WORDS-1) of std_logic_vector(31 downto 0);
  type slv32_arr_t is array (0 to MAX_EXPECTED_STORES-1) of std_logic_vector(31 downto 0);

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

  signal ext_prog_mode  : std_logic := '1';
  signal ext_cpu_enable : std_logic := '0';
  signal ext_imem_we    : std_logic := '0';
  signal ext_imem_addr  : std_logic_vector(31 downto 0) := (others => '0');
  signal ext_imem_wdata : std_logic_vector(31 downto 0) := (others => '0');
  signal ext_dmem_we    : std_logic := '0';
  signal ext_dmem_addr  : std_logic_vector(31 downto 0) := (others => '0');
  signal ext_dmem_wdata : std_logic_vector(31 downto 0) := (others => '0');

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

  signal pc_tmr_error          : std_logic;
  signal state_tmr_error       : std_logic;
  signal regfile_tmr_error     : std_logic;
  signal dmem_ecc_single_error : std_logic;
  signal dmem_ecc_double_error : std_logic;
  signal imem_ecc_single_error : std_logic;
  signal imem_ecc_double_error : std_logic;

  signal payload_words  : word_mem_t := (others => (others => '0'));
  signal payload_nwords : integer := 0;

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

  function lfsr_next(x : unsigned(31 downto 0)) return unsigned is
    variable y : unsigned(31 downto 0) := x;
  begin
    y := y xor shift_left(y, 13);
    y := y xor shift_right(y, 17);
    y := y xor shift_left(y, 5);
    if y = 0 then
      y := x"1ACEB00C";
    end if;
    return y;
  end function;

  function imod(v : unsigned(31 downto 0); m : integer) return integer is
  begin
    return to_integer(v mod to_unsigned(m, 32));
  end function;

  procedure load_payload_file(
    constant filename : in string;
    variable words    : out word_mem_t;
    variable nwords   : out integer
  ) is
    file f           : text;
    variable fstatus : file_open_status;
    variable l       : line;
    variable b       : std_logic_vector(7 downto 0);
    variable bytes   : byte_mem_t := (others => (others => '0'));
    variable len     : integer := 0;
    variable nw      : integer := 0;
    variable w       : std_logic_vector(31 downto 0);
    variable idx     : integer;
  begin
    words := (others => (others => '0'));
    file_open(fstatus, f, filename, read_mode);

    assert fstatus = open_ok
      report "Could not open campaign payload file: " & filename
      severity failure;

    while not endfile(f) loop
      readline(f, l);
      if l'length /= 0 then
        hread(l, b);
        bytes(len) := b;
        len := len + 1;
      end if;
    end loop;

    file_close(f);
    nw := (len + 3) / 4;
    nwords := nw;

    for j in 0 to nw-1 loop
      w := (others => '0');
      for k in 0 to 3 loop
        idx := j*4 + k;
        if idx < len then
          case k is
            when 0 => w(7 downto 0) := bytes(idx);
            when 1 => w(15 downto 8) := bytes(idx);
            when 2 => w(23 downto 16) := bytes(idx);
            when others => w(31 downto 24) := bytes(idx);
          end case;
        end if;
      end loop;
      words(j) := w;
    end loop;
  end procedure;

  procedure load_expected_file(
    constant filename : in string;
    variable addrs    : out slv32_arr_t;
    variable data     : out slv32_arr_t;
    variable count    : out integer
  ) is
    file f           : text;
    variable fstatus : file_open_status;
    variable l       : line;
    variable a       : std_logic_vector(31 downto 0);
    variable d       : std_logic_vector(31 downto 0);
    variable n       : integer := 0;
  begin
    addrs := (others => (others => '0'));
    data  := (others => (others => '0'));
    file_open(fstatus, f, filename, read_mode);

    assert fstatus = open_ok
      report "Could not open campaign expected file: " & filename
      severity failure;

    while not endfile(f) loop
      readline(f, l);
      if l'length /= 0 then
        assert n < MAX_EXPECTED_STORES
          report "Too many expected campaign stores"
          severity failure;
        hread(l, a);
        hread(l, d);
        addrs(n) := a;
        data(n)  := d;
        n := n + 1;
      end if;
    end loop;

    file_close(f);
    count := n;
  end procedure;

  procedure clear_faults(
    signal pc_mask       : out std_logic_vector(31 downto 0);
    signal pc_target     : out std_logic_vector(1 downto 0);
    signal pc_strobe     : out std_logic;
    signal state_mask    : out std_logic_vector(3 downto 0);
    signal state_target  : out std_logic_vector(1 downto 0);
    signal state_strobe  : out std_logic;
    signal dmem_mask     : out std_logic_vector(38 downto 0);
    signal dmem_addr     : out std_logic_vector(9 downto 0);
    signal dmem_strobe   : out std_logic;
    signal rf_mask       : out std_logic_vector(31 downto 0);
    signal rf_addr       : out std_logic_vector(4 downto 0);
    signal rf_target     : out std_logic_vector(1 downto 0);
    signal rf_strobe     : out std_logic;
    signal imem_mask     : out std_logic_vector(38 downto 0);
    signal imem_addr     : out std_logic_vector(11 downto 0);
    signal imem_strobe   : out std_logic
  ) is
  begin
    pc_mask      <= (others => '0');
    pc_target    <= "00";
    pc_strobe    <= '0';
    state_mask   <= (others => '0');
    state_target <= "00";
    state_strobe <= '0';
    dmem_mask    <= (others => '0');
    dmem_addr    <= (others => '0');
    dmem_strobe  <= '0';
    rf_mask      <= (others => '0');
    rf_addr      <= (others => '0');
    rf_target    <= "00";
    rf_strobe    <= '0';
    imem_mask    <= (others => '0');
    imem_addr    <= (others => '0');
    imem_strobe  <= '0';
  end procedure;
begin

  clk <= not clk after CLK_PERIOD/2;

  uut: entity work.riscv_soc_boot
    generic map(
      CLK_FREQ_HZ     => CLK_FREQ_HZ,
      BAUD            => BAUD_SIM,
      IMEM_WORDS      => IMEM_WORDS,
      G_FAULT_INJECT  => G_FAULT_INJECT,
      G_PC_TMR        => G_PC_TMR,
      G_STATE_TMR     => G_STATE_TMR,
      G_RF_TMR        => G_RF_TMR,
      G_RF_SELF_HEAL  => G_RF_SELF_HEAL,
      G_IMEM_ECC      => G_IMEM_ECC,
      G_DMEM_ECC      => G_DMEM_ECC
    )
    port map(
      clk               => clk,
      reset             => reset,
      uart_rx_i         => uart_rx_i,
      uart_tx_o         => uart_tx_o,
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
      ext_prog_mode_i   => ext_prog_mode,
      ext_cpu_enable_i  => ext_cpu_enable,
      ext_imem_we_i     => ext_imem_we,
      ext_imem_addr_i   => ext_imem_addr,
      ext_imem_wdata_i  => ext_imem_wdata,
      ext_dmem_we_i     => ext_dmem_we,
      ext_dmem_addr_i   => ext_dmem_addr,
      ext_dmem_wdata_i  => ext_dmem_wdata,
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
      fi_imem_strobe_i  => fi_imem_strobe,
      pc_tmr_error_o          => pc_tmr_error,
      state_tmr_error_o       => state_tmr_error,
      regfile_tmr_error_o     => regfile_tmr_error,
      dmem_ecc_single_error_o => dmem_ecc_single_error,
      dmem_ecc_double_error_o => dmem_ecc_double_error,
      imem_ecc_single_error_o => imem_ecc_single_error,
      imem_ecc_double_error_o => imem_ecc_double_error
    );

  stim : process
    variable words_v       : word_mem_t;
    variable nwords_v      : integer;
    variable exp_addr_v    : slv32_arr_t;
    variable exp_data_v    : slv32_arr_t;
    variable exp_count_v   : integer;
    variable rnd           : unsigned(31 downto 0) := x"5EED1234";
    variable total_runs    : integer;
    variable masked_runs   : integer := 0;
    variable corrected_runs : integer := 0;
    variable uncorrectable_runs : integer := 0;
    variable failure_runs  : integer := 0;
    variable timeout_runs  : integer := 0;
    variable injected_runs : integer := 0;
    variable domain        : integer;
    variable target        : integer;
    variable bit_idx       : integer;
    variable addr_idx      : integer;
    variable inject_cycle  : integer;
    variable store_idx     : integer;
    variable finish_grace  : integer;
    variable signature_done : boolean;
    variable mismatch      : boolean;
    variable timeout       : boolean;
    variable did_inject    : boolean;
    variable corrected_seen : boolean;
    variable uncorrectable_seen : boolean;
    variable mask39        : std_logic_vector(38 downto 0);
    variable mask32        : std_logic_vector(31 downto 0);
    variable mask4         : std_logic_vector(3 downto 0);
    variable domain_name   : string(1 to 8);
  begin
    load_payload_file(PAYLOAD_FILE, words_v, nwords_v);
    load_expected_file(EXPECTED_FILE, exp_addr_v, exp_data_v, exp_count_v);
    payload_nwords <= nwords_v;
    for i in 0 to MAX_WORDS-1 loop
      payload_words(i) <= words_v(i);
    end loop;

    total_runs := CAMPAIGN_RUNS + 7;
    report "FAULT CAMPAIGN: payload words=" & integer'image(nwords_v) &
           " expected stores=" & integer'image(exp_count_v) &
           " deterministic=6 random=" & integer'image(CAMPAIGN_RUNS)
      severity note;
    report "FAULT CAMPAIGN CONFIG: " &
           "G_PC_TMR=" & boolean'image(G_PC_TMR) &
           " G_STATE_TMR=" & boolean'image(G_STATE_TMR) &
           " G_RF_TMR=" & boolean'image(G_RF_TMR) &
           " G_RF_SELF_HEAL=" & boolean'image(G_RF_SELF_HEAL) &
           " G_IMEM_ECC=" & boolean'image(G_IMEM_ECC) &
           " G_DMEM_ECC=" & boolean'image(G_DMEM_ECC) &
           " G_FAULT_INJECT=" & boolean'image(G_FAULT_INJECT)
      severity note;

    for run_id in 0 to total_runs-1 loop
      clear_faults(
        fi_pc_mask, fi_pc_target, fi_pc_strobe,
        fi_state_mask, fi_state_target, fi_state_strobe,
        fi_dmem_mask, fi_dmem_addr, fi_dmem_strobe,
        fi_rf_mask, fi_rf_addr, fi_rf_target, fi_rf_strobe,
        fi_imem_mask, fi_imem_addr, fi_imem_strobe
      );

      reset <= '1';
      ext_prog_mode  <= '1';
      ext_cpu_enable <= '0';
      ext_imem_we    <= '0';
      ext_dmem_we    <= '0';
      wait for 10*CLK_PERIOD;

      for i in 0 to CLEAR_WORDS-1 loop
        ext_dmem_addr  <= std_logic_vector(to_unsigned(i*4, 32));
        ext_dmem_wdata <= (others => '0');
        ext_dmem_we    <= '1';
        wait until rising_edge(clk);
      end loop;
      ext_dmem_we <= '0';

      for i in 0 to nwords_v-1 loop
        ext_imem_addr  <= std_logic_vector(to_unsigned(i*4, 32));
        ext_imem_wdata <= words_v(i);
        ext_imem_we    <= '1';
        wait until rising_edge(clk);
      end loop;
      ext_imem_we <= '0';
      wait until rising_edge(clk);

      if run_id = 0 then
        domain       := 0;
        inject_cycle := -1;
        domain_name  := "REF     ";
      elsif run_id = 1 then
        domain       := 1;
        target       := 0;
        bit_idx      := 2;
        inject_cycle := 35;
        domain_name  := "PC      ";
      elsif run_id = 2 then
        domain       := 2;
        target       := 1;
        bit_idx      := 0;
        inject_cycle := 35;
        domain_name  := "STATE   ";
      elsif run_id = 3 then
        domain       := 3;
        target       := 1;
        bit_idx      := 3;
        addr_idx     := 5;
        inject_cycle := 45;
        domain_name  := "RF      ";
      elsif run_id = 4 then
        domain       := 4;
        bit_idx      := 10;
        addr_idx     := 0;
        inject_cycle := 30;
        domain_name  := "DMEM    ";
      elsif run_id = 5 then
        domain       := 5;
        bit_idx      := 8;
        addr_idx     := 2;
        inject_cycle := 1;
        domain_name  := "IMEM    ";
      elsif run_id = 6 then
        domain       := 6;
        bit_idx      := 8;
        addr_idx     := 0;
        inject_cycle := 1;
        domain_name  := "IMEM2   ";
      else
        rnd := lfsr_next(rnd);
        domain := 1 + imod(rnd, 5);
        rnd := lfsr_next(rnd);
        target := imod(rnd, 3);
        rnd := lfsr_next(rnd);
        inject_cycle := 10 + imod(rnd, 120);
        rnd := lfsr_next(rnd);

        case domain is
          when 1 =>
            bit_idx := imod(rnd, 8);
            domain_name := "PC-RND  ";
          when 2 =>
            bit_idx := imod(rnd, 4);
            domain_name := "ST-RND  ";
          when 3 =>
            bit_idx := imod(rnd, 8);
            rnd := lfsr_next(rnd);
            addr_idx := 1 + imod(rnd, 15);
            domain_name := "RF-RND  ";
          when 4 =>
            bit_idx := imod(rnd, 39);
            rnd := lfsr_next(rnd);
            addr_idx := imod(rnd, 64);
            domain_name := "DM-RND  ";
          when others =>
            bit_idx := imod(rnd, 39);
            rnd := lfsr_next(rnd);
            addr_idx := imod(rnd, nwords_v);
            domain_name := "IM-RND  ";
        end case;
      end if;

      report "CAMPAIGN RUN " & integer'image(run_id) &
             " domain=" & domain_name &
             " inject_cycle=" & integer'image(inject_cycle)
        severity note;

      store_idx  := 0;
      finish_grace := 0;
      signature_done := false;
      mismatch   := false;
      timeout    := false;
      did_inject := false;
      corrected_seen := false;
      uncorrectable_seen := false;

      wait until rising_edge(clk);
      reset <= '0';
      ext_prog_mode  <= '1';
      ext_cpu_enable <= '1';

      for cycle in 0 to MAX_CYCLES loop
        wait until rising_edge(clk);

        if pc_tmr_error = '1' or state_tmr_error = '1' or regfile_tmr_error = '1' or
           dmem_ecc_single_error = '1' or imem_ecc_single_error = '1' then
          corrected_seen := true;
        end if;

        if dmem_ecc_double_error = '1' or imem_ecc_double_error = '1' then
          uncorrectable_seen := true;
        end if;

        if cycle = inject_cycle then
          did_inject := true;
          injected_runs := injected_runs + 1;

          mask39 := (others => '0');
          mask32 := (others => '0');
          mask4  := (others => '0');

          case domain is
            when 1 =>
              mask32(bit_idx) := '1';
              fi_pc_mask   <= mask32;
              fi_pc_target <= std_logic_vector(to_unsigned(target, 2));
              fi_pc_strobe <= '1';

            when 2 =>
              mask4(bit_idx) := '1';
              fi_state_mask   <= mask4;
              fi_state_target <= std_logic_vector(to_unsigned(target, 2));
              fi_state_strobe <= '1';

            when 3 =>
              mask32(bit_idx) := '1';
              fi_rf_mask   <= mask32;
              fi_rf_addr   <= std_logic_vector(to_unsigned(addr_idx, 5));
              fi_rf_target <= std_logic_vector(to_unsigned(target, 2));
              fi_rf_strobe <= '1';

            when 4 =>
              mask39(bit_idx) := '1';
              fi_dmem_mask   <= mask39;
              fi_dmem_addr   <= std_logic_vector(to_unsigned(addr_idx, 10));
              fi_dmem_strobe <= '1';

            when 5 =>
              mask39(bit_idx) := '1';
              fi_imem_mask   <= mask39;
              fi_imem_addr   <= std_logic_vector(to_unsigned(addr_idx, 12));
              fi_imem_strobe <= '1';

            when 6 =>
              mask39(8) := '1';
              fi_imem_mask   <= mask39;
              fi_imem_addr   <= std_logic_vector(to_unsigned(addr_idx, 12));
              fi_imem_strobe <= '1';

            when others =>
              null;
          end case;

        elsif domain = 6 and cycle = inject_cycle + 1 then
          mask39 := (others => '0');
          mask39(9) := '1';
          fi_imem_mask   <= mask39;
          fi_imem_addr   <= std_logic_vector(to_unsigned(addr_idx, 12));
          fi_imem_strobe <= '1';

        elsif did_inject then
          clear_faults(
            fi_pc_mask, fi_pc_target, fi_pc_strobe,
            fi_state_mask, fi_state_target, fi_state_strobe,
            fi_dmem_mask, fi_dmem_addr, fi_dmem_strobe,
            fi_rf_mask, fi_rf_addr, fi_rf_target, fi_rf_strobe,
            fi_imem_mask, fi_imem_addr, fi_imem_strobe
          );
          did_inject := false;
        end if;

        if dmem_we_o = '1' then
          if store_idx < exp_count_v then
            if dmem_addr_o /= exp_addr_v(store_idx) or dmem_wdata_o /= exp_data_v(store_idx) then
              report "RUN " & integer'image(run_id) &
                     " mismatch store=" & integer'image(store_idx) &
                     " addr=0x" & slv_to_hex(dmem_addr_o) &
                     " data=0x" & slv_to_hex(dmem_wdata_o)
                severity note;
              mismatch := true;
            end if;
          else
            report "RUN " & integer'image(run_id) &
                   " extra store=" & integer'image(store_idx) &
                   " addr=0x" & slv_to_hex(dmem_addr_o) &
                   " data=0x" & slv_to_hex(dmem_wdata_o)
              severity note;
            mismatch := true;
          end if;

          store_idx := store_idx + 1;

          if store_idx = exp_count_v and not signature_done then
            signature_done := true;
            exit;
          end if;
        end if;

        if signature_done then
          if finish_grace = 0 then
            exit;
          else
            finish_grace := finish_grace - 1;
          end if;
        end if;

        if cycle = MAX_CYCLES then
          timeout := true;
        end if;
      end loop;

      if timeout then
        timeout_runs := timeout_runs + 1;
        report "RUN " & integer'image(run_id) & " outcome=TIMEOUT stores=" &
               integer'image(store_idx) &
               " corrected_seen=" & boolean'image(corrected_seen) &
               " uncorrectable_seen=" & boolean'image(uncorrectable_seen)
          severity note;
      elsif store_idx < exp_count_v then
        failure_runs := failure_runs + 1;
        report "RUN " & integer'image(run_id) & " outcome=FAILURE stores=" &
               integer'image(store_idx) &
               " expected=" & integer'image(exp_count_v) &
               " corrected_seen=" & boolean'image(corrected_seen) &
               " uncorrectable_seen=" & boolean'image(uncorrectable_seen)
          severity note;
      elsif mismatch then
        failure_runs := failure_runs + 1;
        report "RUN " & integer'image(run_id) & " outcome=FAILURE stores=" &
               integer'image(store_idx) &
               " corrected_seen=" & boolean'image(corrected_seen) &
               " uncorrectable_seen=" & boolean'image(uncorrectable_seen)
          severity note;
      elsif uncorrectable_seen then
        uncorrectable_runs := uncorrectable_runs + 1;
        report "RUN " & integer'image(run_id) & " outcome=UNCORRECTABLE stores=" &
               integer'image(store_idx) &
               " corrected_seen=" & boolean'image(corrected_seen)
          severity note;
      elsif corrected_seen then
        corrected_runs := corrected_runs + 1;
        report "RUN " & integer'image(run_id) & " outcome=CORRECTED stores=" &
               integer'image(store_idx)
          severity note;
      else
        masked_runs := masked_runs + 1;
        report "RUN " & integer'image(run_id) & " outcome=MASKED stores=" &
               integer'image(store_idx)
          severity note;
      end if;
    end loop;

    report "FAULT CAMPAIGN SUMMARY: total=" & integer'image(total_runs) &
           " injected=" & integer'image(injected_runs) &
           " masked=" & integer'image(masked_runs) &
           " corrected=" & integer'image(corrected_runs) &
           " uncorrectable=" & integer'image(uncorrectable_runs) &
           " failures=" & integer'image(failure_runs) &
           " timeouts=" & integer'image(timeout_runs)
      severity note;

    assert (masked_runs + corrected_runs + uncorrectable_runs) > 0
      report "Campaign did not complete any successful run"
      severity failure;

    finish;
    wait;
  end process;

end architecture;
