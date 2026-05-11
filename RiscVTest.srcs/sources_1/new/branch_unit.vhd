library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity branch_unit is
  port(
    branch_i      : in  std_logic;
    branch_type_i : in  std_logic_vector(2 downto 0);
    rs1_i         : in  std_logic_vector(31 downto 0);
    rs2_i         : in  std_logic_vector(31 downto 0);
    take_o        : out std_logic
  );
end branch_unit;

architecture rtl of branch_unit is
begin
  process(branch_i, branch_type_i, rs1_i, rs2_i)
  begin
    take_o <= '0';

    if branch_i = '1' then
      case branch_type_i is
        when "000" => if rs1_i = rs2_i then take_o <= '1'; end if;
        when "001" => if rs1_i /= rs2_i then take_o <= '1'; end if;
        when "010" => if signed(rs1_i) <  signed(rs2_i) then take_o <= '1'; end if;
        when "011" => if signed(rs1_i) >= signed(rs2_i) then take_o <= '1'; end if;
        when "100" => if unsigned(rs1_i) <  unsigned(rs2_i) then take_o <= '1'; end if;
        when "101" => if unsigned(rs1_i) >= unsigned(rs2_i) then take_o <= '1'; end if;
        when others => null;
      end case;
    end if;
  end process;
end rtl;
