implement Acidb;

include "sys.m";
include "draw.m";
include "bufio.m";

sys : Sys;
bufio : Bufio;

FD : import sys;
Iobuf : import bufio;

Acidb : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

init(nil : ref Draw->Context, nil : list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	# TBS main(argl);
}

False : con 0;
True : con 1;

EVENTSIZE : con 256;

Event : adt {
	c1, c2, q0, q1, flag, nb, nr : int;
	b : array of byte;
	r : array of int;
	# TBS byte	b[EVENTSIZE*UTFmax+1];
	# TBS Rune	r[EVENTSIZE+1];
};

Win : adt {
		winid : int;
		addr : int;
		body : ref Iobuf;
		ctl : int;
		data : int;
		event : int;
		buf : array of byte;
		# TBS byte	buf[512];
		bufp : int;
		nbuf : int;

		wnew : fn(w : ref Win);
		wwritebody : fn(w : ref Win, s : array of byte, n : int);
		wread : fn(w : ref Win, m : int, n : int, s : array of byte);
		wclean : fn(w : ref Win);
		wname : fn(w : ref Win, s : array of byte);
		wdormant : fn(w : ref Win);
		wevent : fn(w : ref Win, e : ref Event);
		wtagwrite : fn(w : ref Win, s : array of byte, n : int);
		wwriteevent : fn(w : ref Win, e : ref Event);
		wslave : fn(w : ref Win, c : chan of Event);
		wreplace : fn(w : ref Win, s : array of byte, b : array of byte, n : int);
		wselect : fn(w : ref Win, s : array of byte);
		wdel : fn(w : ref Win, n : int) : int;
		wreadall : fn(w : ref Win) : (int, array of byte);

		ctlwrite : fn(w : ref Win, s : array of byte);
		getec : fn(w : ref Win) : int;
		geten : fn(w : ref Win) : int;
		geter : fn(w : ref Win, s : array of byte, r : array of int) : int;
		openfile : fn(w : ref Win, b : array of byte) : int;
		openbody : fn(w : ref Win, n : int);
};

Awin : adt {
	w : Win;

	slave : fn(w : ref Awin, s : array of byte, c : chan of int);
	new : fn(w : ref Awin, s : array of byte);
	command : fn(w : ref Awin, s : array of byte) : int;
	send : fn(w : ref Awin, m : int, s : array of byte, n : int);
};

srvfd : ref FD;
stdin : ref FD;
srvenv : array of byte;
# TBS byte	srvenv[64];

srvc : chan of array of byte;
