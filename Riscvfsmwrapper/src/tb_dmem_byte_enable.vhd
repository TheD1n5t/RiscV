library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_dmem_byte_enable is
end entity;

architecture sim of tb_dmem_byte_enable is
  constant CLK_PERIOD : time := 10 ns;

  signal clk       : std_logic := '0';
  signal we        : std_logic := '0';
  signal be        : std_logic_vector(3 downto 0) := (others => '0');
  signal addr      : std_logic_vector(31 downto 0) := (others => '0');
  signal data_in   : std_logic_vector(31 downto 0) := (others => '0');
  signal data_out  : std_logic_vector(31 downto 0);

  signal prog_we    : std_logic := '0';
  signal prog_addr  : std_logic_vector(31 downto 0) := (others => '0');
  signal prog_wdata : std_logic_vector(31 downto 0) := (others => '0');

  signal rs2              : std_logic_vector(31 downto 0) := (others => '0');
  signal store_size       : std_logic_vector(1 downto 0) := "10";
  signal load_size        : std_logic_vector(1 downto 0) := "10";
  signal load_sign        : std_logic := '1';
  signal byte_offset      : std_logic_vector(1 downto 0) := "00";
  signal store_data       : std_logic_vector(31 downto 0);
  signal store_be         : std_logic_vector(3 downto 0);
  signal load_data_aligned: std_logic_vector(31 downto 0);

begin
  clk <= not clk after CLK_PERIOD / 2;

  dut_mem : entity work.dmem
    port map(
      clk        => clk,
      we         => we,
      be         => be,
      addr       => addr,
      data_in    => data_in,
      data_out   => data_out,
      prog_we    => prog_we,
      prog_addr  => prog_addr,
      prog_wdata => prog_wdata
    );

  dut_lsu : entity work.load_store_unit
    port map(
      rs2_i               => rs2,
      store_size_i        => store_size,
      load_size_i         => load_size,
      load_sign_i         => load_sign,
      byte_offset_i       => byte_offset,
      dmem_rdata_i        => data_out,
      store_data_o        => store_data,
      store_be_o          => store_be,
      load_data_aligned_o => load_data_aligned
    );

  stim : process
  begin
    -- Initialize word 0 to 0xAABBCCDD through the boot/programming port.
    addr       <= x"00000000";
    prog_addr  <= x"00000000";
    prog_wdata <= x"AABBCCDD";
    prog_we    <= '1';
    wait until rising_edge(clk);
    prog_we    <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;

    assert data_out = x"AABBCCDD"
      report "Initial DMEM program write failed"
      severity failure;

    -- sb offset 1: 0xAABBCCDD -> 0xAABB11DD.
    rs2         <= x"00000011";
    store_size  <= "00";
    byte_offset <= "01";
    wait for 1 ns;
    assert store_be = "0010" report "SB offset 1 byte enable mismatch" severity failure;
    assert store_data = x"00001100" report "SB offset 1 store data mismatch" severity failure;

    addr    <= x"00000001";
    data_in <= store_data;
    be      <= store_be;
    we      <= '1';
    wait until rising_edge(clk);
    we <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;

    assert data_out = x"AABB11DD"
      report "SB offset 1 did not update only byte lane 1"
      severity failure;

    -- sb offset 3: 0xAABB11DD -> 0x22BB11DD.
    rs2         <= x"00000022";
    store_size  <= "00";
    byte_offset <= "11";
    wait for 1 ns;
    assert store_be = "1000" report "SB offset 3 byte enable mismatch" severity failure;
    assert store_data = x"22000000" report "SB offset 3 store data mismatch" severity failure;

    addr    <= x"00000003";
    data_in <= store_data;
    be      <= store_be;
    we      <= '1';
    wait until rising_edge(clk);
    we <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;

    assert data_out = x"22BB11DD"
      report "SB offset 3 did not update only byte lane 3"
      severity failure;

    -- sh offset 0: 0x22BB11DD -> 0x22BB3344.
    rs2         <= x"00003344";
    store_size  <= "01";
    byte_offset <= "00";
    wait for 1 ns;
    assert store_be = "0011" report "SH lower byte enable mismatch" severity failure;
    assert store_data = x"00003344" report "SH lower store data mismatch" severity failure;

    addr    <= x"00000000";
    data_in <= store_data;
    be      <= store_be;
    we      <= '1';
    wait until rising_edge(clk);
    we <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;

    assert data_out = x"22BB3344"
      report "SH lower did not update only lower halfword"
      severity failure;

    -- sh offset 2: 0x22BB3344 -> 0x55663344.
    rs2         <= x"00005566";
    store_size  <= "01";
    byte_offset <= "10";
    wait for 1 ns;
    assert store_be = "1100" report "SH upper byte enable mismatch" severity failure;
    assert store_data = x"55660000" report "SH upper store data mismatch" severity failure;

    addr    <= x"00000002";
    data_in <= store_data;
    be      <= store_be;
    we      <= '1';
    wait until rising_edge(clk);
    we <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;

    assert data_out = x"55663344"
      report "SH upper did not update only upper halfword"
      severity failure;

    -- sw: full-word write.
    rs2         <= x"89ABCDEF";
    store_size  <= "10";
    byte_offset <= "00";
    wait for 1 ns;
    assert store_be = "1111" report "SW byte enable mismatch" severity failure;
    assert store_data = x"89ABCDEF" report "SW store data mismatch" severity failure;

    addr    <= x"00000000";
    data_in <= store_data;
    be      <= store_be;
    we      <= '1';
    wait until rising_edge(clk);
    we <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;

    assert data_out = x"89ABCDEF"
      report "SW full-word write failed"
      severity failure;

    -- Load alignment and sign/zero extension from 0x89ABCDEF.
    load_size   <= "00";
    load_sign   <= '0';
    byte_offset <= "00";
    wait for 1 ns;
    assert load_data_aligned = x"000000EF"
      report "LBU offset 0 failed"
      severity failure;

    load_size   <= "00";
    load_sign   <= '1';
    byte_offset <= "11";
    wait for 1 ns;
    assert load_data_aligned = x"FFFFFF89"
      report "LB offset 3 sign extension failed"
      severity failure;

    load_size   <= "01";
    load_sign   <= '0';
    byte_offset <= "10";
    wait for 1 ns;
    assert load_data_aligned = x"000089AB"
      report "LHU upper halfword failed"
      severity failure;

    load_size   <= "01";
    load_sign   <= '1';
    byte_offset <= "00";
    wait for 1 ns;
    assert load_data_aligned = x"FFFFCDEF"
      report "LH lower halfword sign extension failed"
      severity failure;

    load_size <= "10";
    wait for 1 ns;
    assert load_data_aligned = x"89ABCDEF"
      report "LW failed"
      severity failure;

    report "DMEM byte enable and load/store unit test passed" severity note;
    wait;
  end process;

end architecture;
