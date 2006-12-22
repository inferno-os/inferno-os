Events: module {
	PATH: con "/dis/charon/event.dis";
	Event: adt {
		pick {
			Ekey =>
				keychar: int;		# Unicode char for pressed key
			Emouse =>
				p: Draw->Point;	# coords of pointer
				mtype: int;		# Mmove, etc.
			Emove =>
				p: Draw->Point;	# new top-left of moved window
			Ereshape =>
				r: Draw->Rect;		# new window place and size
			Equit =>
				dummy: int;
			Estop =>
				dummy: int;
			Eback =>
				dummy: int;
			Efwd =>
				dummy: int;
			Eform =>
				frameid: int;		# which frame is form in
				formid: int;		# which form in the frame
				ftype: int;			# EFsubmit or EFreset
			Eformfield =>
				frameid: int;		# which frame is form in
				formid: int;		# which form in the frame
				fieldid: int;		# which formfield in the form
				fftype: int;		# EFFblur, EFFfocus, etc.
			Ego =>
				url: string;			# where to go
				target: string;		# frame to replace
				delta: int;		# History.go(delta)
				gtype: int;
			Esubmit =>
				subkind: int;		# CU->HGet or CU->HPost
				action: ref Url->Parsedurl;
				data: string;
				target: string;
			Escroll or Escrollr =>
				frameid: int;
				pt: Draw->Point;
			Esettext =>
				frameid: int;
				url: ref Url->Parsedurl;
				text: string;
			Elostfocus =>			# main window has lost keyboard focus
				dummy: int;
			Edismisspopup =>		# popup window has been dismissed by gui
				dummy: int;
		}

		tostring: fn(e: self ref Event) : string;
	};

	# Events sent to scripting engines
	ScriptEvent: adt {
		kind: int;
		frameid: int;
		formid: int;
		fieldid: int;
		anchorid: int;
		imageid: int;
		x: int;
		y: int;
		which: int;
		script: string;
		reply: chan of string;	# onreset/onsubmit reply channel
		ms: int;
	};

	# ScriptEvent kinds
	SEonclick, SEondblclick, SEonkeydown, SEonkeypress, SEonkeyup,
		SEonmousedown, SEonmouseover, SEonmouseout, SEonmouseup, SEonblur, SEonfocus,
		SEonchange, SEonload, SEtimeout, SEonabort, SEonerror,
		SEonreset, SEonresize, SEonselect, SEonsubmit, SEonunload, SEscript, SEinterval, SEnone : con 1 << iota;

	# some special keychars (use Unicode Private Area)
	Kup, Kdown, Khome, Kleft, Kright, Kend, Kaup, Kadown : con (iota + 16rF000);

	# Mouse event subtypes
	Mmove, Mlbuttondown, Mlbuttonup, Mldrag, Mldrop,
		Mmbuttondown, Mmbuttonup, Mmdrag,
		Mrbuttondown, Mrbuttonup, Mrdrag,
		Mhold : con iota;

	# Form event subtypes
	EFsubmit, EFreset : con iota;

	# FormField event subtypes
	EFFblur, EFFfocus, EFFclick, EFFselect, EFFredraw, EFFnone : con iota;

	# Go event subtypes
	EGnormal, EGreplace, EGreload, EGforward, EGback, EGdelta, EGlocation: con iota;

	init: fn(evchan : chan of ref Event);
	autorepeat: fn(ev : ref Event, idlems, ms : int);
	evchan: chan of ref Event;
};
