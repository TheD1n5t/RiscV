library ieee;
use ieee.std_logic_1164.all;

entity load_store_unit is
  port(
    rs2_i              : in  std_logic_vector(31 downto 0);
    store_size_i       : in  std_logic_vector(1 downto 0);
    load_size_i        : in  std_logic_vector(1 downto 0);
    load_sign_i        : in  std_logic;
    byte_offset_i      : in  std_logic_vector(1 downto 0);
    dmem_rdata_i       : in  std_logic_vector(31 downto 0);
    store_data_o       : out std_logic_vector(31 downto 0);
    load_data_aligned_o: out std_logic_vector(31 downto 0)
  );
end load_store_unit;

architecture rtl of load_store_unit is
begin
  process(rs2_i, store_size_i, byte_offset_i, dmem_rdata_i)
    variable tmp : std_logic_vector(31 downto 0);
  begin
    tmp := dmem_rdata_i;

    case store_size_i is
      when "00" =>
        case byte_offset_i is
          when "00"   => tmp(7 downto 0)   := rs2_i(7 downto 0);
          when "01"   => tmp(15 downto 8)  := rs2_i(7 downto 0);
          when "10"   => tmp(23 downto 16) := rs2_i(7 downto 0);
          when others => tmp(31 downto 24) := rs2_i(7 downto 0);
        end case;

      when "01" =>
        if byte_offset_i(1) = '0' then
          tmp(15 downto 0)  := rs2_i(15 downto 0);
        else
          tmp(31 downto 16) := rs2_i(15 downto 0);
        end if;

      when others =>
        tmp := rs2_i;
    end case;

    store_data_o <= tmp;
  end process;

  process(dmem_rdata_i, load_size_i, load_sign_i, byte_offset_i)
    variable b : std_logic_vector(7 downto 0);
    variable h : std_logic_vector(15 downto 0);
  begin
    load_data_aligned_o <= dmem_rdata_i;

    case load_size_i is
      when "00" =>
        case byte_offset_i is
          when "00"   => b := dmem_rdata_i(7 downto 0);
          when "01"   => b := dmem_rdata_i(15 downto 8);
          when "10"   => b := dmem_rdata_i(23 downto 16);
          when others => b := dmem_rdata_i(31 downto 24);
        end case;

        if load_sign_i = '1' and b(7) = '1' then
          load_data_aligned_o <= (31 downto 8 => '1') & b;
        else
          load_data_aligned_o <= (31 downto 8 => '0') & b;
        end if;

      when "01" =>
        if byte_offset_i(1) = '0' then
          h := dmem_rdata_i(15 downto 0);
        else
          h := dmem_rdata_i(31 downto 16);
        end if;

        if load_sign_i = '1' and h(15) = '1' then
          load_data_aligned_o <= (31 downto 16 => '1') & h;
        else
          load_data_aligned_o <= (31 downto 16 => '0') & h;
        end if;

      when others =>
        load_data_aligned_o <= dmem_rdata_i;
    end case;
  end process;
end rtl;
