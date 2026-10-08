-- SPDX-License-Identifier: GPL-3.0-or-later
-- PC-9821 software DIP switches: two banks of twelve bytes at 841Eh..8F1Eh.
-- Settings survive CPU/OSD reset; a full FPGA reload initializes them to FFh.
-- No host-file persistence is provided. Layout/DSW2 translation documented by
-- MAME's pc98_sdip device. Keep legacy OSD DIP inputs until firmware programs
-- the software DSW2 register, so older BIOSes retain their existing settings.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pc98_sdip is
    port (clk, rstn : in std_logic;
          even_address, odd_address : in std_logic_vector(15 downto 0);
          rd, wr : in std_logic;
          wdata : in std_logic_vector(15 downto 0);
          legacy_dsw2 : in std_logic_vector(7 downto 0);
          rdata, dsw2 : out std_logic_vector(7 downto 0);
          oe : out std_logic);
end entity;

architecture rtl of pc98_sdip is
    -- Four unused bytes per bank avoid an address subtractor.
    type ram_t is array(0 to 31) of std_logic_vector(7 downto 0);
    signal settings : ram_t := (others => x"FF");
    attribute ramstyle : string;
    attribute ramstyle of settings : signal is "MLAB";
    signal bank, old_wr : std_logic := '0';
    signal enabled : std_logic := '0';
    signal switch2 : std_logic_vector(7 downto 0) := x"FF";
    signal memsw_init : std_logic := '1';
    signal address : unsigned(4 downto 0);
    signal selected : std_logic;
    signal q : std_logic_vector(7 downto 0);
    signal gdc_2m5 : std_logic := '1';
    function gdc_readback(raw : std_logic_vector(7 downto 0);
                          selected_clock : std_logic) return std_logic_vector is
        variable value : std_logic_vector(7 downto 0);
    begin
        value := raw;
        value(7) := selected_clock;
        -- Bit 4 is parity, not the legacy MEMSW bit. Preserve parity validity:
        -- changing bit 7 flips bit 4 too. Blank/corrupt storage stays invalid
        -- so native firmware still performs its initialization/recovery.
        value(4) := raw(4) xor raw(7) xor selected_clock;
        return value;
    end;

begin
    selected <= '1' when even_address(15 downto 12)=x"8" and
        unsigned(even_address(11 downto 8)) >= 4 and
        even_address(7 downto 0)=x"1E" else '0';
    address <= unsigned(bank & even_address(11 downto 8));
    -- 0534h: 486 high-speed mode (bit 0 clear); no 25/33 MHz selector.
    rdata <= x"00" when even_address=x"0534" else
        gdc_readback(q,gdc_2m5) when bank='0' and even_address=x"851E" else q;
    oe <= rd when selected='1' or even_address=x"0534" else '0';
    dsw2 <= gdc_2m5 & switch2(6 downto 5) & memsw_init & switch2(3 downto 0)
        when enabled='1' else gdc_2m5 & legacy_dsw2(6 downto 0);

    process(clk)
    begin
        if rising_edge(clk) then
            -- F12 is authoritative for GDC speed. Sample while CPU/OSD reset
            -- is asserted, keeping BIOS work-area and hardware setup coherent
            -- for the entire run. Software DIP contents remain intact.
            if rstn='0' then gdc_2m5 <= legacy_dsw2(7); end if;
            -- The PC-98 I/O bridge holds the address before acknowledging.
            q <= settings(to_integer(address));
            if rstn='1' and wr='1' and old_wr='0' and selected='1' then
                settings(to_integer(address)) <= wdata(7 downto 0);
                if bank='0' and even_address(11 downto 8)=x"5" then
                    switch2 <= wdata(7 downto 0);
                    enabled <= '1';
                end if;
                if bank='0' and even_address(11 downto 8)=x"7" then
                    memsw_init <= wdata(5);
                end if;
            end if;
        end if;
    end process;
    process(clk, rstn)
    begin
        if rstn='0' then
            bank <= '0'; old_wr <= '0';
        elsif rising_edge(clk) then
            old_wr <= wr;
            if wr='1' and old_wr='0' and odd_address=x"8F1F" then
                if wdata(15 downto 8)=x"80" then bank <= '0';
                elsif wdata(15 downto 8)=x"C0" then bank <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;
