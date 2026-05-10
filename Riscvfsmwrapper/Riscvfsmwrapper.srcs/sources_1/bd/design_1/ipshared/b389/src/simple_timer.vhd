library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity simple_timer is
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;

    -- MMIO interface (word aligned)
    we      : in  std_logic;
    addr    : in  std_logic_vector(3 downto 0);  -- 0,4,8,C
    wdata   : in  std_logic_vector(31 downto 0);
    rdata   : out std_logic_vector(31 downto 0);

    irq_o   : out std_logic
  );
end entity;

architecture rtl of simple_timer is

  signal cnt      : unsigned(63 downto 0) := (others => '0');
  signal cmp      : unsigned(63 downto 0) := (others => '0');
  signal irq_reg  : std_logic := '0';

  signal rdata_reg : std_logic_vector(31 downto 0) := (others => '0');

begin

  -- counter
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt     <= (others => '0');
        cmp     <= (others => '0');
        irq_reg <= '0';
      else
        cnt <= cnt + 1;

        -- simple compare: pulse when equal
        if cnt = cmp then
          irq_reg <= '1';
        else
          irq_reg <= '0';
        end if;

        if we = '1' then
          case addr(3 downto 2) is
            when "00" =>
              cmp(31 downto 0)  <= unsigned(wdata);
            when "01" =>
              cmp(63 downto 32) <= unsigned(wdata);
            when others =>
              null;
          end case;
        end if;
      end if;
    end if;
  end process;

    -- readback 
  process(addr, cnt, cmp)
  begin
    case addr(3 downto 2) is
      when "00" =>
        rdata_reg <= std_logic_vector(cnt(31 downto 0));
      when "01" =>
        rdata_reg <= std_logic_vector(cnt(63 downto 32));
      when "10" =>
        rdata_reg <= std_logic_vector(cmp(31 downto 0));
      when "11" =>
        rdata_reg <= std_logic_vector(cmp(63 downto 32));
      when others =>
        rdata_reg <= (others => '0');
    end case;
  end process;


  rdata <= rdata_reg;
  irq_o <= irq_reg;

end architecture;
