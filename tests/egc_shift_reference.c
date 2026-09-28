// SPDX-License-Identifier: GPL-3.0-or-later
// Drive the unmodified NP2kai shift routines; this is not an RTL translation.
#define __USE_MINGW_ANSI_STDIO 1
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef uint8_t UINT8;
typedef uint16_t UINT16;
typedef uint32_t UINT32;
typedef uint64_t UINT64;
typedef unsigned int UINT;
#define MEMCALL
#define LOW12(v) ((v) & 0xfff)
#define EGCADDR_L 0
#define EGCADDR_H 1
#include "reference/np2-egc-types.inc"
static _EGC egc;
static EGCQUAD egc_src;
#include "reference/np2-egc-shift.inc"

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    FILE *input = fopen(argv[1], "r"), *output = fopen(argv[2], "w");
    if (!input || !output) return 3;
    uint16_t endian = 1;
    if (*(uint8_t *)&endian != 1) return 4;
    unsigned reload, shift, length;
    unsigned long long data;
    char input_word[17], *word_end;
    while (fscanf(input, "%x %x %x %16s", &reload, &shift, &length, input_word) == 4) {
        data = strtoull(input_word, &word_end, 16);
        if (*word_end) return 7;
        if (reload == 1) {
            memset(&egc, 0, sizeof(egc));
            memset(&egc_src, 0, sizeof(egc_src));
            egc.sft = shift;
            egc.leng = length;
            egcshift();
            // No output is consumed for a reload record.
            egc.srcmask.w = 0;
        } else if (reload >= 2) {
            // Byte access to lane reload-2 (EGCOPE_SHIFTB / egc_readbyte).
            unsigned lane = reload - 2;
            egc.srcmask.w = 0;
            for (int p=0; p<4; ++p)
                egc.inptr[4*p] = (uint8_t)(data >> (16*p + 8*lane));
            shiftinput_byte(lane);
        } else {
            for (int p=0; p<4; ++p) {
                uint16_t word = (uint16_t)(data >> (16*p));
                if (!(egc.sft & 0x1000)) {
                    egc.inptr[4*p] = word;
                    egc.inptr[4*p+1] = word >> 8;
                } else {
                    egc.inptr[4*p-1] = word;
                    egc.inptr[4*p] = word >> 8;
                }
            }
            if (!(egc.sft & 0x1000)) shiftinput_incw();
            else shiftinput_decw();
        }
        unsigned long long words = 0;
        uint16_t mask = egc.srcmask.w;
        if (reload >= 2) {
            // Only the addressed lane is produced; report it in both lanes.
            uint8_t m = egc.srcmask._b[reload - 2];
            mask = m | (m << 8);
            egc.srcmask.w = 0;
        }
        for (unsigned p=0; p<4; ++p) {
            uint16_t w = egc_src.w[p];
            if (reload >= 2) { uint8_t b = egc_src._b[p][reload - 2]; w = b | (b << 8); }
            words |= (uint64_t)(w & mask) << (16*p);
        }
        fprintf(output, "%x %04x %03x %016llx %04x %016llx\n",
                reload, shift, length, data, mask, words);
    }
    if (!feof(input)) return 5;
    if (fclose(output) || fclose(input)) return 6;
    return 0;
}
