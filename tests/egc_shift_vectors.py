#!/usr/bin/env python3
"""Generate shift transactions and check the NP2 oracle using pixel lists.

No source words or masks are computed with the RTL's packed shift equations.
The independent model copies individual pixels through four FIFO lists.
"""
import argparse
from pathlib import Path


def generate(path):
    state = 0x98e6c486

    def word():
        nonlocal state
        state ^= (state << 13) & 0xffffffff
        state ^= state >> 17
        state ^= (state << 5) & 0xffffffff
        return state

    with path.open('w', encoding='ascii', newline='\n') as out:
        for reverse in range(2):
            for src in range(16):
                for dst in range(16):
                    shift = (reverse << 12) | (dst << 4) | src
                    # Reserved bits must not leak into alignment/direction.
                    if (src + dst) & 1:
                        shift |= 0xef00
                    lengths = list(range(1, 34)) + [63, 64, 65, 255, 256, 257, 4095, 4096]
                    for length in lengths:
                        length_register = (length - 1) | (0xa000 if src & 1 else 0)
                        out.write(f'1 {shift:04x} {length_register:04x} 0000000000000000\n')
                        count = (length + dst + 15) // 16 + (src > dst)
                        # Two scanlines without register writes test auto-reload.
                        for _ in range(count * 2):
                            data = (word() << 32) | word()
                            out.write(f'0 {shift:04x} {length_register:04x} {data:016x}\n')
                        # Interrupt another row with the next register reload.
                        if length > 32:
                            data = (word() << 32) | word()
                            out.write(f'0 {shift:04x} {length_register:04x} {data:016x}\n')


def verify(path):
    records = priming = rows = reloads = 0
    queues = [[], [], [], []]
    for line_number, line in enumerate(path.open(encoding='ascii'), 1):
        reload, shift, length, data, expected_mask, expected_data = (
            int(value, 16) for value in line.split())
        length &= 0xfff
        reverse = bool(shift & 0x1000)
        order = list(range(8, 16)) + list(range(8)) if reverse else (
            list(range(7, -1, -1)) + list(range(15, 7, -1)))
        if reload:
            queues = [[], [], [], []]
            source_skip, dest_skip, remaining = shift & 15, (shift >> 4) & 15, length + 1
            reloads += 1
            continue
        for plane in range(4):
            pixels = [(data >> (plane * 16 + bit)) & 1 for bit in order]
            queues[plane].extend(pixels[source_skip:])
        source_skip = 0
        need = 16 - dest_skip
        result = mask = 0
        if len(queues[0]) < need:
            priming += 1
        else:
            take = min(need, remaining)
            for pixel in range(take):
                bit = order[dest_skip + pixel]
                mask |= 1 << bit
                for plane in range(4):
                    result |= queues[plane][pixel] << (plane * 16 + bit)
            queues = [queue[need:] for queue in queues]
            remaining -= take
            dest_skip = 0
            if remaining == 0:
                rows += 1
                queues = [[], [], [], []]
                source_skip, dest_skip, remaining = shift & 15, (shift >> 4) & 15, length + 1
        if (mask, result) != (expected_mask, expected_data):
            raise AssertionError(f'NP2/pixel-list mismatch line={line_number} shift={shift:04x} '
                                 f'length={length+1}: {mask:04x}/{result:016x} != '
                                 f'{expected_mask:04x}/{expected_data:016x}')
        records += 1
    assert reloads == 2 * 16 * 16 * 41
    assert rows >= reloads * 2
    assert priming > 0
    print(f'PASS: EGC NP2/pixel-list agreement: {records} source words, '
          f'{reloads} settings, {rows} completed rows, {priming} priming reads')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['generate', 'verify'])
    parser.add_argument('path', type=Path)
    args = parser.parse_args()
    (generate if args.mode == 'generate' else verify)(args.path)
