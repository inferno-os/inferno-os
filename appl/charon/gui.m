Gui: module {
	PATH: con "/dis/charon/gui.dis";

	Progressmsg : adt {
		bsid : int;
		state : int;
		pcnt : int;
		s : string;
	};

	# Progress states
	Punused, Pstart, Pconnected, Psslconnected, Phavehdr,
	Phavedata, Pdone, Perr, Paborted : con iota;

	display: ref Draw->Display;
	mainwin: ref Draw->Image;
	progress: chan of Progressmsg;

	init: fn(ctxt: ref Draw->Context, cu: CharonUtils): ref Draw->Context;

	snarfput: fn(s: string);
	setstatus: fn(s: string);
	seturl: fn(s: string);
	auth: fn(realm: string) : (int, string, string);
	alert: fn(msg: string);
	confirm: fn(msg: string) : int;
	prompt: fn(msg, dflt: string) : (int, string);
	backbutton: fn(enable : int);
	fwdbutton: fn (enable : int);

	flush: fn (r : Draw->Rect);
	clientfocus: fn();

	getpopup: fn(r: Draw->Rect): ref Menu->Popup;
	cancelpopup: fn(): int;

	exitcharon: fn();

	# Statusbar support
	MNONE, MURL, MLINK: con iota;
	linkcount: int;
	statusbarheight: fn(): int;
	drawstatusbar: fn(dst: ref Draw->Image);
	startinput: fn(mode: int);
	inputmode: fn(): int;
	snarfget: fn(): string;
};
