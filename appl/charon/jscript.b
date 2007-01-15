implement JScript;

include "common.m";
include "ecmascript.m";

ES: Ecmascript;
	Exec, Obj, Call, Prop, Val, Ref, RefVal, Builtin, ReadOnly: import ES;
me: ESHostobj;

# local copies from CU
sys: Sys;
CU: CharonUtils;

D: Draw;
S: String;
T: StringIntTab;
C: Ctype;
B: Build;
	Item: import B;
CH: Charon;
L: Layout;
	Frame, Control: import L;
U: Url;
	Parsedurl: import U;
E: Events;
	Event, ScriptEvent: import E;

G : Gui;

JScript: module
{
	# First, conform to Script interface
	defaultStatus: string;
	jevchan: chan of ref ScriptEvent;
	versions: array of string;

	init: fn(cu: CharonUtils): string;
	frametreechanged: fn(top: ref Layout->Frame);
	havenewdoc: fn(f: ref Layout->Frame);
	evalscript: fn(f: ref Layout->Frame, s: string) : (string, string, string);
	framedone: fn(f : ref Layout->Frame, hasscripts : int);

	#
	# implement the host object interface, too
	#
	get:		fn(ex: ref Exec, o: ref Obj, property: string): ref Val;
	put:		fn(ex: ref Exec, o: ref Obj, property: string, val: ref Val);
	canput:	fn(ex: ref Exec, o: ref Obj, property: string): ref Val;
	hasproperty:	fn(ex: ref Exec, o: ref Obj, property: string): ref Val;
	delete:		fn(ex: ref Exec, o: ref Obj, property: string);
	defaultval:	fn(ex: ref Exec, o: ref Obj, tyhint: int): ref Val;
	call:		fn(ex: ref Exec, func, this: ref Obj, args: array of ref Val, eval: int): ref Ref;
	construct:	fn(ex: ref Exec, func: ref Obj, args: array of ref Val): ref Obj;
};

versions = array [] of {
	"javascript",
	"javascript1.0",
	"javascript1.1",
	"javascript1.2",
	"javascript1.3",
};

# Call init() before calling anything else.
# It makes a global object (a Window) for the browser's top level frame,
# and also puts a navaigator object in it.  The document can't be filled
# in until the first document gets loaded.
#
# This module keeps track of the correspondence between the Script Window
# objects and the corresponding Layout Frames, using the ScriptWin adt to
# build a tree mirroring the structure.  The root of the tree never changes
# after first being set (but changing its document essentially resets all of the
# other data structures).  After charon has built its top-level window, it
# should call frametreechanged(top).
#
# When a frame gets reset or gets some frame children added, call frametreechanged(f),
# where f is the changed frame.  This module will update its ScriptWin tree as needed.
#
# Whenever the document in a (Layout) Frame f changes, call havenewdoc(f)
# after the frame's doc field is set. This causes this module to initialize the document
# object in the corresponding window object.
#
# From within the build process, call evalscript(containing frame, script) to evaluate
# global code fragments as needed.  The return value is two strings: a possible error
# description, and HTML that is the result of a document.write (so it should be spliced
# in at the point where the <SCRIPT> element occurred).  evalscript() also handles
# the job of synching up the Docinfo data (on the Build side) with the document object
# (on the Script side).
#
# For use by other external routines, the xfertoscriptobjs() and xferfromscriptobjs()
# functions that do the just-described synch-up are available for external callers.

# Adt for keeping track of correspondence between Image objects
# and their corresponding Build items.
ScriptImg: adt
{
	item: ref Build->Item.Iimage;
	obj: ref Obj;
};

ScriptForm : adt {
	form : ref Build->Form;
	obj : ref Obj;
	ix : int;		# index in document.forms array
	fields : list of (ref Build->Formfield, ref Obj);
};

# Adt for keeping track of correspondence between Window
# objects and their corresponding Frames.

ScriptWin: adt
{
	frame: ref Layout->Frame;
	ex: ref Exec;		# ex.global is frame's Window obj
	locobj: ref Obj;		# Location object for window
	val : ref Val;		# val of ex.global - used to side-effect entry in parent.frames[]

	parent: ref ScriptWin;
	forms: list of ref ScriptForm;	# no guaranteed order
	kids: cyclic list of ref ScriptWin;
	imgs: list of ref ScriptImg;
	newloc: string;		# url to go to after script finishes executing
	newloctarg: string;	# target frame for newloc
	docwriteout: string;
	inbuild: int;
	active: int;		# frame or sub-frame has scripts
	error: int;
	imgrelocs: list of ref Obj;

	new: fn(f: ref Layout->Frame, ex: ref Exec, loc: ref Obj, par: ref ScriptWin) : ref ScriptWin;
	addkid: fn(sw: self ref ScriptWin, f: ref Layout->Frame);
	dummy: fn(): ref ScriptWin;
#	findbyframe: fn(sw: self ref ScriptWin, f: ref Layout->Frame) : ref ScriptWin;
	findbyframeid: fn(sw: self ref ScriptWin, fid: int) : ref ScriptWin;
	findbydoc: fn(sw: self ref ScriptWin, d: ref Build->Docinfo) : ref ScriptWin;
	findbyobj: fn(sw : self ref ScriptWin, obj : ref Obj) : ref ScriptWin;
	findbyname: fn(sw : self ref ScriptWin, name : string) : ref ScriptWin;
};

opener: ref ScriptWin;
winclose: int;

# Helper adts for initializing objects.
# Methods go in prototype, properties go in objects

MethSpec: adt
{
	name: string;
	args: array of string;
};


IVundef, IVnull, IVtrue, IVfalse, IVnullstr, IVzero, IVzerostr, IVarray: con iota;

PropSpec: adt
{
	name: string;
	attr: int;
	initval: int;	# one of IVnull, etc.
};

ObjSpec: adt
{
	name: string;
	methods: array of MethSpec;
	props: array of PropSpec;
};

MimeSpec: adt
{
	description: string;
	suffixes: string;
	ty: string;
};

# Javascript 1.1 (Netscape 3) client objects

objspecs := array[] of {
    ObjSpec("Anchor", 
	nil,
	array[] of {PropSpec
		("name", ReadOnly, IVnullstr) }
	),
    ObjSpec("Applet",
	nil,
	nil
	),
    ObjSpec("document",
	array[] of {MethSpec
		("close", nil),
		("open", array[] of { "mimetype", "replace" }),
		("write", array[] of { "string" }),
		("writeln", array[] of { "string" }) },
	array[] of {PropSpec
		("alinkColor", 0, IVnullstr),
		("anchors", ReadOnly, IVarray),
		("applets", ReadOnly, IVarray),
		("bgColor", 0, IVnullstr),
		("cookie", 0, IVnullstr),
		("domain", 0, IVnullstr),
		("embeds", ReadOnly, IVarray),
		("fgColor", 0, IVnullstr),
		("forms", ReadOnly, IVarray),
		("images", ReadOnly, IVarray),
		("lastModified", ReadOnly, IVnullstr),
		("linkColor", 0, IVnullstr),
		("links", ReadOnly, IVarray),
		("location", 0, IVnullstr),
		("plugins", ReadOnly, IVarray),
		("referrer", ReadOnly, IVnullstr),
		("title", ReadOnly, IVnullstr),
		("URL", ReadOnly, IVnullstr),
		("vlinkColor", 0, IVnullstr) }
	),
    ObjSpec("Form",
	array[] of {MethSpec
		("reset", nil),
		("submit", nil) },
	array[] of {PropSpec
		("action", 0, IVnullstr),
		("elements", ReadOnly, IVarray),
		("encoding", 0, IVnullstr),
		("length", ReadOnly, IVzero),
		("method", 0, IVnullstr),
		("name", 0, IVnullstr),
		("target", 0, IVnullstr) }
	),
   # This is merge of Netscape objects (to save code & data space):
   # Button, Checkbox, Hidden, Radio, Reset, Select, Text, and Textarea
    ObjSpec("FormField",
	array[] of {MethSpec
		("blur", nil),
		("click", nil),
		("focus", nil),
		("select", nil) },
	array[] of {PropSpec
		("checked", 0, IVundef),
		("defaultChecked", 0, IVundef),
		("defaultValue", 0, IVundef),
		("form", ReadOnly, IVundef),
		("length", 0, IVundef),
		("name", 0, IVnullstr),
		("options", 0, IVundef),
		("type", ReadOnly, IVundef),
		("selectedIndex", 0, IVundef),
		("value", 0, IVnullstr) }
	),
    ObjSpec("History",
	array[] of {MethSpec
		("back", nil),
		("forward", nil),
		("go", array[] of { "location-or-delta" }) },
	array[] of {PropSpec
		("current", ReadOnly, IVnullstr),
		("length", ReadOnly, IVzero),
		("next", ReadOnly, IVnullstr),
		("previous", ReadOnly, IVnullstr) }
	),
    ObjSpec("Image",
	nil,
	array[] of {PropSpec
		("border", ReadOnly, IVzerostr),
		("complete", ReadOnly, IVfalse),
		("height", ReadOnly, IVzerostr),
		("hspace", ReadOnly, IVzerostr),
		("lowsrc", 0, IVnullstr),
		("name", ReadOnly, IVnullstr),
		("src", 0, IVnullstr),
		("vspace", ReadOnly, IVzerostr),
		("width", ReadOnly, IVzerostr) }
	),
    ObjSpec("Link",
	nil,
	array[] of {PropSpec
		("hash", 0, IVnullstr),
		("host", 0, IVnullstr),
		("hostname", 0, IVnullstr),
		("href", 0, IVnullstr),
		("pathname", 0, IVnullstr),
		("port", 0, IVnullstr),
		("protocol", 0, IVnullstr),
		("search", 0, IVnullstr),
		("target", 0, IVnullstr) }
	),
    ObjSpec("Location",
	array[] of {MethSpec
		("reload", array[] of { "forceGet" }),
		("replace", array[] of { "URL" }) },
	array[] of {PropSpec
		("hash", 0, IVnullstr),
		("host", 0, IVnullstr),
		("hostname", 0, IVnullstr),
		("href", 0, IVnullstr),
		("pathname", 0, IVnullstr),
		("port", 0, IVnullstr),
		("protocol", 0, IVnullstr),
		("search", 0, IVnullstr) }
	),
    ObjSpec("MimeType",
	nil,
	array[] of {PropSpec
		("description", ReadOnly, IVnullstr),
		("enabledPlugin", ReadOnly, IVnull),
		("suffixes", ReadOnly, IVnullstr),
		("type", ReadOnly, IVnullstr) }
	),
    ObjSpec("Option",
	nil,
	array[] of {PropSpec
		("defaultSelected", 0, IVfalse),
		("index", 0, IVundef),
		("selected", 0, IVfalse),
		("text", 0, IVnullstr),
		("value", 0, IVnullstr) }
	),
    ObjSpec("navigator",
	array[] of {MethSpec
		("javaEnabled", nil),
		("plugins.refresh", nil),
		("taintEnabled", nil) },
	array[] of {PropSpec
		("appCodeName", ReadOnly, IVnullstr),
		("appName", ReadOnly, IVnullstr),
		("appVersion", ReadOnly, IVnullstr),
		("mimeTypes", ReadOnly, IVarray),
		("platform", ReadOnly, IVnullstr),
		("plugins", ReadOnly, IVarray),
		("userAgent", ReadOnly, IVnullstr) }
	),
    ObjSpec("Plugin",
	nil,
	array[] of {PropSpec
		("description", 0, IVnullstr),
		("filename", 0, IVnullstr),
		("length", 0, IVzero),
		("name", 0, IVnullstr) }
	),
     ObjSpec("Screen",
	nil,
	array[] of {PropSpec
		("availHeight", ReadOnly, IVzero),
		("availWidth", ReadOnly, IVzero),
		("availLeft", ReadOnly, IVzero),
		("availTop", ReadOnly, IVzero),
		("colorDepth", ReadOnly, IVzero),
		("pixelDepth", ReadOnly, IVzero),
		("height", ReadOnly, IVzero),
		("width", ReadOnly, IVzero) }
	),
     ObjSpec("Window",
	array[] of {MethSpec
		("alert", array[] of { "msg" }),
		("blur", nil),
		("clearInterval", array[] of { "intervalid" }),
		("clearTimeout", array[] of { "timeoutid" }),
		("close", nil),
		("confirm", array[] of  { "msg" }),
		("focus", nil),
		("moveBy", array[] of { "dx", "dy" }),
		("moveTo", array[] of { "x", "y" }),
		("open", array[] of { "url", "winname", "winfeatures" }),
		("prompt", array[] of { "msg", "inputdflt" }),
		("resizeBy", array[] of { "dh", "dw" }),
		("resizeTo", array[] of { "width", "height" }),
		("scroll", array[] of { "x", "y"  }),
		("scrollBy", array[] of { "dx", "dy" }),
		("scrollTo", array[] of { "x", "y" }),
		("setInterval", array[] of { "code", "msec" }),
		("setTimeout", array[] of { "expr", "msec" }) },
	array[] of {PropSpec
		("closed", ReadOnly, IVfalse),
		("defaultStatus", 0, IVnullstr),
		("document", 0, IVnull),
		("frames", ReadOnly, IVnull),	# array, really
		("history", 0, IVnull),	# array, really
		("length", ReadOnly, IVzero),
		("location", 0, IVnullstr),
#		("Math", ReadOnly, IVnull),
		("name", 0, IVnullstr),
		("navigator", ReadOnly, IVnull),
		("offscreenBuffering", 0, IVnullstr),
		("opener", 0, IVnull),
		("parent", ReadOnly, IVnull),
		("screen", 0, IVnull),
		("self", ReadOnly, IVnull),
		("status", 0, IVnullstr),
		("top", ReadOnly, IVnull),
		("window", ReadOnly, IVnull) }
	)
};

# Currently supported charon mime types
mimespecs := array[] of {
    MimeSpec("HTML", 
	"htm,html",
	"text/html"
	),
    MimeSpec("Plain text", 
	"txt,text",
	"text/plain"
	),
   MimeSpec("Gif Image", 
	"gif",
	"image/gif"
	),
    MimeSpec("Jpeg Image", 
	"jpeg,jpg,jpe",
	"image/jpeg"
	),
    MimeSpec("X Bitmap Image", 
	"",
	"image/x-xbitmap"
	)
};

# charon's 's' debug flag:
#	1:	basic syntax and runtime errors
#	2:	'event' logging and DOM actions
#	3:	print parsed code and ops as executed
#	4:	print value of expression statements and abort on runtime errors
dbg := 0;
dbgdom := 0;

top: ref ScriptWin;
createdimages : list of ref Obj;
nullstrval: ref Val;
zeroval: ref Val;
zerostrval: ref Val;

# Call this after charon's main (top) frame has been built
init(cu: CharonUtils) : string
{
	CU = cu;
	sys = load Sys Sys->PATH;
	D = load Draw Draw->PATH;
	S = load String String->PATH;
	T = load StringIntTab StringIntTab->PATH;
	U = load Url Url->PATH;
	if (U != nil)
		U->init();
	C = cu->C;
	B = cu->B;
	L = cu->L;
	E = cu->E;
	CH = cu->CH;
	G = cu->G;
	dbg = int (CU->config).dbg['s'];
	if (dbg > 1)
		dbgdom = 1;
	ES = load Ecmascript Ecmascript->PATH;
	if(ES == nil)
		return sys->sprint("could not load module %s: %r", Ecmascript->PATH);
	err := ES->init();
	if (err != nil) 
		return sys->sprint("ecmascript error: %s", err);

	me = load ESHostobj SELF;
	if(me == nil)
		return sys->sprint("jscript: could not load  self as a ESHostobj: %r");
	if(dbg >= 3) {
		ES->debug['p'] = 1;	# print parsed code
		ES->debug['e'] = 1;	# prinv ops as they are executed
		if(dbg >= 4) {
			ES->debug['e'] = 2;
			ES->debug['v'] = 1;	# print value of expression statements
			ES->debug['r'] = 1;	# print and abort if runtime errors
		}
	}
	
	# some constant values, for initialization
	nullstrval = ES->strval("");
	zeroval = ES->numval(0.);
	zerostrval = ES->strval("0");
	jevchan = chan of ref ScriptEvent;
	spawn jevhandler();
	return nil;
}

doneevent := ScriptEvent(-1,0,0,0,0,0,0,0,0,nil,nil,0);

# Used to receive and act upon ScriptEvents from main charon thread.
# Want to queue the events up, so that the main thread doesn't have
# to wait, and spawn off a do_on, one at a time, so that they don't
# interfere with each other.
# When do_on is finished, it must send a copy of doneevent
# so that jevhandler knows it can spawn another do_on.
jevhandler()
{
	q := array[10] of ref ScriptEvent;
	qhead := 0;
	qtail := 0;
	spawnok := 1;
	for(;;) {
		jev := <- jevchan;
		if(jev.kind == -1)
			spawnok = 1;
		else
			q[qtail++] = jev;
		jev = nil;

		# remove next event to process, if ok to and there is one
		if(spawnok && qhead < qtail)
			jev = q[qhead++];

		# adjust queue to make sure there is room for next event
		if(qhead == qtail) {
			qhead = 0;
			qtail = 0;
		}
		if(qtail == len q) {
			if(qhead > 0) {
				q[0:] = q[qhead:qtail];
				qtail -= qhead;
				qhead = 0;
			}
			else {
				newq := array[len q + 10] of ref ScriptEvent;
				newq[0:] = q;
				q = newq;
			}
		}

		# process next event, if any
		if(jev != nil) {
			spawnok = 0;
			spawn do_on(jev);
		}
	}
}

# Create an execution context for the frame.
# The global object of the frame is the frame's Window object.
# Return the execution context and the Location object for the window.
makeframeex(f : ref Layout->Frame) : (ref Exec, ref Obj)
{
	winobj := mkhostobj(nil, "Window");
	ex := ES->mkexec(winobj);
	winobj.prototype = ex.objproto;
	winobj.prototype = mkprototype(ex, specindex("Window"));

	navobj := mknavobj(ex);
	reinitprop(winobj, "navigator", ES->objval(navobj));

	histobj := mkhostobj(ex, "History");
	(length, current, next, previous) := CH->histinfo();
	reinitprop(histobj, "current", ES->strval(current));
	reinitprop(histobj, "length", ES->numval(real length));
	reinitprop(histobj, "next", ES->strval(next));
	reinitprop(histobj, "previous", ES->strval(previous));
	ES->put(ex, winobj, "history", ES->objval(histobj));

	locobj := mkhostobj(ex, "Location");
	src : ref U->Parsedurl;
	di := f.doc;
	if (di != nil && di.src != nil) {
		src = di.src;
		reinitprop(locobj, "hash", ES->strval("#" + src.frag));
		reinitprop(locobj, "host", ES->strval(src.host + ":" + src.port));
		reinitprop(locobj, "hostname", ES->strval(src.host));
		reinitprop(locobj, "href", ES->strval(src.tostring()));
		reinitprop(locobj, "pathname", ES->strval(src.path));
		reinitprop(locobj, "port", ES->strval(src.port));
		reinitprop(locobj, "protocol", ES->strval(src.scheme + ":"));
		reinitprop(locobj, "search", ES->strval("?" + src.query));
	}
	ES->put(ex, winobj, "location", ES->objval(locobj));

	scrobj := mkhostobj(ex, "Screen");
	scr := (CU->G->display).image;
	scrw := D->(scr.r.dx)();
	scrh := D->(scr.r.dy)();
	reinitprop(scrobj, "availHeight", ES->numval(real scrh));
	reinitprop(scrobj, "availWidth", ES->numval(real scrw));
	reinitprop(scrobj, "availLeft", ES->numval(real scr.r.min.x));
	reinitprop(scrobj, "availTop", ES->numval(real scr.r.min.y));
	reinitprop(scrobj, "colorDepth", ES->numval(real scr.depth));
	reinitprop(scrobj, "pixelDepth", ES->numval(real scr.depth));
	reinitprop(scrobj, "height", ES->numval(real scrh));
	reinitprop(scrobj, "width", ES->numval(real scrw));
	ES->put(ex, winobj, "screen", ES->objval(scrobj));

	# make the non-core constructor objects
#	improto := mkprototype(ex, specindex("Image"));
	o := ES->biinst(winobj, Builtin("Image", "Image", array[] of {"width", "height"}, 2),
			ex.funcproto, me);
	o.construct = o.call;

	o = ES->biinst(winobj, Builtin("Option", "Option", array[] of {"text", "value", "defaultSelected", "selected"}, 4),
			ex.funcproto, me);
	o.construct = o.call;
	defaultStatus = "";
	return (ex, locobj);
}

mknavobj(ex: ref Exec) : ref Obj
{
	navobj := mkhostobj(ex, "navigator");
	reinitprop(navobj, "appCodeName", ES->strval("Mozilla"));
	reinitprop(navobj, "appName", ES->strval("Netscape"));
#	reinitprop(navobj, "appVersion", ES->strval("3.0 (Inferno, U)"));
#	reinitprop(navobj, "userAgent", ES->strval("Mozilla/3.0 (Inferno; U)"));
	reinitprop(navobj, "appVersion", ES->strval("4.08 (Charon; Inferno)"));
	reinitprop(navobj, "userAgent", ES->strval("Mozilla/4.08 (Charon; Inferno)"));

	omty := getobj(ex, navobj, "mimeTypes");
	for(i := 0; i < len mimespecs; i++) {
		sp := mimespecs[i];
		v := mkhostobj(ex, "MimeType");
		reinitprop(v, "description", ES->strval(sp.description));
		reinitprop(v, "suffixes", ES->strval(sp.suffixes));
		reinitprop(v, "type", ES->strval(sp.ty));
		arrayput(ex, omty, i, sp.ty, ES->objval(v));
	}
	return navobj;
}

# Something changed in charon's frame tree
frametreechanged(t: ref Layout->Frame)
{
	rebuild : ref ScriptWin;
	if (top == nil) {
		(ex, loc) := makeframeex(t);
		top = ScriptWin.new(t, ex, loc, nil);
		rebuild = top;
	} else {
		rebuild = top.findbyframeid(t.id);
		# t could be new frame - need to look for parent
		while (rebuild == nil && t.parent != nil) {
			t = t.parent;
			rebuild = top.findbyframeid(t.id);
		}
		# if we haven't found it by now, it's not in the official Frame
		# hierarchy, so ignore it
	}
	if (rebuild != nil)
		wininstant(rebuild);
}

# Frame f has just been reset, then given a new doc field
# (with initial values for src, base, refresh, chset).
# We'll defer doing any actual building of the script objects
# until an evalscript; that way, pages that don't use scripts
# incur minimum penalties).
havenewdoc(f: ref Layout->Frame)
{
	sw := top.findbyframeid(f.id);
	if(sw != nil) {
		sw.inbuild = 1;
		sw.forms = nil;
		(sw.ex, sw.locobj) = makeframeex(f);
		if (sw.val != nil)
			# global object is referenced via parent.frames array
			sw.val.obj = sw.ex.global;
		wininstant(sw);
	}
}

# returns (error, output, value)
# error: error message
# output: result of any document.writes
# value: value of last statement executed (used for handling "javascript:" URL scheme)
#
evalscript(f: ref Layout->Frame, s: string) : (string, string, string)
{
	if (top.error)
		return("scripts disabled for this document", "", "");
	sw := top.findbyframeid(f.id);
	if (sw == nil)
		return("cannot find script window", "", "");
	if (sw.ex == nil)
		return("script window has no execution context", "", "");
	if(sw == nil || sw.ex == nil)
		return ("", "", "");

	ex := sw.ex;
	sw.docwriteout = "";
	expval := "";
	createdimages = nil;
	{
		xfertoscriptobjs(f, 1);
		if(s != "") {
			ex.error = nil;
			c := ES->eval(ex, s);
			if (c.kind == ES->CThrow && dbg) {
				sys->print("unhandled error:\n\tvalue:%s\n\treason:%s\n",
					ES->toString(ex, c.val), ex.error);
				sys->print("%s\n", s);
			}
			if (c.kind == ES->CNormal && c.val != nil) {
				if (ES->isstr(c.val))
					expval = c.val.str;
			}
			xferfromscriptobjs(f, 1);
			checknewlocs(top);
			checkopener();
		}
		w := sw.docwriteout;
		sw.docwriteout = nil;
		return("", w, expval);
	}exception exc{
	"*" =>
		if(dbg) {
			sys->print("fatal error %q executing evalscript: %s\nscript=", exc, ex.error);
			sa := array of byte s;
			sys->write(sys->fildes(1), sa, len sa);
			sys->print("\n");
		}
		top.error = 1;
		emsg := "Fatal error processing script\n\nScript processing suspended for this page";
		G->alert(emsg);
		w := sw.docwriteout;
		sw.docwriteout = nil;
		return (ex.error, w, "");
	}
}

xfertoscriptobjs(f: ref Layout->Frame, inbuild: int)
{
	sw := top.findbyframeid(f.id);
	if(sw == nil)
		return;
	ex := sw.ex;
	ow := ex.global;
	di := f.doc;

	for(el := di.events; el != nil; el = tl el) {
		e := hd el;
		hname := "";
		dhname := "";
		case e.attid {
		Lex->Aonblur =>
			hname = "onblur";
			di.evmask |= E->SEonblur;
		Lex->Aonerror =>
			hname = "onerror";
			di.evmask |= E->SEonerror;
		Lex->Aonfocus =>
			hname = "onfocus";
			di.evmask |= E->SEonfocus;
		Lex->Aonload =>
			hname = "onload";
			di.evmask |= E->SEonload;
		Lex->Aonresize =>
			hname = "onresize";
			di.evmask |= E->SEonresize;
		Lex->Aonunload =>
			hname = "onunload";
			di.evmask |= E->SEonunload;
		Lex->Aondblclick =>
			dhname = "ondblclick";
			di.evmask |= E->SEondblclick;
		Lex->Aonkeydown =>
			dhname = "onkeydown";
			di.evmask |= E->SEonkeydown;
		Lex->Aonkeypress =>
			dhname = "onkeypress";
			di.evmask |= E->SEonkeypress;
		Lex->Aonkeyup =>
			dhname = "onkeyup";
			di.evmask |= E->SEonkeyup;
		Lex->Aonmousedown =>
			dhname = "onmousedown";
			di.evmask |= E->SEonmousedown;
		Lex->Aonmouseup =>
			dhname = "onmouseup";
			di.evmask |= E->SEonmouseup;
		}
		if(hname != "")
			puthandler(ex, ow, hname, e.value);
		if(dhname != ""){
			od := getobj(ex, ow, "document");
			if(od == nil) {
				reinitprop(ow, "document", docinstant(ex, f));
				od = getobj(ex, ow, "document");
			}
			puthandler(ex, od, dhname, e.value);
		}
	}
	di.events = nil;

	od := getobj(ex, ow, "document");
	if(od == nil) {
		reinitprop(ow, "document", docinstant(ex, f));
		od = getobj(ex, ow, "document");
		CU->assert(od != nil);
	}
	else if(inbuild) {
		docfill(ex, od, f);
		ES->put(ex, od, "location", ES->objval(sw.locobj));
	}
	for(frml := sw.forms; frml != nil; frml = tl frml) {
		frm := hd frml;
		for (fldl := frm.fields; fldl != nil; fldl = tl fldl) {
			(fld, ofield) := hd fldl;
			if (ofield == nil)
				continue;
			if(fld.ctlid >= 0 && fld.ctlid < len f.controls) {
				pick c := f.controls[fld.ctlid] {
				Centry =>
					reinitprop(ofield, "value", ES->strval(c.s));
				Ccheckbox =>
					cv := ES->false;
					if(c.flags&Layout->CFactive)
						cv = ES->true;
					reinitprop(ofield, "checked", cv);
				Cselect =>
					for(i := 0; i < len c.options; i++) {
						if(c.options[i].selected) {
							reinitprop(ofield, "selectedIndex", ES->numval(real i));
							# hack for common mistake in scripts
							# (implemented by other browsers)
							opts := getobj(ex, ofield, "options");
							if (opts != nil)
								reinitprop(opts, "selectedIndex", ES->numval(real i));
						}
					}
				}
			}
		}
	}
	for(sil := sw.imgs; sil != nil; sil = tl sil) {
		si := hd sil;
		if(si.item.ci.complete != 0)
			reinitprop(si.obj, "complete", ES->true);
	}
}

xferfromscriptobjs(f: ref Layout->Frame, inbuild: int)
{
	sw := top.findbyframeid(f.id);
	if(sw == nil)
		return;
	ex := sw.ex;
	ow := ex.global;
	od := getobj(ex, ow, "document");
	if(od != nil) {
		if(inbuild) {
			di := f.doc;
			di.doctitle = strxfer(ex, od, "title", di.doctitle);
			di.background.color = colorxfer(ex, od, "bgColor", di.background.color);
			di.text = colorxfer(ex, od, "fgColor", di.text);
			di.alink = colorxfer(ex, od, "alinkColor", di.alink);
			di.link = colorxfer(ex, od, "linkColor", di.link);
			di.vlink = colorxfer(ex, od, "vlinkColor", di.vlink);
			if(createdimages != nil) {
				for(oil := createdimages; oil != nil; oil = tl oil) {
					oi := hd oil;
					vsrc := ES->get(ex, oi, "src");
					if(ES->isstr(vsrc)) {
						u := U->parse(vsrc.str);
						if(u.path != "") {
							u = U->mkabs(u, di.base);
							it := Item.newimage(di, u, nil, "", B->Anone,
								0, 0, 0, 0, 0, 0, 0, nil, nil, nil);
							di.images = it :: di.images;
						}
					}
				}
			}
		}
		else {
			for (ol := sw.imgrelocs; ol != nil; ol = tl ol) {
				oi := hd ol;
				vnewsrc := ES->get(ex, oi, "src");
				if(ES->isstr(vnewsrc) && vnewsrc.str != nil) {
					for(sil := sw.imgs; sil != nil; sil = tl sil) {
						si := hd sil;
						if(si.obj == oi) {
							f.swapimage(si.item, vnewsrc.str);
							break;
						}
					}
				}
			}
			sw.imgrelocs = nil;
		}
	}
}

# Check ScriptWin tree for non-empty newlocs.
# When found, generate a go event to the new place.
# If found, don't recurse into children, because those
# child frames are about to go away anyway.
# Otherwise, recurse into all kids -- this might generate
# multiple go events.
# BUG: if multiple events are generated, later ones will
# interrupt (STOP!) loading of pages specified by preceding
# events.  To fix, need to queue them up, probably in
# main charon module.
checknewlocs(sw: ref ScriptWin)
{
	if(sw.newloc != "") {
		E->evchan <-= ref Event.Ego(sw.newloc, sw.newloctarg, 0, E->EGnormal);
		sw.newloc = "";
	}
	else {
		for(l := sw.kids; l != nil; l = tl l)
			checknewlocs(hd l);
	}
}

checkopener()
{
	if(opener != nil && opener.newloc != "") {
		CH->sendopener(sys->sprint("L %s", opener.newloc));	# just location for now
		opener.newloc = "";
	}
	if(winclose)
		G->exitcharon();
}

# if e.anchorid >= 0	=> target is Link
# if e.fieldid > 0	=> target is FormField (and e.formid > 0)
# if e.formid > 0	=> target is Form (e.fieldid == -1)
# if e.imageid >= 0	=> target is Image
# otherwise		=> target is window
do_on(e: ref ScriptEvent)
{
	if(dbgdom)
		sys->print("do_on %d, frameid=%d, formid=%d, fieldid=%d, anchorid=%d, imageid=%d, x=%d, y=%d, which=%d\n",
			e.kind, e.frameid, e.formid, e.fieldid, e.anchorid, e.imageid, e.x, e.y, e.which);
	if (top.error) {
		if (dbgdom)
			sys->print("do_on() previous error prevents processing\n");
		if (e.reply != nil)
			e.reply <-= nil;
		jevchan <-= ref doneevent;
		return;
	}
	sw := top.findbyframeid(e.frameid);
	# BUG FIX: Frame can be reset by Charon main thread
	# between us getting its ref and using it
	# WARNING - xferfromscriptobjs() will not update non-ref-type members of frame adt
	# (currently not a problem) as updates will go to our copy
	f : ref Frame;
	if (sw != nil && !sw.inbuild) {
		f = ref *sw.frame;
		if (f.doc == nil)
			f = nil;
	}
	if (f == nil) {
		if(e.reply != nil)
			e.reply <-= nil;
		jevchan <-= ref doneevent;
		if (dbgdom)
			sys->print("do_on() failed to find frame %d\n", e.frameid);
		return;
	}
	ex := sw.ex;
	ow := ex.global;
	od := getobj(ex, ow, "document");
	sw.docwriteout = nil;
	
{
	# event target types
	TAnchor, TForm, TFormField, TImage, TDocument, TWindow, Tnone: con iota;
	ttype := Tnone;
	target, oform: ref Obj;
	if(e.anchorid >= 0) {
		ttype = TAnchor;
		target = getanchorobj(ex, e.frameid, e.anchorid);
	} else if(e.formid > 0) {
		oform = getformobj(ex, e.frameid, e.formid);
		if(e.fieldid > 0) {
			ttype = TFormField;
			target = getformfieldobj(e.frameid, e.formid, e.fieldid);
		} else {
			ttype = TForm;
			target = oform;
		}
	} else if(e.imageid >= 0) {
		ttype = TImage;
		target = getimageobj(ex, e.frameid, e.imageid);
	} else if(e.kind == E->SEondblclick || e.kind == E->SEonkeydown ||
		    e.kind == E->SEonkeypress || e.kind == E->SEonkeyup ||
		    e.kind == E->SEonmousedown || e.kind == E->SEonmouseup){
		ttype = TDocument;
		target = od;
	} else {
		ttype = TWindow;
		target = ow;
	}
	if(target != nil) {
		oscript: ref Obj;
		scrname := "";
		case e.kind {
		E->SEonabort =>
			scrname = "onabort";
		E->SEonblur =>
			scrname = "onblur";
		E->SEonchange =>
			scrname = "onchange";
		E->SEonclick =>
			scrname = "onclick";
		E->SEondblclick =>
			scrname = "ondblclick";
		E->SEonerror =>
			scrname = "onerror";
		E->SEonfocus =>
			scrname = "onfocus";
		E->SEonkeydown =>
			scrname = "onkeydown";
		E->SEonkeypress =>
			scrname = "onkeypress";
		E->SEonkeyup =>
			scrname = "onkeyup";
		E->SEonload =>
			scrname = "onload";
		E->SEonmousedown =>
			scrname = "onmousedown";
		E->SEonmouseout =>
			scrname = "onmouseout";
		E->SEonmouseover =>
			scrname = "onmouseover";
		E->SEonmouseup =>
			scrname = "onmouseup";
		E->SEonreset =>
			scrname = "onreset";
		E->SEonresize =>
			scrname = "onresize";
		E->SEonselect =>
			scrname = "onselect";
		E->SEonsubmit =>
			scrname = "onsubmit";
		E->SEonunload =>
			scrname = "onunload";
		E->SEtimeout or
		E->SEinterval =>
			oscript = dotimeout(ex, target, e);
		E->SEscript =>
			# TODO - handle document text from evalscript
			# need to determine if document is 'open' or not.
			(nil, nil, val) := evalscript(f, e.script);
			if (e.reply != nil)
				e.reply <- = val;
			e.reply = nil;
		}
		if(scrname != "")
			oscript = getobj(ex, target, scrname);
		if(oscript != nil) {
			xfertoscriptobjs(f, 0);
			if(dbgdom)
				sys->print("calling script\n");
			# establish scope chain per Rhino p. 287 (3rd edition)
			oldsc := ex.scopechain;
			sc := ow :: nil;
			if(ttype != TWindow) {
				sc = od :: sc;
				if(ttype == TFormField)
					sc = oform :: sc;
				if(ttype != TDocument)
					sc = target :: sc;
			}
			ex.scopechain = sc;
			v := ES->call(ex, oscript, target, nil, 1).val;
			# 'fix' for onsubmit
			# JS references state that if the handler returns false
			# then the action is cancelled.
			# other browsers interpret this as "if and only if the handler
			# returns false."
			# When a function completes normally without returning a value
			# its value is 'undefined', toBoolean(undefined) = false
			if (v == ES->undefined)
				v = ES->true;
			else
				v = ES->toBoolean(ex, v);
			ex.scopechain = oldsc;
			# onreset/onsubmit reply channel
			if(e.reply != nil) {
				ans : string;
				if(v == ES->true)
					ans = "true";
				e.reply <-= ans;
				e.reply = nil;
			}
			xferfromscriptobjs(f, 0);
			checknewlocs(top);
			checkopener();

			if (ttype == TFormField && e.kind == E->SEonclick && v == ES->true)
				E->evchan <-= ref Event.Eformfield(e.frameid, e.formid, e.fieldid, E->EFFclick);
			if (ttype == TAnchor && e.kind == E->SEonclick && v == ES->true) {
				gohref := getstr(ex, target, "href");
				gotarget := getstr(ex, target, "target");
				if (gotarget == "")
					gotarget = "_self";
				E->evchan <-= ref Event.Ego(gohref, gotarget, 0, E->EGnormal);
			}
		}
	}
	if(e.reply != nil)
		e.reply <-= nil;
	checkdocwrite(top);
	jevchan <-= ref doneevent;
}
exception exc{
	"*" =>
		if (exc == "throw") {
			# ignore ecmascript runtime errors
			if(dbgdom)
				sys->print("error executing 'on' handler: %s\n", ex.error);
		} else {
			# fatal error
			top.error = 1;
			emsg := "Fatal error in script ("+exc+"):\n" + ex.error + "\n";
			G->alert(emsg);
		}
		if(e.reply != nil)
			e.reply <-= nil;
		jevchan <-= ref doneevent;
		return;
}
}

xferframeset(sw : ref ScriptWin)
{
	if (!sw.inbuild)
		xfertoscriptobjs(sw.frame, 1);
	for (k := sw.kids; k != nil; k = tl k)
		xferframeset(hd k);
}

framedone(f : ref Frame, hasscripts : int)
{
	sw := top.findbyframeid(f.id);
	if (sw != nil) {
		if (!top.active && hasscripts) {
			# need to transfer entire frame tree
			# as one frame can reference objects in another
			xferframeset(top);
		}
		sw.active |= hasscripts;
		top.active |= hasscripts;
		if (top.active)
			xfertoscriptobjs(f, 1);
		sw.inbuild = 0;
	}
}

checkdocwrite(sw : ref ScriptWin) : int
{
	if (sw.inbuild)
		return 0;

	if (sw.docwriteout != nil) {
		# The URL is bogus - not sure what the correct value should be
		ev := ref Event.Esettext(sw.frame.id, sw.frame.src, sw.docwriteout);
		sw.docwriteout = "";
		E->evchan <- = ev;
		return 1;
	}
	for (k := sw.kids; k != nil; k = tl k)
		if (checkdocwrite(hd k))
			break;
	return 0;
}

#
# interface for host objects
#
get(ex: ref Exec, o: ref Obj, property: string): ref Val
{
	if(o.class == "document" && property == "cookie") {
		ans := "";
		target := top.findbyobj(o);
		if(target != nil) {
			url := target.frame.doc.src;
			ans = CU->getcookies(url.host, url.path, url.scheme == "https");
		}
		return ES->strval(ans);
	}
	if(o.class == "Window" && property == "opener"){
		if(!CH->hasopener() || top.ex.global != o)
			v := ES->undefined;
		else{
			if(opener == nil)
				opener = ScriptWin.dummy();
			v = ES->objval(opener.ex.global);
		}
		reinitprop(o, "opener", v);
	}
	return ES->get(ex, o, property);
}


put(ex: ref Exec, o: ref Obj, property: string, val: ref Val)
{
	if(dbgdom)
		sys->print("put property %s in cobj of class %s\n", property, o.class);

	url : ref Parsedurl;
	target : ref ScriptWin;
	str := ES->toString(ex, val);
	ev := E->SEnone;

	case o.class {
	"Array" =>
		# we 'host' the Formfield.options array so as we can
		# track changes to the options list
		vformfield := ES->get(ex, o, "@PRIVformfield");
		if (!ES->isobj(vformfield))
			# not one of our 'options' arrays
			break;
		ix := prop2index(property);
		if (property != "length" && ix == -1)
			# not a property that affects us
			break;
		oformfield := vformfield.obj;
		oform := getobj(ex, oformfield, "form");
		if (oform == nil)
			break;
		ES->put(ex, o, property, val);
		if (ES->isobj(val) && val.obj.class == "Option") {
			ES->put(ex, val.obj, "@PRIVformfield", vformfield);
			ES->put(ex, val.obj, "form", ES->objval(oform));
			reinitprop(val.obj, "index", ES->numval(real ix));
		}
		updateffopts(ex, oform, oformfield, ix);
		return;
	"Window" =>
		case property {
		"defaultStatus" or
		"status" =>
			if(ES->isstr(val)) {
				if(property == "defaultStatus")
					defaultStatus = val.str;
				G->setstatus(val.str);
			}
		"location" =>
			target = top.findbyobj(o);
			if (target == nil)
				break;
			url = U->parse(str);
			# TODO: be more defensive
			url = U->mkabs(url, target.frame.doc.base);
		"name" =>
			sw := top.findbyobj(o);
			if (sw == nil)
				break;
			name := ES->toString(ex, val);
			if (sw.parent != nil) {
				w := sw.parent.ex.global;
				v := sw.val;
				if (sw.frame.name != nil)
					ES->delete(ex, w, sw.frame.name);
				ES->varinstant(w, 0, name, ref RefVal(v));
			}
			# Window.name is used for determining TARGET of <A> etc.
			# update Charon's Frame info so as new name gets used properly
			sw.frame.name = name;
		"offscreenBuffering" =>
			if(ES->isstr(val) || val == ES->true || val == ES->false){
			}	
		"onblur" =>
			ev = E->SEonblur;
		"onerror" =>
			ev = E->SEonerror;
		"onfocus" =>
			ev = E->SEonfocus;
		"onload" =>
			ev = E->SEonload;
		"onresize" =>
			ev = E->SEonresize;
		"onunload" =>
			ev = E->SEonunload;
		"opener" =>
			;
		}
		if(ev != E->SEnone) {
			target = top.findbyobj(o);
			if(target == nil)
				break;
			di := target.frame.doc;
			if(!ES->isobj(val) || val.obj.call == nil)
				di.evmask &= ~ev;
			else
				di.evmask |= ev;
		}
	"Link" =>
		case property {
		"onclick" =>
			ev = E->SEonclick;
		"ondblclick" =>
			ev = E->SEondblclick;
		"onkeydown" =>
			ev = E->SEonkeydown;
		"onkeypress" =>
			ev = E->SEonkeypress;
		"onkeyup" =>
			ev = E->SEonkeyup;
		"onmousedown" =>
			ev = E->SEonmousedown;
		"onmouseout" =>
			ev = E->SEonmouseout;
		"onmouseover" =>
			ev = E->SEonmouseover;
		"onmouseup" =>
			ev = E->SEonmouseup;
		}
		if(ev != E->SEnone) {
			vframeid := ES->get(ex, o, "@PRIVframeid");
			vanchorid := ES->get(ex, o, "@PRIVanchorid");
			if(!ES->isnum(vframeid) || !ES->isnum(vanchorid))
				break;
			frameid := ES->toInt32(ex, vframeid);
			anchorid := ES->toInt32(ex, vanchorid);
			target = top.findbyframeid(frameid);
			if(target == nil)
				break;
			anchor: ref B->Anchor;
			for(al := target.frame.doc.anchors; al != nil; al = tl al) {
				a := hd al;
				if(a.index == anchorid) {
					anchor = a;
					break;
				}
			}
			if(anchor == nil)
				break;
			if(!ES->isobj(val) || val.obj.call == nil)
				anchor.evmask &= ~ev;
			else
				anchor.evmask |= ev;
		}
	"Location" =>
		target = top.findbyobj(o);
		if (target == nil) {
			break;
		}
		url = ref *target.frame.doc.src;
		case property {
		"hash" =>
			if (str != nil && str[0] == '#')
				str = str[1:];
			url.frag = str;
		"host" =>
			# host:port
			(h, p) := S->splitl(str, ":");
			if (p != nil)
				p = p[1:];
			if (h != nil)
				url.host = h;
			if (p != nil)
				url.port = p;
		"hostname" =>
			url.host = str;
		"href" or
		"pathname" =>
			url = U->mkabs(U->parse(str), target.frame.doc.base);
		"port" =>
			url.port = str;
		"protocol" =>
			url.scheme = S->tolower(str);
		"search" =>
			url.query = str;
		* =>
			url = nil;
		}
	"Image" =>
		case property {
		"src" or
		"lowsrc" =>
			# making URLs absolute matches Netscape
			target = top.findbyobj(o);
			if(target == nil)
				break;
			url = U->mkabs(U->parse(str), target.frame.doc.base);
			val = ES->strval(url.tostring());
			target.imgrelocs = o :: target.imgrelocs;
			url = nil;
		"onabort" =>
			ev = E->SEonabort;
		"ondblclick" =>
			ev = E->SEondblclick;
		"onkeydown" =>
			ev = E->SEonkeydown;
		"onkeypress" =>
			ev = E->SEonkeypress;
		"onkeyup" =>
			ev = E->SEonkeyup;
		"onerror" =>
			ev = E->SEonerror;
		"onload" =>
			ev = E->SEonload;
		"onmousedown" =>
			ev = E->SEonmousedown;
		"onmouseout" =>
			ev = E->SEonmouseout;
		"onmouseover" =>
			ev = E->SEonmouseover;
		"onmouseup" =>
			ev = E->SEonmouseup;
		}
		if(ev != E->SEnone) {
			target = top.findbyobj(o);
			if(target == nil)
				break;
			vimageid := ES->get(ex, o, "@PRIVimageid");
			if(!ES->isnum(vimageid))
				break;
			imageid := ES->toInt32(ex, vimageid);
			image: ref (Build->Item).Iimage;
		forloop:
			for(il := target.frame.doc.images; il != nil; il = tl il) {
				pick im := hd il {
				Iimage =>
					if(im.imageid == imageid) {
						image = im;
						break forloop;
					}
				}
			}
			# BUG: if image has no genattr then the event handler update
			# will not be done - can never set a handler for an image that
			# didn't have a handler
			if(image == nil || image.genattr == nil)
				break;
			if(!ES->isobj(val) || val.obj.call == nil)
				image.genattr.evmask &= ~ev;
			else
				image.genattr.evmask |= ev;
		}
	"Form" =>
		action := "";
		case property {
		"onreset" =>
			ev = E->SEonreset;
		"onsubmit" =>
			ev = E->SEonsubmit;
		"action" =>
			action = str;
		* =>
			break;
		}
		vframeid := ES->get(ex, o, "@PRIVframeid");
		vformid := ES->get(ex, o, "@PRIVformid");
		if(!ES->isnum(vframeid) || !ES->isnum(vformid))
			break;
		frameid := ES->toInt32(ex, vframeid);
		formid := ES->toInt32(ex, vformid);
		target = top.findbyframeid(frameid);
		if(target == nil)
			break;
		form: ref B->Form;
		for(fl := target.frame.doc.forms; fl != nil; fl = tl fl) {
			f := hd fl;
			if(f.formid == formid) {
				form = f;
				break;
			}
		}
		if(form == nil)
			break;
		if (ev != E->SEnone) {
			if(!ES->isobj(val) || val.obj.call == nil)
				form.evmask &= ~ev;
			else
				form.evmask |= ev;
			break;
		}
		if (action != "")
			form.action = U->mkabs(U->parse(action), target.frame.doc.base);
	"FormField" =>
		oform := getobj(ex, o, "form");
		vframeid := ES->get(ex, oform, "@PRIVframeid");
		vformid := ES->get(ex, oform, "@PRIVformid");
		vfieldid := ES->get(ex, o, "@PRIVfieldid");
		if(!ES->isnum(vframeid) || !ES->isnum(vformid) || !ES->isnum(vfieldid))
			break;
		frameid := ES->toInt32(ex, vframeid);
		formid := ES->toInt32(ex, vformid);
		fieldid := ES->toInt32(ex, vfieldid);
		target = top.findbyframeid(frameid);
		if(target == nil)
			break;
		form: ref B->Form;
		for(fl := target.frame.doc.forms; fl != nil; fl = tl fl) {
			f := hd fl;
			if(f.formid == formid) {
				form = f;
				break;
			}
		}
		if(form == nil)
			break;
		field: ref B->Formfield;
		for(ffl := form.fields; ffl != nil; ffl = tl ffl) {
			ff := hd ffl;
			if(ff.fieldid == fieldid) {
				field = ff;
			break;
			}
		}
		if(field == nil)
			break;
		case property {
		"onblur" =>
			ev = E->SEonblur;
		"onchange" =>
			ev = E->SEonchange;
		"onclick" =>
			ev = E->SEonclick;
		"ondblclick" =>
			ev = E->SEondblclick;
		"onfocus" =>
			ev = E->SEonfocus;
		"onkeydown" =>
			ev = E->SEonkeydown;
		"onkeypress" =>
			ev = E->SEonkeypress;
		"onkeyup" =>
			ev = E->SEonkeyup;
		"onmousedown" =>
			ev = E->SEonmousedown;
		"onmouseup" =>
			ev = E->SEonmouseup;
		"onselect" =>
			ev = E->SEonselect;
		"value" =>
			field.value = str;
			if(target.frame.controls == nil ||
			   field.ctlid < 0 ||
			   field.ctlid > len target.frame.controls){
				break;
			}
			c := target.frame.controls[field.ctlid];
			pick ctl := c {
			Centry =>
				ctl.s = str;
				ctl.sel = (0, 0);
				E->evchan <-= ref Event.Eformfield(frameid, formid, fieldid, E->EFFredraw);
			}
		}

		if(ev != E->SEnone) {
			if(!ES->isobj(val) || val.obj.call == nil)
				field.evmask &= ~ev;
			else
				field.evmask |= ev;
		}
	"document" =>
		case property {
		"location" =>
			target = top.findbyobj(o);
			if (target == nil)
				break;
			# TODO: be more defensive
			url = U->mkabs(U->parse(str), target.frame.doc.base);
		"cookie" =>
			target = top.findbyobj(o);
			if(target != nil && (CU->config).docookies > 0) {
				url = target.frame.doc.src;
				CU->setcookie(url.host, url.path, str);
			}
			return;
		"ondblclick" =>
			ev = E->SEondblclick;
		"onkeydown" =>
			ev = E->SEonkeydown;
		"onkeypress" =>
			ev = E->SEonkeypress;
		"onkeyup" =>
			ev = E->SEonkeyup;
		"onmousedown" =>
			ev = E->SEonmousedown;
		"onmouseup" =>
			ev = E->SEonmouseup;
		}
		if(ev != E->SEnone){
			target = top.findbyobj(o);
			if(target == nil)
				break;
			di := target.frame.doc;
			if(!ES->isobj(val) || val.obj.call == nil)
				di.evmask &= ~ev;
			else
				di.evmask |= ev;
		}
	"Option" =>
		vformfield := ES->get(ex, o, "@PRIVformfield");
		vindex := ES->get(ex, o, "index");
		if (!ES->isobj(vformfield) || !ES->isnum(vindex))
			# not one of our 'options' objects
			break;
		oformfield := vformfield.obj;
		oform := getobj(ex, oformfield, "form");
		if (oform == nil)
			break;
		ES->put(ex, o, property, val);
		index := ES->toInt32(ex, vindex);
		updateffopts(ex, oform, oformfield, index);
	}
	ES->put(ex, o, property, val);

	if (url != nil && target != nil) {
		if (!CU->urlequal(url, target.frame.doc.src)) {
			target.newloc = url.tostring();
			target.newloctarg = "_top";
			if(target.frame != nil)
				target.newloctarg = target.frame.name;
		}
	}
}

canput(ex: ref Exec, o: ref Obj, property: string): ref Val
{
	return ES->canput(ex, o, property);
}

hasproperty(ex: ref Exec, o: ref Obj, property: string): ref Val
{
	return ES->hasproperty(ex, o, property);
}

delete(ex: ref Exec, o: ref Obj, property: string)
{
	ES->delete(ex, o, property);
}

defaultval(ex: ref Exec, o: ref Obj, tyhint: int): ref Val
{
	return ES->defaultval(ex, o, tyhint);
}

call(ex: ref Exec, func, this: ref Obj, args: array of ref Val, nil: int): ref Ref
{
	if(dbgdom)
		sys->print("call %x (class %s), val %s\n", func, func.class, func.val.str);
	ans := ES->valref(ES->true);
	case func.val.str{
	"document.prototype.open" =>
		sw := top.findbyobj(this);
		if (sw != nil)
			sw.docwriteout = "";
	"document.prototype.close" =>
		# ignore for now
		;
	"document.prototype.write" =>
		sw := top.findbyobj(this);
		if (sw != nil) {
			for (ai := 0; ai < len args; ai++)
				sw.docwriteout += ES->toString(ex, ES->biarg(args, ai));
		}
	"document.prototype.writeln" =>
		sw := top.findbyobj(this);
		if (sw != nil) {
			for (ai := 0; ai < len args; ai++)
				sw.docwriteout += ES->toString(ex, ES->biarg(args, ai));
			sw.docwriteout += "\n";
		}
	"navigator.prototype.javaEnabled" or
	"navigator.prototype.taintEnabled" =>
		ans = ES->valref(ES->false);
	"Form.prototype.reset" or "Form.prototype.submit"=>
		vframeid := ES->get(ex, this, "@PRIVframeid");
		vformid := ES->get(ex, this, "@PRIVformid");
		if(ES->isnum(vframeid) && ES->isnum(vformid)) {
			frameid := ES->toInt32(ex, vframeid);
			formid := ES->toInt32(ex, vformid);
			ftype : int;
			if(func.val.str == "Form.prototype.reset")
				ftype = E->EFreset;
			else
				ftype = E->EFsubmit;
			E->evchan <-= ref Event.Eform(frameid, formid, ftype);
		}
	"FormField.prototype.blur" or
	"FormField.prototype.click" or
	"FormField.prototype.focus" or
	"FormField.prototype.select" =>
		oform := getobj(ex, this, "form");
		vformid := ES->get(ex, oform, "@PRIVformid");
		vframeid := ES->get(ex, oform, "@PRIVframeid");
		vfieldid := ES->get(ex, this, "@PRIVfieldid");
		if(ES->isnum(vframeid) && ES->isnum(vformid) && ES->isnum(vfieldid)) {
			frameid := ES->toInt32(ex, vframeid);
			formid := ES->toInt32(ex, vformid);
			fieldid := ES->toInt32(ex, vfieldid);
			fftype : int;
			case func.val.str{
			"FormField.prototype.blur" =>
				fftype = E->EFFblur;
			"FormField.prototype.click" =>
				fftype = E->EFFclick;
			"FormField.prototype.focus" =>
				fftype = E->EFFfocus;
			"FormField.prototype.select" =>
				fftype = E->EFFselect;
			* =>
				fftype = E->EFFnone;
			}
			E->evchan <-= ref Event.Eformfield(frameid, formid, fieldid, fftype);
		}
	"History.prototype.back" =>
		E->evchan <-= ref Event.Ego("", "", 0, E->EGback);
	"History.prototype.forward" =>
		E->evchan <-= ref Event.Ego("", "", 0, E->EGforward);
	"History.prototype.go" =>
		ego : ref Event.Ego;
		v := ES->biarg(args, 0);
		if(ES->isstr(v))
			ego = ref Event.Ego(v.str, "", 0, E->EGlocation);
		else if(ES->isnum(v)) {
			delta := ES->toInt32(ex, v);
			case delta {
			-1 =>
				ego = ref Event.Ego("", "", 0, E->EGback);
			0 =>
				ego = ref Event.Ego("", "", 0, E->EGreload);
			1 =>
				ego = ref Event.Ego("", "", 0, E->EGforward);
			* =>
				ego = ref Event.Ego("", "", delta,  E->EGdelta);
			}
		}
		if(ego != nil)
			E->evchan <-= ego;
	"Location.prototype.reload" =>
		# ignore 'force' argument for now
		E->evchan <-= ref Event.Ego("", "", 0, E->EGreload);
	"Location.prototype.replace" =>
		v := ES->biarg(args, 0);
		if(ES->isstr(v)) {
			sw := top.findbyobj(this);
			if(sw == nil)
				fname := "_top";
			else
				fname = sw.frame.name;
			if (v.str != nil) {
				url := U->mkabs(U->parse(v.str), sw.frame.doc.base);
				E->evchan <-= ref Event.Ego(url.tostring(), fname, 0, E->EGreplace);
			}
		}
	"Window.prototype.alert" =>
		G->alert(ES->toString(ex, ES->biarg(args, 0)));
	"Window.prototype.blur" =>
		;
#		sw := top.findbyobj(this);
#		if (sw != nil)
#			E->evchan <-= ref Event.Eframefocus(sw.frame.id, 0);
	
	"Window.prototype.clearTimeout" or
	"Window.prototype.clearInterval" =>
		v := ES->biarg(args, 0);
		id := ES->toInt32(ex, v);
		clrtimeout(ex, this, id);
	"Window.prototype.close" =>
		if(this == top.ex.global)
			winclose = 1;
		# no-op
		;
	"Window.prototype.confirm" =>
		code := G->confirm(ES->toString(ex, ES->biarg(args, 0)));
		if(code != 1)
			ans = ES->valref(ES->false);
	"Window.prototype.focus" =>
		;
#		sw := top.findbyobj(this);
#		if (sw != nil)
#			E->evchan <-= ref Event.Eframefocus(sw.frame.id, 1);
	"Window.prototype.moveBy" or
	"Window.prototype.moveTo" =>
		# no-op
		;
	"Window.prototype.open" =>
		if (dbgdom)
			sys->print("window.open called\n");
		u := ES->toString(ex, ES->biarg(args, 0));
		n := ES->toString(ex, ES->biarg(args, 1));
		sw : ref ScriptWin;
		if (n != "")
			sw = top.findbyname(n);
		newch := 0;
		if (sw == nil){
			sw = top;
			newch = 1;
		}
		if(u != "") {
			# Want to replace window by navigation to u
			sw.newloc = u;
			if (sw.frame.name != "")
				sw.newloctarg = sw.frame.name;
			else
				sw.newloctarg = "_top";
			url : ref U->Parsedurl;
			if (sw.frame.doc != nil && sw.frame.doc.base != nil)
				url = U->mkabs(U->parse(u), sw.frame.doc.base);
			else 
				url = CU->makeabsurl(u);
			sw.newloc = url.tostring();
		}
		if(newch){
			# create dummy window
			dw := ScriptWin.dummy();
			spawn newcharon(sw.newloc, sw.newloctarg, sw);
			sw.newloc = "";
			sw.newloctarg = "";
			ans = ES->valref(dw.val);
		}
		else
			ans = ES->valref(sw.val);
	"Window.prototype.prompt" =>
		msg := ES->toString(ex, ES->biarg(args, 0));
		dflt := ES->toString(ex, ES->biarg(args, 1));
		(code, input) := G->prompt(msg, dflt);
		v := ES->null;
		if(code == 1)
			v = ES->strval(input);
		ans = ES->valref(v);
	"Window.prototype.resizeBy" or
	"Window.prototype.resizeTo" =>
		# no-op
		;
	"Window.prototype.scroll" or
	"Window.prototype.scrollTo" =>
		# scroll is done via an event to avoid race in calls to
		# Layout->fixframegeom() [made by scroll code]
		sw := top.findbyobj(this);
		if (sw != nil) {
			(xv, yv) := (ES->biarg(args, 0), ES->biarg(args, 1));
			pt := Draw->Point(ES->toInt32(ex, xv), ES->toInt32(ex, yv));
			E->evchan <-= ref Event.Escroll(sw.frame.id, pt);
		}
	"Window.prototype.scrollBy" =>
		sw := top.findbyobj(this);
		if (sw != nil) {
			(dxv, dyv) := (ES->biarg(args, 0), ES->biarg(args, 1));
			pt := Draw->Point(ES->toInt32(ex, dxv), ES->toInt32(ex, dyv));
			E->evchan <-= ref Event.Escrollr(sw.frame.id, pt);
		}
	"Window.prototype.setTimeout" =>
		(v1, v2) := (ES->biarg(args, 0), ES->biarg(args, 1));
		cmd := ES->toString(ex, v1);
		ms := ES->toInt32(ex, v2);
		id := addtimeout(ex, this, cmd, ms, E->SEtimeout);
		ans = ES->valref(ES->numval(real id));
	"Window.prototype.setInterval" =>
		(v1, v2) := (ES->biarg(args, 0), ES->biarg(args, 1));
		cmd := ES->toString(ex, v1);
		ms := ES->toInt32(ex, v2);
		id := addtimeout(ex, this, cmd, ms, E->SEinterval);
		ans = ES->valref(ES->numval(real id));
	* =>
		ES->runtime(ex, nil, "unknown or unimplemented func "+func.val.str+" in host call");
		return nil;
	}
	return ans;
}

construct(ex: ref Exec, func: ref Obj, args: array of ref Val): ref Obj
{
	if(dbgdom)
		sys->print("construct %x (class %s), val %s\n", func, func.class, func.val.str);
	params: array of string;
	o: ref Obj;
#sys->print("Construct(%s)\n", func.val.str);
	case func.val.str {
	"Image" =>
		o = mkhostobj(ex, "Image");
		params = array [] of {"width", "height"};
		createdimages = o :: createdimages;
	"Option" =>
		o = mkhostobj(ex, "Option");
		params = array [] of {"text", "value", "defaultSelected", "selected"};
	* =>
		return nil;
	}
	for (i := 0; i < len args && i < len params; i++)
		reinitprop(o, params[i], args[i]);
	return o;
}

updateffopts(ex: ref Exec, oform, oformfield: ref Obj, ix: int)
{
	vframeid := ES->get(ex, oform, "@PRIVframeid");
	vformid := ES->get(ex, oform, "@PRIVformid");
	vfieldid := ES->get(ex, oformfield, "@PRIVfieldid");
	if(!ES->isnum(vframeid) || !ES->isnum(vformid) || !ES->isnum(vfieldid))
		return;
	frameid := ES->toInt32(ex, vframeid);
	formid := ES->toInt32(ex, vformid);
	fieldid := ES->toInt32(ex, vfieldid);

	target := top.findbyframeid(frameid);
	if(target == nil)
		return;
	form: ref B->Form;
	for(fl := target.frame.doc.forms; fl != nil; fl = tl fl) {
		f := hd fl;
		if(f.formid == formid) {
			form = f;
			break;
		}
	}
	if(form == nil)
		return;
	field: ref B->Formfield;
	for(ffl := form.fields; ffl != nil; ffl = tl ffl) {
		ff := hd ffl;
		if(ff.fieldid == fieldid) {
			field = ff;
			break;
		}
	}
	if(field == nil)
		return;

	selctl : ref Control.Cselect;
	pick ctl := target.frame.controls[field.ctlid] {
	Cselect =>
		selctl = ctl;
	* =>
		return;
	}

	(opts, nopts) := getarraywithlen(ex, oformfield, "options");
	if (opts == nil)
		return;
	optl: list of ref B->Option;
	selobj, firstobj: ref Obj;
	selopt, firstopt: ref B->Option;
	noptl := 0;
	for (i := 0; i < nopts; i++) {
		vopt := ES->get(ex, opts, string i);
		if (!ES->isobj(vopt) || vopt.obj.class != "Option")
			continue;
		oopt := vopt.obj;
		sel := ES->get(ex, oopt, "selected") == ES->true;
		val := ES->toString(ex, ES->get(ex, oopt, "value"));
		text := ES->toString(ex, ES->get(ex, oopt, "text"));
		option := ref B->Option(sel, val, text);
		optl = option :: optl;
		if (noptl++ == 0) {
			firstobj = oopt;
			firstopt = option;
		}
		if (sel && (selobj == nil || ix == i)) {
			selobj = oopt;
			selopt = option;
		}
		if (! int(field.flags & B->FFmultiple)) {
			ES->put(ex, oopt, "selected", ES->false);
			option.selected = 0;
		}
	}
	if (selobj != nil)
		ES->put(ex, selobj, "selected", ES->true);
	else if (firstobj != nil)
		ES->put(ex, firstobj, "selected", ES->true);
	if (selopt != nil)
		selopt.selected = 1;
	else if (firstopt != nil)
		firstopt.selected = 1;
	opta := array [noptl] of B->Option;
	for (i = noptl - 1; i >= 0; i--)
		(opta[i], optl) = (*hd optl, tl optl);
	# race here with charon.b:form_submit() and layout code
	selctl.options = opta;
	E->evchan <-= ref Event.Eformfield(frameid, formid, fieldid, E->EFFredraw);
}

timeout(e : ref ScriptEvent, ms : int)
{
	sys->sleep(ms);
	jevchan <- = e;
}

# BUGS
#	cannot set a timeout for a window just created by window.open()
#	because it will not have an entry in the ScriptWin tree
#	(This is really a problem with the ScriptEvent adt only taking a frame id)
#
addtimeout(ex : ref Exec, win : ref Obj, cmd : string, ms : int, evk: int) : int
{
	sw := top.findbyobj(win);
	if (sw == nil || cmd == nil || ms <= 0)
		return -1;

	# check for timeout handler array, create if doesn't exist
	(toa, n) := getarraywithlen(ex, win, "@PRIVtoa");
	if (toa == nil) {
		toa = ES->mkobj(ex.arrayproto, "Array");
		ES->varinstant(toa, ES->DontEnum|ES->DontDelete, "length", ref RefVal(ES->numval(0.)));
		ES->varinstant(win, ES->DontEnum|ES->DontDelete, "@PRIVtoa", ref RefVal(ES->objval(toa)));
	}
	# find first free handler
	for (ix := 0; ix < n; ix++) {
		hv := ES->get(ex, toa, string ix);

		if (hv == nil)
			break;
		# val == null		Timeout has been cancelled, but timer still running
		# val == undefined	Timeout has expired
		if (hv == ES->undefined)
			break;
	}

	# construct a private handler for the timeout
	# The code is always executed in the scope of the window object
	# for which the timeout is being set.
	oldsc := ex.scopechain;
	ex.scopechain = win :: nil;
	ES->eval(ex, "function PRIVhandler() {" + cmd + "}");
	hobj := getobj(ex, win, "PRIVhandler");
	ex.scopechain = oldsc;
	if(hobj == nil)
		return -1;
	ES->put(ex, toa, string ix, ES->objval(hobj));
	ev := ref ScriptEvent(evk, sw.frame.id, -1, -1, -1, -1, 0, 0, ix, nil, nil, ms);
	spawn timeout(ev, ms);
	return ix;
}

dotimeout(ex : ref Exec, win : ref Obj, e: ref ScriptEvent) : ref Ecmascript->Obj
{
	id := e.which;
	if (id < 0)
		return nil;

	(toa, n) := getarraywithlen(ex, win, "@PRIVtoa");
	if (toa == nil || id >= n)
		return nil;

	handler := getobj(ex, toa, string id);
	if (handler == nil)
		return nil;
	if(e.kind == E->SEinterval){
		ev := ref ScriptEvent;
		*ev = *e;
		spawn timeout(ev, e.ms);
		return handler;
	}
	if (id == n-1)
		ES->put(ex, toa, "length", ES->numval(real (n-1)));
	else
		ES->put(ex, toa, string id, ES->undefined);
	return handler;
}

clrtimeout(ex : ref Exec, win : ref Obj, id : int)
{
	if (id < 0)
		return;
	(toa, n) := getarraywithlen(ex, win, "@PRIVtoa");
	if (toa == nil || id >= n)
		return;

	ES->put(ex, toa, string id, ES->null);
}

# Make a host object with given class.
# Get the prototype from the objspecs array
# (if none yet, make one up and install the methods).
# Put in required properties, with undefined values initially.
# If mainex is nil (it will be for bootstrapping the initial object),
# the prototype has to be filled in later.
mkhostobj(ex : ref Exec, class: string) : ref Obj
{
	ci := specindex(class);
	proto : ref Obj;
	if(ex != nil)
		proto = mkprototype(ex, ci);
	ans := ES->mkobj(proto, class);
	initprops(ex, ans, objspecs[ci].props);
	ans.host = me;
	return ans;
}

initprops(ex : ref Exec, o: ref Obj, props: array of PropSpec)
{
	if(props == nil)
		return;
	for(i := 0; i < len props; i++) {
		v := ES->undefined;
		case props[i].initval {
		IVundef =>
			v = ES->undefined;
		IVnull =>
			v = ES->null;
		IVtrue =>
			v = ES->true;
		IVfalse =>
			v = ES->false;
		IVnullstr =>
			v = nullstrval;
		IVzero =>
			v = zeroval;
		IVzerostr =>
			v = zerostrval;
		IVarray =>
			# need a separate one for each array,
			# since we'll update these rather than replacing
			ao := ES->mkobj(ex.arrayproto, "Array");
			ES->varinstant(ao, ES->DontEnum|ES->DontDelete, "length", ref RefVal(ES->numval(0.)));
			v = ES->objval(ao);
		* =>
			CU->assert(0);
		}
		ES->varinstant(o, props[i].attr | ES->DontDelete, props[i].name, ref RefVal(v));
	}
}

# Return index into objspecs where class is specified
specindex(class: string) : int
{
	for(i := 0; i < len objspecs; i++)
		if(objspecs[i].name == class)
			break;
	if(i == len objspecs)
		CU->raisex("EXInternal: couldn't find host object class " + class);
	return i;
}

# Make a prototype for host object specified by objspecs[ci]
mkprototype(ex : ref Exec, ci : int) : ref Obj
{
	CU->assert(ex != nil);
	class := objspecs[ci].name;
	prototype := ES->mkobj(ex.objproto, class);
	meths := objspecs[ci].methods;
	for(k := 0; k < len meths; k++) {
		name := meths[k].name;
		fullname := class + ".prototype." + name;
		args := meths[k].args;
		ES->biinst(prototype, Builtin(name, fullname, args, len args),
			ex.funcproto, me);
	}
	return prototype;
}


getframeobj(frameid: int) : ref Obj
{
	sw := top.findbyframeid(frameid);
	if(sw != nil)
		return sw.ex.global;
	return nil;
}

getdocobj(ex : ref Exec, frameid: int) : ref Obj
{
	return getobj(ex, getframeobj(frameid), "document");
}

getformobj(ex : ref Exec, frameid, formid: int) : ref Obj
{
	# frameids are 1-origin, document.forms is 0-origin
	return getarrayelem(ex, getdocobj(ex, frameid), "forms", formid-1);
}

getformfieldobj(frameid, formid, fieldid: int) : ref Obj
{
	sw := top.findbyframeid(frameid);
	if (sw == nil)
		return nil;
	flds : list of (ref Build->Formfield, ref Obj);
	for (fl := sw.forms; fl != nil; fl = tl fl) {
		sf := hd fl;
		if (sf.form.formid == formid) {
			flds = sf.fields;
			break;
		}
	}
	for (; flds != nil; flds = tl flds) {
		(fld, obj) := hd flds;
		if (fld.fieldid == fieldid)
			return obj;
	}
	return nil;
}

getanchorobj(ex: ref Exec, frameid, anchorid: int) : ref Obj
{
	od := getdocobj(ex, frameid);
	if(od != nil) {
		(olinks, olinkslen) := getarraywithlen(ex, od, "links");
		if(olinks != nil) {
			for(i := 0; i < olinkslen; i++) {
				ol := getobj(ex, olinks, string i);
				if(ol != nil) {
					v := ES->get(ex, ol, "@PRIVanchorid");
					if(ES->isnum(v) && ES->toInt32(ex, v) == anchorid)
						return ol;
				}
			}
		}
	}
	return nil;
}

getimageobj(ex: ref Exec, frameid, imageid: int) : ref Obj
{
	od := getdocobj(ex, frameid);
	if(od != nil) {
		(oimages, oimageslen) := getarraywithlen(ex, od, "images");
		if(oimages != nil) {
			for(i := 0; i < oimageslen; i++) {
				oi := getobj(ex, oimages, string i);
				if(oi != nil) {
					v := ES->get(ex, oi, "@PRIVimageid");
					if(ES->isnum(v) && ES->toInt32(ex, v) == imageid)
						return oi;
				}
			}
		}
	}
	return nil;
}

# return nil if none such, or not an object
getobj(ex : ref Exec, o: ref Obj, prop: string) : ref Obj
{
	if(o != nil) {
		v := ES->get(ex, o, prop);
		if(ES->isobj(v))
			return ES->toObject(ex, v);
	}
	return nil;
}

# return nil if none such, or not an object
getarrayelem(ex : ref Exec, o: ref Obj, arrayname: string, index: int) : ref Obj
{
	oarr := getobj(ex, o, arrayname);
	if(oarr != nil) {
		v := ES->get(ex, oarr, string index);
		if(ES->isobj(v))
			return ES->toObject(ex, v);
	}
	return nil;
}

# return "" if none such, or not a string
getstr(ex : ref Exec, o: ref Obj, prop: string) : string
{

	if(o != nil) {
		v := ES->get(ex, o, prop);
		if(ES->isstr(v))
			return ES->toString(ex, v);
	}
	return "";
}

# Property index, -1 if doesn't exist
pind(o: ref Obj, prop: string) : int
{
	props := o.props;
	for(i := 0; i < len props; i++){
		if(props[i] != nil && props[i].name == prop)
			return i;
	}
	return -1;
}

# Reinitialize property prop of object o to value v
# (pay no attention to ReadOnly status, so can't use ES->put).
# Assume the property exists already.
reinitprop(o: ref Obj, prop: string, v: ref Val)
{
	i := pind(o, prop);
	if(i < 0) {
		# set up dummy ex for now - needs sorting out
		ex := ref Exec;
		ES->runtime(ex, nil, "missing property " + prop); # shouldn't happen
	}
	CU->assert(i >= 0);
	o.props[i].val.val = v;
}

# Get the array object named aname from o, and also find its current
# length value.  If there is any problem, return (nil, 0).
getarraywithlen(ex : ref Exec, o: ref Obj, aname: string) : (ref Obj, int)
{
	varray := ES->get(ex, o, aname);
	if(ES->isobj(varray)) {
		oarray := ES->toObject(ex, varray);
		vlen := ES->get(ex, oarray, "length");
		if(vlen != ES->undefined)
			return (oarray, ES->toInt32(ex, vlen));
	}
	return (nil, 0);	
}

# Put val v as property "index" of object oarray.
# Also, if the name doesn't conflict with array properties, add the val as
# a "name" property too
arrayput(ex : ref Exec, oarray: ref Obj, index: int, name: string, v: ref Val)
{
	ES->put(ex, oarray, string index, v);
	if (name != "length" && prop2index(name) == -1)
		ES->put(ex, oarray, name, v);
}

prop2index(p: string): int
{
	if (p == nil)
		return -1;
	v := 0;
	for (i := 0; i < len p; i++) {
		c := p[i];
		if (c < '0' || c > '9')
			return -1;
		v = 10 * v + c - '0';
	}
	return v;
}

# Instantiate window object.
# mkhostobj has already put the property names and default initial values in;
# we have to fill in the proper values.
wininstant(sw: ref ScriptWin)
{
	ex := sw.ex;
	w := ex.global;
	f := sw.frame;

	sw.error = 0;
	prevkids := sw.kids;
	sw.kids = nil;
	sw.forms = nil;
	sw.imgs = nil;
	sw.active = 0;

	# document to be init'd by xfertoscriptobjs - WRONG,
	# has to be init'd up-front as one frame may refer
	# to another's document object (esp. for document.write calls)
	od := getobj(ex, w, "document");
	if(od == nil) {
		docv := ES->objval(mkhostobj(ex, "document"));
		reinitprop(w, "document", docv);
		od = getobj(ex, w, "document");
		CU->assert(od != nil);
	}

	# frames[ ]
	ao := ES->mkobj(ex.arrayproto, "Array");
	ES->varinstant(ao, ES->DontEnum|ES->DontDelete, "length", ref RefVal(ES->numval(0.)));
	reinitprop(w, "frames", ES->objval(ao));
	for (kl := f.kids; kl != nil; kl = tl kl) {
		klf := hd kl;
		# look for original ScriptWin
		for (oldkl := prevkids; oldkl != nil; oldkl = tl oldkl) {
			oldksw := hd oldkl;
			if (oldksw.frame == klf) {
				wininstant(oldksw);
				sw.kids = oldksw :: sw.kids;
				break;
			}
		}
		if (oldkl == nil)
			sw.addkid(klf);
	}
	kn := 0;
	for (swkl := sw.kids; swkl != nil; swkl = tl swkl) {
		k := hd swkl;
		# Yes, frame name should be defined as property of parent
		arrayput(ex, ao, kn++, "", k.val);
		if (k.frame != nil && k.frame.name != nil) {
			ES->put(ex, ao, k.frame.name, k.val);
			ES->varinstant(w, 0, k.frame.name, ref RefVal(k.val));
		}
	}

	reinitprop(w, "length", ES->numval(real len f.kids));

	v := ref Val;
	if (sw.parent == nil)
		v = ES->objval(w);
	else
		v = ES->objval(sw.parent.ex.global);
	reinitprop(w, "parent", v);

	if (f.name != nil)
		reinitprop(w, "name", ES->strval(f.name));
	reinitprop(w, "self", ES->objval(w));
	reinitprop(w, "window", ES->objval(w));
	reinitprop(w, "top", ES->objval(top.ex.global));
	reinitprop(w, "Math", ES->get(ex, top.ex.global, "Math"));
	reinitprop(w, "navigator", ES->get(ex, top.ex.global, "navigator"));
}

# Return initial document object value, based on d
docinstant(ex: ref Exec, f: ref Layout->Frame) : ref Val
{
	od := mkhostobj(ex, "document");
	docfill(ex, od, f);
	return ES->objval(od);
}

# Fill in properties of doc object, based on d.
# Can be called at various points during build.
docfill(ex: ref Exec, od: ref Obj, f: ref Layout->Frame)
{
	sw := top.findbyframeid(f.id);
	if(sw == nil)
		return;
	di := f.doc;
	if(di.src != nil) {
		reinitprop(od, "URL", ES->strval(di.src.tostring()));
		reinitprop(od, "domain", ES->strval(di.src.host));
	}
	if(di.referrer != nil)
		reinitprop(od, "referrer", ES->strval(di.referrer.tostring()));
	if(di.doctitle != "")
		reinitprop(od, "title", ES->strval(di.doctitle));
	reinitprop(od, "lastModified", ES->strval(di.lastModified));
	reinitprop(od, "bgColor", colorval(di.background.color));
	reinitprop(od, "fgColor", colorval(di.text));
	reinitprop(od, "alinkColor", colorval(di.alink));
	reinitprop(od, "linkColor", colorval(di.link));
	reinitprop(od, "vlinkColor", colorval(di.vlink));

	# Forms in d.forms are in reverse order of appearance.
	# Add any that aren't already in the document.forms object,
	# assuming that the relative lengths will tell us what needs
	# to be done.
	if(di.forms != nil) {
		newformslen := len di.forms;
		oldformslen := len sw.forms;
		oforms := getobj(ex, od, "forms");

		# oforms should be non-nil, because the object is initialized
		# to an empty array and is readonly.  The following test
		# is just defensive.
		if(oforms != nil) {
			# run through our existing list of forms, looking
			# for any not marked as Transferred (happens as a result
			# of a script being called in the body of a form, while it is
			# still being parsed)
			for (sfl := sw.forms; sfl != nil; sfl = tl sfl) {
				sf := hd sfl;
				form := sf.form;
				if (form.state != B->FormTransferred) {
#					(sf.obj, sf.fields) = forminstant(ex, form, di.frameid);
					(newobj, newfields) := forminstant(ex, form, di.frameid);
					*sf.obj = *newobj;
					sf.fields = newfields;
				}
				if (form.state == B->FormDone)
					form.state = B->FormTransferred;
			}

			# process additional forms
			fl := di.forms;
			for(i := newformslen-1; i >= oldformslen; i--) {
				form := hd fl;
				fl = tl fl;
				if (form.state != B->FormTransferred) {
					sf := ref ScriptForm (form, nil, i, nil);
					(sf.obj, sf.fields) = forminstant(ex, form, di.frameid);
					arrayput(ex, oforms, i, form.name, ES->objval(sf.obj));
					if(form.name != "")
						ES->put(ex, od, form.name, ES->objval(sf.obj));
					sw.forms = sf :: sw.forms;
				}
				if (form.state == B->FormDone)
					form.state = B->FormTransferred;
			}
		}
	}

	# Charon calls "DestAnchor" what Netscape calls "Anchor".
	# Use same method as for forms to discover new ones.
	if(di.dests != nil) {
		newdestslen := len di.dests;
		(oanchors, oldanchorslen) := getarraywithlen(ex, od, "anchors");
		if(oanchors != nil) {
			dl := di.dests;
			for(i := newdestslen-1; i >= oldanchorslen; i--) {
				dest := hd dl;
				dl = tl dl;
				arrayput(ex, oanchors, i, dest.name, anchorinstant(ex, dest.name));
			}
		}
	}

	# Charon calls "Anchor" what Netscape calls "Link" (how confusing for us!).
	# Use same method as for forms to discover new ones.
	# BUG: Areas are supposed to be in this list too.
	if(di.anchors != nil) {
		newanchorslen := len di.anchors;
		(olinks, oldlinkslen) := getarraywithlen(ex, od, "links");
		if(olinks != nil) {
			al := di.anchors;
			for(i := newanchorslen-1; i >= oldlinkslen; i--) {
				a := hd al;
				al = tl al;
				arrayput(ex, olinks, i, a.name,  linkinstant(ex, a, f.id));
			}
		}
	}

	if(di.images != nil) {
		newimageslen := len di.images;
		(oimages, oldimageslen) := getarraywithlen(ex, od, "images");
		if(oimages != nil) {
			il := di.images;
			for(i := newimageslen-1; i >= oldimageslen; i--) {
				imit := hd il;
				il = tl il;
				pick ii := imit {
				Iimage =>
					vim := imageinstant(ex, ii);
					arrayput(ex, oimages, i, ii.name, vim);
					ES->put(ex, od, ii.name, vim);
					if(ES->isobj(vim)) {
						sw.imgs = ref ScriptImg(ii, vim.obj) :: sw.imgs;
					}
				}
			}
		}
	}

	# private variables
	ES->varinstant(od, ES->DontEnum|ES->DontDelete, "@PRIVframeid",
			ref RefVal(ES->numval(real di.frameid)));
}

forminstant(ex : ref Exec, form: ref Build->Form, frameid: int) : (ref Obj, list of (ref Build->Formfield, ref Obj))
{
	fields : list of (ref Build->Formfield, ref ES->Obj);
	oform := mkhostobj(ex, "Form");
	reinitprop(oform, "action", ES->strval(form.action.tostring()));
	reinitprop(oform, "encoding", ES->strval("application/x-www-form-urlencoded"));
	reinitprop(oform, "length", ES->numval(real form.nfields));
	reinitprop(oform, "method", ES->strval(CU->hmeth[form.method]));
	reinitprop(oform, "name", ES->strval(form.name));
	reinitprop(oform, "target", ES->strval(form.target));
	ffl := form.fields;
	if(ffl != nil) {
		velements := ES->get(ex, oform, "elements");
		if(ES->isobj(velements)) {
			oelements := ES->toObject(ex, velements);
			for(i := 0; i < form.nfields; i++) {
				field := hd ffl;
				ffl = tl ffl;
				vfield := fieldinstant(ex, field, oform);

				# convert multiple fields of same name to an array
				prev := ES->get(ex, oform, field.name);
				if (prev != nil && ES->isobj(prev)) {
					newix := 0;
					ar : ref Obj;
					if (ES->isarray(prev.obj)) {
						ar = prev.obj;
						vlen := ES->get(ex, ar, "length");
						newix = ES->toInt32(ex, vlen);
					} else {
						# create a new array
						ar = ES->mkobj(ex.arrayproto, "Array");
						ES->varinstant(ar, ES->DontEnum|ES->DontDelete, "length", ref RefVal(ES->numval(real 2)));
						ES->put(ex, oform, field.name, ES->objval(ar));
						arrayput(ex, ar, 0, "", prev);
						newix = 1;
					}
					arrayput(ex, ar, newix, "", vfield);
				} else {
					# first time we have seen a field of this name
					ES->put(ex, oform, field.name, vfield);
				}
				# although it is incorrect to add field name to
				# elements array (as well as being indexed)
				# - gives rise to name clashes, e.g radio buttons
				# do it because other browsers do and some fools use it!
				arrayput(ex, oelements, i, field.name, vfield);
				fields = (field, ES->toObject(ex, vfield)) :: fields;
			}
		}
	}
	for(el := form.events; el != nil; el = tl el) {
		e := hd el;
		hname := "";
		case e.attid {
		Lex->Aonreset =>
			hname = "onreset";
			form.evmask |= E->SEonreset;
		Lex->Aonsubmit =>
			hname = "onsubmit";
			form.evmask |= E->SEonsubmit;
		}
		if(hname != "")
			puthandler(ex, oform, hname, e.value);
	}
#	form.events = nil;
	# private variables
	ES->varinstant(oform, ES->DontEnum|ES->DontDelete, "@PRIVformid",
			ref RefVal(ES->numval(real form.formid)));
	ES->varinstant(oform, ES->DontEnum|ES->DontDelete, "@PRIVframeid",
			ref RefVal(ES->numval(real frameid)));
	return (oform, fields);
}

fieldinstant(ex : ref Exec, field: ref Build->Formfield, oform: ref Obj) : ref Val
{
	ofield := mkhostobj(ex, "FormField");
	reinitprop(ofield, "form", ES->objval(oform));
	reinitprop(ofield, "name", ES->strval(field.name));
	reinitprop(ofield, "value", ES->strval(field.value));
	reinitprop(ofield, "defaultValue", ES->strval(field.value));
	chkd := ES->false;
	if((field.flags & Build->FFchecked) != byte 0)
		chkd = ES->true;
	reinitprop(ofield, "checked", chkd);
	reinitprop(ofield, "defaultChecked", chkd);
	nopts := len field.options;
	reinitprop(ofield, "length", ES->numval(real nopts));
	reinitprop(ofield, "selectedIndex", ES->numval(-1.0)); # BUG: search for selected option
	ty : string;
	case field.ftype {
	Build->Ftext =>
		ty = "text";
		reinitprop(ofield, "value", ES->strval(field.value));
	Build->Fpassword =>
		ty = "password";
	Build->Fcheckbox =>
		ty = "checkbox";
	Build->Fradio =>
		ty = "radio";
	Build->Fsubmit =>
		ty = "submit";
	Build->Fhidden =>
		ty = "hidden";
	Build->Fimage =>
		ty = "image";
	Build->Freset =>
		ty = "reset";
	Build->Ffile =>
		ty = "fileupload";
	Build->Fbutton =>
		ty = "button";
	Build->Fselect =>
		ty = "select";
		si := -1;
		options := ES->mkobj(ex.arrayproto, "Array");
		ES->varinstant(options, ES->DontEnum|ES->DontDelete, "length",
					ref RefVal(ES->numval(real nopts)));
		reinitprop(ofield, "options", ES->objval(options));
		optl := field.options;
		vfield := ES->objval(ofield);
		for(i := 0; i < nopts; i++) {
			opt := hd optl;
			optl = tl optl;
			oopt := mkhostobj(ex, "Option");
			reinitprop(oopt, "index", ES->numval(real i));
			reinitprop(oopt, "value", ES->strval(opt.value));
			reinitprop(oopt, "text", ES->strval(opt.display));
			# private variables
			ES->put(ex, oopt, "@PRIVformfield", vfield);
			if(opt.selected) {
				si = i;
				reinitprop(oopt, "selected", ES->true);
				reinitprop(oopt, "defaultSelected", ES->true);
				reinitprop(ofield, "selectedIndex", ES->numval(real i));
			}
			ES->put(ex, options, string i, ES->objval(oopt));
		}
		ES->put(ex, options, "selectedIndex", ES->numval(real si));
		ES->put(ex, options, "@PRIVformfield", vfield);
		options.host = me;
	Build->Ftextarea =>
		ty = "textarea";
	}
	reinitprop(ofield, "type", ES->strval(ty));
	for(el := field.events; el != nil; el = tl el) {
		e := hd el;
		hname := "";
		case e.attid {
		Lex->Aonblur =>
			hname = "onblur";
			field.evmask |= E->SEonblur;
		Lex->Aonchange =>
			hname = "onchange";
			field.evmask |= E->SEonchange;
		Lex->Aonclick =>
			hname = "onclick";
			field.evmask |= E->SEonclick;
		Lex->Aondblclick =>
			hname = "ondblclick";
			field.evmask |= E->SEondblclick;
		Lex->Aonfocus =>
			hname = "onfocus";
			field.evmask |= E->SEonfocus;
		Lex->Aonkeydown =>
			hname = "onkeydown";
			field.evmask |= E->SEonkeydown;
		Lex->Aonkeypress =>
			hname = "onkeypress";
			field.evmask |= E->SEonkeypress;
		Lex->Aonkeyup =>
			hname = "onkeyup";
			field.evmask |= E->SEonkeyup;
		Lex->Aonmousedown =>
			hname = "onmousedown";
			field.evmask |= E->SEonmousedown;
		Lex->Aonmouseup =>
			hname = "onmouseup";
			field.evmask |= E->SEonmouseup;
		Lex->Aonselect =>
			hname = "onselect";
			field.evmask |= E->SEonselect;
		}
		if(hname != "")
			puthandler(ex, ofield, hname, e.value);
	}
#	field.events = nil;
	# private variables
	ES->varinstant(ofield, ES->DontEnum|ES->DontDelete, "@PRIVfieldid",
			ref RefVal(ES->numval(real field.fieldid)));
	return ES->objval(ofield);
}

# Make an event handler named hname in o, with given body.
puthandler(ex: ref Exec, o: ref Obj, hname: string, hbody: string)
{
	ES->eval(ex, "function PRIVhandler() {" + hbody + "}");
	hobj := getobj(ex, ex.global, "PRIVhandler");
	if(hobj != nil) {
		ES->put(ex, o, hname, ES->objval(hobj));
	}
}

anchorinstant(ex : ref Exec, nm: string) : ref Val
{
	oanchor := mkhostobj(ex, "Anchor");
	reinitprop(oanchor, "name", ES->strval(nm));
	return ES->objval(oanchor);
}

# Build ensures that the anchor href has been made absolute
linkinstant(ex: ref Exec, anchor: ref Build->Anchor, frameid: int) : ref Val
{
	olink := mkhostobj(ex, "Link");
	u := anchor.href;
	if(u != nil) {
		if(u.frag != "")
			reinitprop(olink, "hash", ES->strval("#" + u.frag));
		host := u.host;
		if(u.user != "" || u.passwd != "") {
			host = u.user;
			if(u.passwd != "")
				host += ":" + u.passwd;
			host += "@" + u.host;
		}
		reinitprop(olink, "host",  ES->strval(host));
		hostname := host;
		if(u.port != "")
			hostname += ":" + u.port;
		reinitprop(olink, "hostname", ES->strval(hostname));
		reinitprop(olink, "href", ES->strval(u.tostring()));
		reinitprop(olink, "pathname", ES->strval(u.path));
		if(u.port != "")
			reinitprop(olink, "port", ES->strval(u.port));
		reinitprop(olink, "protocol", ES->strval(u.scheme + ":"));
		if(u.query != "")
			reinitprop(olink, "search", ES->strval("?" + u.query));
	}
	if(anchor.target != "")
		reinitprop(olink, "target", ES->strval(anchor.target));

	for(el := anchor.events; el != nil; el = tl el) {
		e := hd el;
		hname := "";
		case e.attid {
		Lex->Aonclick =>
			hname = "onclick";
			anchor.evmask |= E->SEonclick;
		Lex->Aondblclick =>
			hname = "ondblclick";
			anchor.evmask |= E->SEondblclick;
		Lex->Aonkeydown =>
			hname = "onkeydown";
			anchor.evmask |= E->SEonkeydown;
		Lex->Aonkeypress =>
			hname = "onkeypress";
			anchor.evmask |= E->SEonkeypress;
		Lex->Aonkeyup =>
			hname = "onkeyup";
			anchor.evmask |= E->SEonkeyup;
		Lex->Aonmousedown =>
			hname = "onmousedown";
			anchor.evmask |= E->SEonmousedown;
		Lex->Aonmouseout =>
			hname = "onmouseout";
			anchor.evmask |= E->SEonmouseout;
		Lex->Aonmouseover =>
			hname = "onmouseover";
			anchor.evmask |= E->SEonmouseover;
		Lex->Aonmouseup =>
			hname = "onmouseup";
			anchor.evmask |= E->SEonmouseup;
		}
		if(hname != "")
			puthandler(ex, olink, hname, e.value);
	}
	anchor.events = nil;
	# private variable
	ES->varinstant(olink, ES->DontEnum|ES->DontDelete, "@PRIVanchorid",
			ref RefVal(ES->numval(real anchor.index)));
	ES->varinstant(olink, ES->DontEnum|ES->DontDelete, "@PRIVframeid",
			ref RefVal(ES->numval(real frameid)));

	return ES->objval(olink);
}

imageinstant(ex: ref Exec, im: ref Build->Item.Iimage) : ref Val
{
	oim := mkhostobj(ex, "Image");
	src := im.ci.src.tostring();
	reinitprop(oim, "border", ES->numval(real im.border));
	reinitprop(oim, "height", ES->numval(real im.imheight));
	reinitprop(oim, "hspace", ES->numval(real im.hspace));
	reinitprop(oim, "name", ES->strval(im.name));
	reinitprop(oim, "src", ES->strval(src));
	if(im.ci.lowsrc != nil)
		reinitprop(oim, "lowsrc", ES->strval(im.ci.lowsrc.tostring()));
	reinitprop(oim, "vspace", ES->numval(real im.vspace));
	reinitprop(oim, "width", ES->numval(real im.imwidth));
	if(im.ci.complete == 0)
		done := ES->false;
	else
		done = ES->true;
	reinitprop(oim, "complete", done);

	el : list of Lex->Attr = nil;
	if(im.genattr != nil)
		el = im.genattr.events;
	for(; el != nil; el = tl el) {
		e := hd el;
		hname := "";
		case e.attid {
		Lex->Aonabort =>
			hname = "onabort";
			im.genattr.evmask |= E->SEonabort;
		Lex->Aondblclick =>
			hname = "ondblclick";
			im.genattr.evmask |= E->SEondblclick;
		Lex->Aonerror =>
			hname = "onerror";
			im.genattr.evmask |= E->SEonerror;
		Lex->Aonkeydown =>
			hname = "onkeydown";
			im.genattr.evmask |= E->SEonkeydown;
		Lex->Aonkeypress =>
			hname = "onkeypress";
			im.genattr.evmask |= E->SEonkeypress;
		Lex->Aonkeyup =>
			hname = "onkeyup";
			im.genattr.evmask |= E->SEonkeyup;
		Lex->Aonload =>
			hname = "onload";
			im.genattr.evmask |= E->SEonload;
		Lex->Aonmousedown =>
			hname = "onmousedown";
			im.genattr.evmask |= E->SEonmousedown;
		Lex->Aonmouseout =>
			hname = "onmouseout";
			im.genattr.evmask |= E->SEonmouseout;
		Lex->Aonmouseover =>
			hname = "onmouseover";
			im.genattr.evmask |= E->SEonmouseover;
		Lex->Aonmouseup =>
			hname = "onmouseup";
			im.genattr.evmask |= E->SEonmouseup;
		}
		if(hname != "")
			puthandler(ex, oim, hname, e.value);
	}
	if(im.genattr != nil)
		im.genattr.events = nil;

	# private variables
	ES->varinstant(oim, ES->DontEnum|ES->DontDelete, "@PRIVimageid",
			ref RefVal(ES->numval(real im.imageid)));
	# to keep track of src as currently known in item
#	ES->varinstant(oim, ES->DontEnum|ES->DontDelete, "@PRIVsrc",
#			ref RefVal(ES->strval(src)));
	return ES->objval(oim);
}

colorval(v: int) : ref Val
{
	return ES->strval(sys->sprint("%.6x", v));
}

# If the o.name is a recognizable color, return it, else dflt
colorxfer(ex: ref Exec, o: ref Obj, name: string, dflt: int) : int
{
	v := ES->get(ex, o, name);
	if(v == ES->undefined)
		return dflt;
	return CU->color(ES->toString(ex, v), dflt);
}

strxfer(ex : ref Exec, o: ref Obj, name: string, dflt: string) : string
{
	v := ES->get(ex, o, name);
	if(v == ES->undefined)
		return dflt;
	return ES->toString(ex, v);
}

ScriptWin.new(f: ref Layout->Frame, ex: ref Exec, loc: ref Obj, par: ref ScriptWin) : ref ScriptWin
{
	return ref ScriptWin(f, ex, loc, ES->objval(ex.global), par, nil, nil, nil, "", "", "", 1, 0, 0, nil);
}

# Make a new ScriptWin with f as frame and new, empty
# Window object as obj, to be a child window of sw's window.
ScriptWin.addkid(sw: self ref ScriptWin, f: ref Layout->Frame)
{
	(cex, clocobj) := makeframeex(f);
	csw := ScriptWin.new(f, cex, clocobj, sw);
	wininstant(csw);
	sw.kids = csw :: sw.kids;
}

ScriptWin.dummy(): ref ScriptWin
{
	f := ref Layout->Frame;
	f.doc = ref Build->Docinfo;
	f.doc.base = U->parse("");
	f.doc.src = U->parse("");
	(cex, clocobj) := makeframeex(f);
	csw := ScriptWin.new(f, cex, clocobj, nil);
	wininstant(csw);
	return csw;
}

# Find the ScriptWin in the tree with sw as root that has
# f as frame, returning nil if none.
#ScriptWin.findbyframe(sw: self ref ScriptWin, f: ref Layout->Frame) : ref ScriptWin
#{
#	if(sw.frame.id == f.id)
#		return sw;
#	for(l := sw.kids; l != nil; l = tl l) {
#		x := (hd l).findbyframe(f);
#		if(x != nil)
#			return x;
#	}
#	return nil;
#}

# Find the ScriptWin in the tree with sw as root that has
# fid as frame id, returning nil if none.
ScriptWin.findbyframeid(sw: self ref ScriptWin, fid: int) : ref ScriptWin
{
	if(sw.frame.id == fid)
		return sw;
	for(l := sw.kids; l != nil; l = tl l) {
		x := (hd l).findbyframeid(fid);
		if(x != nil)
			return x;
	}
	return nil;
}

# Find the ScriptWin in the tree with sw as root that has
# d as doc for the frame, returning nil if none.
ScriptWin.findbydoc(sw: self ref ScriptWin, d: ref Build->Docinfo) : ref ScriptWin
{
	if(sw.frame.doc == d)
		return sw;
	for(l := sw.kids; l != nil; l = tl l) {
		x := (hd l).findbydoc(d);
		if(x != nil)
			return x;
	}
	return nil;
}

# obj can either be the frame's Window obj, Location obj, or document obj,
# or an Image object within the frame
ScriptWin.findbyobj(sw : self ref ScriptWin, obj : ref Obj) : ref ScriptWin
{
	if (sw.locobj == obj || sw.ex.global == obj || obj == getdocobj(sw.ex, sw.frame.id))
		return sw;
	if(opener != nil && (opener.locobj == obj || opener.ex.global == obj))
		return opener;
	for(sil := sw.imgs; sil != nil; sil = tl sil) {
		if((hd sil).obj == obj)
			return sw;
	}
	for (l := sw.kids; l != nil; l = tl l) {
		x := (hd l).findbyobj(obj);
		if (x != nil)
			return x;
	}
	return nil;
}

ScriptWin.findbyname(sw : self ref ScriptWin, name : string) : ref ScriptWin
{
	if (sw.frame != nil && sw.frame.name == name)
		return sw;
	for (l := sw.kids; l != nil; l = tl l) {
		x := (hd l).findbyname(name);
		if (x != nil)
			return x;
	}
	return nil;
}

newcharon(url: string, nm: string, sw: ref ScriptWin)
{
	cs := chan of string;

	spawn CH->startcharon(url, cs);
	for(;;){
		alt{
			s := <- cs =>
				if(s == "B")
					continue;
				if(s == "E")
					exit;
				(nil, l) := sys->tokenize(s, " ");
				case hd l{
					"L" =>
						sw.newloc = hd tl l;
						sw.newloctarg = nm;
						checknewlocs(sw);
				}
		}
	}
}
