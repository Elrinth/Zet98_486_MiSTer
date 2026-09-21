#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Import standard PC-98 HDM/FDI/NFD-R0 floppies or 512-byte HDI hard disks.

Outputs are new files; originals are never modified. Floppies become D88.
HDI becomes raw IMG/VHD plus geometry metadata, not a boot BIOS. 256-byte
SASI HDI and NFD protection/retry records require separate controller support.
Format references: NP2kai diskimage/fd/fdd_xdf.c, fdd_head_nfd.h and
fdd/sxsihdd.h at 5939e0c6d5985c4c08fc70f289a83290e5d3e6f7.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct


RAW_GEOMETRIES = {
    1261568: (77, 2, 8, 1024),
    1228800: (80, 2, 15, 512),
    1474560: (80, 2, 18, 512),
    655360: (80, 2, 8, 512),
    737280: (80, 2, 9, 512),
    327680: (40, 2, 8, 512),
}


def header_geometry(header, file_size):
    if len(header) < 32:
        raise ValueError('Truncated HDI/FDI header')
    reserved, kind, offset, size, bps, sectors, heads, cylinders = struct.unpack('<8I', header[:32])
    if (reserved != 0 or offset < 32 or offset > file_size or
            bps not in (128, 256, 512, 1024, 2048, 4096) or
            not 1 <= heads <= 255 or not 1 <= sectors <= 255 or
            not 1 <= cylinders <= 65535 or
            size != bps*sectors*heads*cylinders or file_size != offset+size):
        raise ValueError('Inconsistent HDI/FDI geometry or payload length')
    return dict(header_bytes=offset, data_bytes=size, bytes_per_sector=bps,
                sectors_per_track=sectors, heads=heads, cylinders=cylinders, media_type=kind)


def d88_tracks(data):
    if len(data) < 688 or struct.unpack_from('<I', data, 28)[0] != len(data):
        raise ValueError('Expected one complete D88 image')
    tracks, spans = [], []
    for slot, offset in enumerate(struct.unpack_from('<164I', data, 32)):
        if not offset:
            tracks.append([])
            continue
        if offset < 688 or offset+16 > len(data):
            raise ValueError('D88 track offset outside image')
        count = struct.unpack_from('<H', data, offset+4)[0]
        if not 1 <= count <= 255:
            raise ValueError('Invalid D88 sector count')
        start, records = offset, []
        for _ in range(count):
            if offset+16 > len(data):
                raise ValueError('Truncated D88 sector header')
            head = data[offset:offset+16]
            size = struct.unpack_from('<H', head, 14)[0]
            if struct.unpack_from('<H', head, 4)[0] != count or offset+16+size > len(data):
                raise ValueError('Invalid D88 sector payload')
            records.append((head, data[offset+16:offset+16+size]))
            offset += 16+size
        spans.append((start, offset))
        tracks.append(records)
    spans.sort()
    if not spans or any(a[1] > b[0] for a, b in zip(spans, spans[1:])):
        raise ValueError('Empty or overlapping D88 tracks')
    return tracks


def make_d88(tracks, name, media, protected=False):
    if len(tracks) > 164:
        raise ValueError('Too many tracks for D88')
    out = bytearray(688)
    title = name.encode('ascii', 'replace')[:16]
    out[:len(title)] = title
    out[26] = 0x10 if protected else 0
    out[27] = media
    for slot, records in enumerate(tracks):
        if not records:
            continue
        struct.pack_into('<I', out, 32+slot*4, len(out))
        for c, h, r, n, density, deleted, payload in records:
            head = bytearray(16)
            head[:4] = bytes((c, h, r, n))
            struct.pack_into('<H', head, 4, len(records))
            head[6] = density
            head[7] = 0x10 if deleted else 0
            struct.pack_into('<H', head, 14, len(payload))
            out.extend(head)
            out.extend(payload)
    struct.pack_into('<I', out, 28, len(out))
    d88_tracks(out)
    return bytes(out)


def import_floppy(path):
    if path.stat().st_size > 16*1024*1024:
        raise ValueError('Floppy image exceeds supported size')
    data = path.read_bytes()
    ext = path.suffix.lower()
    if ext == '.d88':
        tracks = d88_tracks(data)
        return data, dict(format='D88', sectors=sum(map(len, tracks)))
    protected = False
    if ext in ('.hdm', '.xdf'):
        if len(data) not in RAW_GEOMETRIES:
            raise ValueError('Unknown raw floppy geometry')
        cylinders, heads, sectors, bps = RAW_GEOMETRIES[len(data)]
        offset = 0
    elif ext == '.fdi':
        geometry = header_geometry(data, len(data))
        cylinders, heads, sectors, bps = (geometry[x] for x in
            ('cylinders', 'heads', 'sectors_per_track', 'bytes_per_sector'))
        offset = geometry['header_bytes']
    elif ext == '.nfd':
        if data[:15] != b'T98FDDIMAGE.R0\0':
            raise ValueError('Only NFD revision 0 is supported; R1/retry data is not flattened')
        if len(data) < 68112:
            raise ValueError('Truncated NFD-R0 header')
        offset = struct.unpack_from('<I', data, 272)[0]
        if not 68112 <= offset <= len(data) or data[277] not in (1, 2):
            raise ValueError('Invalid NFD-R0 header')
        protected = bool(data[276])
        tracks, media_codes = [], set()
        for slot in range(163):
            records = []
            for sector in range(26):
                pos = 288+(slot*26+sector)*16
                c, h, r, n, mfm, deleted, status, st0, st1, st2, pda = data[pos:pos+11]
                if c == 255:
                    continue
                if (n > 5 or mfm > 1 or deleted > 1 or status or
                        st0 & 0xf8 or st1 or st2):
                    raise ValueError('NFD error/protection record cannot be represented losslessly by this importer')
                if h >= data[277] or pda not in (0x10, 0x30, 0x90):
                    raise ValueError('Unsupported NFD media/head metadata')
                size = 128 << n
                if offset+size > len(data):
                    raise ValueError('Truncated NFD sector data')
                media_codes.add(0x10 if pda == 0x10 else 0x20)
                records.append((c, h, r, n, 0 if mfm else 0x40, deleted, data[offset:offset+size]))
                offset += size
            tracks.append(records)
        if offset != len(data) or len(media_codes) != 1:
            raise ValueError('NFD has unrepresented trailing data or mixed media')
        result = make_d88(tracks, path.stem, media_codes.pop(), protected)
        return result, dict(format='NFD-R0', sectors=sum(map(len, tracks)), protected=protected)
    else:
        raise ValueError('Expected D88, HDM, XDF, FDI, NFD or HDI')
    if cylinders > 82 or heads not in (1, 2) or sectors > 26:
        raise ValueError('Floppy geometry exceeds D88 track layout')
    n = bps.bit_length()-8
    capacity = bps*cylinders*heads*sectors
    media = 0x00 if cylinders <= 42 and capacity < 500000 else (0x10 if capacity < 1000000 else 0x20)
    tracks = []
    for c in range(cylinders):
        for h in range(2):
            records = []
            if h < heads:
                for r in range(1, sectors+1):
                    records.append((c, h, r, n, 0, False, data[offset:offset+bps]))
                    offset += bps
            tracks.append(records)
    if offset != len(data):
        raise ValueError('Floppy payload length mismatch')
    result = make_d88(tracks, path.stem, media, protected)
    return result, dict(format=ext[1:].upper(), sectors=cylinders*heads*sectors,
                        cylinders=cylinders, heads=heads, sectors_per_track=sectors,
                        bytes_per_sector=bps)


def convert(source, output):
    source, output = Path(source), Path(output)
    metadata_path = Path(str(output)+'.json')
    if source.resolve() == output.resolve() or output.exists() or metadata_path.exists():
        raise ValueError('Output and metadata must be new files')
    if source.suffix.lower() == '.hdi':
        with source.open('rb') as stream:
            metadata = header_geometry(stream.read(32), source.stat().st_size)
            if metadata['bytes_per_sector'] != 512:
                raise ValueError('This HDI uses non-512-byte SASI sectors; it needs SASI support, not header removal')
            if output.suffix.lower() not in ('.img', '.vhd'):
                raise ValueError('HDI output must be raw .img or .vhd')
            stream.seek(metadata['header_bytes'])
            digest = hashlib.sha256()
            with output.open('xb') as dest:
                for block in iter(lambda: stream.read(1024*1024), b''):
                    dest.write(block)
                    digest.update(block)
            metadata.update(format='HDI', output_format='raw', sha256=digest.hexdigest(),
                note='Geometry retained here; a compatible disk BIOS is still required for boot.')
    else:
        if output.suffix.lower() != '.d88':
            raise ValueError('Floppy output must be .d88')
        result, metadata = import_floppy(source)
        with output.open('xb') as dest:
            dest.write(result)
        metadata.update(output_format='D88', sha256=hashlib.sha256(result).hexdigest())
    metadata.update(source_name=source.name, output_name=output.name)
    with metadata_path.open('x', encoding='utf-8') as stream:
        json.dump(metadata, stream, indent=2)
        stream.write('\n')
    return metadata


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(convert(args.source, args.output), indent=2))
    except (ValueError, OSError) as exc:
        parser.exit(1, str(exc)+'\n')
