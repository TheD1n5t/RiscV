library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package cpu_pkg is

  type state_t is (
    ST_RESET,
    ST_FETCH,
    ST_FETCH_WAIT,
    ST_DECODE,
    ST_RF_WAIT,
    ST_EXEC_ALU,
    ST_EXEC_LOAD_ADDR,
    ST_EXEC_STORE_ADDR,
    ST_EXEC_BRANCH,
    ST_EXEC_JUMP,
    ST_EXEC_CSR,
    ST_MEM_READ,
    ST_MEM_WRITE,
    ST_TRAP,
    ST_MRET,
    ST_WB
  );

  constant NOP : std_logic_vector(31 downto 0) := x"00000013";

  function state_to_slv(s : state_t) return std_logic_vector;
  function slv_to_state(v : std_logic_vector(3 downto 0)) return state_t;

end package cpu_pkg;

package body cpu_pkg is

  function state_to_slv(s : state_t) return std_logic_vector is
  begin
    case s is
      when ST_RESET           => return "0000";
      when ST_FETCH           => return "0001";
      when ST_FETCH_WAIT      => return "0010";
      when ST_DECODE          => return "0011";
      when ST_RF_WAIT         => return "0100";
      when ST_EXEC_ALU        => return "0101";
      when ST_EXEC_LOAD_ADDR  => return "0110";
      when ST_EXEC_STORE_ADDR => return "0111";
      when ST_EXEC_BRANCH     => return "1000";
      when ST_EXEC_JUMP       => return "1001";
      when ST_EXEC_CSR        => return "1010";
      when ST_MEM_READ        => return "1011";
      when ST_MEM_WRITE       => return "1100";
      when ST_TRAP            => return "1101";
      when ST_MRET            => return "1110";
      when ST_WB              => return "1111";
    end case;
  end function;

  function slv_to_state(v : std_logic_vector(3 downto 0)) return state_t is
  begin
    case v is
      when "0000" => return ST_RESET;
      when "0001" => return ST_FETCH;
      when "0010" => return ST_FETCH_WAIT;
      when "0011" => return ST_DECODE;
      when "0100" => return ST_RF_WAIT;
      when "0101" => return ST_EXEC_ALU;
      when "0110" => return ST_EXEC_LOAD_ADDR;
      when "0111" => return ST_EXEC_STORE_ADDR;
      when "1000" => return ST_EXEC_BRANCH;
      when "1001" => return ST_EXEC_JUMP;
      when "1010" => return ST_EXEC_CSR;
      when "1011" => return ST_MEM_READ;
      when "1100" => return ST_MEM_WRITE;
      when "1101" => return ST_TRAP;
      when "1110" => return ST_MRET;
      when "1111" => return ST_WB;
      when others => return ST_RESET;
    end case;
  end function;

end package body cpu_pkg;
