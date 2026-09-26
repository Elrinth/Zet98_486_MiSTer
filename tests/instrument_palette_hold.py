#!/usr/bin/env python3
"""Add a simulation-only temporal observer to the actual palette handshake."""
from pathlib import Path
import sys

source = Path('Zet98/grpal.vhd').read_text()
anchor = '        palette_transfer <= palette_hold;'
assert source.count(anchor) == 1
observer = '''
        -- Acknowledge changes on the edge that captures the palette. Observe
        -- actual data events independently of the source's update condition.
        process(palette_hold, palette_ack, rstn)
            variable captured_at : time := 0 ns;
            variable have_capture : boolean := false;
        begin
            if rstn='0' then
                have_capture := false;
            else
                if palette_hold'event and have_capture then
                    assert now-captured_at >= 20 ns
                        report "palette payload changed inside post-capture hold window"
                        severity failure;
                end if;
                if palette_ack'event then
                    captured_at := now;
                    have_capture := true;
                end if;
            end if;
        end process;
'''
Path(sys.argv[1]).write_text(source.replace(anchor, anchor+observer))
