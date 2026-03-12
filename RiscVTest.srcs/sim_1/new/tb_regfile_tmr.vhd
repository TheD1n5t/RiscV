library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_regfile_tmr is
end tb_regfile_tmr;

architecture sim of tb_regfile_tmr is

  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal we   : std_logic := '0';

  signal reg_in_data    : std_logic_vector(31 downto 0) := (others => '0');
  signal reg_read_addr1 : std_logic_vector(4 downto 0) := (others => '0');
  signal reg_read_addr2 : std_logic_vector(4 downto 0) := (others => '0');
  signal reg_write_addr : std_logic_vector(4 downto 0) := (others => '0');
  signal reg_out_data1  : std_logic_vector(31 downto 0);
  signal reg_out_data2  : std_logic_vector(31 downto 0);
  signal regfile_tmr_error_o : std_logic;

  signal fi_rf_mask_i   : std_logic_vector(31 downto 0) := (others => '0');
  signal fi_rf_addr_i   : std_logic_vector(4 downto 0)  := (others => '0');
  signal fi_rf_target_i : std_logic_vector(1 downto 0)  := "00";
  signal fi_rf_strobe_i : std_logic := '0';

begin

  clk <= not clk after 5 ns;

  uut : entity work.regfile
    port map (
      clk                 => clk,
      rst                 => rst,
      we                  => we,
      reg_in_data         => reg_in_data,
      reg_read_addr1      => reg_read_addr1,
      reg_read_addr2      => reg_read_addr2,
      reg_write_addr      => reg_write_addr,
      reg_out_data1       => reg_out_data1,
      reg_out_data2       => reg_out_data2,
      regfile_tmr_error_o => regfile_tmr_error_o,
      fi_rf_mask_i        => fi_rf_mask_i,
      fi_rf_addr_i        => fi_rf_addr_i,
      fi_rf_target_i      => fi_rf_target_i,
      fi_rf_strobe_i      => fi_rf_strobe_i
    );

  stim : process
  begin
    -- Reset
    rst <= '1';
    wait for 20 ns;
    rst <= '0';
    wait for 10 ns;

    -- Write x5 = 0x12345678
    we <= '1';
    reg_write_addr <= "00101";
    reg_in_data    <= x"12345678";
    wait until rising_edge(clk);
    we <= '0';
    wait for 1 ns;

    -- Read x5
    reg_read_addr1 <= "00101";
    wait for 2 ns;

    assert reg_out_data1 = x"12345678"
      report "Initial readback failed"
      severity error;

    -- Inject 1-bit fault into bank B of register x5
    fi_rf_addr_i   <= "00101";
    fi_rf_mask_i   <= x"00000008";
    fi_rf_target_i <= "01";  -- bank B
    fi_rf_strobe_i <= '1';
    wait until rising_edge(clk);
    fi_rf_strobe_i <= '0';
    wait for 2 ns;

    -- Majority vote must still return correct value
    assert reg_out_data1 = x"12345678"
      report "TMR vote failed after single-bank fault"
      severity error;

    assert regfile_tmr_error_o = '1'
      report "TMR error flag did not assert"
      severity error;

    -- Next clock should self-heal because x5 is being read on port 1
    wait until rising_edge(clk);
    wait for 2 ns;

    -- Error should now be gone after repair
    assert reg_out_data1 = x"12345678"
      report "Readback incorrect after self-healing"
      severity error;

    assert regfile_tmr_error_o = '0'
      report "TMR error flag did not clear after self-healing"
      severity error;

    report "Registerfile TMR self-healing test PASSED" severity note;
    wait;
  end process;

end sim;