library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity Sync_Detector is
generic ( sync_length : integer := 16 );
    Port ( clk, reset : in STD_LOGIC;
           bit_in : in STD_LOGIC;
           bit_valid : in STD_LOGIC;
           sync_detected : out STD_LOGIC
         );
end Sync_Detector;

architecture Behavioral of Sync_Detector is

constant SYNC : STD_LOGIC_VECTOR((sync_length-1) downto 0) := "1100010111011000";

signal shift_reg : STD_LOGIC_VECTOR((sync_length-1) downto 0) := (others => '0');

begin

process(clk)
    variable next_shift : STD_LOGIC_VECTOR((sync_length-1) downto 0);
begin
if rising_edge(clk) then

    if reset = '1' then
        shift_reg <= (others => '0');
        sync_detected <= '0';

    else

        sync_detected <= '0';

        if bit_valid = '1' then

          
            next_shift := shift_reg((sync_length-2) downto 0) & bit_in;

            shift_reg <= next_shift;

            if next_shift = SYNC then
                sync_detected <= '1';
            end if;

        end if;

    end if;

end if;
end process;

end Behavioral;
