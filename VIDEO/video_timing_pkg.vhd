library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

package VIDEO_TIMING_pkg is
	-- PC-98 24.8 kHz / 56.4 Hz raster, as the BIOS programs the GDCs for 400
	-- lines: 21.0526 MHz dot clock (63.158 MHz video clock / CPD), 848 dots x
	-- 440 lines; horizontal 80 characters + front porch 10 + sync 8 + back
	-- porch 8, vertical 400 + 7 + 8 + 25.
	constant DOTPU	:integer	:=8;
	constant HWIDTH	:integer	:=848;
	constant HUWIDTH :integer	:=HWIDTH/DOTPU;
	constant VWIDTH	:integer	:=440;
	constant HVIS	:integer	:=640;
	constant HUVIS	:integer	:=HVIS/DOTPU;
	constant VVIS	:integer	:=400;
	constant VVIS2	:integer	:=480;
	constant CPD	:integer	:=3;
	constant HFP	:integer	:=10;
	constant HSY	:integer	:=8;
	constant HBP	:integer	:=HUWIDTH-HUVIS-HFP-HSY;
	constant HIV	:integer	:=HFP+HSY+HBP;
	constant VFP	:integer	:=7;
	constant VSY	:integer	:=8;
	constant VBP	:integer	:=VWIDTH-VVIS-VFP-VSY;
	constant VBP2	:integer	:=VWIDTH-VVIS2-VFP-VSY;
	constant VIV	:integer	:=VFP+VSY+VBP;
	constant VIV2	:integer	:=VFP+VSY+VBP2;
	
end VIDEO_TIMING_pkg;
