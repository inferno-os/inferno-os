implement Crc;

include "crc.m";

init(poly : int, reg : int) : ref CRCstate
{
	if (poly == 0)
		poly = int 16redb88320;
	tab := array[256] of int;
	for(i := 0; i < 256; i++){
		crc := i;
		for(j := 0; j < 8; j++){
			c := crc & 1;
			crc = (crc >> 1) & 16r7fffffff;
			if(c)
				crc ^= poly;
		}
		tab[i] = crc;
	}
	crcs := ref CRCstate;
	crcs.crc = 0;
	crcs.crctab = tab;
	crcs.reg = reg;
	return crcs;
}

crc(crcs : ref CRCstate, buf : array of byte, nb : int) : int
{
	n := nb;
	if (n > len buf)
		n = len buf;
	crc := crcs.crc;
	tab := crcs.crctab;
	crc ^= crcs.reg;
	for (i := 0; i < n; i++)
		crc = tab[int(byte crc ^ buf[i])] ^ ((crc >> 8) & 16r00ffffff);
	crc ^= crcs.reg;
	crcs.crc = crc;
	return crc;
}

reset(crcs : ref CRCstate)
{
	crcs.crc = 0;
}
