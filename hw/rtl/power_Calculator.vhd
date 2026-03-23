


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity power_Calculator is
     generic (   sample_size : integer := 16 );
    Port ( clk, reset : in STD_LOGIC;
           bin0_real : in signed ((sample_size-1) downto 0);
           bin0_imeg : in signed ((sample_size-1) downto 0);
           bin1_real : in signed ((sample_size-1) downto 0);
           bin1_imeg : in signed ((sample_size-1) downto 0);
           bins_valid : in STD_LOGIC;
           power0 : out signed (31 downto 0);     
           power1 : out signed (31 downto 0);
           power_valid : out STD_LOGIC);
end power_Calculator;

architecture Behavioral of power_Calculator is

begin
process (clk)
begin
if rising_edge(clk) then
   if reset = '1' then
    power0<= (others => '0' );
    power1<= (others => '0' );
    power_valid <= '0';
   else
    power_valid<= '0'; 
    if bins_valid = '1' then 
    power0 <= (bin0_real* bin0_real) + (bin0_imeg*bin0_imeg);
    power1 <= ( bin1_real* bin1_real) +(bin1_imeg*bin1_imeg);
    power_valid<= '1';
    end if;
   end if;
 end if;
 end process;   
end Behavioral;
    
