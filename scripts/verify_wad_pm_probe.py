"""Independent full-payload checkpoint verification; never runs guest code."""
import json, struct, sys, zlib
from pathlib import Path

def verify(result, wad):
    assert result[:8]==b'Z98PMRD1'
    status,size,loaded,physical,checked,count=struct.unpack_from('<6I',result,8)
    assert status==0 and size==len(wad) and 12<=size<=32*1024*1024
    assert loaded==checked==size and physical>=0x100000 and physical+size<=0x100000000
    assert count==(size+32767)//32768 and len(result)==64+4*count
    assert result[32:64]==bytes(32)
    crc=0
    for i in range(count):
        crc=zlib.crc32(wad[i*32768:(i+1)*32768],crc)
        assert struct.unpack_from('<I',result,64+4*i)[0]==crc, 'Protected CRC mismatch at chunk %d'%i
    return dict(passed=True,bytes=size,checkpoints=count,physical_base=physical,full_payload_crc32='%08x'%crc,
                limitations=['Self-authored DOS/XMS/32-bit protected reader, not actual Doom runtime.',
                             'CRC32 detects errors; it is not a cryptographic identity proof.',
                             'No startup timing measured.'])

def selftest():
    wad=bytes((i*11+(i>>9))&255 for i in range(65539));crc=0;checks=[]
    for i in range(0,len(wad),32768):crc=zlib.crc32(wad[i:i+32768],crc);checks.append(crc)
    result=b'Z98PMRD1'+struct.pack('<6I',0,len(wad),len(wad),0x110000,len(wad),3)+bytes(32)+struct.pack('<3I',*checks)
    verify(result,wad)
    bad=[]
    for offset in (0,8,12,16,24,28,32,64,68,72):
        r=bytearray(result);r[offset]^=1;bad.append(bytes(r))
    bad.extend((result[:-1],result+b'!',result[:20]+bytes(4)+result[24:]))
    for r in bad:
        try:verify(r,wad)
        except (AssertionError,struct.error):continue
        raise AssertionError('Accepted invalid PM result')
    return dict(passed=True,negative_cases=len(bad))

if __name__=='__main__':
    if sys.argv[1:] == ['--selftest']:print(json.dumps(selftest()))
    else:print(json.dumps(verify(Path(sys.argv[1]).read_bytes(),Path(sys.argv[2]).read_bytes()),indent=2))
