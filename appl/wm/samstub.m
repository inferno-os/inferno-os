Samstub: module
{
	PATH:		con "/dis/wm/samstub.dis";
	SAM:		con "sam -R";

	VERSION:	con 0;
	UTFmax:		con 3;

	TBLOCKSIZE:	con 512;  # largest piece of text sent to terminal ...
	DATASIZE:	con (UTFmax*TBLOCKSIZE+30);
				  # ... including protocol header stuff
	SNARFSIZE:	con 4096; # maximum length of exchanged snarf buffer

	# Message types
	Error, Status, Debug: con iota;

	Sammsg: adt {
		mtype:	int;
		mcount:	int;
		mdata:	array of byte;

		inshort:	fn(h: self ref Sammsg, n: int): int;
		inlong:		fn(h: self ref Sammsg, n: int): int;
		invlong:	fn(h: self ref Sammsg, n: int): big;
		outcopy:	fn(h: self ref Sammsg, pos: int, data: array of byte);
		outshort:	fn(h: self ref Sammsg, pos: int, s: int);
		outlong:	fn(h: self ref Sammsg, pos: int, s: int);
		outvlong:	fn(h: self ref Sammsg, pos: int, s: big);
	};

	Samio: adt {
		ctl:		ref Sys->FD;	# /cmd/nnn/ctl
		data:		ref Sys->FD;	# /cmd/nnn/data
		buffer:		array of byte;	# buffered data read from sam
		index:		int;
		count:		int;		# pointers into buffer

	};

	init:		fn(ctxt: ref Context);

	start:		fn(): (ref Samio, chan of ref Sammsg);
	sender:		fn(s: ref Samio, c: chan of ref Sammsg);
	receiver:	fn(s: ref Samio, c: chan of ref Sammsg);

	outTs:		fn(t, s: int);
	outTv:		fn(t: int, i: big);
	outT0:		fn(t: int);
	outTsl:		fn(t, m, l: int);
	outTslS:	fn(t, s1, l1: int, s: string);
	outTsll:	fn(t, m, l1, l2: int);

	cleanout:	fn();
	close:		fn(win, tag: int);
	cut:		fn(t: ref Text, fl: ref Flayer);
	findhole:	fn(t: ref Text): (int, int);
	grow:		fn(t: ref Text, l1, l2: int);
	horigin:	fn(m, l: int);
	inmesg:		fn(h: ref Sammsg): int;
	keypress:	fn(key: string);
	look:		fn(t: ref Text, fl: ref Flayer);
	menuins:	fn(p: int, s: string, t: ref Text, tg: int);
	newtext:	fn(tag, tp: int): int;
	paste:		fn(t: ref Text, fl: ref Flayer);
	scrollto:	fn(fl: ref Flayer, where: int);
	sctget:		fn(scts: list of ref Section, p1, p2: int): string;
	sctgetlines:	fn(scts: list of ref Section, p, n: int):
				 (int, string);
	scthole:	fn(t: ref Text, f: int): (int, int);
	sctput:		fn(scts: list of ref Section, pos: int, s: string):
				 list of ref Section;
	search:		fn(t: ref Text, fl: ref Flayer);
	send:		fn(t: ref Text, fl: ref Flayer);
	setlock:	fn();
	snarf:		fn(t: ref Text, fl: ref Flayer);
	startcmdfile:	fn();
	startfile:	fn(tag: int): int;
	startnewfile:	fn();
	updatefls:	fn(t: ref Text, l: int, s: string);
	zerox:		fn(t: ref Text);

	Tversion,	# version
	Tstartcmdfile,	# terminal just opened command frame
	Tcheck,		# ask host to poke with Hcheck
	Trequest,	# request data to fill a hole
	Torigin,	# gimme an Horigin near here
	Tstartfile,	# terminal just opened a file's frame
	Tworkfile,	# set file to which commands apply
	Ttype,		# add some characters, but terminal already knows
	Tcut,
	Tpaste,
	Tsnarf,
	Tstartnewfile,	# terminal just opened a new frame
	Twrite,		# write file
	Tclose,		# terminal requests file close; check mod. status
	Tlook,		# search for literal current text
	Tsearch,	# search for last regular expression
	Tsend,		# pretend he typed stuff
	Tdclick,	# double click
	Tstartsnarf,	# initiate snarf buffer exchange
	Tsetsnarf,	# remember string in snarf buffer
	Tack,		# acknowledge Hack
	Texit,		# exit
	TMAX: con iota;

	Hversion,	# version
	Hbindname,	# attach name[0] to text in terminal
	Hcurrent,	# make named file the typing file
	Hnewname,	# create "" name in menu
	Hmovname,	# move file name in menu
	Hgrow,		# insert space in rasp
	Hcheck0,	# see below
	Hcheck,		# ask terminal to check whether it needs more data
	Hunlock,	# command is finished; user can do things
	Hdata,		# store this data in previously allocated space
	Horigin,	# set origin of file/frame in terminal
	Hunlockfile,	# unlock file in terminal
	Hsetdot,	# set dot in terminal
	Hgrowdata,	# Hgrow + Hdata folded together
	Hmoveto,	# scrolling, context search, etc.
	Hclean,		# named file is now 'clean'
	Hdirty,		# named file is now 'dirty'
	Hcut,		# remove space from rasp
	Hsetpat,	# set remembered regular expression
	Hdelname,	# delete file name from menu
	Hclose,		# close file and remove from menu
	Hsetsnarf,	# remember string in snarf buffer
	Hsnarflen,	# report length of implicit snarf
	Hack,		# request acknowledgement
	Hexit,
	HMAX: con iota;
};
