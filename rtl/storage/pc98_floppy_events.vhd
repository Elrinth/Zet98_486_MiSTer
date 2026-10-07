-- Opt-in OpenBIOS media-change latch. Does not issue commands to the uPD765.
-- 7ED0h read: A(version 1), enabled, native IRQ, changed drive 1/0.
-- Write A5h enables; 00h disables; 80h|mask acknowledges changed drives.
library ieee;
use ieee.std_logic_1164.all;

entity pc98_floppy_events is
    port (clk, rstn : in std_logic;
          present : in std_logic_vector(1 downto 0);
          native_irq, busy : in std_logic;
          address : in std_logic_vector(15 downto 0);
          rd, wr : in std_logic;
          wdata : in std_logic_vector(7 downto 0);
          rdata : out std_logic_vector(7 downto 0);
          oe, irq : out std_logic);
end entity;

architecture rtl of pc98_floppy_events is
    signal previous, pending : std_logic_vector(1 downto 0) := "00";
    signal enabled, old_wr, native_quiet, event_quiet : std_logic := '0';
begin
    rdata <= x"A" & enabled & native_irq & pending;
    oe <= '1' when address=x"7ED0" and rd='1' else '0';
    -- Never interrupt an in-flight data command or seek. Native completion
    -- has priority; pending changes survive until the BIOS acknowledges them.
    irq <= '1' when enabled='1' and pending/="00" and busy='0'
                    and native_irq='0' and native_quiet='1'
                    and event_quiet='1' else '0';
    process(clk, rstn)
        variable next_pending : std_logic_vector(1 downto 0);
    begin
        if rstn='0' then
            previous <= "00"; pending <= "00"; enabled <= '0'; old_wr <= '0';
            native_quiet <= '0';
            event_quiet <= '0';
        elsif rising_edge(clk) then
            -- The 8259 is edge-triggered. Leave a low interval after a native
            -- IRQ deasserts, otherwise ORing the pending event would hide the
            -- next rising edge if it arrived after the BIOS sampled status.
            native_quiet <= not native_irq;
            event_quiet <= '1';
            previous <= present;
            old_wr <= wr;
            next_pending := pending;
            if enabled='0' then next_pending := "00"; end if;
            if address=x"7ED0" and wr='1' and old_wr='0' then
                -- Re-arm the edge even when another drive changes between
                -- the BIOS status read and this acknowledgement.
                event_quiet <= '0';
                if wdata=x"A5" then
                    enabled <= '1'; next_pending := "00";
                elsif wdata=x"00" then
                    enabled <= '0'; next_pending := "00";
                elsif wdata(7 downto 2)="100000" then
                    next_pending := next_pending and not wdata(1 downto 0);
                end if;
            end if;
            -- A simultaneous transition wins over W1C, including a same-size
            -- replacement: diskemu drops present while it reloads the image.
            if enabled='1' then
                next_pending := next_pending or (present xor previous);
            end if;
            pending <= next_pending;
        end if;
    end process;
end architecture;
