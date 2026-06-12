library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity channel_selector is
generic (
    N_channel : integer := 2
);
port (
    clk, reset   : in  std_logic;
    power0_in    : in  std_logic_vector(N_channel*32-1 downto 0);
    power1_in    : in  std_logic_vector(N_channel*32-1 downto 0);
    power_valid  : in  std_logic_vector(N_channel-1 downto 0);
    best_channel : out std_logic_vector(2 downto 0);
    best_valid   : out std_logic
);
end channel_selector;

architecture Behavioral of channel_selector is

type power_array is array (0 to N_channel-1) of unsigned(31 downto 0);

signal p0_arr : power_array;
signal p1_arr : power_array;
signal margin : power_array;  -- |P0 - P1|: FSK decision confidence per channel

begin

-- Unpack and compute per-channel margin (combinational).
-- Power values (Re^2 + Im^2) are always non-negative, so unsigned is correct.
-- Margin = |P0 - P1| is the right metric: largest margin = most confident FSK bit.
gen_unpack : for i in 0 to N_channel-1 generate
    p0_arr(i) <= unsigned(power0_in((i+1)*32-1 downto i*32));
    p1_arr(i) <= unsigned(power1_in((i+1)*32-1 downto i*32));

    margin(i) <= p0_arr(i) - p1_arr(i) when p0_arr(i) >= p1_arr(i)
                 else p1_arr(i) - p0_arr(i);
end generate;

-- Find the channel with the largest margin whenever any power update arrives.
-- best_valid and best_channel are sticky: they hold their value between updates.
process(clk)
    variable best_val  : unsigned(31 downto 0);
    variable best_idx  : integer range 0 to N_channel-1;
    variable any_valid : boolean;
begin
    if rising_edge(clk) then
        if reset = '1' then
            best_channel <= (others => '0');
            best_valid   <= '0';
        else
            best_val  := (others => '0');
            best_idx  := 0;
            any_valid := false;

            for i in 0 to N_channel-1 loop
                if power_valid(i) = '1' then
                    any_valid := true;
                    if margin(i) > best_val then
                        best_val := margin(i);
                        best_idx := i;
                    end if;
                end if;
            end loop;

            if any_valid then
                best_channel <= std_logic_vector(to_unsigned(best_idx, 3));
                best_valid   <= '1';
            end if;
        end if;
    end if;
end process;

end Behavioral;
