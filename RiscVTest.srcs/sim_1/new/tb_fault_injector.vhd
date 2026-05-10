library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_fault_injector is
end entity;

architecture sim of tb_fault_injector is
  signal data_i       : std_logic_vector(31 downto 0) := (others => '0');
  signal mask_i       : std_logic_vector(31 downto 0) := (others => '0');
  signal strobe_i     : std_logic := '0';
  signal data_enabled : std_logic_vector(31 downto 0);
  signal data_bypass  : std_logic_vector(31 downto 0);

  signal data8_i       : std_logic_vector(7 downto 0) := (others => '0');
  signal mask8_i       : std_logic_vector(7 downto 0) := (others => '0');
  signal strobe8_i     : std_logic := '0';
  signal data8_enabled : std_logic_vector(7 downto 0);
  signal data8_bypass  : std_logic_vector(7 downto 0);

  signal data1_i       : std_logic_vector(0 downto 0) := (others => '0');
  signal mask1_i       : std_logic_vector(0 downto 0) := (others => '0');
  signal strobe1_i     : std_logic := '0';
  signal data1_enabled : std_logic_vector(0 downto 0);
  signal data1_bypass  : std_logic_vector(0 downto 0);

  type slv32_array_t is array (natural range <>) of std_logic_vector(31 downto 0);
  type slv8_array_t  is array (natural range <>) of std_logic_vector(7 downto 0);

  constant DATA32_PATTERNS : slv32_array_t := (
    x"00000000",
    x"FFFFFFFF",
    x"AAAAAAAA",
    x"55555555",
    x"12345678",
    x"87654321",
    x"80000001",
    x"7FFFFFFE"
  );

  constant MASK32_PATTERNS : slv32_array_t := (
    x"00000000",
    x"00000001",
    x"0000000F",
    x"0000FF00",
    x"00FF00FF",
    x"0F0F0F0F",
    x"80000000",
    x"FFFFFFFF"
  );

  constant DATA8_PATTERNS : slv8_array_t := (
    x"00",
    x"FF",
    x"A5",
    x"5A",
    x"81",
    x"7E"
  );

  constant MASK8_PATTERNS : slv8_array_t := (
    x"00",
    x"01",
    x"0F",
    x"33",
    x"80",
    x"FF"
  );

  procedure check_equal(
    constant actual   : in std_logic_vector;
    constant expected : in std_logic_vector;
    constant msg      : in string
  ) is
  begin
    assert actual = expected
      report msg
      severity failure;
  end procedure;
begin

  dut_enabled : entity work.fault_injector
    generic map(
      WIDTH    => 32,
      G_ENABLE => true
    )
    port map(
      data_i   => data_i,
      mask_i   => mask_i,
      strobe_i => strobe_i,
      data_o   => data_enabled
    );

  dut_bypass : entity work.fault_injector
    generic map(
      WIDTH    => 32,
      G_ENABLE => false
    )
    port map(
      data_i   => data_i,
      mask_i   => mask_i,
      strobe_i => strobe_i,
      data_o   => data_bypass
    );

  dut8_enabled : entity work.fault_injector
    generic map(
      WIDTH    => 8,
      G_ENABLE => true
    )
    port map(
      data_i   => data8_i,
      mask_i   => mask8_i,
      strobe_i => strobe8_i,
      data_o   => data8_enabled
    );

  dut8_bypass : entity work.fault_injector
    generic map(
      WIDTH    => 8,
      G_ENABLE => false
    )
    port map(
      data_i   => data8_i,
      mask_i   => mask8_i,
      strobe_i => strobe8_i,
      data_o   => data8_bypass
    );

  dut1_enabled : entity work.fault_injector
    generic map(
      WIDTH    => 1,
      G_ENABLE => true
    )
    port map(
      data_i   => data1_i,
      mask_i   => mask1_i,
      strobe_i => strobe1_i,
      data_o   => data1_enabled
    );

  dut1_bypass : entity work.fault_injector
    generic map(
      WIDTH    => 1,
      G_ENABLE => false
    )
    port map(
      data_i   => data1_i,
      mask_i   => mask1_i,
      strobe_i => strobe1_i,
      data_o   => data1_bypass
    );

  stim : process
    variable expected32 : std_logic_vector(31 downto 0);
    variable expected8  : std_logic_vector(7 downto 0);
  begin
    ----------------------------------------------------------------
    -- WIDTH = 32: both enabled and disabled paths over many patterns
    ----------------------------------------------------------------
    for data_idx in DATA32_PATTERNS'range loop
      for mask_idx in MASK32_PATTERNS'range loop
        data_i   <= DATA32_PATTERNS(data_idx);
        mask_i   <= MASK32_PATTERNS(mask_idx);
        strobe_i <= '0';
        wait for 1 ns;

        check_equal(data_enabled, DATA32_PATTERNS(data_idx),
          "WIDTH=32 enabled path changed data while strobe was low");
        check_equal(data_bypass, DATA32_PATTERNS(data_idx),
          "WIDTH=32 disabled path changed data while strobe was low");

        strobe_i <= '1';
        wait for 1 ns;
        expected32 := DATA32_PATTERNS(data_idx) xor MASK32_PATTERNS(mask_idx);

        check_equal(data_enabled, expected32,
          "WIDTH=32 enabled path did not XOR data and mask while strobe was high");
        check_equal(data_bypass, DATA32_PATTERNS(data_idx),
          "WIDTH=32 disabled path changed data while strobe was high");
      end loop;
    end loop;

    ----------------------------------------------------------------
    -- Combinational transition checks: no clock, immediate response
    ----------------------------------------------------------------
    data_i   <= x"CAFEBABE";
    mask_i   <= x"00000001";
    strobe_i <= '0';
    wait for 1 ns;
    check_equal(data_enabled, x"CAFEBABE",
      "enabled path failed pre-transition passthrough");

    strobe_i <= '1';
    wait for 1 ns;
    check_equal(data_enabled, x"CAFEBABF",
      "enabled path failed rising strobe transition");

    mask_i <= x"F0F0F0F0";
    wait for 1 ns;
    check_equal(data_enabled, x"3A0E4A4E",
      "enabled path failed mask update while strobe was high");

    data_i <= x"0BADF00D";
    wait for 1 ns;
    check_equal(data_enabled, x"FB5D00FD",
      "enabled path failed data update while strobe was high");

    strobe_i <= '0';
    wait for 1 ns;
    check_equal(data_enabled, x"0BADF00D",
      "enabled path failed falling strobe transition");
    check_equal(data_bypass, x"0BADF00D",
      "disabled path failed transition passthrough");

    ----------------------------------------------------------------
    -- WIDTH = 8: generic width coverage with independent DUTs
    ----------------------------------------------------------------
    for data_idx in DATA8_PATTERNS'range loop
      for mask_idx in MASK8_PATTERNS'range loop
        data8_i   <= DATA8_PATTERNS(data_idx);
        mask8_i   <= MASK8_PATTERNS(mask_idx);
        strobe8_i <= '0';
        wait for 1 ns;

        check_equal(data8_enabled, DATA8_PATTERNS(data_idx),
          "WIDTH=8 enabled path changed data while strobe was low");
        check_equal(data8_bypass, DATA8_PATTERNS(data_idx),
          "WIDTH=8 disabled path changed data while strobe was low");

        strobe8_i <= '1';
        wait for 1 ns;
        expected8 := DATA8_PATTERNS(data_idx) xor MASK8_PATTERNS(mask_idx);

        check_equal(data8_enabled, expected8,
          "WIDTH=8 enabled path did not XOR data and mask while strobe was high");
        check_equal(data8_bypass, DATA8_PATTERNS(data_idx),
          "WIDTH=8 disabled path changed data while strobe was high");
      end loop;
    end loop;

    ----------------------------------------------------------------
    -- WIDTH = 1: edge case for the smallest legal positive width
    ----------------------------------------------------------------
    data1_i   <= "0";
    mask1_i   <= "1";
    strobe1_i <= '0';
    wait for 1 ns;
    check_equal(data1_enabled, "0",
      "WIDTH=1 enabled path changed data while strobe was low");
    check_equal(data1_bypass, "0",
      "WIDTH=1 disabled path changed data while strobe was low");

    strobe1_i <= '1';
    wait for 1 ns;
    check_equal(data1_enabled, "1",
      "WIDTH=1 enabled path failed 0 xor 1");
    check_equal(data1_bypass, "0",
      "WIDTH=1 disabled path changed 0 while strobe was high");

    data1_i <= "1";
    wait for 1 ns;
    check_equal(data1_enabled, "0",
      "WIDTH=1 enabled path failed 1 xor 1");
    check_equal(data1_bypass, "1",
      "WIDTH=1 disabled path changed 1 while strobe was high");

    mask1_i <= "0";
    wait for 1 ns;
    check_equal(data1_enabled, "1",
      "WIDTH=1 enabled path failed 1 xor 0");
    check_equal(data1_bypass, "1",
      "WIDTH=1 disabled path changed 1 with zero mask");

    report "fault_injector extended test passed." severity note;
    finish;
    wait;
  end process;

end architecture;
