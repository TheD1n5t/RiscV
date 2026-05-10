library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity regfile is
  port (
    clk            : in  std_logic;
    rst            : in  std_logic;
    we             : in  std_logic;
    reg_in_data    : in  std_logic_vector(31 downto 0);
    reg_read_addr1 : in  std_logic_vector(4 downto 0);
    reg_read_addr2 : in  std_logic_vector(4 downto 0);
    reg_write_addr : in  std_logic_vector(4 downto 0);
    reg_out_data1  : out std_logic_vector(31 downto 0);
    reg_out_data2  : out std_logic_vector(31 downto 0)
  );
end regfile;

architecture rtl of regfile is

  type mem_t is array(0 to 31) of std_logic_vector(31 downto 0);
  signal regs : mem_t := (others => (others => '0'));

  attribute ram_style : string;
  attribute ram_style of regs : signal is "distributed";

begin

  process(clk)
    variable waddr_int : integer range 0 to 31;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        regs <= (others => (others => '0'));
      else
        waddr_int := to_integer(unsigned(reg_write_addr));

        if we = '1' and reg_write_addr /= "00000" then
          regs(waddr_int) <= reg_in_data;
        end if;

        regs(0) <= (others => '0');
      end if;
    end if;
  end process;

  reg_out_data1 <= reg_in_data
    when (we = '1' and reg_write_addr /= "00000" and reg_write_addr = reg_read_addr1)
    else regs(to_integer(unsigned(reg_read_addr1)));

  reg_out_data2 <= reg_in_data
    when (we = '1' and reg_write_addr /= "00000" and reg_write_addr = reg_read_addr2)
    else regs(to_integer(unsigned(reg_read_addr2)));

end rtl;
