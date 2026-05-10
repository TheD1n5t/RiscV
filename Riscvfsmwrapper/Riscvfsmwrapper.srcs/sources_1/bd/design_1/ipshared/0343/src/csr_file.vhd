library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity csr_file is
  port (
    clk           : in  std_logic;
    rst           : in  std_logic;

    csr_en        : in  std_logic;
    csr_we        : in  std_logic;
    csr_addr      : in  std_logic_vector(11 downto 0);
    csr_wdata     : in  std_logic_vector(31 downto 0);
    csr_cmd       : in  std_logic_vector(1 downto 0);
    csr_rdata     : out std_logic_vector(31 downto 0);

    trap_enter    : in  std_logic;
    trap_pc_in    : in  std_logic_vector(31 downto 0);
    trap_cause_in : in  std_logic_vector(31 downto 0);
    mret_exec     : in  std_logic;
    timer_irq_i   : in  std_logic;

    -- TMR error inputs
    pc_tmr_error_i    : in std_logic;
    state_tmr_error_i : in std_logic;
    csr_tmr_error_i   : in std_logic;

    -- Watchdog output
    watchdog_reset_o  : out std_logic;

    mtvec_out     : out std_logic_vector(31 downto 0);
    mie_out       : out std_logic_vector(31 downto 0);
    mip_out       : out std_logic_vector(31 downto 0);
    mstatus_out   : out std_logic_vector(31 downto 0);
    mepc_out      : out std_logic_vector(31 downto 0);

    dmem_ecc_single_error_i : in std_logic;
    dmem_ecc_double_error_i : in std_logic;
    imem_ecc_single_error_i : in std_logic;
    imem_ecc_double_error_i : in std_logic
  );
end entity;

architecture rtl of csr_file is

  constant CSR_MSTATUS : std_logic_vector(11 downto 0) := x"300";
  constant CSR_MIE     : std_logic_vector(11 downto 0) := x"304";
  constant CSR_MTVEC   : std_logic_vector(11 downto 0) := x"305";
  constant CSR_MEPC    : std_logic_vector(11 downto 0) := x"341";
  constant CSR_MCAUSE  : std_logic_vector(11 downto 0) := x"342";
  constant CSR_MIP     : std_logic_vector(11 downto 0) := x"344";

  -- telemetry
  constant CSR_PC_TMR_ERR      : std_logic_vector(11 downto 0) := x"7C0";
  constant CSR_STATE_TMR_ERR   : std_logic_vector(11 downto 0) := x"7C1";
  constant CSR_CSR_TMR_ERR     : std_logic_vector(11 downto 0) := x"7C2";
  constant CSR_DMEM_ECC_SINGLE : std_logic_vector(11 downto 0) := x"7C3";
  constant CSR_DMEM_ECC_DOUBLE : std_logic_vector(11 downto 0) := x"7C4";
  constant CSR_IMEM_ECC_SINGLE : std_logic_vector(11 downto 0) := x"7C5";
  constant CSR_IMEM_ECC_DOUBLE : std_logic_vector(11 downto 0) := x"7C6";

  -- watchdog
  constant CSR_WDOG_CTRL   : std_logic_vector(11 downto 0) := x"7D0";
  constant CSR_WDOG_RELOAD : std_logic_vector(11 downto 0) := x"7D1";
  constant CSR_WDOG_COUNT  : std_logic_vector(11 downto 0) := x"7D2";

  ---------------------------------------------------------
  -- TMR registers
  ---------------------------------------------------------
  signal mstatus_a, mstatus_b, mstatus_c : std_logic_vector(31 downto 0);
  signal mie_a, mie_b, mie_c             : std_logic_vector(31 downto 0);
  signal mtvec_a, mtvec_b, mtvec_c       : std_logic_vector(31 downto 0);
  signal mepc_a, mepc_b, mepc_c          : std_logic_vector(31 downto 0);
  signal mcause_a, mcause_b, mcause_c    : std_logic_vector(31 downto 0);

  signal mstatus_v, mie_v, mtvec_v, mepc_v, mcause_v : std_logic_vector(31 downto 0);

  ---------------------------------------------------------
  -- error counters
  ---------------------------------------------------------
  signal pc_tmr_error_cnt      : unsigned(31 downto 0) := (others => '0');
  signal state_tmr_error_cnt   : unsigned(31 downto 0) := (others => '0');
  signal csr_tmr_error_cnt     : unsigned(31 downto 0) := (others => '0');
  signal dmem_ecc_single_cnt   : unsigned(31 downto 0) := (others => '0');
  signal dmem_ecc_double_cnt   : unsigned(31 downto 0) := (others => '0');
  signal imem_ecc_single_cnt   : unsigned(31 downto 0) := (others => '0');
  signal imem_ecc_double_cnt   : unsigned(31 downto 0) := (others => '0');

  ---------------------------------------------------------
  -- watchdog
  ---------------------------------------------------------
  signal wdog_enable      : std_logic := '0';
  signal wdog_timeout     : std_logic := '0';
  signal wdog_reload      : unsigned(31 downto 0) := (others => '0');
  signal wdog_count       : unsigned(31 downto 0) := (others => '0');
  signal watchdog_reset_r : std_logic := '0';

  ---------------------------------------------------------
  signal mip         : std_logic_vector(31 downto 0);
  signal csr_current : std_logic_vector(31 downto 0);
  signal write_value : std_logic_vector(31 downto 0);
  signal rdata_reg   : std_logic_vector(31 downto 0);

  ---------------------------------------------------------
  -- Majority voters
  ---------------------------------------------------------
  function vote(a, b, c : std_logic_vector(31 downto 0)) return std_logic_vector is
  begin
    if (a = b) or (a = c) then
      return a;
    elsif b = c then
      return b;
    else
      return a;
    end if;
  end function;

begin

  mstatus_v <= vote(mstatus_a, mstatus_b, mstatus_c);
  mie_v     <= vote(mie_a, mie_b, mie_c);
  mtvec_v   <= vote(mtvec_a, mtvec_b, mtvec_c);
  mepc_v    <= vote(mepc_a, mepc_b, mepc_c);
  mcause_v  <= vote(mcause_a, mcause_b, mcause_c);

  ---------------------------------------------------------
  -- mip interrupt reflection
  ---------------------------------------------------------
  mip <= (31 downto 8 => '0') & timer_irq_i & (6 downto 0 => '0');

  ---------------------------------------------------------
  -- CSR select
  ---------------------------------------------------------
  process(csr_addr, mstatus_v, mie_v, mtvec_v, mepc_v, mcause_v, mip)
  begin
    case csr_addr is
      when CSR_MSTATUS => csr_current <= mstatus_v;
      when CSR_MIE     => csr_current <= mie_v;
      when CSR_MTVEC   => csr_current <= mtvec_v;
      when CSR_MEPC    => csr_current <= mepc_v;
      when CSR_MCAUSE  => csr_current <= mcause_v;
      when CSR_MIP     => csr_current <= mip;
      when others      => csr_current <= (others => '0');
    end case;
  end process;

  ---------------------------------------------------------
  -- write logic
  ---------------------------------------------------------
  process(csr_current, csr_wdata, csr_cmd)
  begin
    case csr_cmd is
      when "00"   => write_value <= csr_wdata;
      when "01"   => write_value <= csr_current or csr_wdata;
      when "10"   => write_value <= csr_current and not csr_wdata;
      when others => write_value <= csr_current;
    end case;
  end process;

  ---------------------------------------------------------
  -- read logic
  ---------------------------------------------------------
  process(
    csr_en, csr_addr,
    mstatus_v, mie_v, mtvec_v, mepc_v, mcause_v, mip,
    pc_tmr_error_cnt, state_tmr_error_cnt, csr_tmr_error_cnt,
    wdog_enable, wdog_timeout, wdog_reload, wdog_count,
    dmem_ecc_single_cnt, dmem_ecc_double_cnt,
    imem_ecc_single_cnt, imem_ecc_double_cnt
  )
    variable wdog_ctrl_rd : std_logic_vector(31 downto 0);
  begin
    rdata_reg <= (others => '0');
    wdog_ctrl_rd := (others => '0');

    wdog_ctrl_rd(0) := wdog_enable;
    wdog_ctrl_rd(1) := wdog_timeout;
    -- bit 2 = kick, write-only, therefore read as 0

    if csr_en = '1' then
      case csr_addr is
        when CSR_MSTATUS =>
          rdata_reg <= mstatus_v;

        when CSR_MIE =>
          rdata_reg <= mie_v;

        when CSR_MTVEC =>
          rdata_reg <= mtvec_v;

        when CSR_MEPC =>
          rdata_reg <= mepc_v;

        when CSR_MCAUSE =>
          rdata_reg <= mcause_v;

        when CSR_MIP =>
          rdata_reg <= mip;

        when CSR_PC_TMR_ERR =>
          rdata_reg <= std_logic_vector(pc_tmr_error_cnt);

        when CSR_STATE_TMR_ERR =>
          rdata_reg <= std_logic_vector(state_tmr_error_cnt);

        when CSR_CSR_TMR_ERR =>
          rdata_reg <= std_logic_vector(csr_tmr_error_cnt);

        when CSR_DMEM_ECC_SINGLE =>
          rdata_reg <= std_logic_vector(dmem_ecc_single_cnt);

        when CSR_DMEM_ECC_DOUBLE =>
          rdata_reg <= std_logic_vector(dmem_ecc_double_cnt);

        when CSR_IMEM_ECC_SINGLE =>
          rdata_reg <= std_logic_vector(imem_ecc_single_cnt);

        when CSR_IMEM_ECC_DOUBLE =>
          rdata_reg <= std_logic_vector(imem_ecc_double_cnt);

        when CSR_WDOG_CTRL =>
          rdata_reg <= wdog_ctrl_rd;

        when CSR_WDOG_RELOAD =>
          rdata_reg <= std_logic_vector(wdog_reload);

        when CSR_WDOG_COUNT =>
          rdata_reg <= std_logic_vector(wdog_count);

        when others =>
          rdata_reg <= (others => '0');
      end case;
    end if;
  end process;

  csr_rdata <= rdata_reg;

  ---------------------------------------------------------
  -- main sequential logic
  ---------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then

      -- default: watchdog reset pulse is one clock long
      watchdog_reset_r <= '0';

      if rst = '1' then

        mstatus_a <= (others => '0');
        mstatus_b <= (others => '0');
        mstatus_c <= (others => '0');

        mie_a <= (others => '0');
        mie_b <= (others => '0');
        mie_c <= (others => '0');

        mtvec_a <= (others => '0');
        mtvec_b <= (others => '0');
        mtvec_c <= (others => '0');

        mepc_a <= (others => '0');
        mepc_b <= (others => '0');
        mepc_c <= (others => '0');

        mcause_a <= (others => '0');
        mcause_b <= (others => '0');
        mcause_c <= (others => '0');

        pc_tmr_error_cnt    <= (others => '0');
        state_tmr_error_cnt <= (others => '0');
        csr_tmr_error_cnt   <= (others => '0');

        dmem_ecc_single_cnt <= (others => '0');
        dmem_ecc_double_cnt <= (others => '0');
        imem_ecc_single_cnt <= (others => '0');
        imem_ecc_double_cnt <= (others => '0');

        wdog_enable      <= '0';
        wdog_timeout     <= '0';
        wdog_reload      <= (others => '0');
        wdog_count       <= (others => '0');
        watchdog_reset_r <= '0';

      else

        --------------------------------------------------
        -- trap / mret / CSR write logic
        --------------------------------------------------
        if trap_enter = '1' then

          mepc_a <= trap_pc_in;
          mepc_b <= trap_pc_in;
          mepc_c <= trap_pc_in;

          mcause_a <= trap_cause_in;
          mcause_b <= trap_cause_in;
          mcause_c <= trap_cause_in;

          mstatus_a(7) <= mstatus_v(3);
          mstatus_b(7) <= mstatus_v(3);
          mstatus_c(7) <= mstatus_v(3);

          mstatus_a(3) <= '0';
          mstatus_b(3) <= '0';
          mstatus_c(3) <= '0';

        elsif mret_exec = '1' then

          mstatus_a(3) <= mstatus_v(7);
          mstatus_b(3) <= mstatus_v(7);
          mstatus_c(3) <= mstatus_v(7);

          mstatus_a(7) <= '1';
          mstatus_b(7) <= '1';
          mstatus_c(7) <= '1';

        elsif csr_en = '1' and csr_we = '1' then

          case csr_addr is

            when CSR_MSTATUS =>
              mstatus_a <= write_value;
              mstatus_b <= write_value;
              mstatus_c <= write_value;

            when CSR_MIE =>
              mie_a <= write_value;
              mie_b <= write_value;
              mie_c <= write_value;

            when CSR_MTVEC =>
              mtvec_a <= write_value;
              mtvec_b <= write_value;
              mtvec_c <= write_value;

            when CSR_MEPC =>
              mepc_a <= write_value;
              mepc_b <= write_value;
              mepc_c <= write_value;

            when CSR_MCAUSE =>
              mcause_a <= write_value;
              mcause_b <= write_value;
              mcause_c <= write_value;

            when CSR_WDOG_CTRL =>
              wdog_enable <= write_value(0);

              if write_value(1) = '0' then
                wdog_timeout <= '0';
              end if;

              if write_value(2) = '1' then
                wdog_count <= wdog_reload;
              end if;

            when CSR_WDOG_RELOAD =>
              wdog_reload <= unsigned(write_value);

            when CSR_WDOG_COUNT =>
              wdog_count <= unsigned(write_value);

            when others =>
              null;

          end case;
        end if;

        --------------------------------------------------
        -- error counters
        --------------------------------------------------
        if pc_tmr_error_i = '1' then
          if pc_tmr_error_cnt /= x"FFFFFFFF" then
            pc_tmr_error_cnt <= pc_tmr_error_cnt + 1;
          end if;
        end if;

        if state_tmr_error_i = '1' then
          if state_tmr_error_cnt /= x"FFFFFFFF" then
            state_tmr_error_cnt <= state_tmr_error_cnt + 1;
          end if;
        end if;

        if csr_tmr_error_i = '1' then
          if csr_tmr_error_cnt /= x"FFFFFFFF" then
            csr_tmr_error_cnt <= csr_tmr_error_cnt + 1;
          end if;
        end if;

        if dmem_ecc_single_error_i = '1' then
          if dmem_ecc_single_cnt /= x"FFFFFFFF" then
            dmem_ecc_single_cnt <= dmem_ecc_single_cnt + 1;
          end if;
        end if;

        if dmem_ecc_double_error_i = '1' then
          if dmem_ecc_double_cnt /= x"FFFFFFFF" then
            dmem_ecc_double_cnt <= dmem_ecc_double_cnt + 1;
          end if;
        end if;

        if imem_ecc_single_error_i = '1' then
          if imem_ecc_single_cnt /= x"FFFFFFFF" then
            imem_ecc_single_cnt <= imem_ecc_single_cnt + 1;
          end if;
        end if;

        if imem_ecc_double_error_i = '1' then
          if imem_ecc_double_cnt /= x"FFFFFFFF" then
            imem_ecc_double_cnt <= imem_ecc_double_cnt + 1;
          end if;
        end if;

        --------------------------------------------------
        -- watchdog countdown
        --------------------------------------------------
        if wdog_enable = '1' then
          if wdog_count /= 0 then
            wdog_count <= wdog_count - 1;
          else
            wdog_timeout     <= '1';
            watchdog_reset_r <= '1';
          end if;
        end if;

      end if;
    end if;
  end process;

  ---------------------------------------------------------
  watchdog_reset_o <= watchdog_reset_r;

  mtvec_out   <= mtvec_v;
  mie_out     <= mie_v;
  mip_out     <= mip;
  mstatus_out <= mstatus_v;
  mepc_out    <= mepc_v;

end architecture;
