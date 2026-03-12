library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decoder is
  port(
    instr          : in  std_logic_vector(31 downto 0);

    rs1            : out std_logic_vector(4 downto 0);
    rs2            : out std_logic_vector(4 downto 0);
    rd             : out std_logic_vector(4 downto 0);

    imm            : out std_logic_vector(31 downto 0);

    alu_op         : out std_logic_vector(3 downto 0);
    alu_src        : out std_logic;
    reg_write      : out std_logic;
    mem_write      : out std_logic;
    mem_read       : out std_logic;
    mem_to_reg     : out std_logic;
    branch         : out std_logic;
    branch_type    : out std_logic_vector(2 downto 0);
    jump           : out std_logic;
    jalr           : out std_logic;
    is_auipc       : out std_logic;

    load_size      : out std_logic_vector(1 downto 0);
    load_sign      : out std_logic;
    store_size     : out std_logic_vector(1 downto 0);

    -- SYSTEM / CSR
    is_ecall       : out std_logic;
    is_ebreak      : out std_logic;
    is_mret        : out std_logic;
    illegal_instr  : out std_logic;
    csr_en         : out std_logic;
    csr_we         : out std_logic;
    csr_addr       : out std_logic_vector(11 downto 0);
    csr_use_imm    : out std_logic;
    csr_cmd        : out std_logic_vector(1 downto 0) -- 00=write, 01=set, 10=clear, 11=none
  );
end entity;

architecture rtl of decoder is
begin

  process(instr)
    variable opcode  : std_logic_vector(6 downto 0);
    variable funct3  : std_logic_vector(2 downto 0);
    variable funct7  : std_logic_vector(6 downto 0);

    variable rs1_v   : std_logic_vector(4 downto 0);
    variable rs2_v   : std_logic_vector(4 downto 0);
    variable rd_v    : std_logic_vector(4 downto 0);
    variable csr_imm : std_logic_vector(4 downto 0);
  begin
    opcode  := instr(6 downto 0);
    funct3  := instr(14 downto 12);
    funct7  := instr(31 downto 25);

    rs1_v   := instr(19 downto 15);
    rs2_v   := instr(24 downto 20);
    rd_v    := instr(11 downto 7);
    csr_imm := instr(19 downto 15);

    rs1 <= rs1_v;
    rs2 <= rs2_v;
    rd  <= rd_v;

    ------------------------------------------------------------------
    -- Defaults
    ------------------------------------------------------------------
    imm           <= (others => '0');

    alu_op        <= "0000";
    alu_src       <= '0';

    reg_write     <= '0';
    mem_write     <= '0';
    mem_read      <= '0';
    mem_to_reg    <= '0';

    branch        <= '0';
    branch_type   <= (others => '0');
    jump          <= '0';
    jalr          <= '0';
    is_auipc      <= '0';

    load_size     <= "10";
    load_sign     <= '1';
    store_size    <= "10";

    is_ecall      <= '0';
    is_ebreak     <= '0';
    is_mret       <= '0';
    illegal_instr <= '0';

    csr_en        <= '0';
    csr_we        <= '0';
    csr_addr      <= instr(31 downto 20);
    csr_use_imm   <= '0';
    csr_cmd       <= "11";

    ------------------------------------------------------------------
    -- Main opcode decode
    ------------------------------------------------------------------
    case opcode is

      ----------------------------------------------------------------
      -- R-type
      ----------------------------------------------------------------
      when "0110011" =>
        reg_write <= '1';

        case funct3 is
          when "000" =>
            if funct7 = "0000000" then
              alu_op <= "0000"; -- ADD
            elsif funct7 = "0100000" then
              alu_op <= "0001"; -- SUB
            elsif funct7 = "0000001" then
              alu_op <= "1010"; -- MUL
            else
              reg_write     <= '0';
              illegal_instr <= '1';
            end if;

          when "111" =>
            if funct7 = "0000000" then
              alu_op <= "0010"; -- AND
            else
              reg_write     <= '0';
              illegal_instr <= '1';
            end if;

          when "110" =>
            if funct7 = "0000000" then
              alu_op <= "0011"; -- OR
            else
              reg_write     <= '0';
              illegal_instr <= '1';
            end if;

          when "100" =>
            if funct7 = "0000000" then
              alu_op <= "0100"; -- XOR
            else
              reg_write     <= '0';
              illegal_instr <= '1';
            end if;

          when "010" =>
            if funct7 = "0000000" then
              alu_op <= "1000"; -- SLT
            else
              reg_write     <= '0';
              illegal_instr <= '1';
            end if;

          when "011" =>
            if funct7 = "0000000" then
              alu_op <= "1001"; -- SLTU
            else
              reg_write     <= '0';
              illegal_instr <= '1';
            end if;

          when "001" =>
            if funct7 = "0000000" then
              alu_op <= "0101"; -- SLL
            else
              reg_write     <= '0';
              illegal_instr <= '1';
            end if;

          when "101" =>
            if funct7 = "0000000" then
              alu_op <= "0110"; -- SRL
            elsif funct7 = "0100000" then
              alu_op <= "0111"; -- SRA
            else
              reg_write     <= '0';
              illegal_instr <= '1';
            end if;

          when others =>
            reg_write     <= '0';
            illegal_instr <= '1';
        end case;

      ----------------------------------------------------------------
      -- I-type ALU
      ----------------------------------------------------------------
      when "0010011" =>
        reg_write <= '1';
        alu_src   <= '1';
        imm       <= std_logic_vector(resize(signed(instr(31 downto 20)), 32));

        case funct3 is
          when "000" => alu_op <= "0000"; -- ADDI
          when "111" => alu_op <= "0010"; -- ANDI
          when "110" => alu_op <= "0011"; -- ORI
          when "100" => alu_op <= "0100"; -- XORI
          when "010" => alu_op <= "1000"; -- SLTI
          when "011" => alu_op <= "1001"; -- SLTIU

          when "001" =>
            if funct7 = "0000000" then
              alu_op <= "0101"; -- SLLI
            else
              reg_write     <= '0';
              illegal_instr <= '1';
            end if;

          when "101" =>
            if funct7 = "0000000" then
              alu_op <= "0110"; -- SRLI
            elsif funct7 = "0100000" then
              alu_op <= "0111"; -- SRAI
            else
              reg_write     <= '0';
              illegal_instr <= '1';
            end if;

          when others =>
            reg_write     <= '0';
            illegal_instr <= '1';
        end case;

      ----------------------------------------------------------------
      -- LOAD
      ----------------------------------------------------------------
      when "0000011" =>
        reg_write  <= '1';
        alu_src    <= '1';
        mem_read   <= '1';
        mem_to_reg <= '1';
        alu_op     <= "0000";
        imm        <= std_logic_vector(resize(signed(instr(31 downto 20)), 32));

        case funct3 is
          when "000" => load_size <= "00"; load_sign <= '1'; -- LB
          when "001" => load_size <= "01"; load_sign <= '1'; -- LH
          when "010" => load_size <= "10"; load_sign <= '1'; -- LW
          when "100" => load_size <= "00"; load_sign <= '0'; -- LBU
          when "101" => load_size <= "01"; load_sign <= '0'; -- LHU
          when others =>
            reg_write     <= '0';
            mem_read      <= '0';
            mem_to_reg    <= '0';
            illegal_instr <= '1';
        end case;

      ----------------------------------------------------------------
      -- STORE
      ----------------------------------------------------------------
      when "0100011" =>
        alu_src   <= '1';
        mem_write <= '1';
        alu_op    <= "0000";
        imm       <= std_logic_vector(
                       resize(
                         signed(instr(31 downto 25) & instr(11 downto 7)),
                         32
                       )
                     );

        case funct3 is
          when "000" => store_size <= "00"; -- SB
          when "001" => store_size <= "01"; -- SH
          when "010" => store_size <= "10"; -- SW
          when others =>
            mem_write     <= '0';
            illegal_instr <= '1';
        end case;

      ----------------------------------------------------------------
      -- BRANCH
      ----------------------------------------------------------------
      when "1100011" =>
        branch <= '1';
        imm    <= std_logic_vector(
                    resize(
                      signed(instr(31) &
                             instr(7) &
                             instr(30 downto 25) &
                             instr(11 downto 8) &
                             '0'),
                      32
                    )
                  );

        case funct3 is
          when "000" => branch_type <= "000"; -- BEQ
          when "001" => branch_type <= "001"; -- BNE
          when "100" => branch_type <= "010"; -- BLT
          when "101" => branch_type <= "011"; -- BGE
          when "110" => branch_type <= "100"; -- BLTU
          when "111" => branch_type <= "101"; -- BGEU
          when others =>
            branch        <= '0';
            illegal_instr <= '1';
        end case;

      ----------------------------------------------------------------
      -- JAL
      ----------------------------------------------------------------
      when "1101111" =>
        jump      <= '1';
        reg_write <= '1';
        alu_src   <= '0';
        alu_op    <= "0000";
        imm       <= std_logic_vector(
                       resize(
                         signed(instr(31) &
                                instr(19 downto 12) &
                                instr(20) &
                                instr(30 downto 21) &
                                '0'),
                         32
                       )
                     );

      ----------------------------------------------------------------
      -- JALR
      ----------------------------------------------------------------
      when "1100111" =>
        if funct3 = "000" then
          jalr      <= '1';
          reg_write <= '1';
          alu_src   <= '1';
          alu_op    <= "0000";
          imm       <= std_logic_vector(resize(signed(instr(31 downto 20)), 32));
        else
          illegal_instr <= '1';
        end if;

      ----------------------------------------------------------------
      -- LUI
      ----------------------------------------------------------------
      when "0110111" =>
        reg_write <= '1';
        alu_src   <= '1';
        alu_op    <= "0000";
        imm       <= instr(31 downto 12) & x"000";
        rs1       <= "00000";
        rs2       <= "00000";

      ----------------------------------------------------------------
      -- AUIPC
      ----------------------------------------------------------------
      when "0010111" =>
        reg_write <= '1';
        alu_src   <= '1';
        alu_op    <= "0000";
        imm       <= instr(31 downto 12) & x"000";
        rs1       <= "00000";
        rs2       <= "00000";
        is_auipc  <= '1';

      ----------------------------------------------------------------
      -- SYSTEM / CSR
      ----------------------------------------------------------------
      when "1110011" =>
        case funct3 is

          ------------------------------------------------------------
          -- ECALL / EBREAK / MRET
          ------------------------------------------------------------
          when "000" =>
            if instr(31 downto 20) = x"000" and instr(19 downto 7) = "0000000000000" then
              is_ecall <= '1';

            elsif instr(31 downto 20) = x"001" and instr(19 downto 7) = "0000000000000" then
              is_ebreak <= '1';

            elsif instr(31 downto 20) = x"302" and instr(19 downto 7) = "0000000000000" then
              is_mret <= '1';

            else
              illegal_instr <= '1';
            end if;

          ------------------------------------------------------------
          -- CSRRW
          ------------------------------------------------------------
          when "001" =>
            csr_en      <= '1';
            csr_we      <= '1';
            csr_use_imm <= '0';
            csr_cmd     <= "00";
            reg_write   <= '1';

          ------------------------------------------------------------
          -- CSRRS
          ------------------------------------------------------------
          when "010" =>
            csr_en      <= '1';
            csr_use_imm <= '0';
            csr_cmd     <= "01";
            reg_write   <= '1';

            if rs1_v = "00000" then
              csr_we <= '0'; -- read only
            else
              csr_we <= '1';
            end if;

          ------------------------------------------------------------
          -- CSRRC
          ------------------------------------------------------------
          when "011" =>
            csr_en      <= '1';
            csr_use_imm <= '0';
            csr_cmd     <= "10";
            reg_write   <= '1';

            if rs1_v = "00000" then
              csr_we <= '0'; -- read only
            else
              csr_we <= '1';
            end if;

          ------------------------------------------------------------
          -- CSRRWI
          ------------------------------------------------------------
          when "101" =>
            csr_en      <= '1';
            csr_we      <= '1';
            csr_use_imm <= '1';
            csr_cmd     <= "00";
            reg_write   <= '1';

          ------------------------------------------------------------
          -- CSRRSI
          ------------------------------------------------------------
          when "110" =>
            csr_en      <= '1';
            csr_use_imm <= '1';
            csr_cmd     <= "01";
            reg_write   <= '1';

            if csr_imm = "00000" then
              csr_we <= '0'; -- read only
            else
              csr_we <= '1';
            end if;

          ------------------------------------------------------------
          -- CSRRCI
          ------------------------------------------------------------
          when "111" =>
            csr_en      <= '1';
            csr_use_imm <= '1';
            csr_cmd     <= "10";
            reg_write   <= '1';

            if csr_imm = "00000" then
              csr_we <= '0'; -- read only
            else
              csr_we <= '1';
            end if;

          when others =>
            illegal_instr <= '1';
        end case;

      ----------------------------------------------------------------
      -- Illegal opcode
      ----------------------------------------------------------------
      when others =>
        illegal_instr <= '1';

    end case;
  end process;

end architecture;