


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Output_Interface is
    generic (  
             adders_length : integer := 7 ;
             sample_size : integer := 16 ;
             sync_length : integer := 16 ;
             windows : integer := 256
              );
    Port ( clk,reset : in STD_LOGIC;
            tready : in  std_logic;
             power0, power1 : in signed (31 downto 0);
             sync_detected : in STD_LOGIC;
             power_valid,adders_valid : in STD_LOGIC;
             adders_out : in STD_LOGIC_VECTOR ((adders_length-1) downto 0);
            tdata  : out std_logic_vector(35 downto 0);
            tvalid : out std_logic    
    );
end Output_Interface;

architecture Behavioral of Output_Interface is
type statType is (power_0,power_1,sync,adders);
signal state , next_stat : statType ; 
signal tvalid_reg : std_logic; 
signal power_send,adders_send,sync_send : std_logic; 
begin
process(clk)
begin
if rising_edge(clk) then 
 if reset ='1' then
    tvalid_reg <= '0';
    state <= power_0;

    power_send  <= '0';
    sync_send   <= '0';
    adders_send <= '0';

 else
    if power_valid = '1' then
        power_send <= '1';
    end if;

    if sync_detected = '1' then
        sync_send <= '1';
    end if;

    if adders_valid = '1' then
        adders_send <= '1';
    end if;
      if tvalid_reg = '0' then

        if adders_send = '1' then
            state <= adders;
            tvalid_reg <= '1';
            adders_send <= '0';

        elsif sync_send = '1' then
            state <= sync;
            tvalid_reg <= '1';
            sync_send <= '0';

        elsif power_send = '1' then
            state <= power_0;
            tvalid_reg <= '1';
            power_send <= '0';
        end if;
       elsif tvalid_reg = '1' and tready = '1' then

    if state = power_0 then
        state <= power_1;
        tvalid_reg <= '1'; 

    else
        state <= power_0;
        tvalid_reg <= '0';
    end if;

end if; 
   end if;
 end if;            
 end process;       
process (state, power0, power1, sync_detected, adders_out)
begin
    tdata <= (others => '0');
case state is
     when power_0=>
     tdata (35 downto 32) <= "0001";     
      tdata(31 downto 0) <= std_logic_vector (power0); 
      when power_1=>
       tdata (35 downto 32) <= "0010";   
      tdata(31 downto 0) <= std_logic_vector (power1);
    
      when sync=> 
       tdata (35 downto 32) <= "0011";   
       tdata(0) <= sync_detected;
       when adders =>
        tdata (35 downto 32) <= "0100";   
        tdata (6 downto 0) <= adders_out;
       end case;
end process;                 
tvalid <= tvalid_reg;
end Behavioral;
