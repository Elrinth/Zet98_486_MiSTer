"""Synthetic D88 images for tests/fdc_d88_tb.vhd. No private assets.

std : standard 2HD, 8 x 1024-byte MFM sectors, R=1..8 (sanity)
fm  : Xanadu-style 2HD boot disk. Tracks 0/1 are single density (D88
      density 40h): 26 x 128-byte FM sectors, interleaved 1,14,2,15,...
      (track 1 has sector 1 last). Track 2 has 5 x 1024 MFM sectors whose
      IDs say C=0 H=1 (copy protection).
loh : Legend of Heroes-style 2HD, 8 x 1024 MFM, D88 density 01h,
      track 0 IDs R=1,49..55, track 1 R=48..55.
Only the first few tracks are present; the others have offset 0.
"""
import pathlib, struct, sys

TRACKS = 164


def sector(c, h, r, n, nsec, density, payload):
    head = bytearray(16)
    head[:4] = bytes((c, h, r, n))
    struct.pack_into('<H', head, 4, nsec)
    head[6] = density
    struct.pack_into('<H', head, 14, len(payload))
    return bytes(head) + payload


def payload(track, r, size, salt):
    return bytes(((i * 7 + r * 31 + track * 57 + salt + (i >> 8) * 3) & 255) ^ (r & 0x5a)
                 for i in range(size))


def image(tracks, media=0x20):
    """tracks: {track_number: [(c,h,r,n,density,bytes)]}"""
    d = bytearray(0x2b0)
    d[:8] = b'FDCTEST\0'
    d[0x1b] = media
    for t in sorted(tracks):
        struct.pack_into('<I', d, 0x20 + 4 * t, len(d))
        secs = tracks[t]
        for c, h, r, n, den, data in secs:
            d += sector(c, h, r, n, len(secs), den, data)
    struct.pack_into('<I', d, 0x1c, len(d))
    return bytes(d)


def std():
    return image({t: [(t // 2, t % 2, r, 3, 0x00, payload(t, r, 1024, 1)) for r in range(1, 9)]
                  for t in range(4)})


def fm():
    order0 = [x for pair in zip(range(1, 14), range(14, 27)) for x in pair]
    order1 = order0[1:] + [1]
    tracks = {0: [(0, 0, r, 0, 0x40, payload(0, r, 128, 2)) for r in order0],
              1: [(0, 1, r, 0, 0x40, payload(1, r, 128, 2)) for r in order1]}
    for t in (2, 3):
        tracks[t] = [(0, 1, r, 3, 0x00, payload(t, r, 1024, 3)) for r in range(1, 6)]
    return image(tracks)


def loh():
    tracks = {0: [(0, 0, r, 3, 0x01, payload(0, r, 1024, 4)) for r in [1] + list(range(49, 56))]}
    for t in (1, 2, 3):
        tracks[t] = [(t // 2, t % 2, r, 3, 0x01, payload(t, r, 1024, 4)) for r in range(48, 56)]
    return image(tracks)


if __name__ == '__main__':
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, build in (('std', std), ('fm', fm), ('loh', loh)):
        (out / f'{name}.d88').write_bytes(build())
