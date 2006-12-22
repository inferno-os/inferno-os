Wmsrv: module{
	PATH: con "/dis/lib/wmsrv.dis";

	init:	fn(): 	(chan of (string, chan of (string, ref Draw->Wmcontext)),
		chan of (ref Client, chan of string),
		chan of (ref Client, array of byte, Sys->Rwrite));

	find:	fn(p: Draw->Point): ref Client;
	top:	fn(): ref Client;

	Window: adt {
		tag:	string;
		r:	Rect;
		img:	ref Draw->Image;
	};

	Client: adt {
		kbd:		chan of int;
		ptr:		chan of ref Draw->Pointer;
		ctl:		chan of string;
		stop:		chan of int;
		flags:	int;			# general purpose.
		cursor:	string;		# hack.
		wins:	list of ref Window;
		znext:	cyclic ref Client;

		# private:
		images:	chan of (ref Draw->Point, ref Draw->Image, chan of int);
		id:		int;				# index into clients array
		fid:		int;
		token:	int;
		wmctxt:	ref Draw->Wmcontext;

		window:	fn(c: self ref Client, tag: string): ref Window;
		contains:	fn(c: self ref Client, p: Draw->Point): int;
		image:	fn(c: self ref Client, tag: string):	ref Draw->Image;
		setimage:	fn(c: self ref Client, tag: string,  i: ref Draw->Image): int;	# only in response to some msgs.
		setorigin:	fn(c: self ref Client, tag: string, o: Draw->Point): int;		# only in response to some msgs.
		top:		fn(c: self ref Client);			# bring to top.
		bottom:	fn(c: self ref Client);			# send to bottom.
		hide:		fn(w: self ref Client);		# move offscreen.
		unhide:	fn(w: self ref Client);		# move onscreen.
		remove:	fn(w: self ref Client);
	};
};

