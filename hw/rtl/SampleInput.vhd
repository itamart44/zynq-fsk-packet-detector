


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;



entity SampleInput is
    generic ( sample_size : integer := 16 );
    Port ( clk, reset : in STD_LOGIC;
           sample_in : in signed ((sample_size-1) downto 0);
           sample_valid : in STD_LOGIC;
           sample_out : out signed ((sample_size-1) downto 0);
           sample_out_valid : out STD_LOGIC);
end SampleInput;

architecture Behavioral of SampleInput is
signal sample_reg : signed((sample_size-1) downto 0);
signal valid_reg  : STD_LOGIC;
begin
process (clk)
begin
if rising_edge (clk) then
 if  reset = '1' then
  sample_reg <= (others => '0' );
    valid_reg<= '0' ;
else
  if sample_valid = '1' then
  sample_reg <=  sample_in;
   valid_reg <= '1' ;
  else
   valid_reg <= '0';
end if;
end if;
end if;
end process;
sample_out <= sample_reg;
sample_out_valid <= valid_reg; 

end Behavioral;
