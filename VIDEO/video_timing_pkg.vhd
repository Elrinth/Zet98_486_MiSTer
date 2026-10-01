library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

package VIDEO_TIMING_pkg is
	-- PC-98 400-line raster: 440 lines (400 + front porch 7 + sync 8 + back
	-- porch 25, as the BIOS programs the GDCs). The real 21.0526 MHz dot clock
	-- needs its own PLL, whose edges cannot be timed against the 90/100 MHz
	-- clocks; the main PLL gives 64.2857 MHz (900 MHz / 14), a 21.43 MHz dot
	-- clock, so the line is 864 dots (80 characters + 10 + 8 + 10): 24.80 kHz
	-- and 56.37 Hz, within 0.1% of the real 24.83 kHz / 56.42 Hz.
	constant DOTPU	:integer	:=8;
	constant HWIDTH	:integer	:=864;
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
