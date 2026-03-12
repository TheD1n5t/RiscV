library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_csr_file is
end entity;

architecture sim of tb_csr_file is
  constant CLK_PERIOD : time := 20 ns;

  signal clk           : std_logic := '0';
  signal rst           : std_logic := '1';

  signal csr_en        : std_logic := '0';
  signal csr_we        : std_logic := '0';
  signal csr_addr      : std_logic_vector(11 downto 0) := (others => '0');
  signal csr_wdata     : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_cmd       : std_logic_vector(1 downto 0) := "00";
  signal csr_rdata     : std_logic_vector(31 downto 0);

  signal trap_enter    : std_logic := '0';
  signal trap_pc_in    : std_logic_vector(31 downto 0) := (others => '0');
  signal trap_cause_in : std_logic_vector(31 downto 0) := (others => '0');
  signal mret_exec     : std_logic := '0';
  signal timer_irq_i   : std_logic := '0';

  signal pc_tmr_error_i    : std_logic := '0';
  signal state_tmr_error_i : std_logic := '0';
  signal csr_tmr_error_i   : std_logic := '0';

  signal watchdog_reset_o  : std_logic;

  signal mtvec_out     : std_logic_vector(31 downto 0);
  signal mie_out       : std_logic_vector(31 downto 0);
  signal mip_out       : std_logic_vector(31 downto 0);
  signal mstatus_out   : std_logic_vector(31 downto 0);
  signal mepc_out      : std_logic_vector(31 downto 0);

  signal dmem_ecc_single_error_i : std_logic := '0';
  signal dmem_ecc_double_error_i : std_logic := '0';

begin

  clk <= not clk after CLK_PERIOD/2;

  dut : entity work.csr_file
    port map(
      clk                      => clk,
      rst                      => rst,
      csr_en                   => csr_en,
      csr_we                   => csr_we,
      csr_addr                 => csr_addr,
      csr_wdata                => csr_wdata,
      csr_cmd                  => csr_cmd,
      csr_rdata                => csr_rdata,
      trap_enter               => trap_enter,
      trap_pc_in               => trap_pc_in,
      trap_cause_in            => trap_cause_in,
      mret_exec                => mret_exec,
      timer_irq_i              => timer_irq_i,
      pc_tmr_error_i           => pc_tmr_error_i,
      state_tmr_error_i        => state_tmr_error_i,
      csr_tmr_error_i          => csr_tmr_error_i,
      watchdog_reset_o         => watchdog_reset_o,
      mtvec_out                => mtvec_out,
      mie_out                  => mie_out,
      mip_out                  => mip_out,
      mstatus_out              => mstatus_out,
      mepc_out                 => mepc_out,
      dmem_ecc_single_error_i  => dmem_ecc_single_error_i,
      dmem_ecc_double_error_i  => dmem_ecc_double_error_i
    );

  stim : process
  begin
    ------------------------------------------------------------------
    -- Reset
    ------------------------------------------------------------------
    rst <= '1';
    wait for 3*CLK_PERIOD;
    rst <= '0';
    wait until rising_edge(clk);

    ------------------------------------------------------------------
    -- Test 1: single ECC event
    ------------------------------------------------------------------
    dmem_ecc_single_error_i <= '1';
    wait until rising_edge(clk);
    dmem_ecc_single_error_i <= '0';
    wait until rising_edge(clk);

    csr_en   <= '1';
    csr_we   <= '0';
    csr_addr <= x"7C3";
    wait for 1 ns;

    assert csr_rdata = x"00000001"
      report "CSR 7C3 single ECC counter mismatch"
      severity failure;

    csr_en <= '0';
    wait until rising_edge(clk);

    ------------------------------------------------------------------
    -- Test 2: second single ECC event
    ------------------------------------------------------------------
    dmem_ecc_single_error_i <= '1';
    wait until rising_edge(clk);
    dmem_ecc_single_error_i <= '0';
    wait until rising_edge(clk);

    csr_en   <= '1';
    csr_we   <= '0';
    csr_addr <= x"7C3";
    wait for 1 ns;

    assert csr_rdata = x"00000002"
      report "CSR 7C3 did not increment to 2"
      severity failure;

    csr_en <= '0';
    wait until rising_edge(clk);

    ------------------------------------------------------------------
    -- Test 3: double ECC event
    ------------------------------------------------------------------
    dmem_ecc_double_error_i <= '1';
    wait until rising_edge(clk);
    dmem_ecc_double_error_i <= '0';
    wait until rising_edge(clk);

    csr_en   <= '1';
    csr_we   <= '0';
    csr_addr <= x"7C4";
    wait for 1 ns;

    assert csr_rdata = x"00000001"
      report "CSR 7C4 double ECC counter mismatch"
      severity failure;

    csr_en <= '0';
    wait until rising_edge(clk);

    report "CSR file ECC counter test passed." severity note;
    finish;
    wait;
  end process;

end architecture;