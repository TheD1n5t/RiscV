library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_flash_boot is
  generic(
    CLK_DIV : positive := 50
  );
  port(
    clk   : in  std_logic;
    reset : in  std_logic;
    start : in  std_logic;

    spi_sck_o  : out std_logic;
    spi_cs_n_o : out std_logic;
    spi_mosi_o : out std_logic;
    spi_miso_i : in  std_logic;

    imem_prog_we_o    : out std_logic;
    imem_prog_addr_o  : out std_logic_vector(31 downto 0);
    imem_prog_wdata_o : out std_logic_vector(31 downto 0);

    dmem_prog_we_o    : out std_logic;
    dmem_prog_addr_o  : out std_logic_vector(31 downto 0);
    dmem_prog_wdata_o : out std_logic_vector(31 downto 0);

    done_o  : out std_logic;
    error_o : out std_logic
  );
end entity;

architecture rtl of spi_flash_boot is

  type spi_state_t is (SPI_IDLE, SPI_CMD, SPI_ADDR2, SPI_ADDR1, SPI_ADDR0, SPI_READ);
  type boot_state_t is (
    BL_IDLE,
    BL_MAGIC0,
    BL_MAGIC1,
    BL_IMEM_LEN0,
    BL_IMEM_LEN1,
    BL_IMEM_LEN2,
    BL_IMEM_LEN3,
    BL_DMEM_LEN0,
    BL_DMEM_LEN1,
    BL_DMEM_LEN2,
    BL_DMEM_LEN3,
    BL_IMEM_DATA,
    BL_DMEM_DATA,
    BL_DONE,
    BL_ERROR
  );

  signal spi_state  : spi_state_t := SPI_IDLE;
  signal boot_state : boot_state_t := BL_IDLE;

  signal div_cnt   : integer range 0 to CLK_DIV-1 := 0;
  signal sck_r     : std_logic := '0';
  signal cs_n_r    : std_logic := '1';
  signal mosi_r    : std_logic := '0';
  signal tx_shift  : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_shift  : std_logic_vector(7 downto 0) := (others => '0');
  signal bit_idx   : integer range 0 to 7 := 7;

  signal byte_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal byte_valid : std_logic := '0';

  signal imem_len       : unsigned(31 downto 0) := (others => '0');
  signal dmem_len       : unsigned(31 downto 0) := (others => '0');
  signal bytes_rcvd     : unsigned(31 downto 0) := (others => '0');
  signal word_index     : unsigned(31 downto 0) := (others => '0');
  signal byte_in_word   : integer range 0 to 3 := 0;
  signal word_buf       : std_logic_vector(31 downto 0) := (others => '0');

  signal imem_we_r      : std_logic := '0';
  signal imem_addr_r    : std_logic_vector(31 downto 0) := (others => '0');
  signal imem_wdata_r   : std_logic_vector(31 downto 0) := (others => '0');
  signal dmem_we_r      : std_logic := '0';
  signal dmem_addr_r    : std_logic_vector(31 downto 0) := (others => '0');
  signal dmem_wdata_r   : std_logic_vector(31 downto 0) := (others => '0');
  signal done_r         : std_logic := '0';
  signal error_r        : std_logic := '0';

begin

  spi_sck_o  <= sck_r;
  spi_cs_n_o <= cs_n_r;
  spi_mosi_o <= mosi_r;

  imem_prog_we_o    <= imem_we_r;
  imem_prog_addr_o  <= imem_addr_r;
  imem_prog_wdata_o <= imem_wdata_r;
  dmem_prog_we_o    <= dmem_we_r;
  dmem_prog_addr_o  <= dmem_addr_r;
  dmem_prog_wdata_o <= dmem_wdata_r;
  done_o            <= done_r;
  error_o           <= error_r;

  process(clk)
    variable rx_next : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      byte_valid <= '0';

      if reset = '1' or start = '0' or done_r = '1' or error_r = '1' then
        spi_state  <= SPI_IDLE;
        div_cnt    <= 0;
        sck_r      <= '0';
        cs_n_r     <= '1';
        mosi_r     <= '0';
        tx_shift   <= (others => '0');
        rx_shift   <= (others => '0');
        bit_idx    <= 7;
      else
        if spi_state = SPI_IDLE then
          spi_state <= SPI_CMD;
          cs_n_r    <= '0';
          sck_r     <= '0';
          tx_shift  <= x"03";
          bit_idx   <= 7;
          mosi_r    <= '0';
          div_cnt   <= 0;
        elsif div_cnt = CLK_DIV-1 then
          div_cnt <= 0;

          if sck_r = '0' then
            sck_r <= '1';

            if spi_state = SPI_READ then
              rx_next := rx_shift;
              rx_next(bit_idx) := spi_miso_i;
              rx_shift <= rx_next;

              if bit_idx = 0 then
                byte_data  <= rx_next;
                byte_valid <= '1';
              end if;
            end if;
          else
            sck_r <= '0';

            if bit_idx = 0 then
              bit_idx <= 7;

              case spi_state is
                when SPI_CMD =>
                  spi_state <= SPI_ADDR2;
                  tx_shift  <= x"00";
                when SPI_ADDR2 =>
                  spi_state <= SPI_ADDR1;
                  tx_shift  <= x"00";
                when SPI_ADDR1 =>
                  spi_state <= SPI_ADDR0;
                  tx_shift  <= x"00";
                when SPI_ADDR0 =>
                  spi_state <= SPI_READ;
                  tx_shift  <= (others => '0');
                  rx_shift  <= (others => '0');
                when others =>
                  rx_shift <= (others => '0');
              end case;
            else
              bit_idx <= bit_idx - 1;
            end if;
          end if;
        else
          div_cnt <= div_cnt + 1;
        end if;

        if sck_r = '0' and spi_state /= SPI_IDLE then
          mosi_r <= tx_shift(bit_idx);
        end if;
      end if;
    end if;
  end process;

  process(clk)
    variable next_word : std_logic_vector(31 downto 0);
    variable dmem_len_next : unsigned(31 downto 0);
  begin
    if rising_edge(clk) then
      imem_we_r <= '0';
      dmem_we_r <= '0';

      if reset = '1' or start = '0' then
        boot_state   <= BL_IDLE;
        imem_len     <= (others => '0');
        dmem_len     <= (others => '0');
        bytes_rcvd   <= (others => '0');
        word_index   <= (others => '0');
        byte_in_word <= 0;
        word_buf     <= (others => '0');
        done_r       <= '0';
        error_r      <= '0';
      else
        if boot_state = BL_IDLE then
          boot_state <= BL_MAGIC0;
          done_r     <= '0';
          error_r    <= '0';
        elsif byte_valid = '1' then
          case boot_state is
            when BL_MAGIC0 =>
              if byte_data = x"55" then
                boot_state <= BL_MAGIC1;
              else
                boot_state <= BL_ERROR;
                error_r    <= '1';
              end if;

            when BL_MAGIC1 =>
              if byte_data = x"AA" then
                boot_state <= BL_IMEM_LEN0;
              else
                boot_state <= BL_ERROR;
                error_r    <= '1';
              end if;

            when BL_IMEM_LEN0 =>
              imem_len(7 downto 0) <= unsigned(byte_data);
              boot_state <= BL_IMEM_LEN1;
            when BL_IMEM_LEN1 =>
              imem_len(15 downto 8) <= unsigned(byte_data);
              boot_state <= BL_IMEM_LEN2;
            when BL_IMEM_LEN2 =>
              imem_len(23 downto 16) <= unsigned(byte_data);
              boot_state <= BL_IMEM_LEN3;
            when BL_IMEM_LEN3 =>
              imem_len(31 downto 24) <= unsigned(byte_data);
              boot_state <= BL_DMEM_LEN0;

            when BL_DMEM_LEN0 =>
              dmem_len(7 downto 0) <= unsigned(byte_data);
              boot_state <= BL_DMEM_LEN1;
            when BL_DMEM_LEN1 =>
              dmem_len(15 downto 8) <= unsigned(byte_data);
              boot_state <= BL_DMEM_LEN2;
            when BL_DMEM_LEN2 =>
              dmem_len(23 downto 16) <= unsigned(byte_data);
              boot_state <= BL_DMEM_LEN3;
            when BL_DMEM_LEN3 =>
              dmem_len_next := unsigned(byte_data) & dmem_len(23 downto 0);
              dmem_len <= dmem_len_next;
              bytes_rcvd   <= (others => '0');
              word_index   <= (others => '0');
              byte_in_word <= 0;
              word_buf     <= (others => '0');

              if imem_len = 0 then
                if dmem_len_next = 0 then
                  boot_state <= BL_DONE;
                  done_r     <= '1';
                else
                  boot_state <= BL_DMEM_DATA;
                end if;
              else
                boot_state <= BL_IMEM_DATA;
              end if;

            when BL_IMEM_DATA =>
              next_word := word_buf;
              case byte_in_word is
                when 0 => next_word(7 downto 0) := byte_data;
                when 1 => next_word(15 downto 8) := byte_data;
                when 2 => next_word(23 downto 16) := byte_data;
                when others => next_word(31 downto 24) := byte_data;
              end case;

              word_buf   <= next_word;
              bytes_rcvd <= bytes_rcvd + 1;

              if byte_in_word = 3 then
                imem_we_r    <= '1';
                imem_addr_r  <= std_logic_vector(shift_left(word_index, 2));
                imem_wdata_r <= next_word;
                word_index   <= word_index + 1;
                byte_in_word <= 0;
                word_buf     <= (others => '0');
              else
                byte_in_word <= byte_in_word + 1;
              end if;

              if (bytes_rcvd + 1) = imem_len then
                if byte_in_word /= 3 then
                  imem_we_r    <= '1';
                  imem_addr_r  <= std_logic_vector(shift_left(word_index, 2));
                  imem_wdata_r <= next_word;
                end if;

                bytes_rcvd   <= (others => '0');
                word_index   <= (others => '0');
                byte_in_word <= 0;
                word_buf     <= (others => '0');

                if dmem_len = 0 then
                  boot_state <= BL_DONE;
                  done_r     <= '1';
                else
                  boot_state <= BL_DMEM_DATA;
                end if;
              end if;

            when BL_DMEM_DATA =>
              next_word := word_buf;
              case byte_in_word is
                when 0 => next_word(7 downto 0) := byte_data;
                when 1 => next_word(15 downto 8) := byte_data;
                when 2 => next_word(23 downto 16) := byte_data;
                when others => next_word(31 downto 24) := byte_data;
              end case;

              word_buf   <= next_word;
              bytes_rcvd <= bytes_rcvd + 1;

              if byte_in_word = 3 then
                dmem_we_r    <= '1';
                dmem_addr_r  <= std_logic_vector(shift_left(word_index, 2));
                dmem_wdata_r <= next_word;
                word_index   <= word_index + 1;
                byte_in_word <= 0;
                word_buf     <= (others => '0');
              else
                byte_in_word <= byte_in_word + 1;
              end if;

              if (bytes_rcvd + 1) = dmem_len then
                if byte_in_word /= 3 then
                  dmem_we_r    <= '1';
                  dmem_addr_r  <= std_logic_vector(shift_left(word_index, 2));
                  dmem_wdata_r <= next_word;
                end if;

                boot_state <= BL_DONE;
                done_r     <= '1';
              end if;

            when BL_DONE =>
              done_r <= '1';
            when BL_ERROR =>
              error_r <= '1';
            when others =>
              null;
          end case;
        end if;
      end if;
    end if;
  end process;

end rtl;
