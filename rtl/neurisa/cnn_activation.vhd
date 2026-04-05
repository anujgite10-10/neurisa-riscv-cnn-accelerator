-- ================================================================================
-- NeurISA — Activation Function Engine (ReLU & Leaky ReLU)
-- ================================================================================
-- Supports ReLU: f(x) = max(0, x)
-- Supports Leaky ReLU: f(x) = x if x >= 0, else x/8 (shift-based approx)
-- Operates on both scalar INT32 (from conv accumulator) and packed 4×INT8
-- ================================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cnn_activation is
  port (
    clk_i          : in  std_ulogic;
    rstn_i         : in  std_ulogic;
    -- Control --
    mode_i         : in  std_ulogic_vector(1 downto 0); -- "00"=ReLU, "01"=LeakyReLU, "10"=bypass
    packed_i       : in  std_ulogic;                     -- '1' = packed 4×INT8, '0' = scalar INT32
    -- Input --
    data_i         : in  std_ulogic_vector(31 downto 0);
    valid_i        : in  std_ulogic;
    -- Output --
    data_o         : out std_ulogic_vector(31 downto 0);
    valid_o        : out std_ulogic
  );
end cnn_activation;

architecture rtl of cnn_activation is

  constant MODE_RELU       : std_ulogic_vector(1 downto 0) := "00";
  constant MODE_LEAKY_RELU : std_ulogic_vector(1 downto 0) := "01";
  constant MODE_BYPASS     : std_ulogic_vector(1 downto 0) := "10";

begin

  -- Pure combinatorial activation with registered output
  act_proc: process(rstn_i, clk_i)
    variable scalar_val : signed(31 downto 0);
    variable byte_val   : signed(7 downto 0);
    variable leaky_byte : signed(7 downto 0);
    variable leaky_scl  : signed(31 downto 0);
  begin
    if rstn_i = '0' then
      data_o  <= (others => '0');
      valid_o <= '0';
    elsif rising_edge(clk_i) then
      valid_o <= valid_i;

      if valid_i = '1' then
        case mode_i is
          when MODE_RELU =>
            if packed_i = '1' then
              -- Packed 4×INT8 ReLU
              for i in 0 to 3 loop
                byte_val := signed(data_i(i*8+7 downto i*8));
                if byte_val >= 0 then
                  data_o(i*8+7 downto i*8) <= data_i(i*8+7 downto i*8);
                else
                  data_o(i*8+7 downto i*8) <= (others => '0');
                end if;
              end loop;
            else
              -- Scalar INT32 ReLU
              scalar_val := signed(data_i);
              if scalar_val >= 0 then
                data_o <= data_i;
              else
                data_o <= (others => '0');
              end if;
            end if;

          when MODE_LEAKY_RELU =>
            if packed_i = '1' then
              -- Packed 4×INT8 Leaky ReLU (leak = x/8)
              for i in 0 to 3 loop
                byte_val := signed(data_i(i*8+7 downto i*8));
                if byte_val >= 0 then
                  data_o(i*8+7 downto i*8) <= data_i(i*8+7 downto i*8);
                else
                  leaky_byte := shift_right(byte_val, 3); -- divide by 8
                  data_o(i*8+7 downto i*8) <= std_ulogic_vector(leaky_byte);
                end if;
              end loop;
            else
              -- Scalar INT32 Leaky ReLU
              scalar_val := signed(data_i);
              if scalar_val >= 0 then
                data_o <= data_i;
              else
                leaky_scl := shift_right(scalar_val, 3);
                data_o <= std_ulogic_vector(leaky_scl);
              end if;
            end if;

          when others => -- MODE_BYPASS and default
            data_o <= data_i;

        end case;
      end if;
    end if;
  end process act_proc;

end rtl;
