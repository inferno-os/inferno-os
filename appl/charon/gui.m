Gui: module {
	PATH: con "/dis/charon/gui.dis";

	Progressmsg : adt {
		bsid : int;
		state : int;
		pcnt : int;
		s : string;
	};

	# clients should never capture Popup.image
	# other than during drawing operations
	Popup: adt {
		r: Draw->Rect;
		image: ref Draw->Image;
		window: ref Draw->Image;

		flush: fn(p: self ref Popup, r: Draw->Rect);
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

	getpopup: fn(r: Draw->Rect): ref Popup;
	cancelpopup: fn(): int;

	exitcharon: fn();
};
