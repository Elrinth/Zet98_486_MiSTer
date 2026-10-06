#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic two-row EGC copy cases for egc_alignment.asm, no game data.

Each 200-byte record contains four header words (shift, length-1, steps,
pixel mask) followed by eight slots of four source, destination and expected
plane words. An independent pixel queue supplies the expected result.
"""
import argparse
import random
import struct
from pathlib import Path


def generate():
    rng = random.Random(0x98e6c486)
    output = bytearray()
    transfers = 0
    for reverse in range(2):
        order = list(range(8, 16)) + list(range(8)) if reverse else (
            list(range(7, -1, -1)) + list(range(15, 7, -1)))
        for source_skip in range(16):
            for destination_skip in range(16):
                shift = (reverse << 12) | (destination_skip << 4) | source_skip
                mask = (0xffff, 0x5555, 0xaaaa, 0xff7e)[(source_skip + destination_skip) % 4]
                steps = ((24 + destination_skip + 15) // 16 + (source_skip > destination_skip)) * 2
                output.extend(struct.pack('<4H', shift, 23, steps, mask))
                queues = [[] for _ in range(4)]
                src, dst, remaining, rows = source_skip, destination_skip, 24, 0
                for step in range(8):
                    if step >= steps:
                        output.extend(bytes(24))
                        continue
                    source = [rng.randrange(65536) for _ in range(4)]
                    destination = [rng.randrange(65536) for _ in range(4)]
                    expected = destination[:]
                    for plane in range(4):
                        queues[plane].extend((source[plane] >> bit) & 1 for bit in order[src:])
                    src = 0
                    need = 16 - dst
                    if len(queues[0]) >= need:
                        for pixel in range(min(need, remaining)):
                            bit = order[dst + pixel]
                            if mask & (1 << bit):
                                for plane in range(4):
                                    expected[plane] = (expected[plane] & ~(1 << bit)) | (queues[plane][pixel] << bit)
                        queues = [q[need:] for q in queues]
                        remaining -= min(need, remaining)
                        dst = 0
                        if remaining == 0:
                            rows += 1
                            queues = [[] for _ in range(4)]
                            src, dst, remaining = source_skip, destination_skip, 24
                    output.extend(struct.pack('<12H', *(source + destination + expected)))
                assert rows == 2 and not any(queues)
                transfers += steps
    assert len(output) == 512 * 200
    return bytes(output), transfers


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    data, transfers = generate()
    args.output.write_bytes(data)
    print(f'512 cases, {transfers} source-read/destination-write pairs, {transfers * 4} plane checks')
