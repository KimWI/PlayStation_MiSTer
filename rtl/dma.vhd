library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;

entity dma is
   generic
   (
      REPRODUCIBLEDMATIMING : std_logic
   );
   port 
   (
      clk1x                : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      
      cpuPaused            : in  std_logic;
      dmaOn                : out std_logic;
      irqOut               : out std_logic := '0';
      
      ram_refresh          : out std_logic;
      ram_dataWrite        : out std_logic_vector(31 downto 0) := (others => '0');
      ram_dataRead         : in  std_logic_vector(127 downto 0);
      ram_Adr              : out std_logic_vector(22 downto 0) := (others => '0');
      ram_be               : out std_logic_vector(3 downto 0) := (others => '0');
      ram_rnw              : out std_logic := '0';
      ram_ena              : out std_logic := '0';
      ram_128              : out std_logic := '0';
      ram_done             : in  std_logic;
      ram_reqprocessed     : in  std_logic;
      ram_idle             : in  std_logic;
      
      gpu_dmaRequest       : in  std_logic;
      DMA_GPU_writeEna     : out std_logic := '0';
      DMA_GPU_readEna      : out std_logic := '0';
      DMA_GPU_write        : out std_logic_vector(31 downto 0);
      DMA_GPU_read         : in  std_logic_vector(31 downto 0);
      
      mdec_dmaWriteRequest : in  std_logic;
      mdec_dmaReadRequest  : in  std_logic;
      DMA_MDEC_writeEna    : out std_logic := '0';
      DMA_MDEC_readEna     : out std_logic := '0';
      DMA_MDEC_write       : out std_logic_vector(31 downto 0);
      DMA_MDEC_read        : in  std_logic_vector(31 downto 0);
      
      DMA_CD_readEna       : out std_logic := '0';
      DMA_CD_read          : in  std_logic_vector(7 downto 0);
      
      bus_addr             : in  unsigned(6 downto 0); 
      bus_dataWrite        : in  std_logic_vector(31 downto 0);
      bus_read             : in  std_logic;
      bus_write            : in  std_logic;
      bus_dataRead         : out std_logic_vector(31 downto 0);
      
      SS_reset             : in  std_logic;
      SS_DataWrite         : in  std_logic_vector(31 downto 0);
      SS_Adr               : in  unsigned(5 downto 0);
      SS_wren              : in  std_logic;
      SS_DataRead          : out std_logic_vector(31 downto 0)
   );
end entity;

architecture arch of dma is

   type tdmaState is
   (
      OFF,
      WAITING,
      READHEADER,
      WAITREAD,
      WORKING,
      STOPPING,
      PAUSING,
      TIMEUP,
      GPUBUSY
   );
   signal dmaState : tdmaState := OFF;

   type dmaRecord is record
      D_MADR            : unsigned(23 downto 0);
      D_BCR             : unsigned(31 downto 0);
      D_CHCR            : unsigned(31 downto 0);
      request           : std_logic;
      timeupPending     : std_logic;
      requestsPending   : std_logic;
   end record;
  
   type tdmaArray is array (0 to 6) of dmaRecord;
   signal dmaArray : tdmaArray;
  
   signal DPCR             : unsigned(31 downto 0);
   signal DICR             : unsigned(23 downto 0);
   signal DICR_readback    : unsigned(31 downto 0);
   signal DICR_IRQs        : unsigned(6 downto 0);
      
   signal triggerDMA       : std_logic_vector(6 downto 0);
   
   signal wordAccu         : integer range 0 to 3 := 0;
   signal DMA_CD_read_accu : std_logic_vector(23 downto 0);
      
   signal isOn             : std_logic;
   signal activeChannel    : integer range 0 to 6;
   signal paused           : std_logic;
   signal gpupaused        : std_logic;
   signal waitcnt          : integer range 0 to 15;
   signal dmaTime          : integer range 0 to 65535;
   signal wordcount        : unsigned(16 downto 0);
   signal toDevice         : std_logic;
   signal directionNeg     : std_logic;
   signal nextAddr         : std_logic_vector(23 downto 0);
   signal blocksleft       : unsigned(15 downto 0);
   signal dmacount         : unsigned(9 downto 0);
      
   signal autoread         : std_logic := '0';
   signal readcount        : unsigned(9 downto 0);
   signal readsize         : unsigned(9 downto 0);
   signal firstword        : std_logic := '0';
   
   signal dataNext         : std_logic_vector(95 downto 0);
   signal dataCount        : integer range 0 to 3 := 0;
   signal firstsize        : integer range 0 to 3 := 0;
   signal requestOnFly     : integer range 0 to 2;
   
   signal fifoIn_reset     : std_logic := '0';
   signal fifoIn_Din       : std_logic_vector(31 downto 0);
   signal fifoIn_Wr        : std_logic; 
   signal fifoIn_Full      : std_logic;
   signal fifoIn_NearFull  : std_logic;
   signal fifoIn_Dout      : std_logic_vector(31 downto 0);
   signal fifoIn_Rd        : std_logic;
   signal fifoIn_Empty     : std_logic;
   signal fifoIn_Valid     : std_logic;   
   
   signal fifoOut_reset    : std_logic := '0';
   signal fifoOut_Din      : std_logic_vector(50 downto 0);
   signal fifoOut_Wr       : std_logic; 
   signal fifoOut_Full     : std_logic;
   signal fifoOut_NearFull : std_logic;
   signal fifoOut_Dout     : std_logic_vector(50 downto 0);
   signal fifoOut_Rd       : std_logic;
   signal fifoOut_Empty    : std_logic;
   signal fifoOut_Done     : std_logic;
   
   signal ramwrite_pending : std_logic;
   
   -- REPRODUCIBLEDMATIMING
   signal REP_counter      : integer;
   signal REP_target       : integer;
   
   -- savestates
   type t_ssarray is array(0 to 63) of std_logic_vector(31 downto 0);
   signal ss_in  : t_ssarray := (others => (others => '0'));  
  
begin 

   dmaOn <= '1' when (dmaState = WAITING or dmaState = READHEADER or dmaState = WAITREAD or dmaState = WORKING or dmaState = STOPPING or dmaState = PAUSING) else '0';

   ram_refresh <= '1' when (dmaState = WAITING and cpuPaused = '1' and waitcnt = 9) else '0';
   ram_be      <= "1111";
   ram_128     <= '1';

   DICR_readback( 5 downto  0) <= DICR( 5 downto 0);
   DICR_readback(14 downto  6) <= "000000000";
   DICR_readback(23 downto 15) <= DICR(23 downto 15);
   DICR_readback(30 downto 24) <= DICR_IRQs;
   DICR_readback(31)           <= '1' when (DICR(15) = '1') else
                                  '1' when (DICR(23) = '1' and (DICR(22 downto 16) and DICR_IRQs) /= "0000000") else 
                                  '0';

   DMA_MDEC_writeEna <= '1' when (dmaState = working and fifoIn_Valid = '1' and activeChannel = 0 and toDevice = '1') else '0'; 
   DMA_MDEC_write    <= fifoIn_Dout;  
   
   DMA_MDEC_readEna  <= '1' when (dmaState = working and fifoOut_NearFull = '0' and activeChannel = 1 and toDevice = '0') else '0';
   
   DMA_GPU_readEna   <= '1' when (dmaState = working and fifoOut_NearFull = '0' and activeChannel = 2 and toDevice = '0') else '0';
   DMA_GPU_writeEna  <= '1' when (dmaState = working and fifoIn_Valid = '1' and activeChannel = 2 and toDevice = '1') else '0'; 
   DMA_GPU_write     <= fifoIn_Dout;

   DMA_CD_readEna    <= '1' when (dmaState = working and fifoOut_NearFull = '0' and activeChannel = 3 and toDevice = '0') else '0';

   process (clk1x)
      variable channel         : integer range 0 to 7;
      variable triggerNew      : std_logic;
      variable triggerchannel  : integer range 0 to 6;
      variable requestOnFlyNew : integer range 0 to 2;
   begin
      if rising_edge(clk1x) then
      
         fifoIn_reset  <= '0';
         fifoOut_reset <= '0';
         
         fifoOut_Wr    <= '0';
      
         irqOut   <= '0';
         
         if (cpuPaused = '1') then
            REP_counter <= REP_counter + 1;
         else
            REP_counter <= 0;
         end if;
      
         if (reset = '1') then
         
            dmaState <= OFF;
            if (ss_in(4)(7 downto 0) = x"07") then
               dmaState <= GPUBUSY;
            end if;
         
            for i in 0 to 6 loop
               dmaArray(i).D_MADR            <= unsigned(ss_in(28 + i)(23 downto 0));
               dmaArray(i).D_BCR             <= unsigned(ss_in(35 + i));
               dmaArray(i).D_CHCR            <= unsigned(ss_in(42 + i));
               dmaArray(i).request           <= ss_in(19 + i)(8);
               dmaArray(i).timeupPending     <= ss_in(19 + i)(10);
               dmaArray(i).requestsPending   <= ss_in(19 + i)(9);
            end loop;
            
            DPCR           <= unsigned(ss_in(26)); -- x"07654321";
            DICR           <= unsigned(ss_in(27)(23 downto 0));
            DICR_IRQs      <= unsigned(ss_in(27)(30 downto 24));
               
            triggerDMA     <= (others => '0');
            isOn           <= ss_in(4)(8);
            activeChannel  <= to_integer(unsigned(ss_in(2)(18 downto 16)));
            paused         <= ss_in(4)(9);
            gpupaused      <= ss_in(4)(10);
            waitcnt        <= 0;
            dmaTime        <= 0;
            
            autoread       <= '0';
            
            fifoIn_reset   <= '1';
            dataCount      <= 0;
            requestOnFly   <= 0;
            
            fifoOut_reset  <= '1';
            fifoOut_Done   <= '1';
            
            ramwrite_pending <= '0';

         elsif (ce = '1') then
         
            ram_ena    <= '0';
         
            triggerDMA <= (others => '0');
         
            bus_dataRead <= (others => '0');

            channel := to_integer(unsigned(bus_addr(6 downto 4)));
            
            dmaArray(0).request <= mdec_dmaWriteRequest;
            dmaArray(1).request <= mdec_dmaReadRequest;
            dmaArray(2).request <= gpu_dmaRequest;
            dmaArray(3).request <= '1';
            dmaArray(4).request <= '0';
            dmaArray(5).request <= '0';
            dmaArray(6).request <= '1';
            
            requestOnFlyNew := requestOnFly;
            
            -- bus read
            if (bus_read = '1') then
               if (channel < 7) then
                  case (bus_addr(3 downto 2)) is
                     when "00" => bus_dataRead <= x"00" & std_logic_vector(dmaArray(channel).D_MADR);
                     when "01" => bus_dataRead <= std_logic_vector(dmaArray(channel).D_BCR); 
                     when "10" => bus_dataRead <= std_logic_vector(dmaArray(channel).D_CHCR);
                     when others => bus_dataRead <= (others => '1');
                  end case;
               else
                  case (bus_addr(3 downto 2)) is
                     when "00" => bus_dataRead <= std_logic_vector(DPCR);
                     when "01" => bus_dataRead <= std_logic_vector(DICR_readback); 
                     when others => bus_dataRead <= (others => '1');
                  end case;
               end if;
            end if;

            -- bus write
            if (bus_write = '1') then
               if (channel < 7) then
                  case (bus_addr(3 downto 2)) is
                     when "00" => dmaArray(channel).D_MADR <= unsigned(bus_dataWrite(23 downto 0));
                     when "01" => dmaArray(channel).D_BCR  <= unsigned(bus_dataWrite);
                     when "10" =>  -- todo: channel 6 has only 3 r/w bits
                        dmaArray(channel).D_CHCR( 1 downto  0) <= unsigned(bus_dataWrite( 1 downto  0));
                        dmaArray(channel).D_CHCR(10 downto  8) <= unsigned(bus_dataWrite(10 downto  8));
                        dmaArray(channel).D_CHCR(18 downto 16) <= unsigned(bus_dataWrite(18 downto 16));
                        dmaArray(channel).D_CHCR(22 downto 20) <= unsigned(bus_dataWrite(22 downto 20));
                        dmaArray(channel).D_CHCR(          24) <= bus_dataWrite(24);
                        dmaArray(channel).D_CHCR(30 downto 28) <= unsigned(bus_dataWrite(30 downto 28));
                        if (dmaArray(channel).request = '1') then
                           triggerDMA(channel) <= '1';
                        end if;
                     when others => null;
                  end case;
               else
                  case (bus_addr(3 downto 2)) is
                     when "00" => 
                        DPCR       <= unsigned(bus_dataWrite);
                        for i in 0 to 6 loop
                           if (dmaArray(i).request = '1') then
                              triggerDMA(i) <= '1';
                           end if;
                        end loop;
                     when "01" => 
                        DICR( 5 downto  0) <= unsigned(bus_dataWrite(5 downto 0));
                        DICR(14 downto  6) <= (14 downto 6 => '0');
                        DICR(          15) <= bus_dataWrite(15);
                        DICR(23 downto 16) <= unsigned(bus_dataWrite(23 downto 16));
                        DICR_IRQs          <= DICR_IRQs and (not unsigned(bus_dataWrite(30 downto 24)));
                        --if (bus_dataWrite(15) = '1') then  -- force bit not used in duckstation, why?
                        --   irqOut <= '1';
                        --end if;
                     when others => null;
                  end case;
               end if;
               
            end if;
            
            -- triggers from modules
            if (mdec_dmaWriteRequest = '1') then triggerDMA(0) <= '1'; end if;
            if (mdec_dmaReadRequest = '1')  then triggerDMA(1) <= '1'; end if;
                
            -- trigger
            triggerNew     := '0';
            triggerchannel := 0;
            for i in 0 to 6 loop
               if (triggerDMA(i) = '1') then
                  if (DPCR((i * 4) + 3) = '1') then -- enable
                     if (dmaArray(i).D_CHCR(24) = '1') then -- start/busy
                        if (isOn = '0' or activeChannel /= i) then
                        
                           if (dmaState = GPUBUSY) then
                              gpupaused <= '1';
                              paused    <= '0';
                           end if;
                           
                           if (dmaState = TIMEUP) then
                              dmaArray(activeChannel).timeupPending <= '1';
                              paused    <= '0';
                           end if;
                           
                           if (dmaState /= OFF and dmaState /= TIMEUP and dmaState /= GPUBUSY) then
                              dmaArray(i).requestsPending <= '1';
                           else
                              -- todo : priority
                              triggerNew     := '1';
                              triggerchannel := i;
                           end if;
                        end if;
                     end if;
                  end if;
               end if;
            end loop;
            
            if (triggerNew = '1') then
               dmaArray(triggerchannel).requestsPending <= '0';
               dmaArray(triggerchannel).timeupPending   <= '0';
               dmaArray(triggerchannel).D_CHCR(28)      <= '0';
               
               dmaState      <= WAITING;
               waitcnt       <= 9;
               isOn          <= '1';
               activeChannel <= triggerchannel;
               dmaTime       <= 0;
               REP_target    <= 32;
            end if;
            
            -- accu
            if (DMA_CD_readEna = '1') then
               case (wordAccu) is
                  when 0 => wordAccu <= 3; 
                  when 1 => wordAccu <= 0; DMA_CD_read_accu(23 downto 16) <= DMA_CD_read;
                  when 2 => wordAccu <= 1; DMA_CD_read_accu(15 downto  8) <= DMA_CD_read;
                  when 3 => wordAccu <= 2; DMA_CD_read_accu( 7 downto  0) <= DMA_CD_read;
                  when others => null;
               end case;
            end if;
            
            case (dmaState) is
            
               when OFF => null;
               
               when WAITING =>
                  if (waitcnt > 0 and cpuPaused = '1') then
                     waitcnt <= waitcnt - 1;
                  end if;
                  if (waitcnt = 8) then
                     dmacount     <= (others => '0');
                     toDevice     <= dmaArray(activeChannel).D_CHCR(0);
                     wordAccu     <= 0;
                     if (activeChannel = 3) then
                        wordAccu <= 3;
                     end if;
                     if (dmaArray(activeChannel).D_CHCR(0) = '1') then
                        if (requestOnFly = 0) then
                           ram_rnw         <= '1';
                           ram_ena         <= '1';
                           ram_Adr         <= "00" & std_logic_vector(dmaArray(activeChannel).D_MADR(20 downto 2)) & "00";
                           autoread        <= '1';
                           requestOnFlyNew := 1;
                        else
                           waitcnt <= waitcnt;
                        end if;
                     else
                        case (dmaArray(activeChannel).D_CHCR(10 downto 9)) is
                           when "00" => -- manual
                              if (dmaArray(activeChannel).D_BCR(15 downto 0) = 0) then
                                 wordcount <= '1' & x"0000";
                              else
                                 wordcount <= '0' & dmaArray(activeChannel).D_BCR(15 downto 0);
                              end if;
                           
                           when "01" => -- request
                              blocksleft  <= dmaArray(activeChannel).D_BCR(31 downto 16) - 1;
                              wordcount   <= '0' & dmaArray(activeChannel).D_BCR(15 downto 0);
                           
                           when others => null;
                        end case;
                     end if;
                     directionNeg <= '0';
                     if (dmaArray(activeChannel).D_CHCR(10) = '0' and dmaArray(activeChannel).D_CHCR(1) = '1') then
                        directionNeg <= '1';
                     end if;                         
                  end if;
                  if (waitcnt = 1) then
                     if (fifoIn_Empty = '1' and toDevice = '1') then
                        waitcnt <= waitcnt;
                     else
                        case (dmaArray(activeChannel).D_CHCR(10 downto 9)) is
                           when "00" => -- manual
                              dmaState    <= WORKING;
                           
                           when "01" => -- request
                              dmaState    <= WORKING;
                           
                           when "10" => -- linked list
                              dmaState    <= READHEADER;
                           
                           when others => 
                              dmaState <= OFF;
                              isOn     <= '0';
                        end case;
                     end if;
                  end if;
               
               when READHEADER =>
                  REP_target <= REP_target + 16;
                  dmacount  <= dmacount + 1;
                  nextAddr  <= fifoIn_Dout(23 downto 0);
                  if (unsigned(fifoIn_Dout(31 downto 24)) > 0) then
                     dmaArray(activeChannel).D_MADR <= dmaArray(activeChannel).D_MADR + 4;
                     dmaState  <= WAITREAD;
                     waitcnt   <= 4;              
                  elsif (fifoIn_Dout(23) = '1' or fifoIn_Dout(23 downto 0) = x"000000" or dmaArray(activeChannel).D_CHCR(0) = '0') then
                     dmaState <= STOPPING;
                     autoread <= '0';
                  else
                     dmaArray(activeChannel).D_MADR <= unsigned(fifoIn_Dout(23 downto 0));
                     waitcnt   <= 9;
                     dmaState  <= WAITING;
                     autoread  <= '0';
                     -- todo: add timeup check
                  end if;  
               
               when WAITREAD =>
                  if (waitcnt > 0) then
                     waitcnt <= waitcnt - 1;
                  end if;
                  if (waitcnt = 1) then
                     dmaState    <= WORKING;
                  end if;
               
               when WORKING =>
                  if (fifoIn_Valid = '1' or (toDevice = '0' and fifoOut_NearFull = '0' and wordAccu = 0)) then
                     dmacount    <= dmacount + 1;
                     REP_target  <= REP_target + 1;
                     case (activeChannel) is
                     
                        when 0 =>
                           if (toDevice = '0') then
                              report "read from MDEC in not possible" severity failure;
                           end if;
                        
                        when 1 =>
                           if (toDevice = '0') then
                              fifoOut_Wr                <= '1';
                              fifoOut_Din(50 downto 32) <= std_logic_vector(dmaArray(1).D_MADR(20 downto 2));
                              fifoOut_Din(31 downto 0)  <= DMA_MDEC_read;
                           else
                              report "write to MDEC out not possible" severity failure;
                           end if;
                     
                        when 2 =>
                           if (toDevice = '0') then
                              fifoOut_Wr                <= '1';
                              fifoOut_Din(50 downto 32) <= std_logic_vector(dmaArray(2).D_MADR(20 downto 2));
                              fifoOut_Din(31 downto 0)  <= DMA_GPU_read;
                           end if;
                           
                        when 3 =>
                           if (toDevice = '0') then
                              fifoOut_Wr                <= '1';
                              fifoOut_Din(50 downto 32) <= std_logic_vector(dmaArray(3).D_MADR(20 downto 2));
                              fifoOut_Din(31 downto 0)  <= DMA_CD_read & DMA_CD_read_accu;
                              REP_target                <= REP_target + 4;
                           end if;
                           
                        when 6 =>
                           if (toDevice = '0') then
                              fifoOut_Wr                <= '1';
                              fifoOut_Din(50 downto 32) <= std_logic_vector(dmaArray(6).D_MADR(20 downto 2));
                              if (wordcount = 1) then
                                 fifoOut_Din(31 downto 0) <= x"00FFFFFF";
                              else
                                 fifoOut_Din(31 downto 0) <= x"00" & std_logic_vector(dmaArray(6).D_MADR(23 downto 2) - 1) & "00";
                              end if;
                           end if;
                     
                        when others => report "DMA channel not implemented" severity failure; 
                     end case;
                     
                     if (dmaArray(activeChannel).D_CHCR(10) = '0' and directionNeg = '1')  then 
                        dmaArray(activeChannel).D_MADR <= dmaArray(activeChannel).D_MADR - 4;
                     else
                        dmaArray(activeChannel).D_MADR <= dmaArray(activeChannel).D_MADR + 4;
                     end if;
                  
                     wordcount <= wordcount - 1;
                     if (wordcount <= 1) then
                        case (dmaArray(activeChannel).D_CHCR(10 downto 9)) is
                           when "00" => -- manual
                              dmaState <= STOPPING;
                              autoread <= '0';
                                 
                           when "01" => -- request
                              dmaArray(activeChannel).D_BCR(31 downto 16) <= blocksleft;
                              blocksleft <= blocksleft - 1;
                              if (blocksleft = 0) then
                                 dmaState <= STOPPING;
                                 autoread <= '0';
                              else
                                 wordcount  <= '0' & dmaArray(activeChannel).D_BCR(15 downto 0);
                                 if (dmaArray(activeChannel).request = '0') then
                                    dmaState <= PAUSING;
                                    autoread <= '0';
                                 elsif (dmacount + dmaArray(activeChannel).D_BCR(15 downto 0) >= 1000) then
                                    dmaState <= WAITING;
                                    waitcnt  <= 9;
                                    autoread <= '0';
                                 end if;
                                 -- todo timeup check
                              end if;
                           
                           when "10" => -- linked list
                              dmaArray(activeChannel).D_MADR <= unsigned(nextAddr);
                              if (nextAddr(23) = '1') then
                                 dmaState <= STOPPING;
                                 autoread <= '0';
                              else
                                 -- todo add timeup
                                 if (gpu_dmaRequest = '1') then
                                    dmaState <= WAITING;
                                    waitcnt  <= 10;
                                    autoread <= '0';
                                 else
                                    dmaState <= GPUBUSY;
                                    paused   <= '1';
                                    autoread <= '0';
                                 end if;
                              end if;
                           
                           when others => null;
                        end case;
                     end if;
                  end if;
               
               when STOPPING =>
                  if (fifoOut_Done = '1' and fifoOut_Wr = '0' and requestOnFly = 0) then
                     if (REPRODUCIBLEDMATIMING = '0' or REP_counter >= REP_target) then
                        dmaState <= OFF;
                        isOn     <= '0';
                        dmaArray(activeChannel).D_CHCR(24) <= '0';
                        if (DICR(16 + activeChannel) = '1') then
                           DICR_IRQs(activeChannel) <= '1';
                           if (DICR(23) = '1') then
                              irqOut <= '1';
                           end if;
                        end if;
                        
                        if (gpupaused = '1') then
                           isOn          <= '1';
                           paused        <= '1';
                           dmaState      <= GPUBUSY;
                           activeChannel <= 2;
                           gpupaused     <= '0';
                        end if;
                     end if;
                  end if;
               
               when PAUSING =>
                  if (fifoOut_Done = '1' and fifoOut_Wr = '0' and requestOnFly = 0) then
                     if (REPRODUCIBLEDMATIMING = '0' or REP_counter >= REP_target) then
                        dmaState <= OFF;
                        isOn     <= '0';
                     end if;
                  end if;
               
               when TIMEUP =>
               
               when GPUBUSY =>
                  if (gpu_dmaRequest = '1') then
                     dmaState <= WAITING;
                     waitcnt  <= 9;
                     autoread <= '0';
                     paused <= '0';
                  end if;
            
            end case;
            
         end if;
         
         if (ram_done = '1' and toDevice = '1') then
            requestOnFlyNew := requestOnFlyNew - 1;
            dataNext        <= ram_dataRead(127 downto 32);
            dataCount       <= 3;
         
            readcount <= readcount + 1;
            if (firstword = '1') then
               firstword <= '0';
               dataCount <= firstsize;
               case (dmaArray(activeChannel).D_CHCR(10 downto 9)) is
                  when "00" => -- manual
                     if (dmaArray(activeChannel).D_BCR(15 downto 0) = 0) then
                        wordcount <= '1' & x"0000";
                        readsize  <= to_unsigned(1000, 10);
                     else
                        wordcount <= '0' & dmaArray(activeChannel).D_BCR(15 downto 0);
                        if (dmaArray(activeChannel).D_BCR(15 downto 0) < 1000) then
                           readsize <= dmaArray(activeChannel).D_BCR(9 downto 0);
                        else
                           readsize <= to_unsigned(1000, 10);
                        end if;
                     end if;
                  
                  when "01" => -- request
                     blocksleft  <= dmaArray(activeChannel).D_BCR(31 downto 16) - 1;
                     wordcount   <= '0' & dmaArray(activeChannel).D_BCR(15 downto 0);
                     if ((dmaArray(activeChannel).D_BCR(15 downto 0) * dmaArray(activeChannel).D_BCR(31 downto 16)) < 1000) then
                        readsize <= to_unsigned(to_integer(dmaArray(activeChannel).D_BCR(15 downto 0) * dmaArray(activeChannel).D_BCR(31 downto 16)), 10);
                     else
                        readsize <= to_unsigned(1000, 10);
                     end if;
                  
                  when "10" => -- linked list
                     wordcount <= "0" & x"00" & unsigned(ram_dataRead(31 downto 24)); 
                     readsize  <= to_unsigned(to_integer(unsigned(ram_dataRead(31 downto 24))) + 1, 10);
                  
                  when others => null;
               end case;
            end if;
         end if;
         
         if (ram_reqprocessed = '1' and autoread = '1') then
            if (readcount + 4 + dataCount < readsize) then
               ram_ena         <= '1';
               requestOnFlyNew := requestOnFlyNew + 1;
            end if;
            if (directionNeg = '1') then
               ram_Adr <= std_logic_vector((unsigned(ram_Adr(22 downto 4)) & "0000") - 16); 
            else
               ram_Adr <= std_logic_vector((unsigned(ram_Adr(22 downto 4)) & "0000") + 16); 
            end if;
         end if;
         
         if (dmaState = WAITING and waitcnt = 8) then
            readsize     <= to_unsigned(8, 10); -- get the transfer pipeline running
            readcount    <= (others => '0');
            firstword    <= '1';
            firstsize    <= to_integer(3 - dmaArray(activeChannel).D_MADR(3 downto 2));
            fifoIn_reset <= '1';
            dataCount    <= 0;
         elsif (dataCount > 0) then
            readcount <= readcount + 1;
            dataCount <= dataCount- 1;
            dataNext  <= x"00000000" & dataNext(95 downto 32);
         end if;
         
         requestOnFly <= requestOnFlyNew;
         
         fifoIn_Valid <= fifoIn_Rd;
         
         -- fifo Out
         if (ram_done = '1') then
            ramwrite_pending <= '0';
         end if;
         
         if (fifoOut_Empty = '0' and (ramwrite_pending = '0' or ram_done = '1')) then
            ram_rnw          <= '0';
            ram_ena          <= '1';
            ram_Adr          <= "00" & fifoOut_Dout(50 downto 32) & "00";
            ram_dataWrite    <= fifoOut_Dout(31 downto 0);
            ramwrite_pending <= '1';
         end if; 
         
         if (fifoOut_Wr = '1') then
            fifoOut_Done <= '0';
         elsif (ram_done = '1' and fifoOut_Empty = '1') then
            fifoOut_Done <= '1';
         end if;
         
      end if;
   end process;
   
   fifoIn_Wr  <= '1' when (toDevice = '1' and (ram_done = '1' or dataCount > 0)) else '0'; 
   
   fifoIn_Din <= ram_dataRead(31 downto 0) when ram_done = '1' else
               dataNext(31 downto 0);
   
   
   fifoIn_Rd <= '1' when (fifoIn_Empty = '0' and ((dmaState = WAITING and waitcnt = 1) or (dmaState = WAITREAD and waitcnt = 1) or dmaState = working)) else '0';

   
   iDMAfifoIn: entity mem.Syncfifo
   generic map
   (
      SIZE             => 64,
      DATAWIDTH        => 32,
      NEARFULLDISTANCE => 32
   )
   port map
   ( 
      clk      => clk1x,
      reset    => fifoIn_reset,  
      Din      => fifoIn_Din,     
      Wr       => fifoIn_Wr,      
      Full     => fifoIn_Full,    
      NearFull => fifoIn_NearFull,
      Dout     => fifoIn_Dout,    
      Rd       => fifoIn_Rd,      
      Empty    => fifoIn_Empty   
   );
   
   fifoOut_Rd <= '1' when (fifoOut_Empty = '0' and (ramwrite_pending = '0' or ram_done = '1')) else '0';
   
   DMAfifoOut: entity mem.SyncFifoFallThrough
   generic map
   (
      SIZE             => 256,
      DATAWIDTH        => 51,
      NEARFULLDISTANCE => 250
   )
   port map
   ( 
      clk      => clk1x,
      reset    => fifoOut_reset,  
      Din      => fifoOut_Din,     
      Wr       => fifoOut_Wr,      
      Full     => fifoOut_Full,    
      NearFull => fifoOut_NearFull,
      Dout     => fifoOut_Dout,    
      Rd       => fifoOut_Rd,      
      Empty    => fifoOut_Empty   
   );

--##############################################################
--############################### savestates
--##############################################################

   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         if (SS_reset = '1') then
         
            for i in 0 to 63 loop
               ss_in(i) <= (others => '0');
            end loop;
            
            ss_in(26) <= x"07654321"; -- DPCR
            
         elsif (SS_wren = '1') then
            ss_in(to_integer(SS_Adr)) <= SS_DataWrite;
         end if;
      
      end if;
   end process;

end architecture;





