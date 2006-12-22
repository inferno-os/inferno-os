#include "lib9.h"
#include "logfs.h"
#include "nandfs.h"
#include "local.h"

static int
hammingdistance(uchar a, uchar b)
{
	uchar c;
	int i, k;
	if (a == b)
		return 0;
	c =  a ^ b;
	for (i = 0x80, k = 0; i; i >>= 1)
		if (c & i)
			k++;
	return k;
}

static int
allones(uchar *data, int len)
{
	while (len-- > 0)
		if (*data++ != 0xff)
			return 0;
	return 1;
}

LogfsLowLevelReadResult
_nandfscorrectauxiliary(NandfsAuxiliary *hdr)
{
	/*
	 * correct single bit errors, detect more than 1, in
	 * tag, signature
	 * TODO: add nerase and path protection
	 */
	LogfsLowLevelReadResult e;
	int x;
	int min, minx;

	e = LogfsLowLevelReadResultOk;
	
	min = 8;
	minx = 0;
	for (x = 0; x < _nandfsvalidtagscount; x++) {
		int d = hammingdistance(hdr->tag, _nandfsvalidtags[x]);
		if (d < min) {
			min = d;
			minx = x;
			if (d == 0)
				break;
		}
	}
	if (min == 1) {
		hdr->tag = _nandfsvalidtags[minx];
		e = LogfsLowLevelReadResultSoftError;
	}
	else if (min > 1)
		e = LogfsLowLevelReadResultHardError;
	else {
		if (hdr->tag != LogfsTnone) {
			ulong tmp = getbig4(hdr->parth);
			if (tmp != 0xfffffffff && _nandfshamming31_26correct(&tmp)) {
				putbig4(hdr->parth, tmp);
				if (e != LogfsLowLevelReadResultOk)	
					e = LogfsLowLevelReadResultSoftError;
			}
			tmp = (getbig2(hdr->nerasemagicmsw) << 16) | getbig2(hdr->nerasemagiclsw);
			if (tmp != 0xffffffff && _nandfshamming31_26correct(&tmp)) {
				putbig2(hdr->nerasemagicmsw, tmp >> 16);
				putbig2(hdr->nerasemagiclsw, tmp);
				if (e != LogfsLowLevelReadResultOk)	
					e = LogfsLowLevelReadResultSoftError;
			}
		}
		else if (allones((uchar *)hdr, sizeof(*hdr)))
			e = LogfsLowLevelReadResultAllOnes;
	}
			
	return e;
}
