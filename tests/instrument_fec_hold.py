#!/usr/bin/env python3
"""Observe the real FEC source hold interval after its qualified capture edge."""
from pathlib import Path
import sys
s=Path('Zet98/sdramc.vhd').read_text()
a='signal fde_read_data, fec_read_data : std_logic_vector(15 downto 0);'
assert s.count(a)==1
s=s.replace(a,a+'''
signal test_fec_captured_at :time := 0 ns;
signal test_fec_has_capture :boolean := false;
''')
a="FECRDAT <= (others=>'0');"
assert s.count(a)==1
s=s.replace(a,a+' test_fec_has_capture <= false;')
a='FECRDAT <= fec_read_crossing;'
assert s.count(a)==1
s=s.replace(a,'''assert fec_read_crossing'stable(5 ns)
                        report "FEC return bundle arrived too late" severity failure;
                    test_fec_captured_at <= now; test_fec_has_capture <= true;
                    '''+a)
a='    fec_read_crossing <= fec_read_data; -- FEC_READ_BUNDLE_TRANSPORT'
assert s.count(a)==1
s=s.replace(a,'''    fec_read_crossing <= transport fec_read_data after 5 ns;
    process(fec_read_data,rstn) begin
        if rstn='1' and fec_read_data'event and test_fec_has_capture then
            assert now-test_fec_captured_at >= 20 ns
                report "FEC payload changed inside post-capture hold window"
                severity failure;
        end if;
    end process;
''')
Path(sys.argv[1]).write_text(s)
# Deliberately overwrite the held response on the next memory edge after
# capture instead of waiting for the next accepted memory transaction.
a='\t\t\tlSTATE<=STATE;'
assert s.count(a)==1
bad=s.replace(a,a+'''
            if test_fec_has_capture then
                fec_read_data <= not fec_read_data;
            end if;
''')
Path(sys.argv[2]).write_text(bad)
