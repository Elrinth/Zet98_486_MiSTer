"""Compare every guest running-CRC checkpoint against a retained WAD file."""
from pathlib import Path
import json
import struct
import sys
import zlib


def verify(result, wad):
    assert result[:8] == b'Z98READ1'
    size, read_seconds, crc_seconds, crc, count, chunk = struct.unpack_from('<6I', result, 8)
    assert chunk == 32768 and size == len(wad) and 12 <= size <= 32*1024*1024
    assert count == (size+chunk-1)//chunk and len(result) == 64+count*4
    assert result[32:64] == bytes(32) and max(read_seconds, crc_seconds) < 120
    running = 0
    for i in range(count):
        running = zlib.crc32(wad[i*chunk:(i+1)*chunk], running)
        assert struct.unpack_from('<I', result, 64+i*4)[0] == running, 'CRC mismatch at chunk %d' % i
    assert crc == running
    return dict(passed=True, full_payload_crc32='%08x' % crc, bytes=size,
                checkpoints=count, sequential_read_rtc_seconds=read_seconds,
                read_plus_crc_rtc_seconds=crc_seconds,
                limitations=['CRC32 is an error-detection checksum, not cryptographic identity.',
                             'Whole RTC seconds; zero is below resolution.',
                             'Two ordered passes can have different cache state.',
                             'Real DOS reads do not prove protected-mode Doom runtime state.'])


if __name__ == '__main__':
    print(json.dumps(verify(Path(sys.argv[1]).read_bytes(), Path(sys.argv[2]).read_bytes()), indent=2))
