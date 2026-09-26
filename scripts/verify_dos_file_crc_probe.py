#!/usr/bin/env python3
"""Compare DOS-read file CRC32 records with a host-generated manifest."""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def verify(data, expected):
    data = bytes(data)
    assert data[:8] == b'Z98FCRC1'
    count, record_size, reserved1, reserved2 = struct.unpack_from('<4H', data, 8)
    assert (record_size, reserved1, reserved2) == (32, 0, 0)
    assert len(data) == 16 + count * 32
    wanted = {bytes.fromhex(item['name_hex']): item for item in expected}
    assert len(wanted) == len(expected) == count
    seen, failures = set(), []
    for index in range(count):
        record = data[16+index*32:48+index*32]
        name = record[:13].split(b'\0')[0]
        assert name in wanted and name not in seen, 'Unexpected or duplicate name'
        seen.add(name)
        size, crc, read = struct.unpack_from('<3I', record, 16)
        item = wanted[name]
        if size != item['size'] or read != item['size'] or crc != item['crc32']:
            failures.append(dict(name_hex=name.hex(), expected=item,
                                 size=size, read=read, crc32=crc))
        assert record[13:16] == b'\0'*3 and record[28:] == b'\0'*4
    return dict(passed=not failures, files=count,
                checked_file_bytes=sum(item['size'] for item in expected),
                failures=failures, sha256=hashlib.sha256(data).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    result = verify(args.capture.read_bytes(), json.loads(args.manifest.read_text()))
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['passed'] else 1)
