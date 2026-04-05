-- ================================================================================
-- NeurISA — 3×3 Convolution Processing Element Array
-- ================================================================================
-- Implements a 3×3 kernel convolution engine using INT8 arithmetic
-- with 9 parallel MAC units arranged as a systolic array.
--   - Supports configurable input/output channels
--   - INT8 weights, INT8 activations, INT32 partial sums
--   - Line buffer based sliding window
-- ================================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cnn_conv_engine is
  generic (
    KERNEL_SIZE : natural := 3;   -- 3×3 kernel
    DATA_WIDTH  : natural := 8;   -- INT8
    ACCUM_WIDTH : natural := 32   -- INT32 accumulator
  );
  port (
    clk_i          : in  std_ulogic;
    rstn_i         : in  std_ulogic;
    -- Control --
    start_i        : in  std_ulogic;  -- start convolution
    clear_accum_i  : in  std_ulogic;  -- clear accumulator
    done_o         : out std_ulogic;  -- convolution complete
    busy_o         : out std_ulogic;  -- engine busy
    -- Kernel weights (3×3 = 9 weights, loaded serially) --
    weight_data_i  : in  std_ulogic_vector(DATA_WIDTH-1 downto 0);
    weight_valid_i : in  std_ulogic;
    weight_addr_i  : in  std_ulogic_vector(3 downto 0); -- 0..8
    -- Input feature data (sliding window, 3×3 patch) --
    pixel_data_i   : in  std_ulogic_vector(DATA_WIDTH-1 downto 0);
    pixel_valid_i  : in  std_ulogic;
    pixel_row_i    : in  std_ulogic_vector(1 downto 0); -- 0..2
    pixel_col_i    : in  std_ulogic_vector(1 downto 0); -- 0..2
    -- Output --
    result_o       : out std_ulogic_vector(ACCUM_WIDTH-1 downto 0);
    result_valid_o : out std_ulogic
  );
end cnn_conv_engine;

architecture rtl of cnn_conv_engine is

  -- Weight register file: 3×3 = 9 weights
  type weight_array_t is array (0 to KERNEL_SIZE*KERNEL_SIZE-1) of signed(DATA_WIDTH-1 downto 0);
  signal weights : weight_array_t;

  -- Input patch buffer: 3×3 = 9 pixels
  type patch_array_t is array (0 to KERNEL_SIZE*KERNEL_SIZE-1) of signed(DATA_WIDTH-1 downto 0);
  signal patch : patch_array_t;

  -- Multiply results (9 products)
  type product_array_t is array (0 to KERNEL_SIZE*KERNEL_SIZE-1) of signed(2*DATA_WIDTH-1 downto 0);
  signal products : product_array_t;

  -- Adder tree signals
  signal sum_01, sum_23, sum_45, sum_67 : signed(ACCUM_WIDTH-1 downto 0);
  signal sum_0123, sum_4567             : signed(ACCUM_WIDTH-1 downto 0);
  signal sum_01234567                   : signed(ACCUM_WIDTH-1 downto 0);
  signal sum_all                        : signed(ACCUM_WIDTH-1 downto 0);

  -- Accumulator
  signal accum : signed(ACCUM_WIDTH-1 downto 0);

  -- Pipeline control
  type state_t is (IDLE, MULTIPLY, ADD_TREE, OUTPUT);
  signal state      : state_t;
  signal patch_full  : std_ulogic;
  signal pixel_count : unsigned(3 downto 0);

begin

  -- ============================================================
  -- Weight Loading
  -- ============================================================
  weight_load: process(rstn_i, clk_i)
  begin
    if rstn_i = '0' then
      weights <= (others => (others => '0'));
    elsif rising_edge(clk_i) then
      if weight_valid_i = '1' then
        weights(to_integer(unsigned(weight_addr_i))) <= signed(weight_data_i);
      end if;
    end if;
  end process weight_load;

  -- ============================================================
  -- Pixel Patch Loading
  -- ============================================================
  pixel_load: process(rstn_i, clk_i)
    variable idx : natural;
  begin
    if rstn_i = '0' then
      patch       <= (others => (others => '0'));
      pixel_count <= (others => '0');
      patch_full  <= '0';
    elsif rising_edge(clk_i) then
      patch_full <= '0';
      if start_i = '1' then
        pixel_count <= (others => '0');
      end if;
      if pixel_valid_i = '1' then
        idx := to_integer(unsigned(pixel_row_i)) * KERNEL_SIZE +
               to_integer(unsigned(pixel_col_i));
        patch(idx) <= signed(pixel_data_i);
        pixel_count <= pixel_count + 1;
        if pixel_count = to_unsigned(KERNEL_SIZE*KERNEL_SIZE-1, 4) then
          patch_full  <= '1';
          pixel_count <= (others => '0');
        end if;
      end if;
    end if;
  end process pixel_load;

  -- ============================================================
  -- 9 Parallel Multipliers (combinatorial)
  -- ============================================================
  mul_gen: for i in 0 to KERNEL_SIZE*KERNEL_SIZE-1 generate
    products(i) <= weights(i) * patch(i);
  end generate;

  -- ============================================================
  -- Adder Tree (combinatorial)
  -- ============================================================
  sum_01       <= resize(products(0), ACCUM_WIDTH) + resize(products(1), ACCUM_WIDTH);
  sum_23       <= resize(products(2), ACCUM_WIDTH) + resize(products(3), ACCUM_WIDTH);
  sum_45       <= resize(products(4), ACCUM_WIDTH) + resize(products(5), ACCUM_WIDTH);
  sum_67       <= resize(products(6), ACCUM_WIDTH) + resize(products(7), ACCUM_WIDTH);
  sum_0123     <= sum_01 + sum_23;
  sum_4567     <= sum_45 + sum_67;
  sum_01234567 <= sum_0123 + sum_4567;
  sum_all      <= sum_01234567 + resize(products(8), ACCUM_WIDTH);

  -- ============================================================
  -- Convolution FSM & Accumulator
  -- ============================================================
  conv_fsm: process(rstn_i, clk_i)
  begin
    if rstn_i = '0' then
      state  <= IDLE;
      accum  <= (others => '0');
      done_o <= '0';
      busy_o <= '0';
      result_valid_o <= '0';
    elsif rising_edge(clk_i) then
      done_o         <= '0';
      result_valid_o <= '0';

      case state is
        when IDLE =>
          busy_o <= '0';
          if clear_accum_i = '1' then
            accum <= (others => '0');
          end if;
          if patch_full = '1' then
            state  <= MULTIPLY;
            busy_o <= '1';
          end if;

        when MULTIPLY =>
          -- Products are combinatorial, advance to add tree
          state <= ADD_TREE;

        when ADD_TREE =>
          -- Accumulate
          accum <= accum + sum_all;
          state <= OUTPUT;

        when OUTPUT =>
          done_o         <= '1';
          result_valid_o <= '1';
          busy_o         <= '0';
          state          <= IDLE;

        when others =>
          state <= IDLE;
      end case;
    end if;
  end process conv_fsm;

  result_o <= std_ulogic_vector(accum);

end rtl;
