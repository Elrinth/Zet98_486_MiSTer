-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.VIDEO_TIMING_pkg.all;

-- Packed 640-pixel raster address generation. Inputs come from the CRTC's
-- parent rising/falling stages; register once more before pixel arithmetic.
-- Byte start = SAD*16, pitch = GDC pitch*8 at5MHz or *16 at2.5MHz.
-- Two-page mode wraps within its selected256KB page; single-page uses512KB.
-- Packed PEGC advances every output row, independently of legacy CSRFORM.
-- Keep repeat_lines on the interface so the coherent snapshot stays unchanged.
-- References: NP2kai makegrex.c and pccore.c (independent implementation).
entity pegc_raster is
    port(clk,rstn:in std_logic;
         mode256,single_page,display_page,fast_clock,graph_enable:in std_logic;
         base0,base1:in std_logic_vector(14 downto 0);
         length0,length1:in std_logic_vector(9 downto 0);
         pitch:in std_logic_vector(7 downto 0);
         repeat_lines:in std_logic_vector(4 downto 0);
         hunit:in integer range 0 to HUWIDTH-1;
         dot:in integer range 0 to DOTPU-1;
         row:in integer range 0 to VWIDTH-1;
         line_start,line_enable,active:out std_logic;
         line_address:out std_logic_vector(18 downto 3);
         pixel_x:out std_logic_vector(9 downto 0);
         mode_pixel:out std_logic);
end;
architecture rtl of pegc_raster is
    signal mode_p,single_p,page_p,fast_p,enable_p:std_logic;
    signal base0_p,base1_p:unsigned(14 downto 0);
    signal length0_p,length1_p:unsigned(9 downto 0);
    signal pitch_p:unsigned(7 downto 0);
    signal repeat_p:unsigned(4 downto 0);
    signal address_now,address_next:unsigned(15 downto 0);
    signal left_now,left_next:integer range 0 to 1024;
    signal repeat_now,repeat_next:unsigned(4 downto 0);
    signal partition_now,partition_next:std_logic;
    signal row_start:std_logic;
    function rows(v:unsigned(9 downto 0)) return integer is
    begin if v=0 then return 1024;else return to_integer(v);end if;end;
begin
    process(clk,rstn) begin
        if rstn='0' then
            mode_p<='0';single_p<='0';page_p<='0';fast_p<='0';enable_p<='0';
            base0_p<=(others=>'0');base1_p<=(others=>'0');
            length0_p<=(others=>'0');length1_p<=(others=>'0');
            pitch_p<=(others=>'0');repeat_p<=(others=>'0');
            address_now<=(others=>'0');left_now<=0;repeat_now<=(others=>'0');partition_now<='0';
        elsif rising_edge(clk) then
            mode_p<=mode256;single_p<=single_page;page_p<=display_page;fast_p<=fast_clock;enable_p<=graph_enable;
            base0_p<=unsigned(base0);base1_p<=unsigned(base1);
            length0_p<=unsigned(length0);length1_p<=unsigned(length1);
            -- Both NP2kai makegrex.c and MAME pc9821_state::screen_update
            -- bypass the legacy GDC character-row repetition in packed mode.
            pitch_p<=unsigned(pitch);repeat_p<=(others=>'0');
            if row_start='1' then
                address_now<=address_next;left_now<=left_next;
                repeat_now<=repeat_next;partition_now<=partition_next;
            end if;
        end if;
    end process;
    row_start<='1' when hunit=0 and dot=0 and row>=VIV else '0';
    process(address_now,left_now,repeat_now,partition_now,row,base0_p,base1_p,length0_p,length1_p,pitch_p,repeat_p,fast_p)
        variable step:unsigned(15 downto 0);
    begin
        address_next<=address_now;left_next<=left_now;repeat_next<=repeat_now;partition_next<=partition_now;
        step:=resize(pitch_p,16);
        if fast_p='0' then step:=shift_left(step,1);end if;
        -- GDC pitch has word granularity even in packed mode.
        step(0):='0';
        if row=VIV then
            address_next<=base0_p & '0';left_next<=rows(length0_p)-1;
            repeat_next<=repeat_p;partition_next<='0';
        elsif repeat_now/=0 then repeat_next<=repeat_now-1;
        else
            repeat_next<=repeat_p;
            if left_now=0 then
                if partition_now='0' then address_next<=base1_p & '0';left_next<=rows(length1_p)-1;
                else address_next<=base0_p & '0';left_next<=rows(length0_p)-1;end if;
                partition_next<=not partition_now;
            else address_next<=address_now+step;left_next<=left_now-1;end if;
        end if;
    end process;
    line_start<=row_start;
    line_enable<=mode_p and enable_p;
    mode_pixel<=mode_p;
    line_address<=std_logic_vector(address_next) when single_p='1' else page_p & std_logic_vector(address_next(14 downto 0));
    active<='1' when row>=VIV and hunit>=HIV else '0';
    pixel_x<=std_logic_vector(to_unsigned((hunit-HIV)*DOTPU+dot,10)) when hunit>=HIV else (others=>'0');
end;
