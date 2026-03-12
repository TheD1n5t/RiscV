library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity riscv_core_memless is
  port(
    clk   : in  std_logic;
    reset : in  std_logic;

    -- Instruction memory interface (synchronous read assumed)
    imem_pc    : out std_logic_vector(31 downto 0);
    imem_instr : in  std_logic_vector(31 downto 0);

    -- Data memory interface (synchronous read assumed)
    dmem_we    : out std_logic;
    dmem_addr  : out std_logic_vector(31 downto 0);
    dmem_wdata : out std_logic_vector(31 downto 0);
    dmem_rdata : in  std_logic_vector(31 downto 0);

    -- External machine timer interrupt
    irq_timer_i : in std_logic;

    -- Fault injection for PC TMR
    fi_pc_mask_i   : in std_logic_vector(31 downto 0) := (others => '0');
    fi_pc_target_i : in std_logic_vector(1 downto 0)  := "00"; -- 00=a, 01=b, 10=c
    fi_pc_strobe_i : in std_logic := '0';

    -- Fault injection for STATE TMR
    fi_state_mask_i   : in std_logic_vector(3 downto 0) := (others => '0');
    fi_state_target_i : in std_logic_vector(1 downto 0) := "00"; -- 00=a, 01=b, 10=c
    fi_state_strobe_i : in std_logic := '0';

    -- Fault injection for RF TMR
    fi_rf_mask_i   : in std_logic_vector(31 downto 0) := (others => '0');
    fi_rf_addr_i   : in std_logic_vector(4 downto 0)  := (others => '0');
    fi_rf_target_i : in std_logic_vector(1 downto 0)  := "00";
    fi_rf_strobe_i : in std_logic := '0';

    -- Watchdog reset pulse from CSR block
    watchdog_reset_o        : out std_logic;
    dmem_ecc_single_error_i : in std_logic := '0';
    dmem_ecc_double_error_i : in std_logic := '0'
  );
end riscv_core_memless;

architecture rtl of riscv_core_memless is

  --------------------------------------------------------------------
  -- Types and constants
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- Generic 3-way voter for std_logic_vector
  --------------------------------------------------------------------
  function vote3(
    a : std_logic_vector;
    b : std_logic_vector;
    c : std_logic_vector
  ) return std_logic_vector is
    variable r : std_logic_vector(a'range);
  begin
    for i in a'range loop
      if (a(i) = b(i)) or (a(i) = c(i)) then
        r(i) := a(i);
      elsif b(i) = c(i) then
        r(i) := b(i);
      else
        r(i) := a(i);
      end if;
    end loop;
    return r;
  end function;

  function vote3_err(
    a : std_logic_vector;
    b : std_logic_vector;
    c : std_logic_vector
  ) return std_logic is
  begin
    if (a = b) and (b = c) then
      return '0';
    else
      return '1';
    end if;
  end function;

  --------------------------------------------------------------------
  -- Helper functions for STATE TMR FI
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- Pack latched decode/control bundle into one TMR-protected vector
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- TMR-protected core state
  --------------------------------------------------------------------
  signal state_a          : state_t := ST_RESET;
  signal state_b          : state_t := ST_RESET;
  signal state_c          : state_t := ST_RESET;
  signal state_v          : state_t := ST_RESET;

  signal state_tmr_error  : std_logic := '0';

  signal state_enc_a      : std_logic_vector(3 downto 0);
  signal state_enc_b      : std_logic_vector(3 downto 0);
  signal state_enc_c      : std_logic_vector(3 downto 0);

  signal state_vote_slv_a : std_logic_vector(3 downto 0);
  signal state_vote_slv_b : std_logic_vector(3 downto 0);
  signal state_vote_slv_c : std_logic_vector(3 downto 0);

  signal state_v_slv      : std_logic_vector(3 downto 0) := "0000";

  signal pc_a             : std_logic_vector(31 downto 0) := (others => '0');
  signal pc_b             : std_logic_vector(31 downto 0) := (others => '0');
  signal pc_c             : std_logic_vector(31 downto 0) := (others => '0');

  signal pc_vote_a        : std_logic_vector(31 downto 0);
  signal pc_vote_b        : std_logic_vector(31 downto 0);
  signal pc_vote_c        : std_logic_vector(31 downto 0);

  signal pc_v             : std_logic_vector(31 downto 0) := (others => '0');
  signal pc_tmr_error     : std_logic := '0';

  signal instr_a          : std_logic_vector(31 downto 0) := NOP;
  signal instr_b          : std_logic_vector(31 downto 0) := NOP;
  signal instr_c          : std_logic_vector(31 downto 0) := NOP;
  signal instr_reg        : std_logic_vector(31 downto 0) := NOP;
  signal instr_tmr_error  : std_logic := '0';

  signal instr_pc         : std_logic_vector(31 downto 0) := (others => '0');
  signal pc_plus4         : std_logic_vector(31 downto 0);

  --------------------------------------------------------------------
  -- Decoder outputs
  --------------------------------------------------------------------
  signal rs1              : std_logic_vector(4 downto 0);
  signal rs2              : std_logic_vector(4 downto 0);
  signal rd               : std_logic_vector(4 downto 0);
  signal imm              : std_logic_vector(31 downto 0);

  signal alu_op           : std_logic_vector(3 downto 0);
  signal alu_src          : std_logic;
  signal reg_write_dec    : std_logic;
  signal mem_write_dec    : std_logic;
  signal mem_read_dec     : std_logic;
  signal mem_to_reg_dec   : std_logic;
  signal branch_dec       : std_logic;
  signal branch_type      : std_logic_vector(2 downto 0);
  signal jump_dec         : std_logic;
  signal jalr_dec         : std_logic;
  signal is_auipc         : std_logic;

  signal load_size        : std_logic_vector(1 downto 0);
  signal load_sign        : std_logic;
  signal store_size       : std_logic_vector(1 downto 0);

  signal is_ecall         : std_logic;
  signal is_ebreak        : std_logic;
  signal is_mret          : std_logic;
  signal illegal_instr    : std_logic;

  signal csr_en           : std_logic;
  signal csr_we           : std_logic;
  signal csr_addr         : std_logic_vector(11 downto 0);
  signal csr_use_imm      : std_logic;
  signal csr_cmd          : std_logic_vector(1 downto 0);

  --------------------------------------------------------------------
  -- Register file interface
  --------------------------------------------------------------------
  signal reg_rs1           : std_logic_vector(31 downto 0);
  signal reg_rs2           : std_logic_vector(31 downto 0);

  signal rf_we             : std_logic := '0';
  signal rf_waddr          : std_logic_vector(4 downto 0) := (others => '0');
  signal rf_wdata          : std_logic_vector(31 downto 0) := (others => '0');

  signal regfile_tmr_error : std_logic := '0';

  --------------------------------------------------------------------
  -- Latched instruction context
  --------------------------------------------------------------------
  signal cur_ctl_a         : std_logic_vector(CUR_CTL_W-1 downto 0) := CUR_CTL_RESET;
  signal cur_ctl_b         : std_logic_vector(CUR_CTL_W-1 downto 0) := CUR_CTL_RESET;
  signal cur_ctl_c         : std_logic_vector(CUR_CTL_W-1 downto 0) := CUR_CTL_RESET;
  signal cur_ctl_v         : std_logic_vector(CUR_CTL_W-1 downto 0) := CUR_CTL_RESET;
  signal cur_ctl_tmr_error : std_logic := '0';

  signal cur_rs1_addr      : std_logic_vector(4 downto 0);
  signal cur_rs2_addr      : std_logic_vector(4 downto 0);
  signal cur_rd_addr       : std_logic_vector(4 downto 0);

  signal cur_rs1_val       : std_logic_vector(31 downto 0) := (others => '0');
  signal cur_rs2_val       : std_logic_vector(31 downto 0) := (others => '0');
  signal cur_imm           : std_logic_vector(31 downto 0);

  signal cur_alu_op        : std_logic_vector(3 downto 0);
  signal cur_alu_src       : std_logic;
  signal cur_branch_ty     : std_logic_vector(2 downto 0);

  signal cur_reg_write     : std_logic;
  signal cur_mem_write     : std_logic;
  signal cur_mem_read      : std_logic;
  signal cur_mem_to_reg    : std_logic;
  signal cur_jump          : std_logic;
  signal cur_jalr          : std_logic;
  signal cur_branch        : std_logic;
  signal cur_is_auipc      : std_logic;

  signal cur_load_size     : std_logic_vector(1 downto 0);
  signal cur_load_sign     : std_logic;
  signal cur_store_size    : std_logic_vector(1 downto 0);

  signal cur_is_ecall      : std_logic;
  signal cur_is_ebreak     : std_logic;
  signal cur_is_mret       : std_logic;
  signal cur_illegal       : std_logic;

  signal cur_csr_en        : std_logic;
  signal cur_csr_we        : std_logic;
  signal cur_csr_addr      : std_logic_vector(11 downto 0);
  signal cur_csr_use_imm   : std_logic;
  signal cur_csr_cmd       : std_logic_vector(1 downto 0);

  --------------------------------------------------------------------
  -- Execute / writeback data
  --------------------------------------------------------------------
  signal alu_a            : std_logic_vector(31 downto 0);
  signal alu_b            : std_logic_vector(31 downto 0);
  signal alu_result       : std_logic_vector(31 downto 0);

  signal exec_result      : std_logic_vector(31 downto 0) := (others => '0');
  signal mem_addr_reg     : std_logic_vector(31 downto 0) := (others => '0');
  signal load_data_reg    : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_read_reg     : std_logic_vector(31 downto 0) := (others => '0');
  signal next_pc_reg      : std_logic_vector(31 downto 0) := (others => '0');

  --------------------------------------------------------------------
  -- Branch / jump helpers
  --------------------------------------------------------------------
  signal br_take          : std_logic;
  signal branch_target    : std_logic_vector(31 downto 0);
  signal jalr_target      : std_logic_vector(31 downto 0);

  --------------------------------------------------------------------
  -- Load / store helpers
  --------------------------------------------------------------------
  signal byte_offset       : std_logic_vector(1 downto 0);
  signal load_data_aligned : std_logic_vector(31 downto 0);
  signal dmem_data_in      : std_logic_vector(31 downto 0);
  signal calc_mem_addr     : std_logic_vector(31 downto 0);

  --------------------------------------------------------------------
  -- CSR / trap
  --------------------------------------------------------------------
  signal csr_wdata        : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_rdata        : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_zimm         : std_logic_vector(31 downto 0);

  signal csr_mstatus      : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_mie          : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_mip          : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_mtvec        : std_logic_vector(31 downto 0) := (others => '0');
  signal csr_mepc         : std_logic_vector(31 downto 0) := (others => '0');

  signal trap_enter       : std_logic := '0';
  signal trap_pc_in       : std_logic_vector(31 downto 0) := (others => '0');
  signal trap_cause_in    : std_logic_vector(31 downto 0) := (others => '0');
  signal mret_exec        : std_logic := '0';

  signal take_timer_irq   : std_logic;
  signal trap_cause_sel   : std_logic_vector(31 downto 0);

  signal watchdog_reset   : std_logic := '0';

  --------------------------------------------------------------------
  -- Accelerator MMIO
  --------------------------------------------------------------------
  signal acc_a_base       : std_logic_vector(31 downto 0) := (others => '0');
  signal acc_b_base       : std_logic_vector(31 downto 0) := (others => '0');
  signal acc_c_base       : std_logic_vector(31 downto 0) := (others => '0');
  signal acc_m            : std_logic_vector(31 downto 0) := (others => '0');
  signal acc_n            : std_logic_vector(31 downto 0) := (others => '0');
  signal acc_k            : std_logic_vector(31 downto 0) := (others => '0');

  signal acc_start_pulse  : std_logic := '0';
  signal acc_busy         : std_logic := '0';
  signal acc_done_raw     : std_logic := '0';
  signal acc_done_sticky  : std_logic := '0';

  signal is_mmio_addr     : std_logic;
  signal is_acc_addr      : std_logic;
  signal acc_reg_rdata    : std_logic_vector(31 downto 0);
  signal dmem_rdata_eff   : std_logic_vector(31 downto 0);

  signal cpu_dmem_we      : std_logic := '0';
  signal cpu_dmem_addr    : std_logic_vector(31 downto 0) := (others => '0');
  signal cpu_dmem_wdata   : std_logic_vector(31 downto 0) := (others => '0');

  signal acc_dmem_we      : std_logic;
  signal acc_dmem_addr    : std_logic_vector(31 downto 0);
  signal acc_dmem_wdata   : std_logic_vector(31 downto 0);
  
  attribute keep : string;

  attribute keep of instr_a : signal is "true";
  attribute keep of instr_b : signal is "true";
  attribute keep of instr_c : signal is "true";
    
  attribute keep of cur_ctl_a : signal is "true";
  attribute keep of cur_ctl_b : signal is "true";
  attribute keep of cur_ctl_c : signal is "true";
    
  attribute keep of pc_a : signal is "true";
  attribute keep of pc_b : signal is "true";
  attribute keep of pc_c : signal is "true";
    
  attribute keep of state_a : signal is "true";
  attribute keep of state_b : signal is "true";
  attribute keep of state_c : signal is "true";
  
begin

  --------------------------------------------------------------------
  -- Fault injection into PC voter inputs
  --------------------------------------------------------------------
  pc_vote_a <= pc_a xor fi_pc_mask_i when (fi_pc_strobe_i = '1' and fi_pc_target_i = "00") else pc_a;
  pc_vote_b <= pc_b xor fi_pc_mask_i when (fi_pc_strobe_i = '1' and fi_pc_target_i = "01") else pc_b;
  pc_vote_c <= pc_c xor fi_pc_mask_i when (fi_pc_strobe_i = '1' and fi_pc_target_i = "10") else pc_c;

  --------------------------------------------------------------------
  -- Fault injection into STATE voter inputs
  --------------------------------------------------------------------
  state_enc_a <= state_to_slv(state_a);
  state_enc_b <= state_to_slv(state_b);
  state_enc_c <= state_to_slv(state_c);

  state_vote_slv_a <= state_enc_a xor fi_state_mask_i
    when (fi_state_strobe_i = '1' and fi_state_target_i = "00")
    else state_enc_a;

  state_vote_slv_b <= state_enc_b xor fi_state_mask_i
    when (fi_state_strobe_i = '1' and fi_state_target_i = "01")
    else state_enc_b;

  state_vote_slv_c <= state_enc_c xor fi_state_mask_i
    when (fi_state_strobe_i = '1' and fi_state_target_i = "10")
    else state_enc_c;

  --------------------------------------------------------------------
  -- TMR voters
  --------------------------------------------------------------------
  process(state_vote_slv_a, state_vote_slv_b, state_vote_slv_c)
  begin
    if (state_vote_slv_a = state_vote_slv_b) or (state_vote_slv_a = state_vote_slv_c) then
      state_v_slv <= state_vote_slv_a;
    elsif state_vote_slv_b = state_vote_slv_c then
      state_v_slv <= state_vote_slv_b;
    else
      state_v_slv <= state_vote_slv_a;
    end if;

    if (state_vote_slv_a = state_vote_slv_b) and (state_vote_slv_b = state_vote_slv_c) then
      state_tmr_error <= '0';
    else
      state_tmr_error <= '1';
    end if;
  end process;

  state_v <= slv_to_state(state_v_slv);

  process(pc_vote_a, pc_vote_b, pc_vote_c)
  begin
    if (pc_vote_a = pc_vote_b) or (pc_vote_a = pc_vote_c) then
      pc_v <= pc_vote_a;
    elsif pc_vote_b = pc_vote_c then
      pc_v <= pc_vote_b;
    else
      pc_v <= pc_vote_a;
    end if;

    if (pc_vote_a = pc_vote_b) and (pc_vote_b = pc_vote_c) then
      pc_tmr_error <= '0';
    else
      pc_tmr_error <= '1';
    end if;
  end process;

  --------------------------------------------------------------------
  -- TMR vote for instruction register
  --------------------------------------------------------------------
  instr_reg       <= vote3(instr_a, instr_b, instr_c);
  instr_tmr_error <= vote3_err(instr_a, instr_b, instr_c);

  --------------------------------------------------------------------
  -- TMR vote for latched decode/control bundle
  --------------------------------------------------------------------
  cur_ctl_v         <= vote3(cur_ctl_a, cur_ctl_b, cur_ctl_c);
  cur_ctl_tmr_error <= vote3_err(cur_ctl_a, cur_ctl_b, cur_ctl_c);

  --------------------------------------------------------------------
  -- Unpack voted decode/control bundle
  --------------------------------------------------------------------
  cur_rs1_addr    <= cur_ctl_v(88 downto 84);
  cur_rs2_addr    <= cur_ctl_v(83 downto 79);
  cur_rd_addr     <= cur_ctl_v(78 downto 74);
  cur_imm         <= cur_ctl_v(73 downto 42);
  cur_alu_op      <= cur_ctl_v(41 downto 38);
  cur_alu_src     <= cur_ctl_v(37);
  cur_branch_ty   <= cur_ctl_v(36 downto 34);
  cur_reg_write   <= cur_ctl_v(33);
  cur_mem_write   <= cur_ctl_v(32);
  cur_mem_read    <= cur_ctl_v(31);
  cur_mem_to_reg  <= cur_ctl_v(30);
  cur_jump        <= cur_ctl_v(29);
  cur_jalr        <= cur_ctl_v(28);
  cur_branch      <= cur_ctl_v(27);
  cur_is_auipc    <= cur_ctl_v(26);
  cur_load_size   <= cur_ctl_v(25 downto 24);
  cur_load_sign   <= cur_ctl_v(23);
  cur_store_size  <= cur_ctl_v(22 downto 21);
  cur_is_ecall    <= cur_ctl_v(20);
  cur_is_ebreak   <= cur_ctl_v(19);
  cur_is_mret     <= cur_ctl_v(18);
  cur_illegal     <= cur_ctl_v(17);
  cur_csr_en      <= cur_ctl_v(16);
  cur_csr_we      <= cur_ctl_v(15);
  cur_csr_addr    <= cur_ctl_v(14 downto 3);
  cur_csr_use_imm <= cur_ctl_v(2);
  cur_csr_cmd     <= cur_ctl_v(1 downto 0);

  --------------------------------------------------------------------
  -- Top-level output muxes
  --------------------------------------------------------------------
  imem_pc    <= pc_v;
  dmem_we    <= acc_dmem_we    when acc_busy = '1' else cpu_dmem_we;
  dmem_addr  <= acc_dmem_addr  when acc_busy = '1' else cpu_dmem_addr;
  dmem_wdata <= acc_dmem_wdata when acc_busy = '1' else cpu_dmem_wdata;

  --------------------------------------------------------------------
  -- Common derived signals
  --------------------------------------------------------------------
  pc_plus4      <= std_logic_vector(unsigned(instr_pc) + 4);
  calc_mem_addr <= std_logic_vector(unsigned(cur_rs1_val) + unsigned(cur_imm));
  byte_offset   <= mem_addr_reg(1 downto 0);
  branch_target <= std_logic_vector(unsigned(instr_pc) + unsigned(cur_imm));
  jalr_target   <= std_logic_vector((unsigned(cur_rs1_val) + unsigned(cur_imm)) and x"FFFFFFFE");

  take_timer_irq <= '1' when (csr_mstatus(3) = '1' and csr_mie(7) = '1' and csr_mip(7) = '1') else '0';

  trap_cause_sel <= x"00000002" when cur_illegal='1' else
                    x"00000003" when cur_is_ebreak='1' else
                    x"0000000B" when cur_is_ecall='1' else
                    x"80000007";

  csr_zimm  <= (31 downto 5 => '0') & cur_rs1_addr;
  csr_wdata <= csr_zimm when cur_csr_use_imm = '1' else cur_rs1_val;

  is_mmio_addr <= '1' when mem_addr_reg(31 downto 16) = x"4000"  else '0';
  is_acc_addr  <= '1' when mem_addr_reg(31 downto 12) = x"40000" else '0';

  --------------------------------------------------------------------
  -- Decoder
  --------------------------------------------------------------------
  decoder_inst : entity work.decoder
    port map(
      instr          => instr_reg,
      rs1            => rs1,
      rs2            => rs2,
      rd             => rd,
      imm            => imm,
      alu_op         => alu_op,
      alu_src        => alu_src,
      reg_write      => reg_write_dec,
      mem_write      => mem_write_dec,
      mem_read       => mem_read_dec,
      mem_to_reg     => mem_to_reg_dec,
      branch         => branch_dec,
      branch_type    => branch_type,
      jump           => jump_dec,
      jalr           => jalr_dec,
      is_auipc       => is_auipc,
      load_size      => load_size,
      load_sign      => load_sign,
      store_size     => store_size,
      is_ecall       => is_ecall,
      is_ebreak      => is_ebreak,
      is_mret        => is_mret,
      illegal_instr  => illegal_instr,
      csr_en         => csr_en,
      csr_we         => csr_we,
      csr_addr       => csr_addr,
      csr_use_imm    => csr_use_imm,
      csr_cmd        => csr_cmd
    );

  --------------------------------------------------------------------
  -- Register file
  --------------------------------------------------------------------
  regfile_inst : entity work.regfile
    generic map(
      G_FAULT_INJECT => true,
      G_SELF_HEAL    => true
    )
    port map(
      clk                 => clk,
      rst                 => reset,
      we                  => rf_we,
      reg_in_data         => rf_wdata,
      reg_read_addr1      => cur_rs1_addr,
      reg_read_addr2      => cur_rs2_addr,
      reg_write_addr      => rf_waddr,
      reg_out_data1       => reg_rs1,
      reg_out_data2       => reg_rs2,
      regfile_tmr_error_o => regfile_tmr_error,
      fi_rf_mask_i        => fi_rf_mask_i,
      fi_rf_addr_i        => fi_rf_addr_i,
      fi_rf_target_i      => fi_rf_target_i,
      fi_rf_strobe_i      => fi_rf_strobe_i
    );

  --------------------------------------------------------------------
  -- CSR file
  --------------------------------------------------------------------
  csr_inst : entity work.csr_file
    port map(
      clk                      => clk,
      rst                      => reset,
      csr_en                   => cur_csr_en,
      csr_we                   => cur_csr_we,
      csr_addr                 => cur_csr_addr,
      csr_wdata                => csr_wdata,
      csr_cmd                  => cur_csr_cmd,
      csr_rdata                => csr_rdata,
      trap_enter               => trap_enter,
      trap_pc_in               => trap_pc_in,
      trap_cause_in            => trap_cause_in,
      mret_exec                => mret_exec,
      timer_irq_i              => irq_timer_i,
      pc_tmr_error_i           => pc_tmr_error,
      state_tmr_error_i        => state_tmr_error,
      csr_tmr_error_i          => regfile_tmr_error,
      watchdog_reset_o         => watchdog_reset,
      mtvec_out                => csr_mtvec,
      mie_out                  => csr_mie,
      mip_out                  => csr_mip,
      mstatus_out              => csr_mstatus,
      mepc_out                 => csr_mepc,
      dmem_ecc_single_error_i  => dmem_ecc_single_error_i,
      dmem_ecc_double_error_i  => dmem_ecc_double_error_i
    );

  --------------------------------------------------------------------
  -- ALU
  --------------------------------------------------------------------
  alu_a <= instr_pc when cur_is_auipc = '1' else cur_rs1_val;
  alu_b <= cur_imm  when cur_alu_src  = '1' else cur_rs2_val;

  alu_inst : entity work.alu
    port map(
      a      => alu_a,
      b      => alu_b,
      alu_op => cur_alu_op,
      result => alu_result,
      zero   => open
    );

  --------------------------------------------------------------------
  -- Branch comparator
  --------------------------------------------------------------------
  process(cur_branch, cur_branch_ty, cur_rs1_val, cur_rs2_val)
  begin
    br_take <= '0';

    if cur_branch = '1' then
      case cur_branch_ty is
        when "000" => if cur_rs1_val = cur_rs2_val then br_take <= '1'; end if;
        when "001" => if cur_rs1_val /= cur_rs2_val then br_take <= '1'; end if;
        when "010" => if signed(cur_rs1_val) <  signed(cur_rs2_val) then br_take <= '1'; end if;
        when "011" => if signed(cur_rs1_val) >= signed(cur_rs2_val) then br_take <= '1'; end if;
        when "100" => if unsigned(cur_rs1_val) <  unsigned(cur_rs2_val) then br_take <= '1'; end if;
        when "101" => if unsigned(cur_rs1_val) >= unsigned(cur_rs2_val) then br_take <= '1'; end if;
        when others => null;
      end case;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Store data formatting
  --------------------------------------------------------------------
  process(cur_rs2_val, cur_store_size, byte_offset, dmem_rdata)
    variable tmp : std_logic_vector(31 downto 0);
  begin
    tmp := dmem_rdata;

    case cur_store_size is
      when "00" =>
        case byte_offset is
          when "00"   => tmp(7 downto 0)   := cur_rs2_val(7 downto 0);
          when "01"   => tmp(15 downto 8)  := cur_rs2_val(7 downto 0);
          when "10"   => tmp(23 downto 16) := cur_rs2_val(7 downto 0);
          when others => tmp(31 downto 24) := cur_rs2_val(7 downto 0);
        end case;

      when "01" =>
        if byte_offset(1) = '0' then
          tmp(15 downto 0)  := cur_rs2_val(15 downto 0);
        else
          tmp(31 downto 16) := cur_rs2_val(15 downto 0);
        end if;

      when others =>
        tmp := cur_rs2_val;
    end case;

    dmem_data_in <= tmp;
  end process;

  --------------------------------------------------------------------
  -- Accelerator MMIO read
  --------------------------------------------------------------------
  process(mem_addr_reg, acc_a_base, acc_b_base, acc_c_base, acc_m, acc_n, acc_k, acc_busy, acc_done_sticky)
  begin
    acc_reg_rdata <= (others => '0');

    case mem_addr_reg(7 downto 0) is
      when x"00" =>
        acc_reg_rdata(1) <= acc_busy;
        acc_reg_rdata(2) <= acc_done_sticky;
      when x"04" => acc_reg_rdata <= acc_a_base;
      when x"08" => acc_reg_rdata <= acc_b_base;
      when x"0C" => acc_reg_rdata <= acc_c_base;
      when x"10" => acc_reg_rdata <= acc_m;
      when x"14" => acc_reg_rdata <= acc_n;
      when x"18" => acc_reg_rdata <= acc_k;
      when others => null;
    end case;
  end process;

  dmem_rdata_eff <= acc_reg_rdata when is_acc_addr = '1' else dmem_rdata;

  --------------------------------------------------------------------
  -- Load align / sign extend
  --------------------------------------------------------------------
  process(dmem_rdata_eff, cur_load_size, cur_load_sign, byte_offset)
    variable b : std_logic_vector(7 downto 0);
    variable h : std_logic_vector(15 downto 0);
  begin
    load_data_aligned <= dmem_rdata_eff;

    case cur_load_size is
      when "00" =>
        case byte_offset is
          when "00"   => b := dmem_rdata_eff(7 downto 0);
          when "01"   => b := dmem_rdata_eff(15 downto 8);
          when "10"   => b := dmem_rdata_eff(23 downto 16);
          when others => b := dmem_rdata_eff(31 downto 24);
        end case;

        if cur_load_sign = '1' and b(7) = '1' then
          load_data_aligned <= (31 downto 8 => '1') & b;
        else
          load_data_aligned <= (31 downto 8 => '0') & b;
        end if;

      when "01" =>
        if byte_offset(1) = '0' then
          h := dmem_rdata_eff(15 downto 0);
        else
          h := dmem_rdata_eff(31 downto 16);
        end if;

        if cur_load_sign = '1' and h(15) = '1' then
          load_data_aligned <= (31 downto 16 => '1') & h;
        else
          load_data_aligned <= (31 downto 16 => '0') & h;
        end if;

      when others =>
        load_data_aligned <= dmem_rdata_eff;
    end case;
  end process;

  --------------------------------------------------------------------
  -- CPU-side data memory outputs
  --------------------------------------------------------------------
  cpu_dmem_we    <= '1' when (state_v = ST_MEM_WRITE and is_acc_addr = '0') else '0';
  cpu_dmem_addr  <= calc_mem_addr when (state_v = ST_EXEC_LOAD_ADDR or state_v = ST_EXEC_STORE_ADDR) else mem_addr_reg;
  cpu_dmem_wdata <= dmem_data_in;

  --------------------------------------------------------------------
  -- Main FSM
  --------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then

      rf_we           <= '0';
      rf_waddr        <= (others => '0');
      rf_wdata        <= (others => '0');

      trap_enter      <= '0';
      trap_pc_in      <= (others => '0');
      trap_cause_in   <= (others => '0');
      mret_exec       <= '0';

      acc_start_pulse <= '0';

      if reset = '1' then
        state_a         <= ST_RESET;
        state_b         <= ST_RESET;
        state_c         <= ST_RESET;

        pc_a            <= (others => '0');
        pc_b            <= (others => '0');
        pc_c            <= (others => '0');

        instr_a         <= NOP;
        instr_b         <= NOP;
        instr_c         <= NOP;
        instr_pc        <= (others => '0');

        cur_ctl_a       <= CUR_CTL_RESET;
        cur_ctl_b       <= CUR_CTL_RESET;
        cur_ctl_c       <= CUR_CTL_RESET;

        cur_rs1_val     <= (others => '0');
        cur_rs2_val     <= (others => '0');

        exec_result     <= (others => '0');
        mem_addr_reg    <= (others => '0');
        load_data_reg   <= (others => '0');
        csr_read_reg    <= (others => '0');
        next_pc_reg     <= (others => '0');

        acc_a_base      <= (others => '0');
        acc_b_base      <= (others => '0');
        acc_c_base      <= (others => '0');
        acc_m           <= (others => '0');
        acc_n           <= (others => '0');
        acc_k           <= (others => '0');
        acc_done_sticky <= '0';

      else
        if acc_done_raw = '1' then
          acc_done_sticky <= '1';
        end if;

        if acc_busy = '1' then
          null;
        else
          case state_v is

            when ST_RESET =>
              pc_a    <= (others => '0');
              pc_b    <= (others => '0');
              pc_c    <= (others => '0');
              state_a <= ST_FETCH;
              state_b <= ST_FETCH;
              state_c <= ST_FETCH;

            when ST_FETCH =>
              state_a <= ST_FETCH_WAIT;
              state_b <= ST_FETCH_WAIT;
              state_c <= ST_FETCH_WAIT;

            when ST_FETCH_WAIT =>
              instr_pc <= pc_v;

              instr_a  <= imem_instr;
              instr_b  <= imem_instr;
              instr_c  <= imem_instr;

              state_a <= ST_DECODE;
              state_b <= ST_DECODE;
              state_c <= ST_DECODE;

            when ST_DECODE =>
              cur_ctl_a <= pack_cur_ctl(
                             rs1,
                             rs2,
                             rd,
                             imm,
                             alu_op,
                             alu_src,
                             branch_type,
                             reg_write_dec,
                             mem_write_dec,
                             mem_read_dec,
                             mem_to_reg_dec,
                             jump_dec,
                             jalr_dec,
                             branch_dec,
                             is_auipc,
                             load_size,
                             load_sign,
                             store_size,
                             is_ecall,
                             is_ebreak,
                             is_mret,
                             illegal_instr,
                             csr_en,
                             csr_we,
                             csr_addr,
                             csr_use_imm,
                             csr_cmd
                           );

              cur_ctl_b <= pack_cur_ctl(
                             rs1,
                             rs2,
                             rd,
                             imm,
                             alu_op,
                             alu_src,
                             branch_type,
                             reg_write_dec,
                             mem_write_dec,
                             mem_read_dec,
                             mem_to_reg_dec,
                             jump_dec,
                             jalr_dec,
                             branch_dec,
                             is_auipc,
                             load_size,
                             load_sign,
                             store_size,
                             is_ecall,
                             is_ebreak,
                             is_mret,
                             illegal_instr,
                             csr_en,
                             csr_we,
                             csr_addr,
                             csr_use_imm,
                             csr_cmd
                           );

              cur_ctl_c <= pack_cur_ctl(
                             rs1,
                             rs2,
                             rd,
                             imm,
                             alu_op,
                             alu_src,
                             branch_type,
                             reg_write_dec,
                             mem_write_dec,
                             mem_read_dec,
                             mem_to_reg_dec,
                             jump_dec,
                             jalr_dec,
                             branch_dec,
                             is_auipc,
                             load_size,
                             load_sign,
                             store_size,
                             is_ecall,
                             is_ebreak,
                             is_mret,
                             illegal_instr,
                             csr_en,
                             csr_we,
                             csr_addr,
                             csr_use_imm,
                             csr_cmd
                           );

              next_pc_reg <= std_logic_vector(unsigned(pc_v) + 4);

              state_a <= ST_RF_WAIT;
              state_b <= ST_RF_WAIT;
              state_c <= ST_RF_WAIT;

            when ST_RF_WAIT =>
              cur_rs1_val <= reg_rs1;
              cur_rs2_val <= reg_rs2;

              if cur_illegal = '1' or cur_is_ebreak = '1' or cur_is_ecall = '1' or take_timer_irq = '1' then
                state_a <= ST_TRAP;
                state_b <= ST_TRAP;
                state_c <= ST_TRAP;
              elsif cur_is_mret = '1' then
                state_a <= ST_MRET;
                state_b <= ST_MRET;
                state_c <= ST_MRET;
              elsif cur_csr_en = '1' then
                state_a <= ST_EXEC_CSR;
                state_b <= ST_EXEC_CSR;
                state_c <= ST_EXEC_CSR;
              elsif cur_mem_read = '1' then
                state_a <= ST_EXEC_LOAD_ADDR;
                state_b <= ST_EXEC_LOAD_ADDR;
                state_c <= ST_EXEC_LOAD_ADDR;
              elsif cur_mem_write = '1' then
                state_a <= ST_EXEC_STORE_ADDR;
                state_b <= ST_EXEC_STORE_ADDR;
                state_c <= ST_EXEC_STORE_ADDR;
              elsif cur_branch = '1' then
                state_a <= ST_EXEC_BRANCH;
                state_b <= ST_EXEC_BRANCH;
                state_c <= ST_EXEC_BRANCH;
              elsif cur_jump = '1' or cur_jalr = '1' then
                state_a <= ST_EXEC_JUMP;
                state_b <= ST_EXEC_JUMP;
                state_c <= ST_EXEC_JUMP;
              else
                state_a <= ST_EXEC_ALU;
                state_b <= ST_EXEC_ALU;
                state_c <= ST_EXEC_ALU;
              end if;

            when ST_EXEC_ALU =>
              exec_result <= alu_result;

              state_a <= ST_WB;
              state_b <= ST_WB;
              state_c <= ST_WB;

            when ST_EXEC_LOAD_ADDR =>
              mem_addr_reg <= calc_mem_addr;

              state_a <= ST_MEM_READ;
              state_b <= ST_MEM_READ;
              state_c <= ST_MEM_READ;

            when ST_EXEC_STORE_ADDR =>
              mem_addr_reg <= calc_mem_addr;

              state_a <= ST_MEM_WRITE;
              state_b <= ST_MEM_WRITE;
              state_c <= ST_MEM_WRITE;

            when ST_EXEC_BRANCH =>
              if br_take = '1' then
                pc_a <= branch_target;
                pc_b <= branch_target;
                pc_c <= branch_target;
              else
                pc_a <= next_pc_reg;
                pc_b <= next_pc_reg;
                pc_c <= next_pc_reg;
              end if;

              state_a <= ST_FETCH;
              state_b <= ST_FETCH;
              state_c <= ST_FETCH;

            when ST_EXEC_JUMP =>
              exec_result <= pc_plus4;

              if cur_jalr = '1' then
                pc_a <= jalr_target;
                pc_b <= jalr_target;
                pc_c <= jalr_target;
              else
                pc_a <= branch_target;
                pc_b <= branch_target;
                pc_c <= branch_target;
              end if;

              state_a <= ST_WB;
              state_b <= ST_WB;
              state_c <= ST_WB;

            when ST_EXEC_CSR =>
              csr_read_reg <= csr_rdata;

              state_a <= ST_WB;
              state_b <= ST_WB;
              state_c <= ST_WB;

            when ST_MEM_READ =>
              load_data_reg <= load_data_aligned;

              state_a <= ST_WB;
              state_b <= ST_WB;
              state_c <= ST_WB;

            when ST_MEM_WRITE =>
              if is_acc_addr = '1' then
                case mem_addr_reg(7 downto 0) is
                  when x"00" =>
                    if cur_rs2_val(0) = '1' then
                      acc_start_pulse <= '1';
                      acc_done_sticky <= '0';
                    end if;
                  when x"04" => acc_a_base <= cur_rs2_val;
                  when x"08" => acc_b_base <= cur_rs2_val;
                  when x"0C" => acc_c_base <= cur_rs2_val;
                  when x"10" => acc_m      <= cur_rs2_val;
                  when x"14" => acc_n      <= cur_rs2_val;
                  when x"18" => acc_k      <= cur_rs2_val;
                  when others => null;
                end case;
              end if;

              pc_a <= next_pc_reg;
              pc_b <= next_pc_reg;
              pc_c <= next_pc_reg;

              state_a <= ST_FETCH;
              state_b <= ST_FETCH;
              state_c <= ST_FETCH;

            when ST_TRAP =>
              trap_enter    <= '1';
              trap_pc_in    <= instr_pc;
              trap_cause_in <= trap_cause_sel;

              pc_a <= csr_mtvec;
              pc_b <= csr_mtvec;
              pc_c <= csr_mtvec;

              state_a <= ST_FETCH;
              state_b <= ST_FETCH;
              state_c <= ST_FETCH;

            when ST_MRET =>
              mret_exec <= '1';

              pc_a <= csr_mepc;
              pc_b <= csr_mepc;
              pc_c <= csr_mepc;

              state_a <= ST_FETCH;
              state_b <= ST_FETCH;
              state_c <= ST_FETCH;

            when ST_WB =>
              if cur_reg_write = '1' and cur_rd_addr /= "00000" then
                rf_we    <= '1';
                rf_waddr <= cur_rd_addr;

                if cur_csr_en = '1' then
                  rf_wdata <= csr_read_reg;
                elsif cur_jump = '1' or cur_jalr = '1' then
                  rf_wdata <= exec_result;
                elsif cur_mem_read = '1' then
                  rf_wdata <= load_data_reg;
                else
                  rf_wdata <= exec_result;
                end if;
              end if;

              if cur_jump = '0' and cur_jalr = '0' then
                pc_a <= next_pc_reg;
                pc_b <= next_pc_reg;
                pc_c <= next_pc_reg;
              end if;

              state_a <= ST_FETCH;
              state_b <= ST_FETCH;
              state_c <= ST_FETCH;

            when others =>
              state_a <= ST_FETCH;
              state_b <= ST_FETCH;
              state_c <= ST_FETCH;

          end case;
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Optional debug
  --------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if state_tmr_error = '1' then
        report "STATE TMR ERROR seen in core" severity note;
      end if;

      if pc_tmr_error = '1' then
        report "PC TMR ERROR seen in core" severity note;
      end if;

      if instr_tmr_error = '1' then
        report "INSTR_REG TMR ERROR seen in core" severity note;
      end if;

      if cur_ctl_tmr_error = '1' then
        report "CUR_CTL TMR ERROR seen in core" severity note;
      end if;

      if regfile_tmr_error = '1' then
        report "REGFILE TMR ERROR seen in core (self-healing active)" severity note;
      end if;
    end if;
  end process;

  watchdog_reset_o <= watchdog_reset;

end rtl;