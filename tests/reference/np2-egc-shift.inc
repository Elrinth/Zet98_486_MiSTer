/* NP2kai 5939e0c6d5985c4c08fc70f289a83290e5d3e6f7; see np2-LICENSE.txt and np2kai-LICENSE.txt.
 * Unmodified extraction; full source identity is in README.md. */
static const UINT8 bytemask_u0[64] =	// dir:right by startbit + (len-1)*8
					{0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01,
					 0xc0, 0x60, 0x30, 0x18, 0x0c, 0x06, 0x03, 0x01,
					 0xe0, 0x70, 0x38, 0x1c, 0x0e, 0x07, 0x03, 0x01,
					 0xf0, 0x78, 0x3c, 0x1e, 0x0f, 0x07, 0x03, 0x01,
					 0xf8, 0x7c, 0x3e, 0x1f, 0x0f, 0x07, 0x03, 0x01,
					 0xfc, 0x7e, 0x3f, 0x1f, 0x0f, 0x07, 0x03, 0x01,
					 0xfe, 0x7f, 0x3f, 0x1f, 0x0f, 0x07, 0x03, 0x01,
					 0xff, 0x7f, 0x3f, 0x1f, 0x0f, 0x07, 0x03, 0x01};

static const UINT8 bytemask_u1[8] =		// dir:right by length
					{0x80, 0xc0, 0xe0, 0xf0, 0xf8, 0xfc, 0xfe, 0xff};

static const UINT8 bytemask_d0[64] =	// dir:left by startbit + (len-1)*8
					{0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,
					 0x03, 0x06, 0x0c, 0x18, 0x30, 0x60, 0xc0, 0x80,
					 0x07, 0x0e, 0x1c, 0x38, 0x70, 0xe0, 0xc0, 0x80,
					 0x0f, 0x1e, 0x3c, 0x78, 0xf0, 0xe0, 0xc0, 0x80,
					 0x1f, 0x3e, 0x7c, 0xf8, 0xf0, 0xe0, 0xc0, 0x80,
					 0x3f, 0x7e, 0xfc, 0xf8, 0xf0, 0xe0, 0xc0, 0x80,
					 0x7f, 0xfe, 0xfc, 0xf8, 0xf0, 0xe0, 0xc0, 0x80,
					 0xff, 0xfe, 0xfc, 0xf8, 0xf0, 0xe0, 0xc0, 0x80};

static const UINT8 bytemask_d1[8] =		// dir:left by length
					{0x01, 0x03, 0x07, 0x0f, 0x1f, 0x3f, 0x7f, 0xff};


void egcshift(void) {

	UINT8	src8, dst8;

	egc.remain = LOW12(egc.leng) + 1;
	egc.func = (egc.sft >> 12) & 1;
	if (!egc.func) {
		egc.inptr = egc.buf;
		egc.outptr = egc.buf;
	}
	else {
		egc.inptr = egc.buf + 4096/8 + 3;
		egc.outptr = egc.buf + 4096/8 + 3;
	}
	egc.srcbit = egc.sft & 0x0f;
	egc.dstbit = (egc.sft >> 4) & 0x0f;

	src8 = egc.srcbit & 0x07;
	dst8 = egc.dstbit & 0x07;
	if (src8 < dst8) {

// dir:inc
// ****---4 -------8 --------
// ******-- -4------ --8----- --
// 1st -> data[0] >> (dst - src)
// 2nd -> (data[0] << (8 - (dst - src))) | (data[1] >> (dst - src))

// dir:dec
//          -------- 8------- 6-----**
//      --- -----8-- -----6-- ---*****
// 1st -> data[0] << (dst - src)
// 2nd -> (data[0] >> (8 - (dst - src))) | (data[1] << (dst - src))

		egc.func += 2;
		egc.sft8bitr = dst8 - src8;
		egc.sft8bitl = 8 - egc.sft8bitr;
	}
	else if (src8 > dst8) {

// dir:inc
// ****---4 -------8 --------
// **---4-- -----8-- ------
// 1st -> (data[0] << (src - dst)) | (data[1] >> (8 - (src - dst))
// 2nd -> (data[0] << (src - dst)) | (data[1] >> (8 - (src - dst))

// dir:dec
//          -------- 8------- 3--*****
//             ----- ---8---- ---3--**
// 1st -> (data[0] >> (dst - src)) | (data[-1] << (8 - (src - dst))
// 2nd -> (data[0] >> (dst - src)) | (data[-1] << (8 - (src - dst))

		egc.func += 4;
		egc.sft8bitl = src8 - dst8;
		egc.sft8bitr = 8 - egc.sft8bitl;
	}
	egc.stack = 0;
}


static void MEMCALL egcsftb_upn_sub(UINT ext) {

	if (egc.dstbit >= 8) {
		egc.dstbit -= 8;
		egc.srcmask._b[ext] = 0;
		return;
	}
	if (egc.dstbit) {
		if ((egc.dstbit + egc.remain) >= 8) {
			egc.srcmask._b[ext] = bytemask_u0[egc.dstbit + (7*8)];
			egc.remain -= (8 - egc.dstbit);
			egc.dstbit = 0;
		}
		else {
			egc.srcmask._b[ext] = bytemask_u0[egc.dstbit +
														(egc.remain - 1) * 8];
			egc.remain = 0;
			egc.dstbit = 0;
		}
	}
	else {
		if (egc.remain >= 8) {
			egc.remain -= 8;
		}
		else {
			egc.srcmask._b[ext] = bytemask_u1[egc.remain - 1];
			egc.remain = 0;
		}
	}
	egc_src._b[0][ext] = egc.outptr[0];
	egc_src._b[1][ext] = egc.outptr[4];
	egc_src._b[2][ext] = egc.outptr[8];
	egc_src._b[3][ext] = egc.outptr[12];
	egc.outptr++;
}

static void MEMCALL egcsftb_dnn_sub(UINT ext) {

	if (egc.dstbit >= 8) {
		egc.dstbit -= 8;
		egc.srcmask._b[ext] = 0;
		return;
	}
	if (egc.dstbit) {
		if ((egc.dstbit + egc.remain) >= 8) {
			egc.srcmask._b[ext] = bytemask_d0[egc.dstbit + (7*8)];
			egc.remain -= (8 - egc.dstbit);
			egc.dstbit = 0;
		}
		else {
			egc.srcmask._b[ext] = bytemask_d0[egc.dstbit +
														(egc.remain - 1) * 8];
			egc.remain = 0;
			egc.dstbit = 0;
		}
	}
	else {
		if (egc.remain >= 8) {
			egc.remain -= 8;
		}
		else {
			egc.srcmask._b[ext] = bytemask_d1[egc.remain - 1];
			egc.remain = 0;
		}
	}
	egc_src._b[0][ext] = egc.outptr[0];
	egc_src._b[1][ext] = egc.outptr[4];
	egc_src._b[2][ext] = egc.outptr[8];
	egc_src._b[3][ext] = egc.outptr[12];
	egc.outptr--;
}


// ****---4 -------8 --------
// ******-- -4------ --8----- --
// 1st -> data[0] >> (dst - src)
// 2nd -> (data[0] << (8 - (dst - src))) | (data[1] >> (dst - src))

static void MEMCALL egcsftb_upr_sub(UINT ext) {

	if (egc.dstbit >= 8) {
		egc.dstbit -= 8;
		egc.srcmask._b[ext] = 0;
		return;
	}
	if (egc.dstbit) {
		if ((egc.dstbit + egc.remain) >= 8) {
			egc.srcmask._b[ext] = bytemask_u0[egc.dstbit + (7*8)];
			egc.remain -= (8 - egc.dstbit);
		}
		else {
			egc.srcmask._b[ext] = bytemask_u0[egc.dstbit +
														(egc.remain - 1) * 8];
			egc.remain = 0;
		}
		egc.dstbit = 0;
		egc_src._b[0][ext] = (egc.outptr[0] >> egc.sft8bitr);
		egc_src._b[1][ext] = (egc.outptr[4] >> egc.sft8bitr);
		egc_src._b[2][ext] = (egc.outptr[8] >> egc.sft8bitr);
		egc_src._b[3][ext] = (egc.outptr[12] >> egc.sft8bitr);
	}
	else {
		if (egc.remain >= 8) {
			egc.remain -= 8;
		}
		else {
			egc.srcmask._b[ext] = bytemask_u1[egc.remain - 1];
			egc.remain = 0;
		}
		egc_src._b[0][ext] = (egc.outptr[0] << egc.sft8bitl) |
							(egc.outptr[1] >> egc.sft8bitr);
		egc_src._b[1][ext] = (egc.outptr[4] << egc.sft8bitl) |
							(egc.outptr[5] >> egc.sft8bitr);
		egc_src._b[2][ext] = (egc.outptr[8] << egc.sft8bitl) |
							(egc.outptr[9] >> egc.sft8bitr);
		egc_src._b[3][ext] = (egc.outptr[12] << egc.sft8bitl) |
							(egc.outptr[13] >> egc.sft8bitr);
		egc.outptr++;
	}
}


//          -------- 8------- 6-----**
//      --- -----8-- -----6-- ---*****
// 1st -> data[0] << (dst - src)
// 2nd -> (data[0] >> (8 - (dst - src))) | (data[-1] << (dst - src))

static void MEMCALL egcsftb_dnr_sub(UINT ext) {

	if (egc.dstbit >= 8) {
		egc.dstbit -= 8;
		egc.srcmask._b[ext] = 0;
		return;
	}
	if (egc.dstbit) {
		if ((egc.dstbit + egc.remain) >= 8) {
			egc.srcmask._b[ext] = bytemask_d0[egc.dstbit + (7*8)];
			egc.remain -= (8 - egc.dstbit);
		}
		else {
			egc.srcmask._b[ext] = bytemask_d0[egc.dstbit +
														(egc.remain - 1) * 8];
			egc.remain = 0;
		}
		egc.dstbit = 0;
		egc_src._b[0][ext] = (egc.outptr[0] << egc.sft8bitr);
		egc_src._b[1][ext] = (egc.outptr[4] << egc.sft8bitr);
		egc_src._b[2][ext] = (egc.outptr[8] << egc.sft8bitr);
		egc_src._b[3][ext] = (egc.outptr[12] << egc.sft8bitr);
	}
	else {
		if (egc.remain >= 8) {
			egc.remain -= 8;
		}
		else {
			egc.srcmask._b[ext] = bytemask_d1[egc.remain - 1];
			egc.remain = 0;
		}
		egc.outptr--;
		egc_src._b[0][ext] = (egc.outptr[1] >> egc.sft8bitl) |
							(egc.outptr[0] << egc.sft8bitr);
		egc_src._b[1][ext] = (egc.outptr[5] >> egc.sft8bitl) |
							(egc.outptr[4] << egc.sft8bitr);
		egc_src._b[2][ext] = (egc.outptr[9] >> egc.sft8bitl) |
							(egc.outptr[8] << egc.sft8bitr);
		egc_src._b[3][ext] = (egc.outptr[13] >> egc.sft8bitl) |
							(egc.outptr[12] << egc.sft8bitr);
	}
}


// ****---4 -------8 --------
// **---4-- -----8-- ------
// 1st -> (data[0] << (src - dst)) | (data[1] >> (8 - (src - dst))
// 2nd -> (data[0] << (src - dst)) | (data[1] >> (8 - (src - dst))

static void MEMCALL egcsftb_upl_sub(UINT ext) {

	if (egc.dstbit >= 8) {
		egc.dstbit -= 8;
		egc.srcmask._b[ext] = 0;
		return;
	}
	if (egc.dstbit) {
		if ((egc.dstbit + egc.remain) >= 8) {
			egc.srcmask._b[ext] = bytemask_u0[egc.dstbit + (7*8)];
			egc.remain -= (8 - egc.dstbit);
			egc.dstbit = 0;
		}
		else {
			egc.srcmask._b[ext] = bytemask_u0[egc.dstbit +
														(egc.remain - 1) * 8];
			egc.remain = 0;
			egc.dstbit = 0;
		}
	}
	else {
		if (egc.remain >= 8) {
			egc.remain -= 8;
		}
		else {
			egc.srcmask._b[ext] = bytemask_u1[egc.remain - 1];
			egc.remain = 0;
		}
	}
	egc_src._b[0][ext] = (egc.outptr[0] << egc.sft8bitl) |
						(egc.outptr[1] >> egc.sft8bitr);
	egc_src._b[1][ext] = (egc.outptr[4] << egc.sft8bitl) |
						(egc.outptr[5] >> egc.sft8bitr);
	egc_src._b[2][ext] = (egc.outptr[8] << egc.sft8bitl) |
						(egc.outptr[9] >> egc.sft8bitr);
	egc_src._b[3][ext] = (egc.outptr[12] << egc.sft8bitl) |
						(egc.outptr[13] >> egc.sft8bitr);
	egc.outptr++;
}


//          -------- 8------- 3--*****
//             ----- ---8---- ---3--**
// 1st -> (data[0] >> (dst - src)) | (data[-1] << (8 - (src - dst))
// 2nd -> (data[0] >> (dst - src)) | (data[-1] << (8 - (src - dst))

static void MEMCALL egcsftb_dnl_sub(UINT ext) {

	if (egc.dstbit >= 8) {
		egc.dstbit -= 8;
		egc.srcmask._b[ext] = 0;
		return;
	}
	if (egc.dstbit) {
		if ((egc.dstbit + egc.remain) >= 8) {
			egc.srcmask._b[ext] = bytemask_d0[egc.dstbit + (7*8)];
			egc.remain -= (8 - egc.dstbit);
			egc.dstbit = 0;
		}
		else {
			egc.srcmask._b[ext] = bytemask_d0[egc.dstbit +
														(egc.remain - 1) * 8];
			egc.remain = 0;
			egc.dstbit = 0;
		}
	}
	else {
		if (egc.remain >= 8) {
			egc.remain -= 8;
		}
		else {
			egc.srcmask._b[ext] = bytemask_d1[egc.remain - 1];
			egc.remain = 0;
		}
	}
	egc.outptr--;
	egc_src._b[0][ext] = (egc.outptr[1] >> egc.sft8bitl) |
						(egc.outptr[0] << egc.sft8bitr);
	egc_src._b[1][ext] = (egc.outptr[5] >> egc.sft8bitl) |
						(egc.outptr[4] << egc.sft8bitr);
	egc_src._b[2][ext] = (egc.outptr[9] >> egc.sft8bitl) |
						(egc.outptr[8] << egc.sft8bitr);
	egc_src._b[3][ext] = (egc.outptr[13] >> egc.sft8bitl) |
						(egc.outptr[12] << egc.sft8bitr);
}


static void MEMCALL egcsftb_upn0(UINT ext) {

	if (egc.stack < (UINT)(8 - egc.dstbit)) {
		egc.srcmask._b[ext] = 0;
		return;
	}
	egc.stack -= (8 - egc.dstbit);
	egcsftb_upn_sub(ext);
	if (!egc.remain) {
		egcshift();
	}
}

static void MEMCALL egcsftw_upn0(void) {

	if (egc.stack < (UINT)(16 - egc.dstbit)) {
		egc.srcmask.w = 0;
		return;
	}
	egc.stack -= (16 - egc.dstbit);
	egcsftb_upn_sub(EGCADDR_L);
	if (egc.remain) {
		egcsftb_upn_sub(EGCADDR_H);
		if (egc.remain) {
			return;
		}
	}
	else {
		egc.srcmask._b[EGCADDR_H] = 0;
	}
	egcshift();
}

static void MEMCALL egcsftb_dnn0(UINT ext) {

	if (egc.stack < (UINT)(8 - egc.dstbit)) {
		egc.srcmask._b[ext] = 0;
		return;
	}
	egc.stack -= (8 - egc.dstbit);
	egcsftb_dnn_sub(ext);
	if (!egc.remain) {
		egcshift();
	}
}

static void MEMCALL egcsftw_dnn0(void) {

	if (egc.stack < (UINT)(16 - egc.dstbit)) {
		egc.srcmask.w = 0;
		return;
	}
	egc.stack -= (16 - egc.dstbit);
	egcsftb_dnn_sub(EGCADDR_H);
	if (egc.remain) {
		egcsftb_dnn_sub(EGCADDR_L);
		if (egc.remain) {
			return;
		}
	}
	else {
		egc.srcmask._b[EGCADDR_L] = 0;
	}
	egcshift();
}


static void MEMCALL egcsftb_upr0(UINT ext) {		// dir:up srcbit < dstbit

	if (egc.stack < (UINT)(8 - egc.dstbit)) {
		egc.srcmask._b[ext] = 0;
		return;
	}
	egc.stack -= (8 - egc.dstbit);
	egcsftb_upr_sub(ext);
	if (!egc.remain) {
		egcshift();
	}
}

static void MEMCALL egcsftw_upr0(void) {			// dir:up srcbit < dstbit

	if (egc.stack < (UINT)(16 - egc.dstbit)) {
		egc.srcmask.w = 0;
		return;
	}
	egc.stack -= (16 - egc.dstbit);
	egcsftb_upr_sub(EGCADDR_L);
	if (egc.remain) {
		egcsftb_upr_sub(EGCADDR_H);
		if (egc.remain) {
			return;
		}
	}
	else {
		egc.srcmask._b[EGCADDR_H] = 0;
	}
	egcshift();
}

static void MEMCALL egcsftb_dnr0(UINT ext) {		// dir:up srcbit < dstbit

	if (egc.stack < (UINT)(8 - egc.dstbit)) {
		egc.srcmask._b[ext] = 0;
		return;
	}
	egc.stack -= (8 - egc.dstbit);
	egcsftb_dnr_sub(ext);
	if (!egc.remain) {
		egcshift();
	}
}

static void MEMCALL egcsftw_dnr0(void) {			// dir:up srcbit < dstbit

	if (egc.stack < (UINT)(16 - egc.dstbit)) {
		egc.srcmask.w = 0;
		return;
	}
	egc.stack -= (16 - egc.dstbit);
	egcsftb_dnr_sub(EGCADDR_H);
	if (egc.remain) {
		egcsftb_dnr_sub(EGCADDR_L);
		if (egc.remain) {
			return;
		}
	}
	else {
		egc.srcmask._b[EGCADDR_L] = 0;
	}
	egcshift();
}


static void MEMCALL egcsftb_upl0(UINT ext) {		// dir:up srcbit > dstbit

	if (egc.stack < (UINT)(8 - egc.dstbit)) {
		egc.srcmask._b[ext] = 0;
		return;
	}
	egc.stack -= (8 - egc.dstbit);
	egcsftb_upl_sub(ext);
	if (!egc.remain) {
		egcshift();
	}
}

static void MEMCALL egcsftw_upl0(void) {			// dir:up srcbit > dstbit

	if (egc.stack < (UINT)(16 - egc.dstbit)) {
		egc.srcmask.w = 0;
		return;
	}
	egc.stack -= (16 - egc.dstbit);
	egcsftb_upl_sub(EGCADDR_L);
	if (egc.remain) {
		egcsftb_upl_sub(EGCADDR_H);
		if (egc.remain) {
			return;
		}
	}
	else {
		egc.srcmask._b[EGCADDR_H] = 0;
	}
	egcshift();
}

static void MEMCALL egcsftb_dnl0(UINT ext) {		// dir:up srcbit > dstbit

	if (egc.stack < (UINT)(8 - egc.dstbit)) {
		egc.srcmask._b[ext] = 0;
		return;
	}
	egc.stack -= (8 - egc.dstbit);
	egcsftb_dnl_sub(ext);
	if (!egc.remain) {
		egcshift();
	}
}

static void MEMCALL egcsftw_dnl0(void) {			// dir:up srcbit > dstbit

	if (egc.stack < (UINT)(16 - egc.dstbit)) {
		egc.srcmask.w = 0;
		return;
	}
	egc.stack -= (16 - egc.dstbit);
	egcsftb_dnl_sub(EGCADDR_H);
	if (egc.remain) {
		egcsftb_dnl_sub(EGCADDR_L);
		if (egc.remain) {
			return;
		}
	}
	else {
		egc.srcmask._b[EGCADDR_L] = 0;
	}
	egcshift();
}


typedef void (MEMCALL * EGCSFTB)(UINT ext);
typedef void (MEMCALL * EGCSFTW)(void);

static const EGCSFTB egcsftb[6] = {
		egcsftb_upn0,	egcsftb_dnn0,
		egcsftb_upr0,	egcsftb_dnr0,
		egcsftb_upl0,	egcsftb_dnl0};

static const EGCSFTW egcsftw[6] = {
		egcsftw_upn0,	egcsftw_dnn0,
		egcsftw_upr0,	egcsftw_dnr0,
		egcsftw_upl0,	egcsftw_dnl0};



// ---------------------------------------------------------------------------

static void MEMCALL shiftinput_byte(UINT ext) {

	if (egc.stack <= 16) {
		if (egc.srcbit >= 8) {
			egc.srcbit -= 8;
		}
		else {
			egc.stack += (8 - egc.srcbit);
			egc.srcbit = 0;
		}
		if (!(egc.sft & 0x1000)) {
			egc.inptr++;
		}
		else {
			egc.inptr--;
		}
	}
	egc.srcmask._b[ext] = 0xff;
	(*egcsftb[egc.func])(ext);
}

static void MEMCALL shiftinput_incw(void) {

	if (egc.stack <= 16) {
		egc.inptr += 2;
		if (egc.srcbit >= 8) {
			egc.outptr++;
		}
		egc.stack += (16 - egc.srcbit);
		egc.srcbit = 0;
	}
	egc.srcmask.w = 0xffff;
	(*egcsftw[egc.func])();
}

static void MEMCALL shiftinput_decw(void) {

	if (egc.stack <= 16) {
		egc.inptr -= 2;
		if (egc.srcbit >= 8) {
			egc.outptr--;
		}
		egc.stack += (16 - egc.srcbit);
		egc.srcbit = 0;
	}
	egc.srcmask.w = 0xffff;
	(*egcsftw[egc.func])();
}
