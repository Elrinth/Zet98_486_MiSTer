-- SPDX-License-Identifier: GPL-3.0-or-later
-- Byte-level floppy data link between the FDC and the disk emulator, in place
-- of FM/MFM bit cells on RDBIT/WRBIT. Both ends run in one clock domain.
-- A byte is {DAT, MARK (missing-clock address mark), MFM (density)}, sent as
-- a one-cycle STB when its last cell would have left the modulator.
--
-- fdlinktx: the fmmod/mfmmod handshake (one-byte holding register, txemp,
--   txend, writeen, 16 cell periods per byte at the byte's density's cell
--   clock) without the cells. A
--   marked byte is sent only if it is a mark the modulator can encode
--   (MFM A1/C2, FM F8/FB/FC/FE); otherwise the write is ignored, as there.
-- fdlinkrx: the fmdem/mfmdem outputs for that byte stream. Like the bit
--   demodulators, each gains byte sync only from its own address marks (MFM:
--   A1, or C2 after another C2 - the C2 pattern spans 32 cells; FM: F8, FB,
--   FC, FE), delivers RXDAT/RXED for every byte after that, and loses sync on
--   init, break or a byte of the other density.
library ieee;
use ieee.std_logic_1164.all;

entity fdlinktx is
port(
	txdat	:in std_logic_vector(7 downto 0);
	txwr	:in std_logic;
	txmark	:in std_logic;		-- txdat is an address mark
	txmfm	:in std_logic;		-- density of this byte
	break	:in std_logic;

	txemp	:out std_logic;
	txend	:out std_logic;
	writeen	:out std_logic;

	DAT		:out std_logic_vector(7 downto 0);
	MARK	:out std_logic;
	MFM		:out std_logic;
	STB		:out std_logic;

	sftfm	:in std_logic;		-- cell clock of an FM byte
	sftmfm	:in std_logic;		-- cell clock of an MFM byte (same signal on the FDC side)
	clk		:in std_logic;
	rstn	:in std_logic
);
end fdlinktx;

architecture rtl of fdlinktx is
	signal nxtemp	:std_logic;
	signal nxtdat	:std_logic_vector(7 downto 0);
	signal nxtmark	:std_logic;
	signal nxtmfm	:std_logic;
	signal curdat	:std_logic_vector(7 downto 0);
	signal curmark	:std_logic;
	signal curmfm	:std_logic;
	signal getnext	:std_logic;
	signal bitcount	:integer range 0 to 15;
	signal valid	:std_logic;
	signal sft		:std_logic;
begin
	-- A byte's cells run at its own density's rate; the next byte starts on
	-- its own density's clock.
	sft<=	sftmfm when (bitcount/=0 and curmfm='1') or (bitcount=0 and nxtmfm='1') else sftfm;
	valid<=	'0' when txwr='0' else
			'1' when txmark='0' else
			'1' when txmfm='1' and (txdat=x"a1" or txdat=x"c2") else
			'1' when txmfm='0' and (txdat=x"f8" or txdat=x"fb" or txdat=x"fc" or txdat=x"fe") else
			'0';
	txemp<=nxtemp and not valid;

	process(clk,rstn)begin
		if(rstn='0')then
			nxtemp<='1';
			nxtdat<=(others=>'0'); nxtmark<='0'; nxtmfm<='0';
		elsif(clk' event and clk='1')then
			if(break='1')then
				nxtemp<='1';
			elsif(nxtemp='1')then
				if(valid='1')then
					nxtdat<=txdat; nxtmark<=txmark; nxtmfm<=txmfm;
					nxtemp<='0';
				end if;
			elsif(getnext='1')then
				nxtemp<='1';
			end if;
		end if;
	end process;

	process(clk,rstn)begin
		if(rstn='0')then
			getnext<='0';
			writeen<='0';
			bitcount<=0;
			txend<='1';
			STB<='0';
			curdat<=(others=>'0'); curmark<='0'; curmfm<='0';
		elsif(clk' event and clk='1')then
			getnext<='0';
			STB<='0';
			if(break='1')then
				writeen<='0';
				bitcount<=0;
			elsif(sft='1')then
				if(bitcount>0)then
					if(bitcount=1)then
						STB<='1';			-- last cell of the byte has left
					end if;
					bitcount<=bitcount-1;
				else
					txend<='1';
					if(nxtemp='0')then
						txend<='0';
						getnext<='1';
						curdat<=nxtdat; curmark<=nxtmark; curmfm<=nxtmfm;
						bitcount<=15;
						writeen<='1';
					else
						writeen<='0';
					end if;
				end if;
			end if;
		end if;
	end process;
	DAT<=curdat;
	MARK<=curmark;
	MFM<=curmfm;
end rtl;

library ieee;
use ieee.std_logic_1164.all;

entity fdlinkrx is
port(
	DAT		:in std_logic_vector(7 downto 0);
	MARK	:in std_logic;
	MFM		:in std_logic;
	STB		:in std_logic;

	fminit	:in std_logic;
	fmbreak	:in std_logic;
	mfminit	:in std_logic;
	mfmbreak:in std_logic;

	RXDAT	:out std_logic_vector(7 downto 0);	-- both demodulators
	FMRXED	:out std_logic;
	DetMF8	:out std_logic;
	DetMFB	:out std_logic;
	DetMFC	:out std_logic;
	DetMFE	:out std_logic;
	MFMRXED	:out std_logic;
	DetMA1	:out std_logic;
	DetMC2	:out std_logic;

	clk		:in std_logic;
	rstn	:in std_logic
);
end fdlinkrx;

architecture rtl of fdlinkrx is
	signal fmsync, mfmsync, lastc2 :std_logic;
begin
	process(clk,rstn)begin
		if(rstn='0')then
			fmsync<='0'; mfmsync<='0'; lastc2<='0';
			RXDAT<=(others=>'0');
			FMRXED<='0'; DetMF8<='0'; DetMFB<='0'; DetMFC<='0'; DetMFE<='0';
			MFMRXED<='0'; DetMA1<='0'; DetMC2<='0';
		elsif(clk' event and clk='1')then
			FMRXED<='0'; DetMF8<='0'; DetMFB<='0'; DetMFC<='0'; DetMFE<='0';
			MFMRXED<='0'; DetMA1<='0'; DetMC2<='0';
			if(STB='1')then
				RXDAT<=DAT;
				if(MFM='1')then
					fmsync<='0';
					lastc2<=MARK and (DAT(7) and DAT(6) and not DAT(5) and not DAT(4) and not DAT(3) and not DAT(2) and DAT(1) and not DAT(0));
					if(MARK='1' and DAT=x"a1")then
						DetMA1<='1'; mfmsync<='1';
					elsif(MARK='1' and DAT=x"c2" and lastc2='1')then
						DetMC2<='1'; mfmsync<='1';
					elsif(mfmsync='1')then
						MFMRXED<='1';
					end if;
				else
					mfmsync<='0'; lastc2<='0';
					if(MARK='1' and DAT=x"f8")then
						DetMF8<='1'; fmsync<='1';
					elsif(MARK='1' and DAT=x"fb")then
						DetMFB<='1'; fmsync<='1';
					elsif(MARK='1' and DAT=x"fc")then
						DetMFC<='1'; fmsync<='1';
					elsif(MARK='1' and DAT=x"fe")then
						DetMFE<='1'; fmsync<='1';
					elsif(fmsync='1')then
						FMRXED<='1';
					end if;
				end if;
			end if;
			-- init/break win over a byte of the same cycle, as in the demodulators
			if(fminit='1' or fmbreak='1')then
				fmsync<='0';
				FMRXED<='0'; DetMF8<='0'; DetMFB<='0'; DetMFC<='0'; DetMFE<='0';
			end if;
			if(mfminit='1' or mfmbreak='1')then
				mfmsync<='0'; lastc2<='0';
				MFMRXED<='0'; DetMA1<='0'; DetMC2<='0';
			end if;
		end if;
	end process;
end rtl;
