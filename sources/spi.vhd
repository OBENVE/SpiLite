library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

-- uncomment the following library declaration if using
-- arithmetic functions with signed or unsigned values
use ieee.numeric_std.all;

library work;
use work.TOP_TIGER_FPGA_PKG.all;
use work.PKG_BTS.all;

entity spi is
Port (     
    -- Reset asynchrone
    aresetn                   : in  std_logic;
                                       
    -- Register interface
    CLK_10MHz                 : in	std_logic; -- CLOCK 10MHz -> Horloge principale utilisée par l'interface registre
    -- CFG_WREN	              : in	std_logic;
    CFG_WRDATA	              : in	std_logic_vector(31 downto 0);	 
    CFG_ADDR	              : in	std_logic_vector(15 downto 0);	 
    CFG_RDRQ	              : in	std_logic;
    CFG_RDDATA	              : out	std_logic_vector(31 downto 0);
    CFG_RDACQ	              : out	std_logic;
    
    -- SPI interface
    nSS                       : in  std_logic;
    SCLK                      : in  std_logic;
    MOSI                      : in  std_logic;

    -- Interface données
    NEW_DATA_RECEIVED         : out std_logic;
    CODEUR_DATA               : out std_logic_vector(13 downto 0);
    RX_READY1                 : out std_logic;
    RX_READY2                 : out std_logic   
);
end spi;

architecture rtl of spi is

-- Module de synchro du reset externe
component SYNCHRONIZE_RESET
    port (
        CLK                 : in  std_logic;    
        anRESET_IN          : in  std_logic;
        nRESET_OUT          : out std_logic;
        RESET_OUT           : out std_logic
    );
end component;

component detect_event
    port(
        nRESET                  : in std_logic;
        CLOCK	                : in std_logic;
        DIN		                : in std_logic;
        RISING_EDGE_DETECTED    : out std_logic;
        FALLING_EDGE_DETECTED   : out std_logic
    );
end component;

signal nRESET_10MHz         : std_logic;
signal RESET_10MHz          : std_logic;

signal CFG_CLK              : std_logic;
signal nSS_reg_meta         : std_logic_vector(1 downto 0);
signal nSS_meta             : std_logic;
signal sSPI_DATA_VALID      : std_logic;
signal sRESET_BUFFER        : std_logic;
signal sSCLK_reg_meta       : std_logic_vector(1 downto 0);
signal sSCLK_meta           : std_logic;
signal sSCLK_STROBE_META    : std_logic;
signal sMOSI_reg_meta       : std_logic_vector(1 downto 0);
signal sMOSI_meta           : std_logic;

signal sCFG_RESET_SPI       : std_logic;

signal sDATA_BUFFER         : std_logic_vector(31 downto 0);

-- Signaux Configuration
signal sCFG_WREN	                        : std_logic;
signal sCFG_WRDATA	                        : std_logic_vector(31 downto 0);	 
signal sCFG_ADDR	                        : std_logic_vector(15 downto 0);	 
signal sCFG_RDRQ	                        : std_logic;
signal sCFG_RDDATA	                        : std_logic_vector(31 downto 0);
signal sCFG_RDACQ	                        : std_logic;
    
signal sCODEUR_DATA                         : std_logic_vector(13 downto 0);        
signal sRX_READY1                           : std_logic;            
signal sRX_READY2                           : std_logic;

begin


CODEUR_DATA <= sCODEUR_DATA;     
RX_READY1 <= sRX_READY1  ;
RX_READY2 <= sRX_READY2  ;
CFG_CLK <= CLK_10MHz;
NEW_DATA_RECEIVED <= sRESET_BUFFER;
--------------------------------------------------------------------------------
-- Synchro du signal reset aresetn
--------------------------------------------------------------------------------
    C_SYNCHRONIZE_RESET : entity work.SYNCHRONIZE_RESET 
    port map(
        CLK              => CFG_CLK, 
        anRESET_IN       => aresetn,
        nRESET_OUT       => nRESET_10MHz,
        RESET_OUT        => RESET_10MHz
    );
--------------------------------------------------------------------------------
-- METASTABILITE
--------------------------------------------------------------------------------
    P_META: process(CFG_CLK)
    begin
        if (rising_edge(CFG_CLK)) then
            if (nRESET_10MHz = '0') then
                nSS_reg_meta    <= (others => '1');
                sSCLK_reg_meta  <= (others => '1');
                sMOSI_reg_meta  <= (others => '1');
            else
                nSS_reg_meta    <= nSS_reg_meta(0) & nSS;
                sSCLK_reg_meta  <= sSCLK_reg_meta(0) & SCLK;
                sMOSI_reg_meta  <= sMOSI_reg_meta(0) & MOSI;
            end if;
        end if;
    end process P_META;
    
    nSS_meta    <= nSS_reg_meta(1);
    sSCLK_meta  <= sSCLK_reg_meta(1);
    sMOSI_meta  <= sMOSI_reg_meta(1);
  
--------------------------------------------------------------------------------
-- RECEPTION DES DONNEES
--------------------------------------------------------------------------------  
    P_DETECT_SCLK_RISING_EDGE : detect_event
    port map(
        nRESET                  => nRESET_10MHz,
        CLOCK	                => CLK_10MHz,
        DIN		                => sSCLK_meta,
        RISING_EDGE_DETECTED    => sSCLK_STROBE_META,
        FALLING_EDGE_DETECTED   => open
    );

    P_DETECT_nSS_RISING_EDGE : detect_event
    port map(
        nRESET                  => nRESET_10MHz,
        CLOCK	                => CLK_10MHz,
        DIN		                => nSS_meta,
        RISING_EDGE_DETECTED    => sSPI_DATA_VALID,
        FALLING_EDGE_DETECTED   => open
    );
    
    P_READ_MOSI: process(CFG_CLK)
    begin
        if (rising_edge(CFG_CLK)) then
            if (nRESET_10MHz = '0') then
                sDATA_BUFFER <= (others => '0');
                sRESET_BUFFER <= '0';
                sCODEUR_DATA  <= (others => '0');         
                sRX_READY1    <= '0';             
                sRX_READY2    <= '0';
            else
            
                if (sCFG_RESET_SPI = '1') then
                    sDATA_BUFFER <= (others => '0');
                    sRESET_BUFFER <= '0';
                    sCODEUR_DATA  <= (others => '0');        
                    sRX_READY1    <= '0';             
                    sRX_READY2    <= '0';
                else
                    sRESET_BUFFER <= sSPI_DATA_VALID;
                    
                    -- Transfert des data du buffer 32 bits vers les registres de sortie 
                    if (sSPI_DATA_VALID = '1') then
                        sCODEUR_DATA  <= sDATA_BUFFER(13 downto 0);           
                        sRX_READY1    <= sDATA_BUFFER(14);                        
                        sRX_READY2    <= sDATA_BUFFER(15);           
                    end if;
                                     
                    -- Buffer de 32 bits qui permet de stocker les data lues sur l'entrée MOSI
                    if (sRESET_BUFFER = '1') then
                        sDATA_BUFFER <= (others => '0');             
                    elsif (sSCLK_STROBE_META = '1' and nSS_meta = '0') then
                        sDATA_BUFFER <= sDATA_BUFFER(30 downto 0) & sMOSI_meta;
                    else
                        NULL;
                    end if;
                end if;

            end if;
        end if;
    end process P_READ_MOSI;
   

--------------------------------------------------------------------------------
-- CFG_CLK CLOCK DOMAIN
--------------------------------------------------------------------------------

    --------------------------------------------------------------------------------
    -- Latch du bus de config entrant
    --------------------------------------------------------------------------------
    P_LATCH_BUS_CFG : process(CFG_CLK)
    begin
        if (rising_edge(CFG_CLK)) then
            sCFG_WREN           <= CFG_WREN;
            sCFG_WRDATA         <= CFG_WRDATA;
            sCFG_ADDR           <= CFG_ADDR;
            sCFG_RDRQ           <= CFG_RDRQ;
        end if;
    end process P_LATCH_BUS_CFG;

    --------------------------------------------------------------------------------
    -- Sorties du bus de config
    --------------------------------------------------------------------------------
    CFG_RDDATA  <= sCFG_RDDATA; 
    CFG_RDACQ   <= sCFG_RDACQ;
        
    --------------------------------------------------------------------------------
    -- Registers management   
    -- Followings processes allows to manage wrting and reading of debug registers
    -- Register map:
    -- sREG_REC_CTL (W)
    -- sREG_REC_PRE_TRIGGER (W/R)
    -- sREG_REC_POST_TRIGGER (W/R)
    -- sREG_REC_LAST (W/R)
    -- sREG_REC_DEBUG (RO)
    --------------------------------------------------------------------------------  

    P_WRITE_REGISTER : process(CFG_CLK)
    begin
        if (rising_edge(CFG_CLK)) then
            sCFG_RESET_SPI   <= '0';

            if (sCFG_WREN = '1') then
                case(conv_integer(sCFG_ADDR)) is
                    when cREG_SPI_CTL =>                   
                        sCFG_RESET_SPI <= sCFG_WRDATA(0);  
                    when others =>
                        NULL;
                end case ;
            end if;
        end if;
    end process P_WRITE_REGISTER;
    
    P_READ_REGISTER : process(CFG_CLK)
    begin
        if (rising_edge(CFG_CLK)) then
            sCFG_RDACQ   <= '0'; --valeur par defaut

            if (sCFG_RDRQ = '1') then
                case(conv_integer(sCFG_ADDR)) is                                  
                    when cREG_SPI_DATA  =>   
                        sCFG_RDDATA <= x"0000" & sRX_READY2 & sRX_READY1 & sCODEUR_DATA;
                        sCFG_RDACQ  <= '1';
                    when cREG_SPI_DEBUG  =>   
                        sCFG_RDDATA <= (others => '0');
                        sCFG_RDACQ  <= '1';
                    when cREG_SPI_CTL  =>   
                        sCFG_RDDATA(0) <= sCFG_RESET_SPI;
                        sCFG_RDDATA(31 downto 1) <= (others => '0');
                        sCFG_RDACQ  <= '1';
          
                    when others =>
                        NULL;
                end case ;
            end if;
        end if;
    end process P_READ_REGISTER;

    


end rtl;
