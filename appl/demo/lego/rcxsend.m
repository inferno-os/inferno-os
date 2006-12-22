RcxSend : module {
	init: fn (pnum, dbg : int) : string;
	send : fn (data : array of byte, slen, rlen : int) : array of byte;
};