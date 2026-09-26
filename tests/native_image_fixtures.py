"""Synthetic images and independent D88 oracle. No private assets."""
import pathlib,struct,sys
out=pathlib.Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
def fixture(name,source,oracle,reject=False,direct=False):
 (out/(name+'.image')).write_bytes(source);(out/(name+'.expected')).write_bytes(oracle)
 with (out/'cases.txt').open('a') as f:f.write(f'{name} {int(reject)} {int(direct)}\n')
def floppy(c,s,b):
 raw=bytes((i*37+(i>>9)*13)&255 for i in range(c*2*s*b));d=bytearray(688);d[26]=16;d[27]=32 if len(raw)>=1000000 else (0 if c<=42 else 16)
 for t in range(c*2):
  struct.pack_into('<I',d,32+4*t,len(d))
  for r in range(s):
   h=bytearray(16);h[:4]=bytes((t//2,t%2,r+1,b.bit_length()-8));struct.pack_into('<H',h,4,s);struct.pack_into('<H',h,14,b)
   start=(t*s+r)*b;d.extend(h+raw[start:start+b])
 struct.pack_into('<I',d,28,len(d));return raw,bytes(d)
for c,s,b in [(77,8,1024),(80,15,512),(80,18,512),(80,8,512),(80,9,512),(40,8,512)]:
 raw,d88=floppy(c,s,b);fixture(f'hdm-{c}-{s}',raw,d88)
 if c==77:
  fixture('d88',d88,d88,direct=True)
  for offset in (37,4096):fixture(f'fdi-{offset}',struct.pack('<8I',0,0x90,offset,len(raw),b,s,2,c)+bytes(offset-32)+raw,d88)
  nfd=bytearray(68112);nfd[:15]=b'T98FDDIMAGE.R0\0';struct.pack_into('<I',nfd,272,68112);nfd[277]=2
  for t in range(163):
   for r in range(26):
    p=288+(t*26+r)*16
    nfd[p:p+11]=bytes((t//2,t%2,r+1,3,1,0,0,(t%2)*4,0,0,0x90)) if t<154 and r<8 else bytes([255])*11
  fixture('nfd',nfd+raw,d88);nfd[296]=32;fixture('nfd-crc',nfd+raw,d88,reject=True)
  nfd[12]=ord('1');fixture('nfd-r1',nfd+raw,d88,reject=True)
  bad=bytearray(struct.pack('<8I',0,0x90,4096,len(raw),b,s,2,c)+bytes(4064)+raw);bad[12]^=1;fixture('fdi-length',bad,d88,reject=True)
raw=bytes((i*19+(i>>9))&255 for i in range(512*17*4*7))
fixture('hdi',struct.pack('<8I',0,5,4096,len(raw),512,17,4,7)+bytes(4064)+raw,raw)
fixture('hdi-256',struct.pack('<8I',0,5,4096,len(raw),256,34,4,7)+bytes(4064)+raw,raw,reject=True)
fixture('raw',raw,raw,direct=True)
