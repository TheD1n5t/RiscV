library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_dmem_ecc is
end entity;

architecture sim of tb_dmem_ecc is
    constant CLK_PERIOD : time := 20 ns;

    signal clk              : std_logic := '0';
    signal we               : std_logic := '0';
    signal addr             : std_logic_vector(31 downto 0) := (others => '0');
    signal data_in          : std_logic_vector(31 downto 0) := (others => '0');
    signal data_out         : std_logic_vector(31 downto 0);
    signal ecc_single_error : std_logic;
    signal ecc_double_error : std_logic;

    signal fi_dmem_mask_i   : std_logic_vector(38 downto 0) := (others => '0');
    signal fi_dmem_addr_i   : std_logic_vector(9 downto 0)  := (others => '0');
    signal fi_dmem_strobe_i : std_logic := '0';
begin

    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.dmem
    generic map(
        G_FAULT_INJECT => true
    )
    port map(
        clk              => clk,
        we               => we,
        addr             => addr,
        data_in          => data_in,
        data_out         => data_out,
        ecc_single_error => ecc_single_error,
        ecc_double_error => ecc_double_error,
        fi_dmem_mask_i   => fi_dmem_mask_i,
        fi_dmem_addr_i   => fi_dmem_addr_i,
        fi_dmem_strobe_i => fi_dmem_strobe_i
    );

    stim: process
        variable mask_v : std_logic_vector(38 downto 0);
    begin
        ----------------------------------------------------------------
        -- Test 1: normal write
        ----------------------------------------------------------------
        addr    <= x"00000000";
        data_in <= x"00000011";
        we      <= '1';
        
        wait until rising_edge(clk);  -- write happens here
        
        we <= '0';
        
        wait until rising_edge(clk);  -- read register captures written word
        wait for 1 ns;
        
        assert data_out = x"00000011"
            report "Initial readback mismatch"
            severity failure;
        
        assert ecc_single_error = '0'
            report "Unexpected single ECC error after clean write"
            severity failure;
        
        assert ecc_double_error = '0'
            report "Unexpected double ECC error after clean write"
            severity failure;

        ----------------------------------------------------------------
        -- Test 2: inject single-bit error
        ----------------------------------------------------------------
        mask_v := (others => '0');
        mask_v(10) := '1';

        fi_dmem_addr_i   <= (others => '0');
        fi_dmem_mask_i   <= mask_v;
        fi_dmem_strobe_i <= '1';

        wait until rising_edge(clk);  -- inject into RAM here

        fi_dmem_strobe_i <= '0';
        fi_dmem_mask_i   <= (others => '0');
        
        wait until rising_edge(clk);  -- read corrupted word into rd_word_reg
        wait for 1 ns;

        assert data_out = x"00000011"
            report "Single-bit ECC correction failed"
            severity failure;

        assert ecc_single_error = '1'
            report "Single-bit ECC was not detected"
            severity failure;

        assert ecc_double_error = '0'
            report "Single-bit error incorrectly flagged as double-bit"
            severity failure;

        ----------------------------------------------------------------
        -- Re-write clean word before double-bit test
        ----------------------------------------------------------------
        we      <= '1';
        data_in <= x"00000011";
        
        wait until rising_edge(clk);
        we <= '0';
        
        wait until rising_edge(clk);
        wait for 1 ns;

        ----------------------------------------------------------------
        -- Test 3: inject double-bit error
        ----------------------------------------------------------------
        mask_v := (others => '0');
        mask_v(10) := '1';
        mask_v(11) := '1';
        
        fi_dmem_addr_i   <= (others => '0');
        fi_dmem_mask_i   <= mask_v;
        fi_dmem_strobe_i <= '1';
        
        wait until rising_edge(clk);
        
        fi_dmem_strobe_i <= '0';
        fi_dmem_mask_i   <= (others => '0');
        
        wait until rising_edge(clk);
        wait for 1 ns;
        
        assert ecc_double_error = '1'
            report "Double-bit ECC was not detected"
            severity failure;

        report "DMEM ECC test passed." severity note;
        finish;
        wait;
    end process;

end architecture;