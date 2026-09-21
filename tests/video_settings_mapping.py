#!/usr/bin/env python3
"""Check the real top-level GDC field wiring against the preceding port map.

The RTL handshake is tested separately. This catches swapped/overlapping bit
fields while packing both vector and integer CRTC settings through that link.
"""
import json
from pathlib import Path
import random
import re
import sys


def bits(text):
    numbers = [int(n) for n in re.findall(r'\d+', text)]
    return (numbers[0], numbers[0]) if len(numbers) == 1 else tuple(numbers)


def normalize(text):
    return re.sub(r'\s+', '', text).lower()


def check(source):
    fields = json.loads(Path('tests/reference/gdc_settings_fields.json').read_text())
    assignments = [(bits(span), normalize(expression)) for span, expression in re.findall(
        r'video_settings_source\(([^)]+)\)\s*<=\s*([^;]+);', source)]
    assert len(assignments) == len(fields)
    coverage = []
    for (hi, lo), _ in assignments:
        assert hi >= lo
        coverage.extend(range(lo, hi+1))
    assert sorted(coverage) == list(range(121)), 'Missing or overlapping GDC snapshot bits'
    block = source.split('VID\t:CRTC98 port map(', 1)[1].split('\n\t);', 1)[0]
    outputs = {}
    for name, width, expression in fields:
        port = re.search(r'^\s*'+name+r'\s*=>\s*(.*),\s*$', block, re.M).group(1)
        match = re.fullmatch(r'(?:conv_integer\()?video_settings_received\(([^)]+)\)\)?', port)
        assert match, (name, port)
        hi, lo = bits(match[1])
        assert hi-lo+1 == width, name
        assert port.startswith('conv_integer') == (name in ('CURUPPER', 'CURLOWER'))
        outputs[name] = hi, lo
    rng = random.Random(0x98cd121)
    # One-hot basis tests expose individual dropped/swapped bits; random words
    # exercise mixed field values. Expression names preserve original inversions.
    vectors = [0] + [1 << i for i in range(121)] + [rng.getrandbits(121) for _ in range(10000)]
    for vector in vectors:
        values = {}
        position = 0
        for name, width, expression in fields:
            values[normalize(expression)] = (vector >> position) & ((1 << width)-1)
            position += width
        packed = 0
        for (hi, lo), expression in assignments:
            packed |= values[expression] << lo
        for name, width, expression in fields:
            hi, lo = outputs[name]
            actual = (packed >> lo) & ((1 << width)-1)
            assert actual == values[normalize(expression)], 'GDC field mismatch: '+name
    print('PASS actual GDC settings mapping:', len(vectors), 'vectors,', len(fields), 'fields')


if __name__ == '__main__':
    source = Path(sys.argv[1] if len(sys.argv)>1 else 'Zet98/Zet98MiSTer.vhd').read_text(encoding='utf-8')
    check(source)
    # Deliberately wire graphics pitch to text pitch, the same width. This
    # must fail even though VHDL type checking would accept the port map.
    wrong = re.sub(r'(GPITCH\s*=>\s*)video_settings_received\(112 downto 105\)',
                   r'\1video_settings_received(20 downto 13)', source)
    assert wrong != source, 'Negative control did not change graphics pitch'
    try:
        check(wrong)
    except AssertionError as error:
        assert str(error) == 'GDC field mismatch: GPITCH', str(error)
        print('PASS swapped text/graphics pitch negative control rejected')
    else:
        raise AssertionError('Swapped GDC pitch wiring was accepted')
