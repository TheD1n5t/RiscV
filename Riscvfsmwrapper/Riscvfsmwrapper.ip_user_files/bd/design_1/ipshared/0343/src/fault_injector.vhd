library ieee;
use ieee.std_logic_1164.all;

entity fault_injector is
  generic(
    WIDTH    : positive := 32;
    G_ENABLE : boolean := false
  );
  port(
    data_i   : in  std_logic_vector(WIDTH-1 downto 0);
    mask_i   : in  std_logic_vector(WIDTH-1 downto 0);
    strobe_i : in  std_logic;
    data_o   : out std_logic_vector(WIDTH-1 downto 0)
  );
end entity;

architecture rtl of fault_injector is
begin

  gen_enabled : if G_ENABLE generate
    data_o <= data_i xor mask_i when strobe_i = '1' else data_i;
  end generate;

  gen_disabled : if not G_ENABLE generate
    data_o <= data_i;
  end generate;

end architecture;
