"""Compare a guest DOS directory dump with a separately retained WAD file."""
from pathlib import Path
import hashlib
import json
import struct
import sys
import zlib


def verify(result_path, wad_path):
    result = Path(result_path).read_bytes()
    with Path(wad_path).open('rb') as f:
        header = f.read(12)
        magic, count, offset = struct.unpack('<4sII', header)
        assert magic in (b'IWAD', b'PWAD') and 0 < count <= 2048
        f.seek(offset)
        directory = f.read(count * 16)
    assert len(directory) == count * 16
    assert result[:8] == b'Z98WAD1\0'
    assert len(result) == 64 + len(directory)
    assert struct.unpack_from('<I', result, 8)[0] == Path(wad_path).stat().st_size
    assert result[12:24] == header, 'Guest header differs from retained WAD'
    assert result[64:] == directory, 'Guest directory differs from retained WAD'
    assert struct.unpack_from('<II', result, 24) == (zlib.crc32(directory), count)
    names = {}
    for i in range(count):
        pos, size, name = struct.unpack_from('<II8s', directory, i * 16)
        assert pos + size <= Path(wad_path).stat().st_size
        names[name.rstrip(b'\0')] = i
    wanted = [b'DEMO1', b'DEMO3', b'TITLEPIC', b'E1M1', b'E1M2']
    expected = tuple(names.get(name, 0xffffffff) for name in wanted)
    actual = struct.unpack_from('<5I', result, 32)
    assert actual == expected, 'Guest name indices differ'
    assert result[52:64] == bytes(12)
    return dict(passed=True, directory_entries=count, directory_bytes=len(directory),
                directory_crc32=f'{zlib.crc32(directory):08x}',
                exact_header_and_directory=True,
                indices={n.decode(): v for n, v in zip(wanted, actual)},
                result_sha256=hashlib.sha256(result).hexdigest(),
                limitation='Checks DOS header/directory reads; not every lump payload or Doom runtime state.')


if __name__ == '__main__':
    print(json.dumps(verify(sys.argv[1], sys.argv[2]), indent=2))
