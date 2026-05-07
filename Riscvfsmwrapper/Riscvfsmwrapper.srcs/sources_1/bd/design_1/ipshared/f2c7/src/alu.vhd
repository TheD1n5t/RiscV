library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alu is
  Port (
    a       : in  std_logic_vector(31 downto 0);
    b       : in  std_logic_vector(31 downto 0);
    alu_op  : in  std_logic_vector(3 downto 0);
    result  : out std_logic_vector(31 downto 0);
    zero    : out std_logic
  );
end alu;

architecture Behavioral of alu is
begin

    process(a, b, alu_op)
        variable tmp : std_logic_vector(31 downto 0);
        variable prod : unsigned(63 downto 0);
    begin
        tmp := (others => '0');
        prod := (others => '0');
        case alu_op is
            when "0000" =>
                tmp := std_logic_vector(unsigned(a) + unsigned(b));  -- ADD

            when "0001" =>
                tmp := std_logic_vector(unsigned(a) - unsigned(b));  -- SUB

            when "0010" =>
                tmp := a and b;  -- AND

            when "0011" =>
                tmp := a or b;   -- OR

            when "0100" =>
                tmp := a xor b;  -- XOR

            when "0101" =>
                tmp := std_logic_vector(
                          unsigned(a) sll to_integer(unsigned(b(4 downto 0)))
                       ); -- SLL

            when "0110" =>
                tmp := std_logic_vector(
                          unsigned(a) srl to_integer(unsigned(b(4 downto 0)))
                       ); -- SRL

            when "0111" =>
                tmp := std_logic_vector(
                          shift_right(signed(a), to_integer(unsigned(b(4 downto 0))))
                       ); -- SRA

            when "1000" =>  -- SLT
                if signed(a) < signed(b) then
                    tmp(0) := '1';
                end if;

            when "1001" =>  -- SLTU
                if unsigned(a) < unsigned(b) then
                    tmp(0) := '1';
                end if;
            when "1010" =>  -- MUL low 32
                    prod := unsigned(a) * unsigned(b);
                    tmp  := std_logic_vector(prod(31 downto 0));

            when "1111" =>
                tmp := std_logic_vector(unsigned(a) + 4);

            when others =>
                tmp := (others => '0');
        end case;

        result <= tmp;

        -- Zero flag
        if tmp = x"00000000" then
            zero <= '1';
        else
            zero <= '0';
        end if;
    end process;

end Behavioral;
