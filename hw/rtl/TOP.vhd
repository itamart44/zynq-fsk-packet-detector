library IEEE;
library xil_defaultlib;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TOP is
generic ( 
             adders_length : integer := 7 ;
             sample_size : integer := 16 ;
             sync_length : integer := 16 ;
             windows : integer := 256
              );
    Port ( clk, reset : in STD_LOGIC;
           sample_in : in signed ((sample_size-1) downto 0);
           sample_valid : in STD_LOGIC;
           tready : in  std_logic;
           tdata  : out std_logic_vector(35 downto 0);
           tvalid : out std_logic
         );
end TOP;


architecture Behavioral of TOP is
signal sample_out : signed ((sample_size-1) downto 0);
signal sample_out_valid : STD_LOGIC;
signal energy_detected : STD_LOGIC;
signal energy_valid : STD_LOGIC;
signal buffer_full : STD_LOGIC;         
signal read_data  :  signed((sample_size-1) downto 0);
signal read_addr  : integer range 0 to windows-1;
signal fft_data_in : signed((sample_size-1) downto 0);
signal fft_data_ready :  STD_LOGIC; 
signal fft_valid :  STD_LOGIC;
signal fft_start :  STD_LOGIC;
signal fft_out :  STD_LOGIC_vector ( 31 downto 0);
signal fft_ready : std_logic;
signal  bin_k :  integer range 0 to windows -1 ;
signal bin_index_int : integer range 0 to windows-1;
signal fft_output_valid : STD_LOGIC;
signal bin0_real : signed ((sample_size -1) downto 0);
signal bin0_imeg : signed ((sample_size -1) downto 0);
signal bin1_real : signed ((sample_size -1) downto 0);
signal bin1_imeg : signed ((sample_size -1) downto 0);
signal bins_valid :STD_LOGIC;
signal power0 :  signed (31 downto 0);     
signal power1 :  signed (31 downto 0);
signal power_valid :  STD_LOGIC;
signal bit_valid : STD_LOGIC;
signal bit_out : STD_LOGIC;
signal sync_detected : STD_LOGIC;
signal adders_out :  STD_LOGIC_VECTOR ((adders_length-1) downto 0);
signal adders_valid :  STD_LOGIC;
signal fft_bin_index : std_logic_vector(7 downto 0);
signal fft_input_axis : std_logic_vector(31 downto 0);
signal fft_last : std_logic;
signal fft_config_valid : std_logic := '0';
signal fft_config_data  : std_logic_vector(15 downto 0) := (others=>'0');
signal fft_config_ready : std_logic;
component xfft_0
port (
    aclk : in std_logic;

    s_axis_config_tdata  : in std_logic_vector(15 downto 0);
    s_axis_config_tvalid : in std_logic;
    s_axis_config_tready : out std_logic;

    s_axis_data_tdata  : in std_logic_vector(31 downto 0);
    s_axis_data_tvalid : in std_logic;
    s_axis_data_tready : out std_logic;
    s_axis_data_tlast  : in std_logic;

    m_axis_data_tdata  : out std_logic_vector(31 downto 0);
    m_axis_data_tvalid : out std_logic;
    m_axis_data_tready : in std_logic;
    m_axis_data_tlast  : out std_logic;
    m_axis_data_tuser : out STD_LOGIC_VECTOR ( 7 downto 0 );
    event_frame_started : out std_logic;
    event_tlast_unexpected : out std_logic;
    event_tlast_missing : out std_logic;
    event_status_channel_halt : out std_logic;
    event_data_in_channel_halt : out std_logic;
    event_data_out_channel_halt : out std_logic
);
end component;

begin
fft_input_axis(31 downto 16) <= std_logic_vector(fft_data_in);
fft_input_axis(15 downto 0)  <= (others => '0'); 
bin_index_int <= to_integer(unsigned(fft_bin_index));
SampleInput_inst : entity work.SampleInput
port map (     clk => clk,
             reset => reset,
        sample_in  => sample_in,
      sample_valid => sample_valid,         
        sample_out => sample_out,
  sample_out_valid => sample_out_valid
);

Energy_Detector_inst : entity work.Energy_Detector
port map (    clk => clk,
            reset => reset, 
       sample_in  =>  sample_out,
     sample_valid =>  sample_out_valid,
  energy_detected =>  energy_detected,
     energy_valid =>  energy_valid
);

sample_buffer_inst : entity work.sample_buffer
port map (     clk => clk,
             reset => reset,
     fft_read_done =>  fft_data_ready,
        sample_in  =>  sample_out,
      sample_valid =>  sample_out_valid,
   energy_detected => energy_detected,
      energy_valid => energy_valid ,
        read_addr  => read_addr,
         read_data =>  read_data,
       buffer_full => buffer_full
);

FFFT_controller_inst : entity work.FFT_controller
port map ( 
    clk => clk,
    reset => reset,
    buffer_ready => buffer_full,     
    read_data  => read_data,
    read_addr  => read_addr,
    fft_data_in => fft_data_in,
    fft_data_ready => fft_data_ready, 
    fft_valid => fft_valid,
    fft_ready => fft_ready,
    fft_last  => fft_last
);

xfft_0_inst : xfft_0
port map (    aclk => clk,
    s_axis_data_tdata  => fft_input_axis,
    s_axis_data_tvalid => fft_valid,
    s_axis_data_tready => fft_ready,
    s_axis_data_tlast  => fft_last,
    m_axis_data_tdata => fft_out,
    m_axis_data_tvalid =>fft_output_valid, 
    m_axis_data_tready => '1',
    m_axis_data_tlast => open,
    m_axis_data_tuser => fft_bin_index,
    
  s_axis_config_tdata  => fft_config_data,
    s_axis_config_tvalid => fft_config_valid,
    s_axis_config_tready => fft_config_ready,
    event_frame_started => open,
    event_tlast_unexpected => open,
    event_tlast_missing => open,
    event_status_channel_halt  => open,
    event_data_in_channel_halt => open,
    event_data_out_channel_halt =>  open
);


 Bin_selector_inst : entity work.Bin_selector 
port map (     clk => clk,
             reset => reset,
             bin_k => bin_index_int, 
      fft_real_out => fft_out (31 downto 16),
      fft_imeg_out => fft_out (15 downto 0),
  fft_output_valid => fft_output_valid,
         bin0_real => bin0_real,
         bin0_imeg =>  bin0_imeg,
         bin1_real => bin1_real,
         bin1_imeg => bin1_imeg,
         bins_valid => bins_valid
);

power_Calculator_inst : entity work.power_Calculator
port map (       clk => clk,
               reset => reset,
           bin0_real => bin0_real,
           bin0_imeg =>  bin0_imeg,
           bin1_real => bin1_real,
           bin1_imeg => bin1_imeg,
          bins_valid => bins_valid,
              power0 => power0, 
              power1 => power1,
        power_valid  => power_valid  
);


 FSK_Decision_inst : entity work.FSK_Decision
port map (     clk => clk,
             reset => reset,
            power0 => power0, 
            power1 => power1,
       power_valid => power_valid,
           bit_valid => bit_valid,
           bit_out => bit_out
);

Sync_Detector_inst : entity work.Sync_Detector
port map (      clk => clk,
             reset => reset,
            bit_in => bit_out,
         bit_valid => bit_valid,
     sync_detected =>  sync_detected
);

Adders_Extractor_inst : entity work.Adders_Extractor
port map (     clk => clk,
             reset => reset,
            bit_in => bit_out,
         bit_valid => bit_valid, 
     sync_detected => sync_detected,
        adders_out => adders_out,
      adders_valid => adders_valid 
);
Output_Interface_inst : entity work.Output_Interface
port map (     clk => clk,
             reset => reset,
            tready => tready,
            power0 => power0, 
            power1 => power1,
     sync_detected => sync_detected,
       power_valid => power_valid,
      adders_valid => adders_valid,
        adders_out => adders_out,
            tdata  => tdata,
            tvalid => tvalid
            );
process(clk)
begin
if rising_edge(clk) then

    if reset='1' then
        fft_config_valid <= '1';

    elsif fft_config_ready='1' then
        fft_config_valid <= '0';
    end if;

end if;
end process;






end Behavioral;
