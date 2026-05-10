library ieee;
use ieee.std_logic_1164.all;

entity tmr_fault_voter is
  generic(
    WIDTH          : positive := 32;
    G_FAULT_INJECT : boolean := false
  );
  port(
    data_a_i   : in  std_logic_vector(WIDTH-1 downto 0);
    data_b_i   : in  std_logic_vector(WIDTH-1 downto 0);
    data_c_i   : in  std_logic_vector(WIDTH-1 downto 0);

    fi_mask_i   : in std_logic_vector(WIDTH-1 downto 0) := (others => '0');
    fi_target_i : in std_logic_vector(1 downto 0) := "00";
    fi_strobe_i : in std_logic := '0';

    voted_o     : out std_logic_vector(WIDTH-1 downto 0);
    tmr_error_o : out std_logic
  );
end entity;

architecture rtl of tmr_fault_voter is
  signal fi_strobe_a : std_logic;
  signal fi_strobe_b : std_logic;
  signal fi_strobe_c : std_logic;

  signal vote_a : std_logic_vector(WIDTH-1 downto 0);
  signal vote_b : std_logic_vector(WIDTH-1 downto 0);
  signal vote_c : std_logic_vector(WIDTH-1 downto 0);
begin

  fi_strobe_a <= fi_strobe_i when fi_target_i = "00" else '0';
  fi_strobe_b <= fi_strobe_i when fi_target_i = "01" else '0';
  fi_strobe_c <= fi_strobe_i when fi_target_i = "10" else '0';

  fi_a : entity work.fault_injector
    generic map(
      WIDTH    => WIDTH,
      G_ENABLE => G_FAULT_INJECT
    )
    port map(
      data_i   => data_a_i,
      mask_i   => fi_mask_i,
      strobe_i => fi_strobe_a,
      data_o   => vote_a
    );

  fi_b : entity work.fault_injector
    generic map(
      WIDTH    => WIDTH,
      G_ENABLE => G_FAULT_INJECT
    )
    port map(
      data_i   => data_b_i,
      mask_i   => fi_mask_i,
      strobe_i => fi_strobe_b,
      data_o   => vote_b
    );

  fi_c : entity work.fault_injector
    generic map(
      WIDTH    => WIDTH,
      G_ENABLE => G_FAULT_INJECT
    )
    port map(
      data_i   => data_c_i,
      mask_i   => fi_mask_i,
      strobe_i => fi_strobe_c,
      data_o   => vote_c
    );

  process(vote_a, vote_b, vote_c)
  begin
    if (vote_a = vote_b) or (vote_a = vote_c) then
      voted_o <= vote_a;
    elsif vote_b = vote_c then
      voted_o <= vote_b;
    else
      voted_o <= vote_a;
    end if;

    if (vote_a = vote_b) and (vote_b = vote_c) then
      tmr_error_o <= '0';
    else
      tmr_error_o <= '1';
    end if;
  end process;

end architecture;
