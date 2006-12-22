RcxSend : module {
	PATH: con "/dis/lego/rcxsend.dis";

	init: fn (pnum, dbg : int) : string;
	send : fn (data : array of byte, slen, rlen : int) : array of byte;
};