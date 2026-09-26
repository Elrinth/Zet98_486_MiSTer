"""Check paired READ/VERIFY records against the preserved raw disk tail."""
import struct
import zlib


def verify(result, tail):
    assert len(result) == 128 and result[:8] == b'Z98BIO1\0'
    assert struct.unpack_from('<4I', result, 8) == (136, 8388608, 32768, 4)
    assert result[24:32] == bytes(8) and result[96:] == bytes(32)
    assert len(tail) == 32768
    values = []
    for i, command in enumerate((6, 1, 1, 6)):
        actual, seconds, crc, canary = struct.unpack_from('<4I', result, 32+i*16)
        expected = zlib.crc32(tail if command == 6 else b'\x5a\xa5' * 16384)
        assert actual == command and seconds < 60 and canary == 1 and crc == expected
        values.append(dict(command='READ' if command == 6 else 'VERIFY',
                           rtc_seconds=seconds, final_buffer_crc32='%08x' % crc))
    return dict(passed=True, bytes_per_pass=8388608, records=values,
                limitations=['Whole RTC seconds, endpoint quantization applies.',
                             'Ordering balances but does not eliminate host cache effects.',
                             'VERIFY still performs ATA reads into the BIOS bounce buffer.',
                             'Only the last READ buffer is checksummed outside timing.',
                             'Not a Doom startup or protected-runtime correctness measurement.'])
