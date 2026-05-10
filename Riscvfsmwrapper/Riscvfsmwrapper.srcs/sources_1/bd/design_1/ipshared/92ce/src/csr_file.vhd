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

    watchdog_reset_o : out std_logic;

    mtvec_out   : out std_logic_vector(31 downto 0);
    mie_out     : out std_logic_vector(31 downto 0);
    mip_out     : out std_logic_vector(31 downto 0);
    mstatus_out : out std_logic_vector(31 downto 0);
    mepc_out    : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of csr_file is

  constant CSR_MSTATUS : std_logic_vector(11 downto 0) := x"300";
  constant CSR_MIE     : std_logic_vector(11 downto 0) := x"304";
  constant CSR_MTVEC   : std_logic_vector(11 downto 0) := x"305";
  constant CSR_MEPC    : std_logic_vector(11 downto 0) := x"341";
  constant CSR_MCAUSE  : std_logic_vector(11 downto 0) := x"342";
  constant CSR_MIP     : std_logic_vector(11 downto 0) := x"344";

  constant CSR_WDOG_CTRL   : std_logic_vector(11 downto 0) := x"7D0";
  constant CSR_WDOG_RELOAD : std_logic_vector(11 downto 0) := x"7D1";
  constant CSR_WDOG_COUNT  : std_logic_vector(11 downto 0) := x"7D2";

  signal mstatus : std_logic_vector(31 downto 0) := (others => '0');
  signal mie     : std_logic_vector(31 downto 0) := (others => '0');
  signal mtvec   : std_logic_vector(31 downto 0) := (others => '0');
  signal mepc    : std_logic_vector(31 downto 0) := (others => '0');
  signal mcause  : std_logic_vector(31 downto 0) := (others => '0');

  signal wdog_enable      : std_logic := '0';
  signal wdog_timeout     : std_logic := '0';
  signal wdog_reload      : unsigned(31 downto 0) := (others => '0');
  signal wdog_count       : unsigned(31 downto 0) := (others => '0');
  signal watchdog_reset_r : std_logic := '0';

  signal mip         : std_logic_vector(31 downto 0);
  signal csr_current : std_logic_vector(31 downto 0);
  signal write_value : std_logic_vector(31 downto 0);
  signal rdata_reg   : std_logic_vector(31 downto 0);

begin

  mip <= (31 downto 8 => '0') & timer_irq_i & (6 downto 0 => '0');

  process(csr_addr, mstatus, mie, mtvec, mepc, mcause, mip)
  begin
    case csr_addr is
      when CSR_MSTATUS => csr_current <= mstatus;
      when CSR_MIE     => csr_current <= mie;
      when CSR_MTVEC   => csr_current <= mtvec;
      when CSR_MEPC    => csr_current <= mepc;
      when CSR_MCAUSE  => csr_current <= mcause;
      when CSR_MIP     => csr_current <= mip;
      when others      => csr_current <= (others => '0');
    end case;
  end process;

  process(csr_current, csr_wdata, csr_cmd)
  begin
    case csr_cmd is
      when "00"   => write_value <= csr_wdata;
      when "01"   => write_value <= csr_current or csr_wdata;
      when "10"   => write_value <= csr_current and not csr_wdata;
      when others => write_value <= csr_current;
    end case;
  end process;

  process(
    csr_en, csr_addr,
    mstatus, mie, mtvec, mepc, mcause, mip,
    wdog_enable, wdog_timeout, wdog_reload, wdog_count
  )
    variable wdog_ctrl_rd : std_logic_vector(31 downto 0);
  begin
    rdata_reg <= (others => '0');
    wdog_ctrl_rd := (others => '0');

    wdog_ctrl_rd(0) := wdog_enable;
    wdog_ctrl_rd(1) := wdog_timeout;

    if csr_en = '1' then
      case csr_addr is
        when CSR_MSTATUS    => rdata_reg <= mstatus;
        when CSR_MIE        => rdata_reg <= mie;
        when CSR_MTVEC      => rdata_reg <= mtvec;
        when CSR_MEPC       => rdata_reg <= mepc;
        when CSR_MCAUSE     => rdata_reg <= mcause;
        when CSR_MIP        => rdata_reg <= mip;
        when CSR_WDOG_CTRL  => rdata_reg <= wdog_ctrl_rd;
        when CSR_WDOG_RELOAD=> rdata_reg <= std_logic_vector(wdog_reload);
        when CSR_WDOG_COUNT => rdata_reg <= std_logic_vector(wdog_count);
        when others         => rdata_reg <= (others => '0');
      end case;
    end if;
  end process;

  csr_rdata <= rdata_reg;

  process(clk)
  begin
    if rising_edge(clk) then
      watchdog_reset_r <= '0';

      if rst = '1' then
        mstatus <= (others => '0');
        mie     <= (others => '0');
        mtvec   <= (others => '0');
        mepc    <= (others => '0');
        mcause  <= (others => '0');

        wdog_enable      <= '0';
        wdog_timeout     <= '0';
        wdog_reload      <= (others => '0');
        wdog_count       <= (others => '0');
        watchdog_reset_r <= '0';
      else
        if trap_enter = '1' then
          mepc       <= trap_pc_in;
          mcause     <= trap_cause_in;
          mstatus(7) <= mstatus(3);
          mstatus(3) <= '0';
        elsif mret_exec = '1' then
          mstatus(3) <= mstatus(7);
          mstatus(7) <= '1';
        elsif csr_en = '1' and csr_we = '1' then
          case csr_addr is
            when CSR_MSTATUS =>
              mstatus <= write_value;
            when CSR_MIE =>
              mie <= write_value;
            when CSR_MTVEC =>
              mtvec <= write_value;
            when CSR_MEPC =>
              mepc <= write_value;
            when CSR_MCAUSE =>
              mcause <= write_value;
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

  watchdog_reset_o <= watchdog_reset_r;

  mtvec_out   <= mtvec;
  mie_out     <= mie;
  mip_out     <= mip;
  mstatus_out <= mstatus;
  mepc_out    <= mepc;

end architecture;
