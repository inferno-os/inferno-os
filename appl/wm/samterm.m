include "tk.m";
include "wmlib.m";

Samterm: module
{

	PATH:		con "/dis/wm/sam.dis";

	Section: adt
	{
		nrunes:	int;
		text:	string;		# if null, we haven't got it
	};

	Range: adt {
		first, last: int;
	};

	Flayer: adt {
		tag:		int;
		t:		ref Tk->Toplevel;
		tkwin:		string;	# tk window name
		scope:		Range;	# part of file in range
		dot:		Range;	# cursor position wrt file, not scope
		width:		int;	# window width (not used yet)
		lineheigth:	int;	# height of a single line (for resize)
		lines:		int;	# window height in lines
		scrollbar:	Range;	# current position of scrollbar
		typepoint:	int;	# -1, or pos of first unsent char typed
	};

	Text: adt {
		tag:		int;
		lock:		int;
		flayers:	list of ref Flayer;	# hd flayers is current
		nrunes:		int;
		sects:		list of ref Section;
		state:		int;
	};

	Dirty:	con 1;
	LDirty:	con 2;

	Menu: adt {
		tag:		int;
		name:		string;
		text:		ref Text;
	};

	Context: adt {
		ctxt:		ref Draw->Context;
		tag:		int;	# globally unique tag generator
		lock:		int;	# global lock

		keysel:		array of chan of string;
		scrollsel:	array of chan of string;
		buttonsel:	array of chan of string;
		menu2sel:	array of chan of string;
		menu3sel:	array of chan of string;
		titlesel:	array of chan of string;
		flayers:	array of ref Flayer;

		menus:		array of ref Menu;
		texts:		array of ref Text;

		cmd:		ref Text;	# sam command window
		which:		ref Flayer;	# current flayer (sam or work)
		work:		ref Flayer;	# current work flayer

		pgrp:		int;		# process group
		logfd:		ref FD;
	};

	init:		fn(ctxt: ref Draw->Context, args: list of string);
};
