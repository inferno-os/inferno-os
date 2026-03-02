Windowm : module {
	PATH : con "/dis/xenith/wind.dis";

	init : fn(mods : ref Dat->Mods);

	Window : adt {
		qlock : ref Dat->Lock;
		refx : ref Dat->Ref;
		tag : 	cyclic ref Textm->Text;
		body : cyclic ref Textm->Text;
		r : Draw->Rect;
		isdir : int;
		isscratch : int;
		filemenu : int;
		dirty : int;
		autoindent: int;
		id : int;
		addr : Dat->Range;
		limit : Dat->Range;
		nopen : array of byte;
		nomark : int;
		noscroll : int;
		echomode : int;
		wrselrange : Dat->Range;
		rdselrange : Dat->Range;	# saved selection range for Edit pipe commands
		rdselfd : ref Sys->FD;
		col : cyclic ref Columnm->Column;
		eventx : cyclic ref Xfidm->Xfid;
		events : string;
		nevents : int;
		owner : int;
		maxlines :	int;
		dlp : array of ref Dat->Dirlist;
		ndl : int;
		putseq : int;
		nincl : int;
		incl : array of string;
		reffont : ref Dat->Reffont;
		ctllock : ref Dat->Lock;
		ctlfid : int;
		dumpstr : string;
		dumpdir : string;
		dumpid : int;
		colorstr : string;	# per-window color overrides, nil = use global
		imagemode : int;	# 0 = text mode, 1 = image/content mode
		bodyimage : ref Draw->Image;	# rendered content for display
		imagepath : string;	# path to current content
		imageoffset : Draw->Point;	# pan offset for large images
		contentdata : array of byte;	# raw content bytes (for renderer commands / render mode)
		contentrenderer : Renderer;	# active renderer module (nil = legacy image path)
		rendering : int;	# 1 while async render in progress (debounce)
		pendingcmd : string;	# deferred command during rendering (latest wins)
		rendermode : int;	# 0 = raw text, 1 = formatted view (Render command toggle)
		zoomscale : int;	# zoom percentage: 100 = fit-to-window, 200 = 2x, etc.
		zoomedcache : ref Draw->Image;	# cached scaled page for fast pan/redraw
		utflastqid : int;
		utflastboff : int;
		utflastq : int;
		tagsafe : int;
		tagexpand : int;
		taglines : int;
		tagtop : Draw->Rect;
		creatormnt : int;	# Mount session ID that created this window (0 = user/Xenith)
		asyncload : ref Asyncio->AsyncOp;	# Current async file load operation (nil = none)
		asyncsave : ref Asyncio->AsyncOp;	# Current async file save operation (nil = none)
		savename : string;	# Name being saved to (for async save completion)

		init : fn(w : self ref Window, w0 : ref Window, r : Draw->Rect);
		lock : fn(w : self ref Window, n : int);
		lock1 : fn(w : self ref Window, n : int);
		unlock : fn(w : self ref Window);
		typex : fn(w : self ref Window, t : ref Textm->Text, r : int);
		undo : fn(w : self ref Window, n : int);
		setname : fn(w : self ref Window, r : string, n : int);
		settag : fn(w : self ref Window);
		settag1 : fn(w : self ref Window);
		commit : fn(w : self ref Window, t : ref Textm->Text);
		reshape : fn(w : self ref Window, r : Draw->Rect, n : int, keepextra: int) : int;
		close : fn(w : self ref Window);
		delete : fn(w : self ref Window);
		clean : fn(w : self ref Window, n : int, exiting : int) : int;
		dirfree : fn(w : self ref Window);
		event : fn(w : self ref Window, b : string);
		mousebut : fn(w : self ref Window);
		addincl : fn(w : self ref Window, r : string, n : int);
		cleartag : fn(w : self ref Window);
		ctlprint : fn(w : self ref Window, fonts : int) : string;
		applycolors : fn(w : self ref Window);
		loadimage : fn(w : self ref Window, path : string) : string;
		loadcontent : fn(w : self ref Window, path : string) : string;
		clearimage : fn(w : self ref Window);
		drawimage : fn(w : self ref Window);
		prerenderzoomed : fn(w : self ref Window) : ref Draw->Image;
		contentcommands : fn(w : self ref Window) : list of ref Renderer->Command;
		contentcommand : fn(w : self ref Window, cmd, arg : string) : string;
		asynccontentcommand : fn(w : self ref Window, cmd, arg : string);
	};
};
