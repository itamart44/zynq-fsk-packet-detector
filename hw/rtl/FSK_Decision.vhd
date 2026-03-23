


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity FSK_Decision is
    Port ( clk, reset : in STD_LOGIC;
           power0, power1 : in signed (31 downto 0);
           power_valid : in STD_LOGIC;
           bit_valid : out STD_LOGIC;
           bit_out : out STD_LOGIC);
end FSK_Decision;

architecture Behavioral of FSK_Decision is

begin
process(clk)
begin
if rising_edge(clk) then
   if reset = '1' then
   bit_valid <= '0' ;
   bit_out <= '0';
   else
     bit_valid <= '0' ;
     if power_valid = '1' then
       if power0 > power1 then
       bit_out <= '1' ;
       else
       bit_out <= '0' ;
       end if;
       bit_valid <= '1' ;
      end if;
     end if;
  end if;
  end process;       
end Behavioral;
