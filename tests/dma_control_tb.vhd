library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity dma_control_tb is
    generic(CPU486 : integer := 2);
end;
architecture test of dma_control_tb is
    signal cpuclk : std_logic := '0';
    signal srstn, iord, iowr : std_logic := '0';
    signal ioaddr_odd : std_logic_vector(15 downto 0) := x"0439";
    signal io_wdata : std_logic_vector(15 downto 0) := x"0000";
    signal IO439_LATCH, IO439_READ, IO439_ODAT : std_logic_vector(7 downto 0);
    signal DMA1MMASK, FASTLIOBIOSEN, IO439_DOE : std_logic;
begin
    cpuclk <= not cpuclk after 5 ns;
    process
        procedure tick is
        begin wait until rising_edge(cpuclk); wait for 1 ns; end;
        variable expected : std_logic_vector(7 downto 0);
    begin
        tick; tick; srstn <= '1'; iord <= '1'; tick; tick;
        if CPU486/=0 then
            assert IO439_ODAT=x"00" report "Reset status cannot be zero" severity failure;
        else
            assert IO439_ODAT=x"08" report "Legacy reset status changed" severity failure;
        end if;
        for value in 0 to 255 loop
            expected := std_logic_vector(to_unsigned(value, 8));
            wait until falling_edge(cpuclk);
            iowr <= '1'; iord <= '0'; io_wdata <= expected & x"ff";
            tick; tick;
            iowr <= '0'; iord <= '1'; tick; tick;
            assert DMA1MMASK=expected(2) and FASTLIOBIOSEN=expected(1)
                report "DMA/fast BIOS control outputs changed" severity failure;
            if CPU486=0 then expected := (expected and x"06") or x"08"; end if;
            assert IO439_DOE='1' and IO439_ODAT=expected
                report "0439h write/read mismatch " & integer'image(value) severity failure;
        end loop;
        ioaddr_odd <= x"043b"; tick;
        assert IO439_DOE='0' report "Read decode aliases 043Bh" severity failure;
        report "DMA control readback PASS, CPU486=" & integer'image(CPU486);
        stop; wait;
    end process;
    -- The runner appends the actual top-level production wiring here.
end;
