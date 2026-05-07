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

  constant NOP       : std_logic_vector(31 downto 0) := x"00000013";
  constant CUR_CTL_W : integer := 89;

  function state_to_slv(s : state_t) return std_logic_vector;
  function slv_to_state(v : std_logic_vector(3 downto 0)) return state_t;

  function pack_cur_ctl(
    rs1_addr      : std_logic_vector(4 downto 0);
    rs2_addr      : std_logic_vector(4 downto 0);
    rd_addr       : std_logic_vector(4 downto 0);
    imm_i         : std_logic_vector(31 downto 0);
    alu_op_i      : std_logic_vector(3 downto 0);
    alu_src_i     : std_logic;
    branch_ty_i   : std_logic_vector(2 downto 0);
    reg_write_i   : std_logic;
    mem_write_i   : std_logic;
    mem_read_i    : std_logic;
    mem_to_reg_i  : std_logic;
    jump_i        : std_logic;
    jalr_i        : std_logic;
    branch_i      : std_logic;
    is_auipc_i    : std_logic;
    load_size_i   : std_logic_vector(1 downto 0);
    load_sign_i   : std_logic;
    store_size_i  : std_logic_vector(1 downto 0);
    is_ecall_i    : std_logic;
    is_ebreak_i   : std_logic;
    is_mret_i     : std_logic;
    illegal_i     : std_logic;
    csr_en_i      : std_logic;
    csr_we_i      : std_logic;
    csr_addr_i    : std_logic_vector(11 downto 0);
    csr_use_imm_i : std_logic;
    csr_cmd_i     : std_logic_vector(1 downto 0)
  ) return std_logic_vector;

  constant CUR_CTL_RESET : std_logic_vector(CUR_CTL_W-1 downto 0);

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

  function pack_cur_ctl(
    rs1_addr      : std_logic_vector(4 downto 0);
    rs2_addr      : std_logic_vector(4 downto 0);
    rd_addr       : std_logic_vector(4 downto 0);
    imm_i         : std_logic_vector(31 downto 0);
    alu_op_i      : std_logic_vector(3 downto 0);
    alu_src_i     : std_logic;
    branch_ty_i   : std_logic_vector(2 downto 0);
    reg_write_i   : std_logic;
    mem_write_i   : std_logic;
    mem_read_i    : std_logic;
    mem_to_reg_i  : std_logic;
    jump_i        : std_logic;
    jalr_i        : std_logic;
    branch_i      : std_logic;
    is_auipc_i    : std_logic;
    load_size_i   : std_logic_vector(1 downto 0);
    load_sign_i   : std_logic;
    store_size_i  : std_logic_vector(1 downto 0);
    is_ecall_i    : std_logic;
    is_ebreak_i   : std_logic;
    is_mret_i     : std_logic;
    illegal_i     : std_logic;
    csr_en_i      : std_logic;
    csr_we_i      : std_logic;
    csr_addr_i    : std_logic_vector(11 downto 0);
    csr_use_imm_i : std_logic;
    csr_cmd_i     : std_logic_vector(1 downto 0)
  ) return std_logic_vector is
    variable r : std_logic_vector(CUR_CTL_W-1 downto 0);
  begin
    r :=
      rs1_addr      &
      rs2_addr      &
      rd_addr       &
      imm_i         &
      alu_op_i      &
      alu_src_i     &
      branch_ty_i   &
      reg_write_i   &
      mem_write_i   &
      mem_read_i    &
      mem_to_reg_i  &
      jump_i        &
      jalr_i        &
      branch_i      &
      is_auipc_i    &
      load_size_i   &
      load_sign_i   &
      store_size_i  &
      is_ecall_i    &
      is_ebreak_i   &
      is_mret_i     &
      illegal_i     &
      csr_en_i      &
      csr_we_i      &
      csr_addr_i    &
      csr_use_imm_i &
      csr_cmd_i;
    return r;
  end function;

  constant CUR_CTL_RESET : std_logic_vector(CUR_CTL_W-1 downto 0) :=
    pack_cur_ctl(
      (others => '0'),
      (others => '0'),
      (others => '0'),
      (others => '0'),
      (others => '0'),
      '0',
      (others => '0'),
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
      "10",
      '1',
      "10",
      '0',
      '0',
      '0',
      '0',
      '0',
      '0',
      (others => '0'),
      '0',
      "11"
    );

end package body cpu_pkg;
