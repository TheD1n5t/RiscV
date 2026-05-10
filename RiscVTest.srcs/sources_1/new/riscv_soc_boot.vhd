library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity riscv_soc_boot is
  generic(
    CLK_FREQ_HZ : integer := 50_000_000;
    BAUD        : integer := 115200;
    IMEM_WORDS  : integer := 4096;
    G_FAULT_INJECT : boolean := false;
    G_PC_TMR       : boolean := false;
    G_STATE_TMR    : boolean := false;
    G_RF_TMR       : boolean := false;
    G_RF_SELF_HEAL : boolean := false;
    G_IMEM_ECC     : boolean := false;
    G_DMEM_ECC     : boolean := false
  );
  port(
    clk       : in  std_logic;
    reset     : in  std_logic;
    uart_rx_i : in  std_logic;
    uart_tx_o : out std_logic;
    led0_o    : out std_logic;

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
    ext_dmem_wdata_i  : in std_logic_vector(31 downto 0) := (others => '0');

    -- Fault injection for PC TMR
    fi_pc_mask_i      : in std_logic_vector(31 downto 0) := (others => '0');
    fi_pc_target_i    : in std_logic_vector(1 downto 0)  := "00";
    fi_pc_strobe_i    : in std_logic := '0';
    fi_state_mask_i   : in std_logic_vector(3 downto 0)  := (others => '0');
    fi_state_target_i : in std_logic_vector(1 downto 0)  := "00";
    fi_state_strobe_i : in std_logic := '0';

    fi_dmem_mask_i    : in std_logic_vector(38 downto 0) := (others => '0');
    fi_dmem_addr_i    : in std_logic_vector(9 downto 0)  := (others => '0');
    fi_dmem_strobe_i  : in std_logic := '0';

    fi_rf_mask_i      : in std_logic_vector(31 downto 0) := (others => '0');
    fi_rf_addr_i      : in std_logic_vector(4 downto 0)  := (others => '0');
    fi_rf_target_i    : in std_logic_vector(1 downto 0)  := "00";
    fi_rf_strobe_i    : in std_logic := '0';

    -- Fault injection for IMEM
    fi_imem_mask_i    : in std_logic_vector(38 downto 0) := (others => '0');
    fi_imem_addr_i    : in std_logic_vector(11 downto 0) := (others => '0');
    fi_imem_strobe_i  : in std_logic := '0';

    -- Fault-monitor debug outputs for campaign testbenches
    pc_tmr_error_o          : out std_logic := '0';
    state_tmr_error_o       : out std_logic := '0';
    regfile_tmr_error_o     : out std_logic := '0';
    dmem_ecc_single_error_o : out std_logic := '0';
    dmem_ecc_double_error_o : out std_logic := '0';
    imem_ecc_single_error_o : out std_logic := '0';
    imem_ecc_double_error_o : out std_logic := '0'
  );
end entity;

architecture rtl of riscv_soc_boot is

  --------------------------------------------------------------------
  -- UART RX
  --------------------------------------------------------------------
  signal rx_byte  : std_logic_vector(7 downto 0);
  signal rx_valid : std_logic;

  --------------------------------------------------------------------
  -- Bootloader state
  --------------------------------------------------------------------
  type bl_state_t is (WAIT_55, WAIT_AA, LEN0, LEN1, LEN2, LEN3, DATA, DONE);
  signal bl_state : bl_state_t := WAIT_55;

  signal length_bytes : unsigned(31 downto 0) := (others => '0');
  signal bytes_rcvd   : unsigned(31 downto 0) := (others => '0');

  signal word_buf     : std_logic_vector(31 downto 0) := (others => '0');
  signal byte_in_word : integer range 0 to 3 := 0;
  signal word_index   : unsigned(31 downto 0) := (others => '0');

  signal prog_we      : std_logic := '0';
  signal prog_addr    : std_logic_vector(31 downto 0) := (others => '0');
  signal prog_wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal prog_we_mux   : std_logic;
  signal prog_addr_mux : std_logic_vector(31 downto 0);
  signal prog_wdata_mux : std_logic_vector(31 downto 0);

  signal boot_done    : std_logic := '0';
  signal boot_done_eff : std_logic;

  signal watchdog_reset         : std_logic := '0';
  signal watchdog_reset_stretch : unsigned(2 downto 0) := (others => '0');
  signal watchdog_reset_long    : std_logic := '0';
  signal cpu_reset_int          : std_logic;

  --------------------------------------------------------------------
  -- CPU / IMEM
  --------------------------------------------------------------------
  signal imem_pc    : std_logic_vector(31 downto 0);
  signal imem_instr : std_logic_vector(31 downto 0);
  signal imem_ecc_single_error : std_logic;
  signal imem_ecc_double_error : std_logic;
  signal imem_ecc_single_prev  : std_logic := '0';
  signal imem_ecc_double_prev  : std_logic := '0';
  signal imem_ecc_single_pulse : std_logic := '0';
  signal imem_ecc_double_pulse : std_logic := '0';

  --------------------------------------------------------------------
  -- CPU / DMEM
  --------------------------------------------------------------------
  signal dmem_we               : std_logic;
  signal dmem_addr             : std_logic_vector(31 downto 0);
  signal dmem_wdata            : std_logic_vector(31 downto 0);
  signal dmem_rdata            : std_logic_vector(31 downto 0);

  signal dmem_rdata_ram        : std_logic_vector(31 downto 0);
  signal dmem_we_ram           : std_logic;
  signal dmem_addr_ram         : std_logic_vector(31 downto 0);
  signal dmem_wdata_ram        : std_logic_vector(31 downto 0);
  signal dmem_ecc_single_error : std_logic;
  signal dmem_ecc_double_error : std_logic;

  signal dmem_ecc_single_prev  : std_logic := '0';
  signal dmem_ecc_double_prev  : std_logic := '0';
  signal dmem_ecc_single_pulse : std_logic := '0';
  signal dmem_ecc_double_pulse : std_logic := '0';

  signal pc_tmr_error          : std_logic;
  signal state_tmr_error       : std_logic;
  signal regfile_tmr_error     : std_logic;

  --------------------------------------------------------------------
  -- Timer MMIO
  --------------------------------------------------------------------
  signal irq_timer      : std_logic;
  signal timer_we       : std_logic;
  signal timer_addr     : std_logic_vector(31 downto 0);
  signal timer_rdata    : std_logic_vector(31 downto 0);
  signal timer_addr_sel : std_logic;

  --------------------------------------------------------------------
  -- UART TX MMIO
  --------------------------------------------------------------------
  signal uart_tx_start    : std_logic := '0';
  signal uart_tx_data     : std_logic_vector(7 downto 0) := (others => '0');
  signal uart_tx_busy     : std_logic;
  signal uart_tx_addr_sel : std_logic;
  signal uart_tx_we       : std_logic;
  signal uart_tx_rdata    : std_logic_vector(31 downto 0);

  --------------------------------------------------------------------
  -- Debug / keep-alive signals
  --------------------------------------------------------------------
  signal dbg_mix : std_logic_vector(31 downto 0);
  signal hb_cnt  : unsigned(25 downto 0) := (others => '0');
  signal led_reg : std_logic := '0';

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
  -- UART transmitter, memory mapped at 0x40002000
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
      tx    => uart_tx_o,
      busy  => uart_tx_busy
    );

  prog_we_mux    <= ext_imem_we_i    when ext_prog_mode_i = '1' else prog_we;
  prog_addr_mux  <= std_logic_vector(shift_right(unsigned(ext_imem_addr_i), 2))
                    when ext_prog_mode_i = '1' else prog_addr;
  prog_wdata_mux <= ext_imem_wdata_i when ext_prog_mode_i = '1' else prog_wdata;
  boot_done_eff  <= '1'              when ext_prog_mode_i = '1' else boot_done;

  --------------------------------------------------------------------
  -- Instruction memory
  --------------------------------------------------------------------
  u_imem : entity work.imem_dp_ram
    generic map(
      WORDS          => IMEM_WORDS,
      G_FAULT_INJECT => G_FAULT_INJECT,
      G_ECC_ENABLE   => G_IMEM_ECC
    )
    port map(
      clk              => clk,
      pc               => imem_pc,
      instr_out        => imem_instr,
      ecc_single_error => imem_ecc_single_error,
      ecc_double_error => imem_ecc_double_error,
      prog_we          => prog_we_mux,
      prog_addr        => prog_addr_mux,
      prog_wdata       => prog_wdata_mux,
      fi_imem_mask_i   => fi_imem_mask_i,
      fi_imem_addr_i   => fi_imem_addr_i,
      fi_imem_strobe_i => fi_imem_strobe_i
    );

  --------------------------------------------------------------------
  -- Data memory
  --------------------------------------------------------------------
  u_dmem : entity work.dmem
    generic map(
      G_FAULT_INJECT => G_FAULT_INJECT,
      G_ECC_ENABLE   => G_DMEM_ECC
    )
    port map(
      clk              => clk,
      we               => dmem_we_ram,
      addr             => dmem_addr_ram,
      data_in          => dmem_wdata_ram,
      data_out         => dmem_rdata_ram,
      ecc_single_error => dmem_ecc_single_error,
      ecc_double_error => dmem_ecc_double_error,
      fi_dmem_mask_i   => fi_dmem_mask_i,
      fi_dmem_addr_i   => fi_dmem_addr_i,
      fi_dmem_strobe_i => fi_dmem_strobe_i
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

  timer_addr_sel   <= '1' when dmem_addr(31 downto 12) = x"40001" else '0';
  uart_tx_addr_sel <= '1' when dmem_addr = x"40002000" else '0';
  timer_we       <= dmem_we and timer_addr_sel;
  uart_tx_we     <= dmem_we and uart_tx_addr_sel;
  dmem_we_ram    <= ext_dmem_we_i when (ext_prog_mode_i = '1' and ext_dmem_we_i = '1') else
                    dmem_we and (not timer_addr_sel) and (not uart_tx_addr_sel);
  dmem_addr_ram  <= ext_dmem_addr_i  when (ext_prog_mode_i = '1' and ext_dmem_we_i = '1') else dmem_addr;
  dmem_wdata_ram <= ext_dmem_wdata_i when (ext_prog_mode_i = '1' and ext_dmem_we_i = '1') else dmem_wdata;
  timer_addr     <= dmem_addr;
  uart_tx_rdata  <= (31 downto 2 => '0') & (not uart_tx_busy) & uart_tx_busy;

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
  -- DMEM/IMEM read mux + ECC edge detect
  --------------------------------------------------------------------
  dmem_rdata <= timer_rdata   when timer_addr_sel = '1' else
                uart_tx_rdata when uart_tx_addr_sel = '1' else
                dmem_rdata_ram;

  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        dmem_ecc_single_prev <= '0';
        dmem_ecc_double_prev <= '0';
        imem_ecc_single_prev <= '0';
        imem_ecc_double_prev <= '0';
      else
        dmem_ecc_single_prev <= dmem_ecc_single_error;
        dmem_ecc_double_prev <= dmem_ecc_double_error;
        imem_ecc_single_prev <= imem_ecc_single_error;
        imem_ecc_double_prev <= imem_ecc_double_error;
      end if;
    end if;
  end process;

  dmem_ecc_single_pulse <= dmem_ecc_single_error and not dmem_ecc_single_prev;
  dmem_ecc_double_pulse <= dmem_ecc_double_error and not dmem_ecc_double_prev;
  imem_ecc_single_pulse <= imem_ecc_single_error and not imem_ecc_single_prev;
  imem_ecc_double_pulse <= imem_ecc_double_error and not imem_ecc_double_prev;

  --------------------------------------------------------------------
  -- CPU core
  --------------------------------------------------------------------
  u_cpu : entity work.riscv_core_memless
    generic map(
      G_FAULT_INJECT => G_FAULT_INJECT,
      G_PC_TMR       => G_PC_TMR,
      G_STATE_TMR    => G_STATE_TMR,
      G_RF_TMR       => G_RF_TMR,
      G_RF_SELF_HEAL => G_RF_SELF_HEAL
    )
    port map(
      clk                     => clk,
      reset                   => cpu_reset_int,
      imem_pc                 => imem_pc,
      imem_instr              => imem_instr,
      dmem_we                 => dmem_we,
      dmem_addr               => dmem_addr,
      dmem_wdata              => dmem_wdata,
      dmem_rdata              => dmem_rdata,
      irq_timer_i             => irq_timer,
      fi_pc_mask_i            => fi_pc_mask_i,
      fi_pc_target_i          => fi_pc_target_i,
      fi_pc_strobe_i          => fi_pc_strobe_i,
      fi_state_mask_i         => fi_state_mask_i,
      fi_state_target_i       => fi_state_target_i,
      fi_state_strobe_i       => fi_state_strobe_i,
      fi_rf_mask_i            => fi_rf_mask_i,
      fi_rf_addr_i            => fi_rf_addr_i,
      fi_rf_target_i          => fi_rf_target_i,
      fi_rf_strobe_i          => fi_rf_strobe_i,
      watchdog_reset_o        => watchdog_reset,
      dmem_ecc_single_error_i => dmem_ecc_single_pulse,
      dmem_ecc_double_error_i => dmem_ecc_double_pulse,
      imem_ecc_single_error_i => imem_ecc_single_pulse,
      imem_ecc_double_error_i => imem_ecc_double_pulse,
      pc_tmr_error_o          => pc_tmr_error,
      state_tmr_error_o       => state_tmr_error,
      regfile_tmr_error_o     => regfile_tmr_error
    );

  --------------------------------------------------------------------
  -- Bootloader FSM
  --------------------------------------------------------------------
  process(clk)
    variable next_word : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk) then
      if reset = '1' then
        bl_state     <= WAIT_55;
        length_bytes <= (others => '0');
        bytes_rcvd   <= (others => '0');
        word_buf     <= (others => '0');
        byte_in_word <= 0;
        word_index   <= (others => '0');
        prog_we      <= '0';
        prog_addr    <= (others => '0');
        prog_wdata   <= (others => '0');
        boot_done    <= '0';
      else
        prog_we <= '0';

        case bl_state is

          when WAIT_55 =>
            boot_done <= '0';
            if rx_valid = '1' then
              if rx_byte = x"55" then
                bl_state <= WAIT_AA;
              end if;
            end if;

          when WAIT_AA =>
            if rx_valid = '1' then
              if rx_byte = x"AA" then
                bl_state <= LEN0;
              else
                bl_state <= WAIT_55;
              end if;
            end if;

          when LEN0 =>
            if rx_valid = '1' then
              length_bytes(7 downto 0) <= unsigned(rx_byte);
              bl_state <= LEN1;
            end if;

          when LEN1 =>
            if rx_valid = '1' then
              length_bytes(15 downto 8) <= unsigned(rx_byte);
              bl_state <= LEN2;
            end if;

          when LEN2 =>
            if rx_valid = '1' then
              length_bytes(23 downto 16) <= unsigned(rx_byte);
              bl_state <= LEN3;
            end if;

          when LEN3 =>
            if rx_valid = '1' then
              length_bytes(31 downto 24) <= unsigned(rx_byte);
              bytes_rcvd   <= (others => '0');
              word_index   <= (others => '0');
              byte_in_word <= 0;
              word_buf     <= (others => '0');
              bl_state     <= DATA;
            end if;

          when DATA =>
            if rx_valid = '1' then
              next_word := word_buf;

              case byte_in_word is
                when 0 =>
                  next_word(7 downto 0) := rx_byte;
                when 1 =>
                  next_word(15 downto 8) := rx_byte;
                when 2 =>
                  next_word(23 downto 16) := rx_byte;
                when others =>
                  next_word(31 downto 24) := rx_byte;
              end case;

              word_buf   <= next_word;
              bytes_rcvd <= bytes_rcvd + 1;

              if byte_in_word = 3 then
                prog_we      <= '1';
                prog_addr    <= std_logic_vector(word_index);
                prog_wdata   <= next_word;
                word_index   <= word_index + 1;
                byte_in_word <= 0;
                word_buf     <= (others => '0');
              else
                byte_in_word <= byte_in_word + 1;
              end if;

              if (bytes_rcvd + 1) = length_bytes then
                if byte_in_word /= 3 then
                  prog_we    <= '1';
                  prog_addr  <= std_logic_vector(word_index);
                  prog_wdata <= next_word;
                  word_index <= word_index + 1;
                end if;

                bl_state  <= DONE;
                boot_done <= '1';
              end if;
            end if;

          when DONE =>
            boot_done <= '1';

        end case;
      end if;
    end if;
  end process;

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
  led0_o <= led_reg;

  boot_done_o  <= boot_done_eff;
  boot_error_o <= '0';
  prog_we_o    <= prog_we_mux;
  prog_addr_o  <= prog_addr_mux;
  prog_wdata_o <= prog_wdata_mux;
  imem_pc_o    <= imem_pc;

  -- expose only real RAM writes, not timer MMIO writes
  dmem_we_o    <= dmem_we_ram;
  dmem_addr_o  <= dmem_addr;
  dmem_wdata_o <= dmem_wdata;

  pc_tmr_error_o          <= pc_tmr_error;
  state_tmr_error_o       <= state_tmr_error;
  regfile_tmr_error_o     <= regfile_tmr_error;
  dmem_ecc_single_error_o <= dmem_ecc_single_pulse;
  dmem_ecc_double_error_o <= dmem_ecc_double_pulse;
  imem_ecc_single_error_o <= imem_ecc_single_pulse;
  imem_ecc_double_error_o <= imem_ecc_double_pulse;

end rtl;
