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
    (void)shiftinput_byte; // Retained verbatim in the upstream source excerpt.
    while (fscanf(input, "%x %x %x %16s", &reload, &shift, &length, input_word) == 4) {
        data = strtoull(input_word, &word_end, 16);
        if (*word_end) return 7;
        if (reload) {
            memset(&egc, 0, sizeof(egc));
            memset(&egc_src, 0, sizeof(egc_src));
            egc.sft = shift;
            egc.leng = length;
            egcshift();
            // No output is consumed for a reload record.
            egc.srcmask.w = 0;
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
        for (unsigned p=0; p<4; ++p)
            words |= (uint64_t)(egc_src.w[p] & egc.srcmask.w) << (16*p);
        fprintf(output, "%x %04x %03x %016llx %04x %016llx\n",
                reload, shift, length, data, egc.srcmask.w, words);
    }
    if (!feof(input)) return 5;
    if (fclose(output) || fclose(input)) return 6;
    return 0;
}
