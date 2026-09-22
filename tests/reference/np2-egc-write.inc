/* NP2kai 5939e0c6d5985c4c08fc70f289a83290e5d3e6f7; see np2-LICENSE.txt and np2kai-LICENSE.txt.
 * Unmodified extraction; full source identity is in README.md. */

#define	EGCOPE_SHIFTB											\
	do {														\
		if (egc.ope & 0x400) {									\
			egc.inptr[ 0] = (UINT8)value;						\
			egc.inptr[ 4] = (UINT8)value;						\
			egc.inptr[ 8] = (UINT8)value;						\
			egc.inptr[12] = (UINT8)value;						\
			shiftinput_byte(EGCADDR(ad & 1));					\
		}														\
	} while(0)

#define	EGCOPE_SHIFTW											\
	do {														\
		if (egc.ope & 0x400) {									\
			if (!(egc.sft & 0x1000)) {							\
				egc.inptr[ 0] = (UINT8)value;					\
				egc.inptr[ 1] = (UINT8)(value >> 8);			\
				egc.inptr[ 4] = (UINT8)value;					\
				egc.inptr[ 5] = (UINT8)(value >> 8);			\
				egc.inptr[ 8] = (UINT8)value;					\
				egc.inptr[ 9] = (UINT8)(value >> 8);			\
				egc.inptr[12] = (UINT8)value;					\
				egc.inptr[13] = (UINT8)(value >> 8);			\
				shiftinput_incw();								\
			}													\
			else {												\
				egc.inptr[-1] = (UINT8)value;					\
				egc.inptr[ 0] = (UINT8)(value >> 8);			\
				egc.inptr[ 3] = (UINT8)value;					\
				egc.inptr[ 4] = (UINT8)(value >> 8);			\
				egc.inptr[ 7] = (UINT8)value;					\
				egc.inptr[ 8] = (UINT8)(value >> 8);			\
				egc.inptr[11] = (UINT8)value;					\
				egc.inptr[12] = (UINT8)(value >> 8);			\
				shiftinput_decw();								\
			}													\
		}														\
	} while(0)

#define	EGCOPE_SHIFTW2											\
	do {														\
			if (!(egc.sft & 0x1000)) {							\
				egc.inptr[ 0] = (UINT8)value;					\
				egc.inptr[ 1] = (UINT8)(value >> 8);			\
				egc.inptr[ 4] = (UINT8)value;					\
				egc.inptr[ 5] = (UINT8)(value >> 8);			\
				egc.inptr[ 8] = (UINT8)value;					\
				egc.inptr[ 9] = (UINT8)(value >> 8);			\
				egc.inptr[12] = (UINT8)value;					\
				egc.inptr[13] = (UINT8)(value >> 8);			\
				shiftinput_incw();								\
			}													\
			else {												\
				egc.inptr[-1] = (UINT8)value;					\
				egc.inptr[ 0] = (UINT8)(value >> 8);			\
				egc.inptr[ 3] = (UINT8)value;					\
				egc.inptr[ 4] = (UINT8)(value >> 8);			\
				egc.inptr[ 7] = (UINT8)value;					\
				egc.inptr[ 8] = (UINT8)(value >> 8);			\
				egc.inptr[11] = (UINT8)value;					\
				egc.inptr[12] = (UINT8)(value >> 8);			\
				shiftinput_decw();								\
			}													\
	} while(0)

// ----

static const UINT8 data_00[8] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00};
static const UINT8 data_ff[8] = {0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff};

static const EGCQUAD * MEMCALL ope_00(REG8 ope, UINT32 ad) {

	(void)ope;
	(void)ad;
	return((EGCQUAD *)data_00);
}

static const EGCQUAD * MEMCALL ope_0f(REG8 ope, UINT32 ad) {

	egc_data.d[0] = ~egc_src.d[0];
	egc_data.d[1] = ~egc_src.d[1];

	(void)ope;
	(void)ad;
	return(&egc_data);
}

static const EGCQUAD * MEMCALL ope_c0(REG8 ope, UINT32 ad) {

	EGCQUAD	dst;

	dst.w[0] = *(UINT16 *)(&mem[ad + VRAM_B]);
	dst.w[1] = *(UINT16 *)(&mem[ad + VRAM_R]);
	dst.w[2] = *(UINT16 *)(&mem[ad + VRAM_G]);
	dst.w[3] = *(UINT16 *)(&mem[ad + VRAM_E]);
	egc_data.d[0] = (egc_src.d[0] & dst.d[0]);
	egc_data.d[1] = (egc_src.d[1] & dst.d[1]);

	(void)ope;
	(void)ad;
	return(&egc_data);
}

static const EGCQUAD * MEMCALL ope_f0(REG8 ope, UINT32 ad) {

	(void)ope;
	(void)ad;
	return(&egc_src);
}

static const EGCQUAD * MEMCALL ope_fc(REG8 ope, UINT32 ad) {

	EGCQUAD	dst;

	dst.w[0] = *(UINT16 *)(&mem[ad + VRAM_B]);
	dst.w[1] = *(UINT16 *)(&mem[ad + VRAM_R]);
	dst.w[2] = *(UINT16 *)(&mem[ad + VRAM_G]);
	dst.w[3] = *(UINT16 *)(&mem[ad + VRAM_E]);
	egc_data.d[0] = egc_src.d[0];
	egc_data.d[0] |= ((~egc_src.d[0]) & dst.d[0]);
	egc_data.d[1] = egc_src.d[1];
	egc_data.d[1] |= ((~egc_src.d[1]) & dst.d[1]);

	(void)ope;
	(void)ad;
	return(&egc_data);
}

static const EGCQUAD * MEMCALL ope_ff(REG8 ope, UINT32 ad) {

	(void)ope;
	(void)ad;
	return((EGCQUAD *)data_ff);
}

static const EGCQUAD * MEMCALL ope_nd(REG8 ope, UINT32 ad) {

	EGCQUAD	pat;

	switch(egc.fgbg & 0x6000) {
		case 0x2000:
			pat.d[0] = egc.bgc.d[0];
			pat.d[1] = egc.bgc.d[1];
			break;

		case 0x4000:
			pat.d[0] = egc.fgc.d[0];
			pat.d[1] = egc.fgc.d[1];
			break;

		case 0x6000:
			pat.d[0] = egc.fgc.d[0];
			pat.d[1] = egc.bgc.d[1];
			break;


		default:
			if ((egc.ope & 0x0300) == 0x0100) {
				pat.d[0] = egc_src.d[0];
				pat.d[1] = egc_src.d[1];
			}
			else {
				pat.d[0] = egc.patreg.d[0];
				pat.d[1] = egc.patreg.d[1];
			}
			break;
	}

	egc_data.d[0] = 0;
	egc_data.d[1] = 0;
	if (ope & 0x80) {
		egc_data.d[0] |= (pat.d[0] & egc_src.d[0]);
		egc_data.d[1] |= (pat.d[1] & egc_src.d[1]);
	}
	if (ope & 0x40) {
		egc_data.d[0] |= ((~pat.d[0]) & egc_src.d[0]);
		egc_data.d[1] |= ((~pat.d[1]) & egc_src.d[1]);
	}
	if (ope & 0x08) {
		egc_data.d[0] |= (pat.d[0] & (~egc_src.d[0]));
		egc_data.d[1] |= (pat.d[1] & (~egc_src.d[1]));
	}
	if (ope & 0x04) {
		egc_data.d[0] |= ((~pat.d[0]) & (~egc_src.d[0]));
		egc_data.d[1] |= ((~pat.d[1]) & (~egc_src.d[1]));
	}
	(void)ad;
	return(&egc_data);
}

static const EGCQUAD * MEMCALL ope_np(REG8 ope, UINT32 ad) {

	EGCQUAD	dst;

	dst.w[0] = *(UINT16 *)(&mem[ad + VRAM_B]);
	dst.w[1] = *(UINT16 *)(&mem[ad + VRAM_R]);
	dst.w[2] = *(UINT16 *)(&mem[ad + VRAM_G]);
	dst.w[3] = *(UINT16 *)(&mem[ad + VRAM_E]);

	egc_data.d[0] = 0;
	egc_data.d[1] = 0;
	if (ope & 0x80) {
		egc_data.d[0] |= (egc_src.d[0] & dst.d[0]);
		egc_data.d[1] |= (egc_src.d[1] & dst.d[1]);
	}
	if (ope & 0x20) {
		egc_data.d[0] |= (egc_src.d[0] & (~dst.d[0]));
		egc_data.d[1] |= (egc_src.d[1] & (~dst.d[1]));
	}
	if (ope & 0x08) {
		egc_data.d[0] |= ((~egc_src.d[0]) & dst.d[0]);
		egc_data.d[1] |= ((~egc_src.d[1]) & dst.d[1]);
	}
	if (ope & 0x02) {
		egc_data.d[0] |= ((~egc_src.d[0]) & (~dst.d[0]));
		egc_data.d[1] |= ((~egc_src.d[1]) & (~dst.d[1]));
	}
	return(&egc_data);
}

static const EGCQUAD * MEMCALL ope_xx(REG8 ope, UINT32 ad) {

	EGCQUAD	pat;
	EGCQUAD	dst;

	switch(egc.fgbg & 0x6000) {
		case 0x2000:
			pat.d[0] = egc.bgc.d[0];
			pat.d[1] = egc.bgc.d[1];
			break;

		case 0x4000:
			pat.d[0] = egc.fgc.d[0];
			pat.d[1] = egc.fgc.d[1];
			break;

		case 0x6000:
			pat.d[0] = egc.fgc.d[0];
			pat.d[1] = egc.bgc.d[1];
			break;

		default:
			if ((egc.ope & 0x0300) == 0x0100) {
				pat.d[0] = egc_src.d[0];
				pat.d[1] = egc_src.d[1];
			}
			else {
				pat.d[0] = egc.patreg.d[0];
				pat.d[1] = egc.patreg.d[1];
			}
			break;
	}
	dst.w[0] = *(UINT16 *)(&mem[ad + VRAM_B]);
	dst.w[1] = *(UINT16 *)(&mem[ad + VRAM_R]);
	dst.w[2] = *(UINT16 *)(&mem[ad + VRAM_G]);
	dst.w[3] = *(UINT16 *)(&mem[ad + VRAM_E]);

	egc_data.d[0] = 0;
	egc_data.d[1] = 0;
	if (ope & 0x80) {
		egc_data.d[0] |= (pat.d[0] & egc_src.d[0] & dst.d[0]);
		egc_data.d[1] |= (pat.d[1] & egc_src.d[1] & dst.d[1]);
	}
	if (ope & 0x40) {
		egc_data.d[0] |= ((~pat.d[0]) & egc_src.d[0] & dst.d[0]);
		egc_data.d[1] |= ((~pat.d[1]) & egc_src.d[1] & dst.d[1]);
	}
	if (ope & 0x20) {
		egc_data.d[0] |= (pat.d[0] & egc_src.d[0] & (~dst.d[0]));
		egc_data.d[1] |= (pat.d[1] & egc_src.d[1] & (~dst.d[1]));
	}
	if (ope & 0x10) {
		egc_data.d[0] |= ((~pat.d[0]) & egc_src.d[0] & (~dst.d[0]));
		egc_data.d[1] |= ((~pat.d[1]) & egc_src.d[1] & (~dst.d[1]));
	}
	if (ope & 0x08) {
		egc_data.d[0] |= (pat.d[0] & (~egc_src.d[0]) & dst.d[0]);
		egc_data.d[1] |= (pat.d[1] & (~egc_src.d[1]) & dst.d[1]);
	}
	if (ope & 0x04) {
		egc_data.d[0] |= ((~pat.d[0]) & (~egc_src.d[0]) & dst.d[0]);
		egc_data.d[1] |= ((~pat.d[1]) & (~egc_src.d[1]) & dst.d[1]);
	}
	if (ope & 0x02) {
		egc_data.d[0] |= (pat.d[0] & (~egc_src.d[0]) & (~dst.d[0]));
		egc_data.d[1] |= (pat.d[1] & (~egc_src.d[1]) & (~dst.d[1]));
	}
	if (ope & 0x01) {
		egc_data.d[0] |= ((~pat.d[0]) & (~egc_src.d[0]) & (~dst.d[0]));
		egc_data.d[1] |= ((~pat.d[1]) & (~egc_src.d[1]) & (~dst.d[1]));
	}
	return(&egc_data);
}

typedef const EGCQUAD * (MEMCALL * OPEFN)(REG8 ope, UINT32 ad);

static const OPEFN opefn[256] = {
			ope_00, ope_xx, ope_xx, ope_np,
			ope_xx, ope_nd, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_nd, ope_xx,
			ope_np, ope_xx, ope_xx, ope_0f,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			 ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			 ope_xx, ope_xx, ope_xx, ope_xx,
			ope_np, ope_xx, ope_xx, ope_np,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_np, ope_xx, ope_xx, ope_np,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_nd, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_nd, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_nd, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_nd,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_nd, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_nd, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_nd, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_nd,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_c0, ope_xx, ope_xx, ope_np,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_np, ope_xx, ope_xx, ope_np,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_xx, ope_xx,
			ope_f0, ope_xx, ope_xx, ope_np,
			ope_xx, ope_nd, ope_xx, ope_xx,
			ope_xx, ope_xx, ope_nd, ope_xx,
			ope_fc, ope_xx, ope_xx, ope_ff};


// ----

static const EGCQUAD * MEMCALL egc_opeb(UINT32 ad, REG8 value) {

	UINT	tmp;

	egc.mask2.w = egc.mask.w;
	switch(egc.ope & 0x1800) {
		case 0x0800:
			EGCOPE_SHIFTB;
			egc.mask2.w &= egc.srcmask.w;
			tmp = egc.ope & 0xff;
			return((*opefn[tmp])((REG8)tmp, ad & (~1)));

		case 0x1000:
			switch(egc.fgbg & 0x6000) {
				case 0x2000:
					return(&egc.bgc);

				case 0x4000:
					return(&egc.fgc);

				default:
					EGCOPE_SHIFTB;
					egc.mask2.w &= egc.srcmask.w;
					return(&egc_src);
			}
			break;

		default:
			tmp = value & 0xff;
			tmp = tmp | (tmp << 8);
			egc_data.w[0] = (UINT16)tmp;
			egc_data.w[1] = (UINT16)tmp;
			egc_data.w[2] = (UINT16)tmp;
			egc_data.w[3] = (UINT16)tmp;
			return(&egc_data);
	}
}

static const EGCQUAD * MEMCALL egc_opew(UINT32 ad, REG16 value) {

	UINT	tmp;

	egc.mask2.w = egc.mask.w;
	switch(egc.ope & 0x1800) {
		case 0x0800:
			EGCOPE_SHIFTW;
			egc.mask2.w &= egc.srcmask.w;
			tmp = egc.ope & 0xff;
			return((*opefn[tmp])((REG8)tmp, ad));

		case 0x1000:
	     EGCOPE_SHIFTW2;
            egc.mask2.w &= egc.srcmask.w;
			switch(egc.fgbg & 0x6000) {
				case 0x2000:
					return(&egc.bgc);
				case 0x4000:
					return(&egc.fgc);
				default:
					return(&egc.patreg);
			}
			break;

		default:
#if defined(BYTESEX_BIG)
			value = ((value >> 8) & 0xff) | ((value & 0xff) << 8);
#endif
			egc_data.w[0] = (UINT16)value;
			egc_data.w[1] = (UINT16)value;
			egc_data.w[2] = (UINT16)value;
			egc_data.w[3] = (UINT16)value;
			EGCOPE_SHIFTW2;
			egc.mask2.w &= egc.srcmask.w;
			return(&egc_data);
	}
}


// ----
