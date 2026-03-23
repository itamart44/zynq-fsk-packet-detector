


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Adders_Extractor is
    generic ( adders_length : integer := 7 );
    Port ( clk, reset : in STD_LOGIC;
           bit_in : in STD_LOGIC;
           bit_valid : in STD_LOGIC;
           sync_detected : in STD_LOGIC;
           adders_out : out STD_LOGIC_VECTOR ((adders_length-1) downto 0);
           adders_valid : out STD_LOGIC);
end Adders_Extractor;

architecture Behavioral of Adders_Extractor is
signal index : integer range 0 to (adders_length-1) := 0 ;
signal collecting : std_logic := '0';
begin
process(clk)
begin
if rising_edge(clk) then
   if reset ='1' then
       adders_out <= (others => '0');
       adders_valid <=  '0';
       collecting <=  '0';
       index <= 0 ;
    else
       adders_valid <= '0';
       if sync_detected = '1' then
       collecting <= '1';
       index <= 0 ;
       end if;
     if bit_valid  = '1' and collecting = '1' then
       adders_out(index) <= bit_in ; 
       if index = (adders_length-1) then
          index <= 0 ;
          adders_valid <= '1';
          collecting <=  '0';
       else 
          index <= index +1;
       end if;
     end if;
    end if;               
end if;       
     end process;   
end Behavioral;
