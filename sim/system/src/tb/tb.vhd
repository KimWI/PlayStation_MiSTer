library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

library tb;
library psx;

library procbus;
use procbus.pProc_bus.all;
use procbus.pRegmap.all;

library reg_map;
use reg_map.pReg_tb.all;

entity etb  is
end entity;

architecture arch of etb is

   constant clk_speed : integer := 100000000;
   constant baud      : integer := 25000000;
 
   signal clk33       : std_logic := '1';
   signal clk66       : std_logic := '1';
   signal clk100      : std_logic := '1';
   
   signal reset       : std_logic;
   
   signal command_in  : std_logic;
   signal command_out : std_logic;
   signal command_out_filter : std_logic;
   
   signal proc_bus_in : proc_bus_type;
   
   -- settings
   signal psx_on              : std_logic_vector(Reg_psx_on.upper             downto Reg_psx_on.lower)             := (others => '0');
   signal psx_LoadExe         : std_logic_vector(Reg_psx_LoadExe.upper        downto Reg_psx_LoadExe.lower)        := (others => '0');
   signal psx_SaveState       : std_logic_vector(Reg_psx_SaveState.upper      downto Reg_psx_SaveState.lower)      := (others => '0');
   signal psx_LoadState       : std_logic_vector(Reg_psx_LoadState.upper      downto Reg_psx_LoadState.lower)      := (others => '0');
   
   signal bus_out_Din         : std_logic_vector(31 downto 0);
   signal bus_out_Dout        : std_logic_vector(31 downto 0);
   signal bus_out_Adr         : std_logic_vector(25 downto 0);
   signal bus_out_rnw         : std_logic;
   signal bus_out_ena         : std_logic;
   signal bus_out_done        : std_logic;
      
   signal SAVE_out_Din        : std_logic_vector(63 downto 0);
   signal SAVE_out_Dout       : std_logic_vector(63 downto 0);
   signal SAVE_out_Adr        : std_logic_vector(25 downto 0);
   signal SAVE_out_be         : std_logic_vector(7 downto 0);
   signal SAVE_out_rnw        : std_logic;                    
   signal SAVE_out_ena        : std_logic;                    
   signal SAVE_out_active     : std_logic;                    
   signal SAVE_out_done       : std_logic;                    
      
   signal cpu_loopback        : std_logic_vector(31 downto 0);
      
   signal Cheat_written       : std_logic;
   signal cheats_vector       : std_logic_vector(127 downto 0);
   
   -- psx signals    
   signal pixel_out_x         : integer range 0 to 239;
   signal pixel_out_y         : integer range 0 to 159;
   signal pixel_out_data      : std_logic_vector(17 downto 0);  
   signal pixel_out_we        : std_logic;
                           
   signal sound_out_left      : std_logic_vector(15 downto 0);
   signal sound_out_right     : std_logic_vector(15 downto 0);
      
   --sdram access 
   signal ram_dataWrite       : std_logic_vector(31 downto 0);
   signal ram_dataRead        : std_logic_vector(127 downto 0);
   signal ram_Adr             : std_logic_vector(22 downto 0);
   signal ram_be              : std_logic_vector(3 downto 0);
   signal ram_rnw             : std_logic;
   signal ram_ena             : std_logic;
   signal ram_128             : std_logic;
   signal ram_done            : std_logic;   
   signal ram_reqprocessed    : std_logic;   
   signal ram_idle            : std_logic;   
   
   -- ddrram
   signal DDRAM_CLK           : std_logic;
   signal DDRAM_BUSY          : std_logic;
   signal DDRAM_BURSTCNT      : std_logic_vector(7 downto 0);
   signal DDRAM_ADDR          : std_logic_vector(28 downto 0);
   signal DDRAM_DOUT          : std_logic_vector(63 downto 0);
   signal DDRAM_DOUT_READY    : std_logic;
   signal DDRAM_RD            : std_logic;
   signal DDRAM_DIN           : std_logic_vector(63 downto 0);
   signal DDRAM_BE            : std_logic_vector(7 downto 0);
   signal DDRAM_WE            : std_logic;
   
   -- video
   signal hblank              : std_logic;
   signal vblank              : std_logic;
   signal video_ce            : std_logic;
   signal video_interlace     : std_logic;
   signal video_r             : std_logic_vector(7 downto 0);
   signal video_g             : std_logic_vector(7 downto 0);
   signal video_b             : std_logic_vector(7 downto 0);
   
   -- keys
   signal KeyTriangle         : std_logic := '0'; 
   signal KeyCircle           : std_logic := '0'; 
   signal KeyCross            : std_logic := '0'; 
   signal KeySquare           : std_logic := '0';
   signal KeySelect           : std_logic := '0';
   signal KeyStart            : std_logic := '0';
   signal KeyRight            : std_logic := '0';
   signal KeyLeft             : std_logic := '0';
   signal KeyUp               : std_logic := '0';
   signal KeyDown             : std_logic := '0';
   signal KeyR1               : std_logic := '0';
   signal KeyR2               : std_logic := '0';
   signal KeyR3               : std_logic := '0';
   signal KeyL1               : std_logic := '0';
   signal KeyL2               : std_logic := '0';
   signal KeyL3               : std_logic := '0';
   signal Analog1X            : signed(7 downto 0) := (others => '0');
   signal Analog1Y            : signed(7 downto 0) := (others => '0');
   signal Analog2X            : signed(7 downto 0) := (others => '0');
   signal Analog2Y            : signed(7 downto 0) := (others => '0'); 
   
   --cd
   signal cd_req              : std_logic;
   signal cd_addr             : std_logic_vector(26 downto 0) := (others => '0');
   signal cd_data             : std_logic_vector(31 downto 0);
   signal cd_done             : std_logic := '0';
   
   signal ram2_do             : std_logic_vector(127 downto 0);
   
   signal cdSize              : unsigned(29 downto 0);
   
   
begin

   clk33  <= not clk33  after 15 ns;
   clk66  <= not clk66  after 7500 ps;
   clk100 <= not clk100 after 5 ns;
   
   reset  <= not psx_on(0);
   
   KeyTriangle <= '0';
   KeyCircle   <= '0';
   KeyCross    <= '0';
   KeySquare   <= '0';
   KeySelect   <= '0';
   KeyStart    <= '0';
   KeyRight    <= '0'; --'1' after 300 ms;
   KeyLeft     <= '0';
   KeyUp       <= '0';
   KeyDown     <= '0';
   KeyR1       <= '0';
   KeyR2       <= '0';
   KeyR3       <= '0';
   KeyL1       <= '0';
   KeyL2       <= '0';
   KeyL3       <= '0';
   Analog1X    <= (others => '0');
   Analog1Y    <= (others => '0');
   Analog2X    <= (others => '0');
   Analog2Y    <= (others => '0');
   
   -- registers
   iReg_psx_on            : entity procbus.eProcReg generic map (Reg_psx_on)        port map (clk100, proc_bus_in, psx_on        , psx_on);      
   iReg_psx_LoadExe       : entity procbus.eProcReg generic map (Reg_psx_LoadExe)   port map (clk100, proc_bus_in, psx_LoadExe   , psx_LoadExe); 
   iReg_psx_SaveState     : entity procbus.eProcReg generic map (Reg_psx_SaveState) port map (clk100, proc_bus_in, psx_SaveState , psx_SaveState);      
   iReg_psx_LoadState     : entity procbus.eProcReg generic map (Reg_psx_LoadState) port map (clk100, proc_bus_in, psx_LoadState , psx_LoadState);   
     
   ipsx_mister : entity psx.psx_mister
   generic map
   (
      is_simu               => '1',
      REPRODUCIBLEGPUTIMING => '0',
      REPRODUCIBLEDMATIMING => '1'
   )
   port map
   (
      clk1x                 => clk33,          
      clk2x                 => clk66, 
      reset                 => reset,
      -- commands 
      loadExe               => psx_LoadExe(0),
      fastboot              => '1',
      -- RAM/BIOS interface        
      ram_dataWrite         => ram_dataWrite,
      ram_dataRead          => ram_dataRead, 
      ram_Adr               => ram_Adr,      
      ram_be                => ram_be,      
      ram_rnw               => ram_rnw,      
      ram_ena               => ram_ena,      
      ram_128               => ram_128,      
      ram_done              => ram_done,
      ram_reqprocessed      => ram_reqprocessed,
      ram_idle              => ram_idle,
      -- vram/ddr3 interface
      DDRAM_BUSY            => DDRAM_BUSY,      
      DDRAM_BURSTCNT        => DDRAM_BURSTCNT,  
      DDRAM_ADDR            => DDRAM_ADDR,      
      DDRAM_DOUT            => DDRAM_DOUT,      
      DDRAM_DOUT_READY      => DDRAM_DOUT_READY,
      DDRAM_RD              => DDRAM_RD,        
      DDRAM_DIN             => DDRAM_DIN,       
      DDRAM_BE              => DDRAM_BE,        
      DDRAM_WE              => DDRAM_WE,
      -- cd
      fastCD                => '1',
      cd_Size               => cdSize,
      cd_req                => cd_req, 
      cd_addr               => cd_addr,
      cd_data               => cd_data,
      cd_done               => cd_done,
      -- video
      videoout_on           => '1',
      isPal                 => '1',
      hblank                => hblank,  
      vblank                => vblank,  
      video_ce              => video_ce,
      video_interlace       => video_interlace,
      video_r               => video_r, 
      video_g               => video_g,    
      video_b               => video_b,   
      -- Keys - all active high
      KeyTriangle           => KeyTriangle,           
      KeyCircle             => KeyCircle,           
      KeyCross              => KeyCross,           
      KeySquare             => KeySquare,           
      KeySelect             => KeySelect,      
      KeyStart              => KeyStart,       
      KeyRight              => KeyRight,       
      KeyLeft               => KeyLeft,        
      KeyUp                 => KeyUp,          
      KeyDown               => KeyDown,        
      KeyR1                 => KeyR1,           
      KeyR2                 => KeyR2,           
      KeyR3                 => KeyR3,           
      KeyL1                 => KeyL1,           
      KeyL2                 => KeyL2,           
      KeyL3                 => KeyL3,           
      Analog1X              => Analog1X,       
      Analog1Y              => Analog1Y,       
      Analog2X              => Analog2X,       
      Analog2Y              => Analog2Y,      
      -- sound              => -- sound       
      sound_out_left        => sound_out_left, 
      sound_out_right       => sound_out_right,
      -- savestates              
      increaseSSHeaderCount => '0',
      save_state            => psx_SaveState(0),
      load_state            => psx_LoadState(0),
      savestate_number      => 0,
      state_loaded          => open,
      rewind_on             => '0',
      rewind_active         => '0'
   );
   
   iddrram_model : entity tb.ddrram_model
   port map
   (
      DDRAM_CLK        => clk66,      
      DDRAM_BUSY       => DDRAM_BUSY,      
      DDRAM_BURSTCNT   => DDRAM_BURSTCNT,  
      DDRAM_ADDR       => DDRAM_ADDR,      
      DDRAM_DOUT       => DDRAM_DOUT,      
      DDRAM_DOUT_READY => DDRAM_DOUT_READY,
      DDRAM_RD         => DDRAM_RD,        
      DDRAM_DIN        => DDRAM_DIN,       
      DDRAM_BE         => DDRAM_BE,        
      DDRAM_WE         => DDRAM_WE        
   );
   
   isdram_model : entity tb.sdram_model 
   generic map
   (
      SCRIPTLOADING => '1'
   )
   port map
   (
      clk          => clk33,
      addr(26 downto 23) => "0000",
      addr(22 downto  0) =>  ram_Adr,
      req          => ram_ena,
      ram_128      => ram_128,
      rnw          => ram_rnw,
      be           => ram_be,
      di           => ram_dataWrite,
      do           => ram_dataRead,
      done         => ram_done,
      reqprocessed => ram_reqprocessed,
      ram_idle     => ram_idle
   );
   
   isdram_model2 : entity tb.sdram_model 
   generic map
   (
      FILELOADING => '1',
      INITFILE    => ""
   )
   port map
   (
      clk          => clk33,
      addr         => cd_addr,
      req          => cd_req,
      ram_128      => '0',
      rnw          => '1',
      be           => "0000",
      di           => x"00000000",
      do           => ram2_do,
      done         => cd_done,
      reqprocessed => open,
      ram_idle     => open,
      fileSize     => cdSize
   );
   
   cd_data <= ram2_do(31 downto 0);
   
   iframebuffer : entity work.framebuffer
   port map
   (
      clk               => clk66,     
      hblank            => hblank,  
      vblank            => vblank,  
      video_ce          => video_ce,
      video_interlace   => video_interlace,
      video_r           => video_r, 
      video_g           => video_g,    
      video_b           => video_b  
   );
   
   iTestprocessor : entity procbus.eTestprocessor
   generic map
   (
      clk_speed => clk_speed,
      baud      => baud,
      is_simu   => '1'
   )
   port map 
   (
      clk               => clk100,
      bootloader        => '0',
      debugaccess       => '1',
      command_in        => command_in,
      command_out       => command_out,
            
      proc_bus          => proc_bus_in,
      
      fifo_full_error   => open,
      timeout_error     => open
   );
   
   command_out_filter <= '0' when command_out = 'Z' else command_out;
   
   itb_interpreter : entity tb.etb_interpreter
   generic map
   (
      clk_speed => clk_speed,
      baud      => baud
   )
   port map
   (
      clk         => clk100,
      command_in  => command_in, 
      command_out => command_out_filter
   );
   
end architecture;


