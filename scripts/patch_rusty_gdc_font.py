#!/usr/bin/env python3
"""Create a corrected copy of the known Rusty English GDC graphics driver.

The English EGC driver uses single-width ROM glyphs for its menu letters.
The older GDC driver in the tested package retains the Japanese conversion
constants. Adjust its two compressed-stream literals without changing the
compression layout. Only the exact verified input is accepted; no game
content is included and neither the input nor an existing output is replaced.
"""
import argparse
import hashlib
from pathlib import Path

ORIGINAL_SHA256 = 'cf69d2ad1d6eca07e6dfa13f4f21c03c488db44b4a4bbbc14f6faa50a23b0f99'
CORRECTED_SHA256 = '5a42d4f76bd0c87d1e8473cd503447501902f072a1ee781530e01caf7707aded'


def correct(data):
    if len(data) != 7800 or hashlib.sha256(data).hexdigest() != ORIGINAL_SHA256:
        raise ValueError('Unsupported driver: expected the verified Rusty English GRPGDC.COM')
    result = bytearray(data)
    result[0x146e] = 0x00
    result[0x1471] = 0x1a
    if hashlib.sha256(result).hexdigest() != CORRECTED_SHA256:
        raise ValueError('Corrected driver verification failed')
    return bytes(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.input.resolve() == args.output.resolve():
        parser.error('Choose a new output file; the original must be preserved')
    try:
        result = correct(args.input.read_bytes())
        with args.output.open('xb') as destination:
            destination.write(result)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    print(f'Created {args.output}: {CORRECTED_SHA256}')


if __name__ == '__main__':
    main()
