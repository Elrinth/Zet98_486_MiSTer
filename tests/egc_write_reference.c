// SPDX-License-Identifier: GPL-3.0-or-later
// Pinned NP2 word-write functions supply results, including P loaded from D.
#define __USE_MINGW_ANSI_STDIO 1
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint8_t UINT8;
typedef uint16_t UINT16;
typedef uint32_t UINT32;
typedef uint64_t UINT64;
typedef unsigned int UINT, REG8, REG16;
#define MEMCALL
#define LOW12(v) ((v) & 0xfff)
#define EGCADDR_L 0
#define EGCADDR_H 1
#define EGCADDR(a) (a)
#define VRAM_B 0
#define VRAM_R 2
#define VRAM_G 4
#define VRAM_E 6
#include "reference/np2-egc-types.inc"
static _EGC egc;
static EGCQUAD egc_src, egc_data;
static union { uint64_t align; uint8_t b[8]; } memory;
#define mem memory.b
#include "reference/np2-egc-shift.inc"
#include "reference/np2-egc-write.inc"

static uint32_t rng = 0x98e6c01;
static uint32_t next(void) {
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng;
}
static uint64_t quad(void) { uint64_t hi=next(); return (hi << 32) | next(); }
static uint64_t expand(unsigned color) {
    uint64_t value=0;
    for (unsigned p=0; p<4; ++p) if (color & (1u << p)) value |= (uint64_t)0xffff << (16*p);
    return value;
}

static void record(FILE *out, unsigned serial, unsigned op, unsigned mode,
                   unsigned load, unsigned color, unsigned cpu_source,
                   unsigned planes, unsigned bytes, unsigned length, unsigned shift) {
    uint64_t original_source=quad(), pattern=quad(), destination=quad();
    uint16_t cpu=next(), mask=next();
    // Include the common unmasked case as well as arbitrary protected pixels.
    if ((serial & 3) == 0) mask=0xffff;
    memset(&egc, 0, sizeof(egc));
    egc.ope=(mode << 11) | (load << 8) | (cpu_source << 10) | op;
    egc.fgbg=color << 13;
    egc.fg=next() & 15; egc.bg=next() & 15;
    egc.fgc.q=expand(egc.fg); egc.bgc.q=expand(egc.bg);
    egc.sft=shift; egc.leng=length-1; egc.mask.w=mask;
    egcshift(); egc.srcmask.w=0xffff;
    egc_src.q=original_source;
    // This is the pre-write load done by egc_writeword, before egc_opew.
    egc.patreg.q=load == 2 ? destination : pattern;
    memory.align=destination;
    const EGCQUAD *data=egc_opew(0,cpu);
    uint64_t expected=destination;
    uint16_t enabled=egc.mask2.w & ((bytes & 1 ? 0xff : 0) | (bytes & 2 ? 0xff00 : 0));
    for (unsigned p=0;p<4;++p) if (planes & (1u << p)) {
        uint64_t active=(uint64_t)enabled << (16*p);
        expected=(expected & ~active) | (data->q & active);
    }
    fprintf(out,"%04x %04x %04x %016llx %016llx %016llx %016llx %04x %04x %x %x %016llx %016llx\n",
        egc.ope,egc.fgbg,cpu,(unsigned long long)egc_src.q,(unsigned long long)pattern,
        (unsigned long long)egc.fgc.q,(unsigned long long)egc.bgc.q,
        mask,egc.srcmask.w,planes,bytes,(unsigned long long)destination,(unsigned long long)expected);
}

int main(int argc,char **argv) {
    if (argc != 2) return 2;
    uint16_t endian=1;
    if (*(uint8_t *)&endian != 1) return 3;
    FILE *out=fopen(argv[1],"w"); if (!out) return 4;
    unsigned serial=0;
    (void)egc_opeb;
    for (unsigned op=0;op<256;++op)
    for (unsigned mode=0;mode<3;++mode)
    for (unsigned load=0;load<3;++load)
    for (unsigned color=0;color<3;++color)
    for (unsigned cpu=0;cpu<2;++cpu)
        record(out,serial++,op,mode,load,color,cpu,15,3,16,0);
    // All plane/byte masks with each source and pattern mode; asymmetric
    // shifted/clipped source data comes from the same unmodified NP2 code.
    for (unsigned masks=0;masks<64;++masks)
    for (unsigned mode=0;mode<3;++mode)
    for (unsigned load=0;load<3;++load)
    for (unsigned color=0;color<3;++color)
    for (unsigned cpu=0;cpu<2;++cpu) {
        unsigned op=next() & 255, shift=next() & 0x10ff, length=1+(next() & 31);
        record(out,serial++,op,mode,load,color,cpu,masks & 15,masks >> 4,length,shift);
    }
    if (fclose(out)) return 5;
    printf("Generated %u pinned NP2 EGC write cases\n",serial);
    return 0;
}
