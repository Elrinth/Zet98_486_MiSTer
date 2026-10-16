-- SPDX-License-Identifier: GPL-3.0-or-later
-- Byte-level replacement for KBIF/PS2IF fed by MiSTer hps_io's parallel
-- events, so hps_io needs no PS/2 serialisers (PS2DIV=0) and the core no PS/2
-- receivers. The converter side keeps the KBIF interface: a command byte on a
-- WRn low cycle, received bytes as one-cycle RXED pulses with DATOUT.
--  Keyboard (MOUSE=false): EVT = hps_io ps2_key {toggle, pressed, extended,
--   code}; each event becomes [E0] [F0] code. Commands are answered like an
--   AT keyboard: FF -> FA AA, F2 -> FA AB 83, others FA. The byte after ED
--   is the LED mask, driven on LED (bit 0 scroll, 1 num, 2 caps).
--  Mouse (MOUSE=true): EVT = hps_io ps2_mouse {toggle, Y, X, flags}; each
--   event becomes the 3-byte packet, sent only while streaming is enabled
--   (after F4, until F5/F6/FF), as a real mouse does. FF -> FA AA 00,
--   F2 -> FA 00, others FA.
-- HOLD (clock inhibit) delays bytes; they wait in a 4-byte FIFO (one event
-- or reply; the converter has its own queue).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity PS2DIRECT is
generic(
	MOUSE	:boolean	:=false
);
port(
	DATIN	:in std_logic_vector(7 downto 0);
	DATOUT	:out std_logic_vector(7 downto 0);
	WRn		:in std_logic;
	BUSY	:out std_logic;
	RXED	:out std_logic;

	EVT		:in std_logic_vector(24 downto 0);
	HOLD	:in std_logic	:='0';
	LED		:out std_logic_vector(2 downto 0);

	clk		:in std_logic;
	rstn	:in std_logic
);
end PS2DIRECT;

architecture rtl of PS2DIRECT is
	type fifo_t is array(0 to 3) of std_logic_vector(7 downto 0);
	signal fifo		:fifo_t;
	signal rd, wr	:unsigned(1 downto 0);
	signal count	:integer range 0 to 4;
	signal gap		:integer range 0 to 7;
	signal last_wr	:std_logic;
	signal last_tog	:std_logic;
	signal primed	:std_logic;		-- last_tog holds the live toggle (no replay after reset)
	signal arg_next	:std_logic;		-- next command byte is an argument
	signal led_next	:std_logic;		-- next command byte is the LED mask
	signal stream	:std_logic;		-- mouse: data reporting enabled
	signal led_r	:std_logic_vector(2 downto 0);
	function tog_bit return integer is begin
		if MOUSE then return 24; else return 10; end if;
	end function;
begin
	BUSY<='1' when WRn='0' else '0';
	LED<=led_r;

	process(clk,rstn)
		type bytes_t is array(0 to 2) of std_logic_vector(7 downto 0);
		variable b		:bytes_t;
		variable n		:integer range 0 to 3;
		variable w		:unsigned(1 downto 0);
		variable c		:integer range 0 to 4;
		variable popped	:boolean;
	begin
		if rstn='0' then
			rd<=(others=>'0'); wr<=(others=>'0'); count<=0; gap<=0;
			last_wr<='1'; last_tog<='0'; primed<='0'; arg_next<='0'; led_next<='0';
			stream<='0'; led_r<="000"; RXED<='0'; DATOUT<=(others=>'0');
		elsif rising_edge(clk) then
			RXED<='0';
			last_wr<=WRn;
			c:=count;
			-- Send the oldest byte, spaced like back-to-back serial frames.
			popped:=false;
			if gap/=0 then
				gap<=gap-1;
			elsif c/=0 and HOLD='0' then
				DATOUT<=fifo(to_integer(rd)); RXED<='1';
				rd<=rd+1; c:=c-1; gap<=7; popped:=true;
			end if;
			-- At most one source adds bytes per cycle: a command reply first.
			n:=0;
			if primed='0' then
				last_tog<=EVT(tog_bit); primed<='1';
			end if;
			if WRn='0' and last_wr='1' then
				b(0):=x"FA"; n:=1;
				if led_next='1' then
					led_r<=DATIN(2 downto 0); led_next<='0';
				elsif arg_next='1' then
					arg_next<='0';
				elsif MOUSE then
					case DATIN is
						when x"FF" => b(1):=x"AA"; b(2):=x"00"; n:=3; stream<='0';
						when x"F2" => b(1):=x"00"; n:=2;
						when x"F4" => stream<='1';
						when x"F5" | x"F6" => stream<='0';
						when x"F3" | x"E8" => arg_next<='1';
						when others => null;
					end case;
				else
					case DATIN is
						when x"FF" => b(1):=x"AA"; n:=2;
						when x"F2" => b(1):=x"AB"; b(2):=x"83"; n:=3;
						when x"ED" => led_next<='1';
						when x"F3" => arg_next<='1';
						when others => null;
					end case;
				end if;
			elsif primed='1' and EVT(tog_bit)/=last_tog then
				-- Taken only here: an event that meets a command write waits a cycle.
				last_tog<=EVT(tog_bit);
				if MOUSE then
					if stream='1' then
						b(0):=EVT(7 downto 0); b(1):=EVT(15 downto 8); b(2):=EVT(23 downto 16); n:=3;
					end if;
				else
					if EVT(8)='1' then b(n):=x"E0"; n:=n+1; end if;
					if EVT(9)='0' then b(n):=x"F0"; n:=n+1; end if;
					b(n):=EVT(7 downto 0); n:=n+1;
				end if;
			end if;
			-- A sequence that no longer fits is dropped whole (never split).
			if n/=0 and c+n<=4 then
				w:=wr;
				for i in 0 to 2 loop
					if i<n then fifo(to_integer(w))<=b(i); w:=w+1; end if;
				end loop;
				wr<=w; c:=c+n;
			end if;
			count<=c;
		end if;
	end process;
end rtl;
