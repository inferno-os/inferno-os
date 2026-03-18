implement Layout;

include "common.m";
include "keyboard.m";

sys: Sys;
CU: CharonUtils;
	ByteSource, MaskedImage, CImage, ImageCache, max, min,
	White, Black, Grey, DarkGrey, LightGrey, Blue, Navy, Red, Green, DarkRed: import CU;

D: Draw;
	Point, Rect, Font, Image, Display, Pointer: import D;
S: String;
T: StringIntTab;
U: Url;
	Parsedurl: import U;
I: Img;
	ImageSource: import I;
J: Script;
E: Events;
	Event: import E;
G: Gui;
B: Build;
W: Widget;
	Scrollbar: import W;

# B : Build, declared in layout.m so main program can use it
	Item, ItemSource,
	IFbrk, IFbrksp, IFnobrk, IFcleft, IFcright, IFwrap, IFhang,
	IFrjust, IFcjust, IFsmap, IFindentshift, IFindentmask,
	IFhangmask,
	Voffbias,
	ISPnull, ISPvline, ISPhspace, ISPgeneral,
	Align, Dimen, Formfield, Option, Form,
	Table, Tablecol, Tablerow, Tablecell,
	Anchor, DestAnchor, Map, Area, Kidinfo, Docinfo,
	Anone, Aleft, Acenter, Aright, Ajustify, Achar, Atop, Amiddle,
	Abottom, Abaseline,
	Dnone, Dpixels, Dpercent, Drelative,
	Ftext, Fpassword, Fcheckbox, Fradio, Fsubmit, Fhidden, Fimage,
	Freset, Ffile, Fbutton, Fselect, Ftextarea,
	Femail, Furl, Fnumber, Ftel, Fsearch, Fdate, Ftime, Fcolor, Frange,
	Background,
	FntR, FntI, FntB, FntT, NumStyle,
	Tiny, Small, Normal, Large, Verylarge, NumSize, NumFnt, DefFnt,
	ULnone, ULunder, ULmid,
	FRnoresize, FRnoscroll, FRhscroll, FRvscroll,
	FRhscrollauto, FRvscrollauto,
	ComputedStyle, STYLNONE,
	BSnone, BSsolid, BSdotted, BSdashed, BSdouble, BSgroove, BSridge, BSinset, BSoutset,
	OVvisible, OVhidden, OVscroll, OVauto,
	POSstatic, POSrelative, POSabsolute, POSfixed, POSsticky,
	FLnone, FLleft, FLright,
	CLnone, CLleft, CLright, CLboth,
	VISvisible, VIShidden,
	FFrequired, FFautofocus,
	BSZcontent, BSZborder,
	WBnormal, WBbreak_all,
	TOclip, TOellipsis,
	DSPINLINEBLOCK,
	DSPflex, DSPinline_flex,
	DSPgrid, DSPinline_grid,
	FDrow, FDrow_reverse, FDcolumn, FDcolumn_reverse,
	FWnowrap, FWwrap, FWwrap_reverse,
	JCflex_start, JCflex_end, JCcenter, JCspace_between, JCspace_around, JCspace_evenly,
	AIflex_start, AIflex_end, AIcenter, AIstretch, AIbaseline,
	BGRrepeat, BGRno_repeat, BGRrepeat_x, BGRrepeat_y,
	BGSZcover, BGSZcontain
    : import B;

# font stuff
Fontinfo : adt {
	name:	string;
	f:	ref Font;
	spw:	int;			# width of a space in this font
};

# Use combined/DejaVu k8 antialiased fonts with size and weight variants.
# k8 AA fonts render correctly at any DPI (unlike k1 bitmap fonts).
#
# Size mapping:
#   Tiny/Small = 12pt, Normal = 14pt, Large = 18pt, Verylarge = 24pt
#
# Weight mapping:
#   FntR/FntI = regular weight, FntB = bold weight (DejaVuSans-Bold)
#
# After a fresh clone, run `cd fonts/dejavu && mk` to generate the
# bold and multi-size subfonts from DejaVuSans-Bold.ttf.
fonts := array[NumFnt] of {
	FntR*NumSize+Tiny     => Fontinfo("/fonts/combined/unicode.sans.12.font", nil, 0),
	FntR*NumSize+Small    => ("/fonts/combined/unicode.sans.12.font", nil, 0),
	FntR*NumSize+Normal   => ("/fonts/combined/unicode.sans.14.font", nil, 0),
	FntR*NumSize+Large    => ("/fonts/combined/unicode.sans.18.font", nil, 0),
	FntR*NumSize+Verylarge => ("/fonts/combined/unicode.sans.24.font", nil, 0),

	FntI*NumSize+Tiny     => ("/fonts/combined/unicode.sans.12.font", nil, 0),
	FntI*NumSize+Small    => ("/fonts/combined/unicode.sans.12.font", nil, 0),
	FntI*NumSize+Normal   => ("/fonts/combined/unicode.sans.14.font", nil, 0),
	FntI*NumSize+Large    => ("/fonts/combined/unicode.sans.18.font", nil, 0),
	FntI*NumSize+Verylarge => ("/fonts/combined/unicode.sans.24.font", nil, 0),

	FntB*NumSize+Tiny     => ("/fonts/combined/unicode.sans.bold.12.font", nil, 0),
	FntB*NumSize+Small    => ("/fonts/combined/unicode.sans.bold.12.font", nil, 0),
	FntB*NumSize+Normal   => ("/fonts/combined/unicode.sans.bold.14.font", nil, 0),
	FntB*NumSize+Large    => ("/fonts/combined/unicode.sans.bold.18.font", nil, 0),
	FntB*NumSize+Verylarge => ("/fonts/combined/unicode.sans.bold.24.font", nil, 0),

	FntT*NumSize+Tiny     => ("/fonts/combined/unicode.14.font", nil, 0),
	FntT*NumSize+Small    => ("/fonts/combined/unicode.14.font", nil, 0),
	FntT*NumSize+Normal   => ("/fonts/combined/unicode.14.font", nil, 0),
	FntT*NumSize+Large    => ("/fonts/combined/unicode.14.font", nil, 0),
	FntT*NumSize+Verylarge => ("/fonts/combined/unicode.14.font", nil, 0),
};

# Seems better to use a slightly smaller font in Controls, to match other browsers
CtlFnt: con (FntR*NumSize+Small);

# color stuff.  have hash table mapping RGB values to D->Image for that color
Colornode : adt {
	rgb:	int;
	im:	ref Image;
	next:	ref Colornode;
};

# Flex layout line (for flex-wrap partitioning)
FlexLine : adt {
	start:	int;		# first item index
	count:	int;		# number of items
	maxh:	int;		# tallest item in line
};

# Source of info for page (html, image, etc.)
Source: adt {
	bs:	ref ByteSource;
	redirects:	int;
	pick {
		Srequired or
		Shtml =>
			itsrc: ref ItemSource;
		Simage =>
			ci: ref CImage;
			itl: list of ref Item;
			imsrc: ref ImageSource;
	}
};

Sources: adt {
	main: ref Source;
	reqd: ref Source;
	srcs: list of ref Source;

	new: fn(m : ref Source) : ref Sources;
	add: fn(srcs: self ref Sources, s: ref Source, required: int);
	done: fn(srcs: self ref Sources, s: ref Source);
	waitsrc: fn(srcs : self ref Sources) : ref Source;
};

NCOLHASH : con 19;	# 19 checked for standard colors: only 1 collision
colorhashtab := array[NCOLHASH] of ref Colornode;

# No line break should happen between adjacent characters if
# they are 'wordchars' : set in this array, or outside the array range.
# We include certain punctuation characters that are not traditionally
# regarded as 'word' characters.
wordchar := array[16rA0] of {
	'!' => byte 1, 
	'0'=>byte 1, '1'=>byte 1, '2'=>byte 1, '3'=>byte 1, '4'=>byte 1,
	'5'=>byte 1, '6'=>byte 1, '7'=>byte 1, '8'=>byte 1, '9'=>byte 1,
	':'=>byte 1, ';' => byte 1,
	'?' => byte 1,
	'A'=>byte 1, 'B'=>byte 1, 'C'=>byte 1, 'D'=>byte 1, 'E'=>byte 1, 'F'=>byte 1,
	'G'=>byte 1, 'H'=>byte 1, 'I'=>byte 1, 'J'=>byte 1, 'K'=>byte 1, 'L'=>byte 1,
	'M'=>byte 1, 'N'=>byte 1, 'O'=>byte 1, 'P'=>byte 1, 'Q'=>byte 1, 'R'=>byte 1,
	'S'=>byte 1, 'T'=>byte 1, 'U'=>byte 1, 'V'=>byte 1, 'W'=>byte 1, 'X'=>byte 1,
	'Y'=>byte 1, 'Z'=>byte 1,
	'a'=>byte 1, 'b'=>byte 1, 'c'=>byte 1, 'd'=>byte 1, 'e'=>byte 1, 'f'=>byte 1,
	'g'=>byte 1, 'h'=>byte 1, 'i'=>byte 1, 'j'=>byte 1, 'k'=>byte 1, 'l'=>byte 1,
	'm'=>byte 1, 'n'=>byte 1, 'o'=>byte 1, 'p'=>byte 1, 'q'=>byte 1, 'r'=>byte 1,
	's'=>byte 1, 't'=>byte 1, 'u'=>byte 1, 'v'=>byte 1, 'w'=>byte 1, 'x'=>byte 1,
	'y'=>byte 1, 'z'=>byte 1,
	'_'=>byte 1,
	'\''=>byte 1, '"'=>byte 1, '.'=>byte 1, ','=>byte 1, '('=>byte 1, ')'=>byte 1,
	* => byte 0
};

TABPIX: con 30;		# number of pixels in a tab
CAPSEP: con 5;			# number of pixels separating tab from caption
SCRBREADTH: con 14;	# scrollbar breadth (normal)
SCRFBREADTH: con 14;	# scrollbar breadth (inside child frame or select control)
FRMARGIN: con 0;		# default margin around frames
RULESP: con 7;			# extra space before and after rules
POPUPLINES: con 12;	# number of lines in popup select list
MINSCR: con 6;			# min size in pixels of scrollbar drag widget
SCRDELTASF: con 10000;	# fixed-point scale factor for scrollbar per-pixel step

# all of the following include room for relief
CBOXWID: con 14;		# check box width
CBOXHT: con 12;		# check box height
ENTVMARGIN : con 4;	# vertical margin inside entry box
ENTHMARGIN : con 6;	# horizontal margin inside entry box
SELMARGIN : con 4;		# margin inside select control
BUTMARGIN: con 4;		# margin inside button control
PBOXWID: con 10;		# progress box width
PBOXHT: con 16;		# progress box height
PBOXBD: con 2;		# progress box border width

TABLEMAXTARGET: con 2000;	# targetwidth to get max width of table cell
TABLEFLOATTARGET: con 1;	# targetwidth for floating tables

SELBG: con 16r00FFFF;	# aqua

ARPAUSE : con 500;			# autorepeat initial delay (ms)
ARTICK : con 100;			# autorepeat tick delay (ms)

display: ref D->Display;

dbg := 0;
dbgtab := 0;
dbgev := 0;
linespace := 0;
lineascent := 0;
charspace := 0;
spspace := 0;
ctllinespace := 0;
ctllineascent := 0;
ctlcharspace := 0;
ctlspspace := 0;
frameid := 0;
zp := Point(0,0);

init(cu: CharonUtils)
{
	CU = cu;
	sys = load Sys Sys->PATH;
	D = load Draw Draw->PATH;
	S = load String String->PATH;
	T = load StringIntTab StringIntTab->PATH;
	U = load Url Url->PATH;
	if (U != nil)
		U->init();
	E = cu->E;
	G = cu->G;
	I = cu->I;
	J = cu->J;
	B = cu->B;
	display = G->display;
	W = load Widget Widget->PATH;

	if(display == nil) {
		# Headless mode: no display, use fixed fallback metrics.
		# Layout still runs (building items and lines for text extraction)
		# but font metrics are approximated with constants.
		linespace = 15;
		lineascent = 12;
		charspace = 8;
		spspace = 4;
		ctllinespace = 15;
		ctllineascent = 12;
		ctlcharspace = 8;
		ctlspspace = 4;
		return;
	}
	#TODO should read from env $font or config
	if((CU->config).doacme)
		for(i := 0; i < len fonts; i++)
			fonts[i] = Fontinfo("/fonts/vera/Vera/unicode.14.font", nil, 0);
	# make sure default and control fonts are loaded
	getfont(DefFnt);
	fnt := fonts[DefFnt].f;
	linespace = fnt.height;
	lineascent = fnt.ascent;
	charspace = fnt.width("a");	# a kind of average char width
	spspace = fonts[DefFnt].spw;
	getfont(CtlFnt);
	fnt = fonts[CtlFnt].f;
	ctllinespace = fnt.height;
	ctllineascent = fnt.ascent;
	ctlcharspace = fnt.width("a");
	ctlspspace = fonts[CtlFnt].spw;
	if(W != nil)
		W->init(display, fonts[DefFnt].f);
}

stringwidth(s: string): int
{
	f := fonts[DefFnt].f;
	if(f == nil || charspace == 0)
		return len(s);
	return f.width(s)/charspace;
}

# Use bsmain to fill frame f.
# Return buffer containing source when done.
layout(f: ref Frame, bsmain: ref ByteSource, linkclick: int) : array of byte
{
	dbg = int (CU->config).dbg['l'];
	dbgtab = int (CU->config).dbg['t'];
	dbgev = int (CU->config).dbg['e'];
	if(dbgev)
		CU->event("LAYOUT", 0);
	sources : ref Sources;
	hdr := bsmain.hdr;
	auth := "";
	url : ref Parsedurl;
	if (bsmain.req != nil) {
		auth = bsmain.req.auth;
		url = bsmain.req.url;
	}
#	auth := bsmain.req.auth;
	ans : array of byte = nil;
	di := Docinfo.new();
	if(linkclick && f.doc != nil)
		di.referrer = f.doc.src;
	f.reset();
	f.doc = di;
	di.frameid = f.id;
	di.src = hdr.actual;
	di.base = hdr.base;
	di.refresh = hdr.refresh;
	if (hdr.chset != nil)
		di.chset = hdr.chset;
	di.lastModified = hdr.lastModified;
	if(J != nil)
		J->havenewdoc(f);
	oclipr := f.cim.clipr;
	f.cim.clipr = f.cr;
	if(f.framebd != 0) {
		f.cr = f.r.inset(2);
		drawborder(f.cim, f.cr, 2, DarkGrey);
	}
	fillbg(f, f.cr);
	G->flush(f.cr);
	f.cim.clipr = oclipr;
	if(f.flags&FRvscroll)
		createvscroll(f);
	if(f.flags&FRhscroll)
		createhscroll(f);
	l := Lay.new(f.cr.dx(), Aleft, f.marginw, di.background);
	f.layout = l;
	anyanim := 0;
	if(hdr.mtype == CU->TextHtml || hdr.mtype == CU->TextPlain) {
		itsrc := ItemSource.new(bsmain, f, hdr.mtype);
		sources = Sources.new(ref Source.Shtml(bsmain, 0, itsrc));
	}
	else {
		# for now, must be supported image type
		if(I == nil || !I->supported(hdr.mtype)) {
			sys->print("Need to implement something: source isn't supported image type\n");
			return nil;
		}
		imsrc := I->ImageSource.new(bsmain, 0, 0);
		ci := CImage.new(url, nil, 0, 0);
		simage := ref Source.Simage(bsmain, 0, ci, nil, imsrc);
		sources = Sources.new(simage);
		it := ref Item.Iimage(nil, 0, 0, 0, 0, 0, nil, len di.images, ci, 0, 0, "", nil, nil, -1, Abottom, byte 0, byte 0, byte 0);
		di.images = it :: nil;
		appenditems(f, l, it);
		simage.itl = it :: nil;
	}
	while ((src := sources.waitsrc()) != nil) {
		if(dbgev)
			CU->event("LAYOUT GETSOMETHING", 0);
		bs := src.bs;
		freeit := 0;
		if(bs.err != "") {
			if(dbg)
				sys->print("error getting %s: %s\n", bs.req.url.tostring(), bs.err);
			pick s := src {
			Srequired =>
				s.itsrc.reqddata = array [0] of byte;
				sources.done(src);
				CU->freebs(bs);
				src.bs = nil;
				continue;
			}
			freeit = 1;
		}
		else {
			if(bs.hdr != nil && !bs.seenhdr) {
				(use, error, challenge, newurl) := CU->hdraction(bs, 0, src.redirects);
				if(challenge != nil) {
					sys->print("Need to implement authorization credential dialog\n");
					error = "Need authorization";
					use = 0;
				}
				if(error != "" && dbg)
					sys->print("subordinate error: %s\n", error);
				if(newurl != nil) {
					freeit = 1;
					pick ps := src {
					Shtml or Srequired =>
						sys->print("unexpected redirect of subord\n");
					Simage =>
						newci := CImage.new(newurl, nil, ps.ci.width, ps.ci.height);
						for(itl := ps.itl; itl != nil ; itl = tl itl) {
							pick imi := hd itl {
							Iimage =>
								imi.ci = newci;
							}
						}
						news := ref Source.Simage(nil, 0, newci, ps.itl, nil);
						sources.add(news, 0);
						startimreq(news, auth);
					}
				}
				if(!use)
					freeit = 1;
			}
			if(!freeit) {
				pick s := src {
				Srequired or
				Shtml =>
					if (tagof src == tagof Source.Srequired) {
						s.itsrc.reqddata = bs.data;
						sources.done(src);
						CU->freebs(bs);
						src.bs = nil;
						continue;
#						src = sources.main;
#						CU->assert(src != nil);
					}
					itl := s.itsrc.getitems();
					if(di.kidinfo != nil) {
						if(s.itsrc.kidstk == nil) {
							layframeset(f, di.kidinfo);
							G->flush(f.r);
							freeit = 1;
						}
					}
					else {
						l.background = di.background;
						anyanim |= addsubords(sources, di, auth);
						if(itl != nil) {
							appenditems(f, l, itl);
							fixframegeom(f);
							if(dbgev)
								CU->event("LAYOUT_DRAWALL", 0);
							f.dirty(f.totalr);
							drawall(f);
						}
					}
					if (s.itsrc.reqdurl != nil) {
						news := ref Source.Srequired(nil, 0, s.itsrc);
						sources.add(news, 1);
						rbs := CU->startreq(ref CU->ReqInfo(s.itsrc.reqdurl, CU->HGet, nil, "", ""));
						news.bs = rbs;
					} else {
						if (bs.eof && bs.lim == bs.edata && s.itsrc.toks == nil)
							freeit = 1;
					}
				Simage =>
					(ret, mim) := s.imsrc.getmim();
					# mark it done even if error
					s.ci.complete = ret;
					if(ret == I->Mimerror) {
						bs.err = s.imsrc.err;
						freeit = 1;
					}
					else if(ret != I->Mimnone) {
						if(s.ci.mims == nil) {
							s.ci.mims = array[1] of { mim };
							s.ci.width = s.imsrc.width;
							s.ci.height = s.imsrc.height;
							if(ret == I->Mimdone && (CU->config).imagelvl <= CU->ImgNoAnim)
								freeit = 1;
						}
						else {
							n := len s.ci.mims;
							if(mim != s.ci.mims[n-1]) {
								newmims := array[n + 1] of ref MaskedImage;
								newmims[0:] = s.ci.mims;
								newmims[n] = mim;
								s.ci.mims = newmims;
								anyanim = 1;
							}
						}
						if(s.ci.mims[0] == mim)
							haveimage(f, s.ci, s.itl);
						if(bs.eof && bs.lim == bs.edata && CU->imcache != nil)
							(CU->imcache).add(s.ci);
					}
					if(!freeit && bs.eof && bs.lim == bs.edata)
						freeit = 1;
				}
			}
		}
		if(freeit) {
			if(bs == bsmain)
				ans = bs.data[0:bs.edata];
			CU->freebs(bs);
			src.bs = nil;
			sources.done(src);
		}
	}
	if(anyanim && (CU->config).imagelvl > CU->ImgNoAnim)
		spawn animproc(f);
	if(dbgev)
		CU->event("LAYOUT_END", 0);
	return ans;
}

# return value is 1 if found any existing images needed animation
addsubords(sources: ref Sources, di: ref Docinfo, auth: string) : int
{
	anyanim := 0;
	if((CU->config).imagelvl == CU->ImgNone)
		return anyanim;
	newsims: list of ref Source.Simage = nil;
	for(il := di.images; il != nil; il = tl il) {
		it := hd il;
		pick i := it {
		Iimage =>
			if(i.ci.mims == nil && CU->imcache != nil) {
				cachedci := (CU->imcache).look(i.ci);
				if(cachedci != nil) {
					i.ci = cachedci;
					if(i.imwidth == 0)
						i.imwidth = i.ci.width;
					if(i.imheight == 0)
						i.imheight = i.ci.height;
					anyanim |= (len cachedci.mims > 1);
				}
				else {
				    sloop:
					for(sl := sources.srcs; sl != nil; sl = tl sl) {
						pick s := hd sl {
						Simage =>
							if(s.ci.match(i.ci)) {
								s.itl = it :: s.itl;
								# want all items on list to share same ci;
								# want most-specific dimension specs
								iciw := i.ci.width;
								icih := i.ci.height;
								i.ci = s.ci;
								if(s.ci.width == 0 && s.ci.height == 0) {
									s.ci.width = iciw;
									s.ci.height = icih;
								}
								break sloop;
							}
						}
					}
					if(sl == nil) {
						# didn't find existing Source for this image
						s := ref Source.Simage(nil, 0, i.ci, it:: nil, nil);
						newsims = s :: newsims;
						sources.add(s, 0);
					}
				}
			}
		}
	}
	# Start requests for new newsources.
	# di.images are in last-in-document-first order,
	# so newsources is in first-in-document-first order (good order to load in).
	for(sl := newsims; sl != nil; sl = tl sl)
		startimreq(hd sl, auth);
	return anyanim;
}

startimreq(s: ref Source.Simage, auth: string)
{
	if(I == nil)
		return;
	if(dbgev)
		CU->event(sys->sprint("LAYOUT STARTREQ %s", s.ci.src.tostring()), 0);
	bs := CU->startreq(ref CU->ReqInfo(s.ci.src, CU->HGet, nil, auth, ""));
	s.bs = bs;
	s.imsrc = I->ImageSource.new(bs, s.ci.width, s.ci.height);
}

createvscroll(f: ref Frame)
{
	breadth := SCRBREADTH;
	if(f.parent != nil)
		breadth = SCRFBREADTH;
	length := f.cr.dy();
	if(f.flags&FRhscroll)
		length -= breadth;
	f.vscr = Control.newscroll(f, 1, length, breadth);
	f.vscr.r = f.vscr.r.addpt(Point(f.cr.max.x-breadth, f.cr.min.y));
	f.cr.max.x -= breadth;
	if(f.cr.dx() <= 2*f.marginw)
		CU->raisex("EXInternal: frame too small for layout");
	if(W != nil) {
		pick sc := f.vscr {
		Cscrollbar =>
			sc.wsb = Scrollbar.new(f.vscr.r, 1);
		}
	}
	f.vscr.draw(1);
}

createhscroll(f: ref Frame)
{
	breadth := SCRBREADTH;
	if(f.parent != nil)
		breadth = SCRFBREADTH;
	length := f.cr.dx();
	x := f.cr.min.x;
	f.hscr = Control.newscroll(f, 0, length, breadth);
	f.hscr.r = f.hscr.r.addpt(Point(x,f.cr.max.y-breadth));
	f.cr.max.y -= breadth;
	if(f.cr.dy() <= 2*f.marginh)
		CU->raisex("EXInternal: frame too small for layout");
	if(W != nil) {
		pick sc := f.hscr {
		Cscrollbar =>
			sc.wsb = Scrollbar.new(f.hscr.r, 0);
		}
	}
	f.hscr.draw(1);
}

# Call after a change to f.layout or f.viewr.min to fix totalr and viewr
# (We are to leave viewr.min unchanged, if possible, as
# user might be scrolling).
fixframegeom(f: ref Frame)
{
	l := f.layout;
	if(dbg)
		sys->print("fixframegeom, layout width=%d, height=%d\n", l.width, l.height);
	crwidth := f.cr.dx();
	crheight := f.cr.dy();
	layw := max(l.width, crwidth);
	layh := max(l.height, crheight);
	f.totalr.max = Point(layw, layh);
	crchanged := 0;
	n := l.height+l.margin-crheight;
	if(n > 0 && f.vscr == nil && (f.flags&FRvscrollauto)) {
		createvscroll(f);
		crchanged = 1;
		crwidth = f.cr.dx();
	}
	if(f.viewr.min.y > n)
		f.viewr.min.y = max(0, n);
	n = l.width+l.margin-crwidth;
	if(!crchanged && n > 0 && f.hscr == nil && (f.flags&FRhscrollauto)) {
		createhscroll(f);
		crchanged = 1;
		crheight = f.cr.dy();
	}
	if(crchanged) {
		relayout(f, l, crwidth, l.just);
		fixframegeom(f);
		return;
	}
	if(f.viewr.min.x > n)
		f.viewr.min.x = max(0, n);
	f.viewr.max.x = min(f.viewr.min.x+crwidth, layw);
	f.viewr.max.y = min(f.viewr.min.y+crheight, layh);
	if(f.vscr != nil)
		f.vscr.scrollset(f.viewr.min.y, f.viewr.max.y, f.totalr.max.y, 0, 1);
	if(f.hscr != nil)
		f.hscr.scrollset(f.viewr.min.x, f.viewr.max.x, f.totalr.max.x, f.viewr.dx()/5, 1);
}

# The items its within f are Iimage items,
# and its image, ci, now has at least a ci.mims[0], which may be partially
# or fully filled.
haveimage(f: ref Frame, ci: ref CImage, itl: list of ref Item)
{
	if(dbgev)
		CU->event("HAVEIMAGE", 0);
	if(dbg)
		sys->print("\nHAVEIMAGE src=%s w=%d h=%d\n", ci.src.tostring(), ci.width, ci.height);
	# make all base images repl'd - makes handling backgrounds much easier
	if(ci.mims == nil || ci.mims[0] == nil || ci.mims[0].im == nil)
		return;
	im := ci.mims[0].im;
	im.repl = 1;
	im.clipr = Rect((-16rFFFFFFF, -16r3FFFFFFF), (16r3FFFFFFF, 16r3FFFFFFF));
	dorelayout := 0;
	for( ; itl != nil; itl = tl itl) {
		it := hd itl;
		pick i := it {
		Iimage =>
			if (!(it.state & B->IFbkg)) {
				# If i.imwidth and i.imheight are not both 0, the HTML specified the dimens.
				# If one of them is 0, the other is to be scaled by the same factor;
				# we have to relay the line in that case too.
				if(i.imwidth == 0 || i.imheight == 0) {
					i.imwidth = ci.width;
					i.imheight = ci.height;
					setimagedims(i);
					loc := f.find(zp, it);
					# sometimes the image was added to doc image list, but
					# never made it to layout (e.g., because html bug prevented
					# a table from being added).
					# also, script-created images won't have items
					if(loc != nil) {
						f.layout.flags |= Lchanged;
						markchanges(loc);
						dorelayout = 1;
						# Floats are assumed to be premeasured, so if there
						# are any floats in the loc list, remeasure them
						for(k := loc.n-1; k > 0; k--) {
							if(loc.le[k].kind == LEitem) {
								locit := loc.le[k].item;
								pick fit := locit {
								Ifloat =>
									pick xi := fit.item {
									Iimage =>
										fit.height = fit.item.height;
									Itable =>
										checktabsize(f, xi, TABLEFLOATTARGET);
									Ibox =>
										checkboxsize(f, fit, xi, TABLEFLOATTARGET);
										fit.height = fit.item.height;
									}
								}
							}
						}
					}
				}
			}
			if(dbg > 1) {
				sys->print("\nhaveimage item: ");
				it.print();
			}
		}
	}
	if(dorelayout) {
		relayout(f, f.layout, f.layout.targetwidth, f.layout.just);
		fixframegeom(f);
	}
	f.dirty(f.totalr);
	drawall(f);
	if(dbgev)
		CU->event("HAVEIMAGE_END", 0);
}
# For first layout of subelements, such as table cells.
# After this, content items will be dispersed throughout resulting lay.
# Return index into f.sublays.
# (This roundabout way of storing sublayouts avoids pointers to Lay
# in Build, so that all of the layout-related stuff can be in Layout
# where it belongs.)
sublayout(f: ref Frame, targetwidth: int, just: byte, bg: Background, content: ref Item) : int
{
	if(dbg)
		sys->print("sublayout, targetwidth=%d\n", targetwidth);
	l := Lay.new(targetwidth, just, 0, bg);
	if(f.sublayid >= len f.sublays) {
		newsublays := array[len f.sublays + 30] of ref Lay;
		newsublays[0:] = f.sublays;
		f.sublays = newsublays;
	}
	id := f.sublayid;
	f.sublays[id] = l;
	f.sublayid++;
	appenditems(f, l, content);
	l.flags &= ~Lchanged;
	if(dbg)
		sys->print("after sublayout, width=%d\n", l.width);
	return id;
}

# Relayout of lay, given a new target width or if something changed inside
# or if the global justification for the layout changed.
# Floats are hard: for now, just relay everything with floats temporarily
# moved way down, if there are any floats.
relayout(f: ref Frame, lay: ref Lay, targetwidth: int, just: byte)
{
	if(dbg)
		sys->print("relayout, targetwidth=%d, old target=%d, changed=%d\n",
			targetwidth, lay.targetwidth, (lay.flags&Lchanged) != byte 0);
	changeall := (lay.targetwidth != targetwidth || lay.just != just);
	if(!changeall && !int(lay.flags&Lchanged))
		return;
	if(lay.floats != nil) {
		# move the current y positions of floats to a big value,
		# so they don't contribute to floatw until after they've
		# been encountered in current fixgeom
		for(flist := lay.floats; flist != nil; flist = tl flist) {
			ff := hd flist;
			ff.y = 16r6fffffff;
		}
		changeall = 1;
	}
	lay.targetwidth = targetwidth;
	lay.just = just;
	lay.height = 0;
	lay.width = 0;
	if(changeall)
		changelines(lay.start.next, lay.end);
	fixgeom(f, lay, lay.start.next);
	lay.flags &= ~Lchanged;
	if(dbg)
		sys->print("after relayout, width=%d\n", lay.width);
}

# Measure and append the items to the end of layout lay,
# and fix the geometry.
appenditems(f: ref Frame, lay: ref Lay, items: ref Item)
{
	measure(f, items);
	if(dbg)
		items.printlist("appenditems, after measure");
	it := items;
	if(it == nil)
		return;
	lprev := lay.end.prev;
	l : ref Line;
	lit := lastitem(lprev.items);
	if(lit == nil || (it.state&IFbrk)) {
		# start a new line after existing last line
		l = Line.new();
		appendline(lprev, l);
		l.items = it;
	}
	else {
		# start appending items to existing last line
		l = lprev;
		lit.next = it;
	}
	l.flags |= Lchanged;
	while(it != nil) {
		nexti := it.next;
		if(nexti == nil || (nexti.state&IFbrk)) {
			it.next = nil;
			fixgeom(f, lay, l);
			if(nexti == nil)
				break;
			# now there may be multiple lines containing the
			# items from l, but the one after the last is lay.end
			l = Line.new();
			appendline(lay.end.prev, l);
			l.flags |= Lchanged;
			it = nexti;
			l.items = it;
		}
		else
			it = nexti;
	}
}

# Fix up the geometry of line l and successors.
# Assume geometry of previous line is correct.
fixgeom(f: ref Frame, lay: ref Lay, l: ref Line)
{
	while(l != nil) {
		fixlinegeom(f, lay, l);
		mergetext(l);
		l = l.next;
	}
	lay.height = max(lay.height, lay.end.pos.y);
}

mergetext(l: ref Line)
{
	lastit : ref Item;
	for (it := l.items; it != nil; it = it.next) {
		pick i := it {
		Itext =>
			if (lastit == nil)
				break; #pick
			pick pi := lastit {
			Itext =>
				# ignore item state flags as fixlinegeom() 
				# will have taken account of them.
				if (pi.anchorid == i.anchorid &&
				pi.fnt == i.fnt && pi.fg == i.fg && pi.voff == i.voff && pi.ul == i.ul) {
					# compatible - merge
					pi.s += i.s;
					pi.width += i.width;
					pi.next = i.next;
					continue;
				}
			}
		}
		lastit = it;
	}
}

# Fix geom for one line.
# This may change the overall lay.width, if there is no way
# to fit the line into the target width. 
fixlinegeom(f: ref Frame, lay: ref Lay, l: ref Line)
{
	lprev := l.prev;
	y := lprev.pos.y + lprev.height;
	it := l.items;
	state := it.state;
	if(dbg > 1) {
		sys->print("\nfixlinegeom start, y=prev.y+prev.height=%d+%d=%d, changed=%d\n",
				l.prev.pos.y, lprev.height, y, int (l.flags&Lchanged));
		if(dbg > 2)
			it.printlist("items");
		else {
			sys->print("first item: ");
			it.print();
		}
	}
	if(state&IFbrk) {
		y = pastbrk(lay, y, state);
		if(dbg > 1 && y != lprev.pos.y + lprev.height)
			sys->print("after pastbrk, line y is now %d\n", y);
	}
	l.pos.y = y;
	lineh := max(l.height, linespace);
	lfloatw := floatw(y, y+lineh, lay.floats, Aleft);
	rfloatw := floatw(y, y+lineh, lay.floats, Aright);
	if((l.flags&Lchanged) == byte 0) {
		# possibly adjust lay.width
		n := (lay.width-rfloatw)-(l.pos.x-lay.margin+l.width);
		if(n < 0)
			lay.width += -n;
		return;
	}
	hang := (state&IFhangmask)*TABPIX/10;
	linehang := hang;
	hangtogo := hang;
	indent := ((state&IFindentmask)>>IFindentshift)*TABPIX;
	# CSS text-indent: apply to first line of block
	if(lay.text_indent != 0 && lprev == lay.start)
		indent += lay.text_indent;
	just := (state&(IFcjust|IFrjust));
	if(just == 0 && lay.just != Aleft) {
		if(lay.just == byte Acenter)
			just = IFcjust;
		else if(lay.just == Aright)
			just = IFrjust;
	}
	right := lay.targetwidth - lay.margin;
	lwid := right - (lfloatw+rfloatw+indent+lay.margin);
	if(lwid < 0) {
		if (right - lwid > lay.width)
			lay.width = right - lwid;
		right += -lwid;
		lwid = 0;
	}
	lwid += hang;
	if(dbg > 1) {
		sys->print("fixlinegeom, now y=%d, lfloatw=%d, rfloatw=%d, indent=%d, hang=%d, lwid=%d\n",
				y, lfloatw, rfloatw, indent, hang, lwid);
	}
	w := 0;
	lineh = 0;
	linea := 0;
	lastit: ref Item = nil;
	nextfloats: list of ref Item.Ifloat = nil;
	anystuff := 0;
	eol := 0;
	while(it != nil && !eol) {
		if(dbg > 2) {
			sys->print("fixlinegeom loop head, w=%d, loop item:\n", w);
			it.print();
		}
		state = it.state;
		wrapping := int (state&IFwrap);
		# CSS white-space: nowrap disables line wrapping
		if(lay.white_space == B->WSnowrap)
			wrapping = 0;
		if(anystuff && (state&IFbrk))
			break;
		checkw := 1;
		if(hang && !(state&IFhangmask)) {
			lwid -= hang;
			hang = 0;
			if(hangtogo > 0) {
				# insert a null spacer item
				spaceit := Item.newspacer(ISPgeneral, 0);
				spaceit.width = hangtogo;
				if(lastit != nil) {
					spaceit.state = lastit.state & ~(IFbrk|IFbrksp|IFnobrk|IFcleft|IFcright);
					lastit.next = spaceit;
				}
				else
					lastit = spaceit;
				spaceit.next = it;
			}
		}
		pick i := it {
		Ifloat =>
			if(anystuff) {
				# float will go after this line
				nextfloats = i :: nextfloats;
			}
			else {
				# add float beside current line, adjust widths
				fixfloatxy(lay, y, i);
				# TODO: only do following if y and/or height changed
				changelines(l.next, lay.end);
				newlfloatw := floatw(y, y+lineh, lay.floats, Aleft);
				newrfloatw := floatw(y, y+lineh, lay.floats, Aright);
				lwid -= (newlfloatw-lfloatw) + (newrfloatw-rfloatw);
				if (lwid < 0) {
					right += -lwid;
					lwid = 0;
				}
				lfloatw = newlfloatw;
				rfloatw = newrfloatw;
			}
			checkw = 0;
		Itable =>
			# When just doing layout for cell dimensions, don't
			# want a "100%" spec to make the table really wide
			kindspec := 0;
			if(lay.targetwidth == TABLEMAXTARGET && i.table.width.kind() == Dpercent) {
				kindspec = i.table.width.kindspec;
				i.table.width = Dimen.make(Dnone, 0);
			}
			checktabsize(f, i, lwid-w);
			if(kindspec != 0)
				i.table.width.kindspec = kindspec;
		Ibox =>
			# Size box using sublayout, like a table cell
			checkboxsize(f, i, i, lwid-w);
		Irule =>
			avail := lwid-w;
			# When just doing layout for cell dimensions, don't
			# want a "100%" spec to make the rule really wide
			if(lay.targetwidth == TABLEMAXTARGET)
				avail = min(10, avail);
			i.width = widthfromspec(i.wspec, avail);
		Iformfield =>
			checkffsize(f, i, i.formfield);
		}
		if(checkw) {
			iw := it.width;
			# CSS letter-spacing / word-spacing: adjust text item widths
			pick ti := it {
			Itext =>
				if(lay.letter_spacing != STYLNONE && lay.letter_spacing != 0 && len ti.s > 1)
					iw += lay.letter_spacing * (len ti.s - 1);
				if(lay.word_spacing != STYLNONE && lay.word_spacing != 0) {
					nsp := 0;
					for(si := 0; si < len ti.s; si++)
						if(ti.s[si] == ' ')
							nsp++;
					iw += lay.word_spacing * nsp;
				}
				it.width = iw;
			}
			if(wrapping && w + iw > lwid) {
				# it doesn't fit; see if it can be broken
				takeit: int;
				noneok := (anystuff || lfloatw != 0 || rfloatw != 0) && !(state&IFnobrk);
				(takeit, iw) = trybreak(it, lwid-w, iw, noneok);
				eol = 1;
				if(!takeit) {
					if(lastit == nil) {
						# Nothing added because one of the float widths
						# is nonzero, and not enough room for anything else.
						# Move y down until there's more room and try again.
						CU->assert(lfloatw != 0 || rfloatw != 0);
						oldy := y;
						y = pastbrk(lay, y, IFcleft|IFcright);
						if(dbg > 1)
							sys->print("moved y past %d, now y=%d\n", oldy, y);
						CU->assert(y > oldy);	# else infinite recurse
						# Do the move down by artificially increasing the
						# height of the previous line
						lprev.height += y-oldy;
						fixlinegeom(f, lay, l);
						return;
					} else
						break;
				}
			}
			w += iw;
			if(hang)
				hangtogo -= w;
			(lineh, linea) = lgeom(lineh, linea, it);
			if(!anystuff) {
				anystuff = 1;
				# don't count an ordinary space as 'stuff' if wrapping
				pick t := it {
				Itext =>
					if(wrapping && t.s == " ")
						anystuff = 0;
				}
			}
		}
		lastit = it;
		it = it.next;
		if(it == nil && !eol) {
			# perhaps next lines items can now fit on this line
			nextl := l.next;
			nit := nextl.items;
			if(nextl != lay.end && !(nit.state&IFbrk)) {
				lastit.next = nit;
				# remove nextl
				l.next = nextl.next;
				l.next.prev = l;
				it = nit;
			}
		}
	}
	# line is complete, next line will start with it (or it is nil)
	rest := it;
	if(lastit == nil)
		CU->raisex("EXInternal: no items on line");
	lastit.next = nil;

	l.width = w;
	x := lfloatw + lay.margin + indent - linehang;
	# shift line if it begins with a space or a rule
	pick pi := l.items {
	Itext =>
		if(pi.s != nil && pi.s[0] == ' ')
			x -= fonts[pi.fnt].spw;
	Irule =>
		# note: build ensures that rules appear on lines
		# by themselves
		if(pi.align == Acenter)
			just = IFcjust;
		else if(pi.align == Aright)
			just = IFrjust;
	Ifloat =>
		if(pi.next != nil) {
			pick qi := pi.next {
			Itext =>
				if(qi.s != nil && qi.s[0] == ' ')
					x -= fonts[qi.fnt].spw;
			}
		}
	}
	xright := x+w;
	if (xright + rfloatw > lay.width)
		lay.width = xright+rfloatw;
	n := lay.targetwidth-(lay.margin+rfloatw+xright);
	if(n > 0 && just) {
		if(just&IFcjust)
			x += n/2;
		else
			x += n;
	}
	if(dbg > 1) {
		sys->print("line geometry fixed, (x,y)=(%d,%d), w=%d, h=%d, a=%d, lfloatw=%d, rfloatw=%d, lay.width=%d\n",
			x, l.pos.y, w, lineh, linea, lfloatw, rfloatw, lay.width);
		if(dbg > 2)
			l.items.printlist("final line items");
	}
	l.pos.x = x;
	# CSS line-height: enforce minimum line height
	if(lay.line_height != STYLNONE && lineh < lay.line_height) {
		extra := lay.line_height - lineh;
		linea += extra / 2;	# center content vertically in line
		lineh = lay.line_height;
	}
	l.height = lineh;
	l.ascent = linea;
	l.flags &= ~Lchanged;

	if(nextfloats != nil)
		fixfloatsafter(lay, l, nextfloats);

	if(rest != nil) {
		nextl := l.next;
		if(nextl == lay.end || (nextl.items.state&IFbrk)) {
			nextl = Line.new();
			appendline(l, nextl);
		}
		li := lastitem(rest);
		li.next = nextl.items;
		nextl.items = rest;
		nextl.flags |= Lchanged;
	}
}

# Return y coord after y due to a break.
pastbrk(lay: ref Lay, y, state: int) : int
{
	nextralines := 0;
	if(state&IFbrksp)
		nextralines = 1;
	ynext := y;
	if(state&IFcleft)
		ynext = floatclry(lay.floats, Aleft, ynext);
	if(state&IFcright)
		ynext = max(ynext, floatclry(lay.floats, Aright, ynext));
	ynext += nextralines*linespace;
	return ynext;
}

# Add line l after lprev (and before lprev's current successor)
appendline(lprev, l: ref Line)
{
	l.next = lprev.next;
	l.prev = lprev;
	l.next.prev = l;
	lprev.next = l;
}

# Mark lines l up to but not including lend as changed
changelines(l, lend: ref Line)
{
	for( ; l != lend; l = l.next)
		l.flags |= Lchanged;
}

# Return a ref Font for font number num = (style*NumSize + size)
getfont(num: int) : ref Font
{
	if(display == nil)
		return nil;
	f := fonts[num].f;
	if(f == nil) {
		f = Font.open(display, fonts[num].name);
		if(f == nil) {
			if(num == DefFnt)
				CU->raisex(sys->sprint("exLayout: can't open default font %s: %r", fonts[num].name));
			else {
				if(int (CU->config).dbg['w'])
					sys->print("warning: substituting default for font %s\n",
						fonts[num].name);
				f = fonts[DefFnt].f;
			}
		}
		fonts[num].f = f;
		fonts[num].spw = f.width(" ");
	}
	return f;
}

# Set the width, height and ascent fields of all items, getting any necessary fonts.
# Some widths and heights depend on the available width on the line, and may be
# wrong until checked during fixlinegeom.
# Don't do tables here at all (except floating tables).
# Configure Controls for form fields.
measure(fr: ref Frame, items: ref Item)
{
	for(it := items; it != nil; it = it.next) {
		pick t := it {
		Itext =>
			f := getfont(t.fnt);
			if(f == nil) {
				it.width = len(t.s) * charspace;
				it.height = linespace;
				it.ascent = lineascent;
			} else {
				it.width = f.width(t.s);
				a := f.ascent;
				h := f.height;
				if(t.voff != byte Voffbias) {
					a -= (int t.voff) - Voffbias;
					if(a > h)
						h = a;
				}
				it.height = h;
				it.ascent = a;
			}
		Irule =>
			it.height =  t.size + 2*RULESP;
			it.ascent = t.size + RULESP;
		Iimage =>
			setimagedims(t);
		Iformfield =>
			c := Control.newff(fr, t.formfield);
			if(c != nil) {
				t.formfield.ctlid = fr.addcontrol(c);
				it.width = c.r.dx();
				it.height = c.r.dy();
				it.ascent = it.height;
				pick pc := c {
				Centry =>
					it.ascent = lineascent + ENTVMARGIN;
				Cselect =>
					it.ascent = lineascent + SELMARGIN;
				Cbutton =>
					if(pc.dorelief)
						it.ascent -= BUTMARGIN;
				}
			}
		Ifloat =>
			# Leave w at zero, so it doesn't contribute to line width in normal way
			# (Can find its width in t.item.width).
			pick i := t.item {
			Iimage =>
				setimagedims(i);
				it.height = t.item.height;
			Itable =>
				checktabsize(fr, i, TABLEFLOATTARGET);
			Ibox =>
				# float containing a box
				measure(fr, i.content);
				checkboxsize(fr, t.item, i, TABLEFLOATTARGET);
				# Include CSS margins in float dimensions for text wrapping
				if(i.cstyle != nil) {
					ml := i.cstyle.margin[3];
					mr := i.cstyle.margin[1];
					mt := i.cstyle.margin[0];
					mb := i.cstyle.margin[2];
					if(ml > 0)
						t.item.width += ml;
					if(mr > 0)
						t.item.width += mr;
					if(mt > 0)
						t.item.height += mt;
					if(mb > 0)
						t.item.height += mb;
				}
				it.height = t.item.height;
			* =>
				CU->assert(0);
			}
			it.ascent = it.height;
		Ibox =>
			# Box with CSS box model
			measure(fr, t.content);
			# Estimate box size from content (will be refined in fixlinegeom)
			contentw := 0;
			contenth := 0;
			for(ci := t.content; ci != nil; ci = ci.next) {
				contentw += ci.width;
				if(ci.height > contenth)
					contenth = ci.height;
			}
			# Add padding and border
			cs := t.cstyle;
			padw := 0;
			padh := 0;
			if(cs != nil) {
				padw = cs.padding[1] + cs.padding[3] + cs.border_width[1] + cs.border_width[3];
				padh = cs.padding[0] + cs.padding[2] + cs.border_width[0] + cs.border_width[2];
			}
			it.width = contentw + padw;
			it.height = contenth + padh;
			it.ascent = it.height;
		Ispacer =>
			case t.spkind {
			ISPvline =>
				f := getfont(t.fnt);
				if(f == nil) {
					it.height = linespace;
					it.ascent = lineascent;
				} else {
					it.height = f.height;
					it.ascent = f.ascent;
				}
			ISPhspace =>
				getfont(t.fnt);
				it.width = fonts[t.fnt].spw;
			}
		}
	}
}

# Set the dimensions of an image item
setimagedims(i: ref Item.Iimage)
{
	i.width = i.imwidth + 2*(int i.hspace + int i.border);
	i.height = i.imheight + 2*(int i.vspace + int i.border);
	i.ascent = i.height - (int i.vspace + int i.border);
	if((CU->config).imagelvl == CU->ImgNone && i.altrep != "") {
		f := fonts[DefFnt].f;
		i.width = max(i.width, f.width(i.altrep));
		i.height = max(i.height, f.height);
		i.ascent = f.ascent;
	}
}

# Line geometry function:
# Given current line height (H) and ascent (distance from top to baseline) (A),
# and an item, see if that item changes height and ascent.
# Return (H', A'), the updated line height and ascent.
lgeom(H, A: int, it: ref Item) : (int, int)
{
	h := it.height;
	a := it.ascent;
	atype := Abaseline;
	pick i := it {
	Iimage =>
		atype = i.align;
	Itable =>
		atype = Atop;
	Ibox =>
		# inline-block with vertical-align uses specified alignment
		if(i.cstyle != nil && i.cstyle.display == DSPINLINEBLOCK
		    && i.cstyle.vertical_align != Anone)
			atype = i.cstyle.vertical_align;
		else
			atype = Atop;
	Ifloat =>
		return (H, A);
	}
	d := h-a;
	Hnew := H;
	Anew := A;
	case int atype {
	int Abaseline or int Abottom =>
		if(a > A) {
			Anew = a;
			Hnew += (Anew - A);
		}
		if(d > Hnew - Anew)
			Hnew = Anew + d;
	int Atop =>
		# OK to ignore what comes after in the line
		if(h > H)
			Hnew = h;
	int Amiddle or int Acenter =>
		# supposed to align middle with baseline
		hhalf := h/2;
		if(hhalf > A)
			Anew = hhalf;
		if(hhalf > H-Anew)
			Hnew = Anew + hhalf;
	}
	return (Hnew, Anew);
}

# Try breaking item bit to make it fit in availw.
# If that is possible, change bit to be the part that fits
# and insert the rest between bit and bit.next.
# iw is the current width of bit.
# If noneok is 0, break off the minimum size word
# even if it exceeds availw.
# Return (1 if supposed to take bit, iw' = new width of bit)
trybreak(bit: ref Item, availw, iw, noneok: int) : (int, int)
{
	if(iw <= 0)
		return (1, iw);
	if(availw < 0) {
		if(noneok)
			return (0, iw);
		else
			availw = 0;
	}
	pick t := bit {
	Itext =>
		if(len t.s < 2)
			return (!noneok, iw);
		(s1, w1, s2, w2) := breakstring(t.s, iw, fonts[t.fnt].f, availw, noneok);
		if(w1 == 0)
			return (0, iw);
		itn := Item.newtext(s2, t.fnt, t.fg, int t.voff, t.ul);
		itn.width = w2;
		itn.height = t.height;
		itn.ascent = t.ascent;
		itn.anchorid = t.anchorid;
		itn.state = t.state & ~(IFbrk|IFbrksp|IFnobrk|IFcleft|IFcright);
		itn.next = t.next;
		t.next = itn;
		t.s = s1;
		t.width = w1;
		return (1, w1);
	}
	return (!noneok, iw);
}

# s has width sw when drawn in fnt.
# Break s into s1 and s2 so that s1 fits in availw.
# If noneok is true, it is ok for s1 to be nil, otherwise might
# have to return an s1 that overflows availw somewhat.
# Return (s1, w1, s2, w2) where w1 and w2 are widths of s1 and s2.
# Assume caller has already checked that sw > availw.
breakstring(s: string, sw: int, fnt: ref Font, availw, noneok: int) : (string, int, string, int)
{
	slen := len s;
	if(slen < 2) {
		if(noneok)
			return (nil, 0, s, sw);
		else
			return (s, sw, nil, 0);
	}

	# Use linear interpolation to guess break point.
	# We know avail < iw by conditions of trybreak call.
	i := slen*availw / sw - 1;
	if(i < 0)
		i = 0;
	i = breakpoint(s, i, -1);
	(ss, ww) := tryw(fnt, s, i);
	if(ww > availw) {
		while(ww > availw) {
			i = breakpoint(s, i-1, -1);
			if(i <= 0)
				break;
			(ss, ww) = tryw(fnt, s, i);
		}
	}
	else {
		oldi := i;
		oldss := ss;
		oldww := ww;
		while(ww < availw) {
			oldi = i;
			oldss = ss;
			oldww = ww;
			i = breakpoint(s, i+1, 1);
			if(i >= slen)
				break;
			(ss, ww) = tryw(fnt, s, i);
		}
		i = oldi;
		ss = oldss;
		ww = oldww;
	}
	if(i <= 0 || i >= slen) {
		if(noneok)
			return (nil, 0, s, sw);
		i = breakpoint(s, 1, 1);
		(ss,ww) = tryw(fnt, s, i);
	}
	return (ss, ww, s[i:slen], sw-ww);
}

# If can break between s[i-1] and s[i], return i.
# Else move i in direction incr until this is true.
# (Might end up returning 0 or len s).
breakpoint(s: string, i, incr: int) : int
{
	slen := len s;
	ans := 0;
	while(i > 0 && i < slen) {
		ci := s[i];
		di := s[i-1];
		
		# ASCII rules
		if ((ci < 16rA0 && !int wordchar[ci]) || (di < 16rA0 && !int wordchar[di])) {
			ans = i;
			break;
		}

		# Treat all ideographs as breakable.
		# The following range includes unassigned unicode code points.
		# All assigned code points in the range are class ID (ideograph) as defined
		# by the Unicode consortium's LineBreak data.
		# There are many other class ID code points outside of this range.
		# For details on how to do unicode line breaking properly see:
		# Unicode Standard Annex #14 (http://www.unicode.org/unicode/reports/tr14/)

		if ((ci >= 16r30E && ci <= 16r9FA5) || (di >= 16r30E && di <= 16r9FA5)) {
			ans = i;
			break;
		}

		# consider all other characters as unbreakable
		i += incr;
	}
	if(i == slen)
		ans = slen;
	return ans;
}

# Return (s[0:i], width of that slice in font fnt)
tryw(fnt: ref Font, s: string, i: int) : (string, int)
{
	if(i == 0)
		return ("", 0);
	ss := s[0:i];
	return (ss, fnt.width(ss));
}

# Return max width of a float that overlaps [ymin, ymax) on given side.
# Floats are in reverse order of addition, so each float's y is <= that of
# preceding floats in list.  Floats from both sides are intermixed.
floatw(ymin, ymax: int, flist: list of ref Item.Ifloat, side: byte) : int
{
	ans := 0;
	for( ; flist != nil; flist = tl flist) {
		fl := hd flist;
		if(fl.side != side)
			continue;
		fymin := fl.y;
		fymax := fymin + fl.item.height;
		if(fl.item.height == 0)
			fymax++;	# assume float will have some height later
		if((fymin <= ymin && ymin < fymax) ||
		   (ymin <= fymin && fymin < ymax)) {
			w := fl.x;
			if(side == Aleft)
				w += fl.item.width;
			if(ans < w)
				ans = w;
		}
	}
	return ans;
}

# Float f is to be at vertical position >= y.
# Fix its (x,y) pos and add it to lay.floats, if not already there.
fixfloatxy(lay: ref Lay, y: int, f: ref Item.Ifloat)
{
	height := f.item.height;
	width := f.item.width;
	f.y = y;
	flist := lay.floats;
	if(f.infloats != byte 0) {
		# only take previous floats into account for width
		while(flist != nil) {
			x := hd flist;
			flist = tl flist;
			if(x == f)
				break;
		}
	}
	f.x = floatw(y, y+height, flist, f.side);
	endx := f.x + width + lay.margin;
	if (endx > lay.width)
		lay.width = endx;
	if (f.side == Aright)
		f.x += width;
	endy := f.y + height + lay.margin;
	if (endy > lay.height)
		lay.height = endy;
	if(f.infloats == byte 0) {
		lay.floats = f :: lay.floats;
		f.infloats = byte 1;
	}
}

# Floats in flist are to go after line l.
fixfloatsafter(lay: ref Lay, l: ref Line, flist: list of ref Item.Ifloat)
{
	change := 0;
	y := l.pos.y + l.height;
	for(itl := Item.revlist(flist); itl != nil; itl = tl itl) {
		pick fl := hd itl {
		Ifloat =>
			oldy := fl.y;
			fixfloatxy(lay, y, fl);
			if(fl.y != oldy)
				change = 1;
			y += fl.item.height;
		}
	}
#	if(change)
# TODO only change if y and/or height changed
		changelines(l.next, lay.end);
}

# If there's a float on given side that starts on or before y and
# ends after y, return ending y of that float, else return original y.
# Assume float list is bottom up.
floatclry(flist: list of ref Item.Ifloat, side: byte, y: int) : int
{
	ymax := y;
	for( ; flist != nil; flist = tl flist) {
		fl := hd flist;
		if(fl.side == side) {
			if(fl.y <= y) {
				flymax := fl.y + fl.item.height;
				if (fl.item.height == 0)
					# assume it will have some height later
					flymax++;
				if(flymax > ymax)
					ymax = flymax;
			}
		}
	}
	return ymax;
}

# Do preliminaries to laying out table tab in target width linewidth,
# setting total height and width.
sizetable(f: ref Frame, tab: ref Table, availwidth: int)
{
	if(dbgtab)
		sys->print("sizetable %d, availwidth=%d, nrow=%d, ncol=%d, changed=%x, tab.availw=%d\n",
			tab.tableid, availwidth, tab.nrow, tab.ncol, int (tab.flags&Lchanged), tab.availw);
	if(tab.ncol == 0 || tab.nrow == 0)
		return;
	if(tab.availw == availwidth && (tab.flags&Lchanged) == byte 0)
		return;
	# table-layout: fixed — use first row/col specs for widths, skip content measuring
	if(tab.table_layout == byte 1 && tab.width.kind() != Dnone) {
		sizetable_fixed(f, tab, availwidth);
		return;
	}
	(hsp, vsp, pad, bd, cbd, hsep, vsep) := tableparams(tab);
	totw := widthfromspec(tab.width, availwidth);
	# reduce totw by spacing, padding, and rule widths
	# to leave amount left for contents
	totw -= (tab.ncol-1)*hsep+ 2*(hsp+bd+pad+cbd);
	if(totw <= 0)
		totw = 1;
	if(dbgtab)
		sys->print("\nsizetable %d, totw=%d, hsp=%d, vsp=%d, pad=%d, bd=%d, cbd=%d, hsep=%d, vsep=%d\n",
			tab.tableid, totw, hsp, vsp, pad, bd, cbd, hsep, vsep);
	for(cl := tab.cells; cl != nil; cl = tl cl) {
		c := hd cl;
		clay : ref Lay = nil;
		if(c.layid >= 0)
			clay = f.sublays[c.layid];
		if(clay == nil || (clay.flags&Lchanged) != byte 0) {
			c.minw = -1;
			tw := TABLEMAXTARGET;
			if(c.wspec.kind() != Dnone)
				tw = widthfromspec(c.wspec, totw);

			# When finding max widths, want to lay out using Aleft alignment,
			# because we don't yet know final width for proper justification.
			# If the max widths are accepted, we'll redo those needing other justification.
			if(clay == nil) {
				if(dbg)
					sys->print("Initial layout for cell %d.%d\n", tab.tableid, c.cellid);
				c.layid = sublayout(f, tw, Aleft, c.background, c.content);
				clay = f.sublays[c.layid];
				c.content = nil;
			}
			else {
				if(dbg)
					sys->print("Relayout (for max) for cell %d.%d\n", tab.tableid, c.cellid);
				relayout(f, clay, tw, Aleft);
			}
			clay.flags |= Lchanged;	# for min test, below
			c.maxw = clay.width;
			if(dbgtab)
				sys->print("sizetable %d for cell %d max layout done, targw=%d, c.maxw=%d\n",
						tab.tableid, c.cellid, tw, c.maxw);
			if(c.wspec.kind() == Dpixels) {
				# Other browsers don't make the following adjustment for
				# percentage and relative widths
				if(c.maxw <= tw)
					c.maxw = tw;
				if(dbgtab)
					sys->print("after spec adjustment, c.maxw=%d\n", c.maxw);
			}
		}
	}

	# calc max column widths
	colmaxw := array[tab.ncol] of { * => 0};
	maxw := widthcalc(tab, colmaxw, hsep, 1);

	if(dbgtab)
		sys->print("sizetable %d maxw=%d, totw=%d\n", tab.tableid, maxw, totw);
	ci: int;
	if(maxw <= totw) {
		# trial layouts are fine,
		# but if table width was specified, add more space
		d := 0;
		adjust := (totw > maxw && tab.width.kind() != Dnone);
		for(ci = 0; ci < tab.ncol; ci++) {
			if (adjust) {
				delta := (totw-maxw);
				d = delta / (tab.ncol - ci);
				if (d <= 0) {
					d = delta;
					adjust = 0;
				}
				maxw += d;
			}
			tab.cols[ci].width = colmaxw[ci] + d;
		}
	}
	else {
		# calc min column widths and  apportion out
		# differences
		if(dbgtab)
			sys->print("sizetable %d, availwidth %d, need min widths too\n", tab.tableid, availwidth);
		for(cl = tab.cells; cl != nil; cl = tl cl) {
			c := hd cl;
			clay := f.sublays[c.layid];
			if(c.minw == -1 || (clay.flags&Lchanged) != byte 0) {
				if(dbg)
					sys->print("Relayout (for min) for cell %d.%d\n", tab.tableid, c.cellid);
				relayout(f, clay, 1, Aleft);
				c.minw = clay.width;
				if(dbgtab)
					sys->print("sizetable %d for cell %d min layout done, c.min=%d\n",
						tab.tableid, c.cellid, clay.width);
			}
		}
		colminw := array[tab.ncol] of { * => 0};
		minw := widthcalc(tab, colminw, hsep, 0);
		w := totw - minw;
		d := maxw - minw;
		if(dbgtab)
			sys->print("sizetable %d minw=%d, w=%d, d=%d\n", tab.tableid, minw, w, d);
		for(ci = 0; ci < tab.ncol; ci++) {
			wd : int;
			if(w < 0 || d < 0)
				wd = colminw[ci];
			else
				wd = colminw[ci] + (colmaxw[ci] - colminw[ci])*w/d;
			if(dbgtab)
				sys->print("sizetable %d col[%d].width = %d\n", tab.tableid, ci, wd);
			tab.cols[ci].width = wd;
		}

		if(dbgtab)
			sys->print("sizetable %d, availwidth %d, doing final layouts\n", tab.tableid, availwidth);
	}

	# now have col widths; set actual cell dimensions
	# and relayout (note: relayout will do no work if the target width
	# and just haven't changed from last layout)
	for(cl = tab.cells; cl != nil; cl = tl cl) {
		c := hd cl;
		clay := f.sublays[c.layid];
		wd := cellwidth(tab, c, hsep);
		if(dbgtab)
			sys->print("sizetable %d for cell %d, clay.width=%d, cellwidth=%d\n",
					tab.tableid, c.cellid, clay.width, wd);
		if(dbg)
			sys->print("Relayout (final) for cell %d.%d\n", tab.tableid, c.cellid);
		relayout(f, clay, wd, c.align.halign);
		if(dbgtab)
			sys->print("sizetable %d for cell %d, final width %d, got width %d, height %d\n",
					tab.tableid, c.cellid, wd, clay.width, clay.height);
	}

	# set row heights and ascents
	# first pass: ignore cells with rowspan > 1
	for(ri := 0; ri < tab.nrow; ri++) {
		row := tab.rows[ri];
		h := 0;
		a := 0;
		n : int;
		for(rcl := row.cells; rcl != nil; rcl = tl rcl) {
			c := hd rcl;
			if(c.rowspan > 1 || c.layid < 0)
				continue;
			al := c.align.valign;
			if(al == Anone)
				al = tab.rows[c.row].align.valign;
			clay := f.sublays[c.layid];
			if(al == Abaseline) {
				n = c.ascent;
				if(n > a) {
					h += (n - a);
					a = n;
				}
				n = clay.height - c.ascent;
				if(n > h-a)
					h = a + n;
			}
			else {
				n = clay.height;
				if(n > h)
					h = n;
			}
		}
		row.height = h;
		row.ascent = a;
	}
	# second pass: take care of rowspan > 1
	# (this algorithm isn't quite right -- it might add more space
	# than is needed in the presence of multiple overlapping rowspans)
	for(cl = tab.cells; cl != nil; cl = tl cl) {
		c := hd cl;
		if(c.rowspan > 1) {
			spanht := 0;
			for(i := 0; i < c.rowspan && c.row+i < tab.nrow; i++)
				spanht += tab.rows[c.row+i].height;
			if(c.layid < 0)
				continue;
			clay := f.sublays[c.layid];
			ht := clay.height - (c.rowspan-1)*vsep;
			if(ht > spanht) {
				# add extra space to last spanned row
				i = c.row+c.rowspan-1;
				if(i >= tab.nrow)
					i = tab.nrow - 1;
				tab.rows[i].height += ht - spanht;
				if(dbgtab)
					sys->print("sizetable %d, row %d height %d\n", tab.tableid, i, tab.rows[i].height);
			}
		}
	}
	# get total width, heights, and col x / row y positions
	totw = bd + hsp + cbd + pad;
	for(ci = 0; ci < tab.ncol; ci++) {
		tab.cols[ci].pos.x = totw;
		if(dbgtab)
			sys->print("sizetable %d, col %d at x=%d\n", tab.tableid, ci, totw);
		totw += tab.cols[ci].width + hsep;
	}
	totw = totw - (cbd+pad) + bd;
	toth := bd + vsp + cbd + pad;
	# first time: move tab.caption items into layout
	if(tab.caption != nil) {
		# lay caption with Aleft; drawing will center it over the table width
		tab.caption_lay = sublayout(f, availwidth, Aleft, f.layout.background, tab.caption);
		caplay := f.sublays[tab.caption_lay];
		tab.caph = caplay.height + CAPSEP;
		tab.caption = nil;
	}
	else if(tab.caption_lay >= 0) {
		caplay := f.sublays[tab.caption_lay];
		if(tab.availw != availwidth || (caplay.flags&Lchanged) != byte 0) {
			relayout(f, caplay, availwidth, Aleft);
			tab.caph = caplay.height + CAPSEP;
		}
	}
	if(tab.caption_place == Atop)
		toth += tab.caph;
	for(ri = 0; ri < tab.nrow; ri++) {
		tab.rows[ri].pos.y = toth;
		if(dbgtab)
			sys->print("sizetable %d, row %d at y=%d\n", tab.tableid, ri, toth);
		toth += tab.rows[ri].height + vsep;
	}
	toth = toth - (cbd+pad) + bd;
	if(tab.caption_place == Abottom)
		toth += tab.caph;
	tab.totw = totw;
	tab.toth = toth;
	tab.availw = availwidth;
	tab.flags &= ~Lchanged;
	if(dbgtab)
		sys->print("\ndone sizetable %d, availwidth %d, totw=%d, toth=%d\n\n",
			tab.tableid, availwidth, totw, toth);
}

# Fixed table layout: column widths from col specs and first-row cells only.
# Much faster than auto layout for large tables.
sizetable_fixed(f: ref Frame, tab: ref Table, availwidth: int)
{
	(hsp, vsp, pad, bd, cbd, hsep, vsep) := tableparams(tab);
	totw := widthfromspec(tab.width, availwidth);
	totw -= (tab.ncol-1)*hsep + 2*(hsp+bd+pad+cbd);
	if(totw <= 0)
		totw = 1;

	# Determine column widths from col specs or first-row cells
	colw := array[tab.ncol] of { * => 0 };
	assigned := 0;
	remaining := totw;

	# First pass: explicit col specs
	for(ci := 0; ci < tab.ncol; ci++) {
		if(ci < len tab.cols && tab.cols[ci].width > 0) {
			colw[ci] = tab.cols[ci].width;
			assigned++;
			remaining -= colw[ci];
		}
	}

	# Second pass: first-row cell widths for unassigned columns
	if(tab.nrow > 0) {
		row := tab.rows[0];
		for(rcl := row.cells; rcl != nil; rcl = tl rcl) {
			c := hd rcl;
			if(c.colspan == 1 && c.col < tab.ncol && colw[c.col] == 0) {
				if(c.wspec.kind() == Dpixels) {
					colw[c.col] = c.wspec.spec();
					assigned++;
					remaining -= colw[c.col];
				} else if(c.wspec.kind() == Dpercent) {
					colw[c.col] = totw * c.wspec.spec() / 100;
					assigned++;
					remaining -= colw[c.col];
				}
			}
		}
	}

	# Distribute remaining width equally among unassigned columns
	unassigned := tab.ncol - assigned;
	if(unassigned > 0 && remaining > 0) {
		share := remaining / unassigned;
		for(ci = 0; ci < tab.ncol; ci++)
			if(colw[ci] == 0)
				colw[ci] = share;
	}

	# Set final column widths
	for(ci = 0; ci < tab.ncol; ci++)
		tab.cols[ci].width = colw[ci];

	# Recalculate totw from actual column widths
	totw = 0;
	for(ci = 0; ci < tab.ncol; ci++)
		totw += tab.cols[ci].width;
	totw += (tab.ncol-1)*hsep + 2*(hsp+bd+pad+cbd);

	# Layout all cells at fixed widths
	for(cl := tab.cells; cl != nil; cl = tl cl) {
		c := hd cl;
		wd := cellwidth(tab, c, hsep);
		if(c.layid < 0) {
			c.layid = sublayout(f, wd, c.align.halign, c.background, c.content);
			c.content = nil;
		} else
			relayout(f, f.sublays[c.layid], wd, c.align.halign);
	}

	# Set row heights (same logic as auto layout)
	for(ri := 0; ri < tab.nrow; ri++) {
		row := tab.rows[ri];
		h := 0;
		for(rcl := row.cells; rcl != nil; rcl = tl rcl) {
			c := hd rcl;
			if(c.rowspan > 1 || c.layid < 0)
				continue;
			clay := f.sublays[c.layid];
			if(clay.height > h)
				h = clay.height;
		}
		row.height = h;
		row.ascent = 0;
	}

	# Handle rowspan > 1
	for(cl = tab.cells; cl != nil; cl = tl cl) {
		c := hd cl;
		if(c.rowspan > 1 && c.layid >= 0) {
			spanht := 0;
			for(i := 0; i < c.rowspan && c.row+i < tab.nrow; i++)
				spanht += tab.rows[c.row+i].height;
			clay := f.sublays[c.layid];
			ht := clay.height - (c.rowspan-1)*vsep;
			if(ht > spanht) {
				extra := ht - spanht;
				for(i = 0; i < c.rowspan && c.row+i < tab.nrow; i++) {
					h := extra / (c.rowspan - i);
					tab.rows[c.row+i].height += h;
					extra -= h;
				}
			}
		}
	}

	# Set column positions
	x := hsp + bd + pad + cbd;
	for(ci = 0; ci < tab.ncol; ci++) {
		tab.cols[ci].pos.x = x;
		x += tab.cols[ci].width + hsep;
	}

	# Caption
	toth := vsp + bd;
	if(tab.caption != nil) {
		tab.caption_lay = sublayout(f, availwidth, Aleft, Background(nil, -1), tab.caption);
		caplay := f.sublays[tab.caption_lay];
		tab.caph = caplay.height + CAPSEP;
		tab.caption = nil;
	} else if(tab.caption_lay >= 0) {
		caplay := f.sublays[tab.caption_lay];
		if(tab.availw != availwidth || (caplay.flags&Lchanged) != byte 0) {
			relayout(f, caplay, availwidth, Aleft);
			tab.caph = caplay.height + CAPSEP;
		}
	}
	if(tab.caption_place == Atop)
		toth += tab.caph;
	for(ri = 0; ri < tab.nrow; ri++) {
		tab.rows[ri].pos.y = toth;
		toth += tab.rows[ri].height + vsep;
	}
	toth = toth - (cbd+pad) + bd;
	if(tab.caption_place == Abottom)
		toth += tab.caph;
	tab.totw = totw;
	tab.toth = toth;
	tab.availw = availwidth;
	tab.flags &= ~Lchanged;
}

# Calculate various table spacing parameters
# Handles CSS border-collapse and border-spacing
tableparams(tab: ref Table) : (int, int, int, int, int, int, int)
{
	bd := tab.border;
	hsp := tab.cellspacing;
	vsp := hsp;
	pad := tab.cellpadding;

	# CSS border-spacing overrides cellspacing when set
	if(tab.border_spacing > 0) {
		hsp = tab.border_spacing;
		vsp = tab.border_spacing;
	}

	# border-collapse: collapse eliminates inter-cell spacing
	if(tab.border_collapse == byte 1) {
		hsp = 0;
		vsp = 0;
	}

	if(bd != 0)
		cbd := 1;
	else
		cbd = 0;

	# In collapsed mode, no cell border distinction
	if(tab.border_collapse == byte 1)
		cbd = 0;

	hsep := 2*(cbd+pad)+hsp;
	vsep := 2*(cbd+pad)+vsp;
	return (hsp, vsp, pad, bd, cbd, hsep, vsep);
}

# return cell width, taking multicol spanning into account
cellwidth(tab: ref Table, c: ref Tablecell, hsep: int) : int
{
	if(c.colspan == 1)
		return tab.cols[c.col].width;
	wd := (c.colspan-1)*hsep;
	for(i := 0; i < c.colspan && c.col + i < tab.ncol; i++)
		wd += tab.cols[c.col + i].width;
	return wd;
}

# return cell height, taking multirow spanning into account
cellheight(tab: ref Table, c: ref Tablecell, vsep: int) : int
{
	if(c.rowspan == 1)
		return tab.rows[c.row].height;
	ht := (c.rowspan-1)*vsep;
	for(i := 0; i < c.rowspan && c.row + i < tab.nrow; i++)
		ht += tab.rows[c.row + i].height;
	return ht;
}

# Calculate the column widths w as the max of the cells
# maxw or minw (as domax is 1 or 0).
# Return the total of all w.
# (hseps were accounted for by the adjustment that got
# totw from availwidth).
# hsep is amount of free space available between columns
# where there is multicolumn spanning.
# This is a two-pass algorithm.  The first pass ignores
# cells that span multiple columns.  The second pass
# sees if those multispanners need still more space, and
# if so, apportions the space out.
widthcalc(tab: ref Table, w: array of int, hsep, domax: int) : int
{
	anyspan := 0;
	totw := 0;
	for(pass := 1; pass <= 2; pass++) {
		if(pass==2 && !anyspan)
			break;
		totw = 0;
		for(ci := 0; ci < tab.ncol; ci++) {
			for(ri := 0; ri < tab.nrow; ri++) {
				c := tab.grid[ri][ci];
				if(c == nil)
					continue;
				if(domax)
					cwd := c.maxw;
				else
					cwd = c.minw;
				if(pass == 1) {
					if(c.colspan > 1) {
						anyspan = 1;
						continue;
					}
					if(cwd > w[ci])
						w[ci] = cwd;
				}
				else {
					if(c.colspan == 1 || !(ci==c.col && ri==c.row))
						continue;
					curw := 0;
					iend := ci+c.colspan;
					if(iend > tab.ncol)
						iend = tab.ncol;
					for(i:=ci; i < iend; i++)
						curw += w[i];
				
					# padding between spanned cols is free
					cwd -= hsep*(c.colspan-1);
					diff := cwd-curw;
					if(diff <= 0)
						continue;
					# doesn't fit: apportion diff among cols
					# in proportion to their current w
					for(i = ci; i < iend; i++) {
						if(curw == 0)
							w[i] = diff/c.colspan;
						else
							w[i] += diff*w[i]/curw;
					}
				}
			}
			totw += w[ci];
		}
	}
	return totw;
}

layframeset(f: ref Frame, ki: ref Kidinfo)
{
	fwid := f.cr.dx();
	fht := f.cr.dy();
	if(dbg)
		sys->print("layframeset, configuring frame %d wide by %d high\n", fwid, fht);
	(nrow, rowh) := frdimens(ki.rows, fht);
	(ncol, colw) := frdimens(ki.cols, fwid);
	l := ki.kidinfos;
	y := f.cr.min.y;
	for(i := 0; i < nrow; i++) {
		x := f.cr.min.x;
		for(j := 0; j < ncol; j++) {
			if(l == nil)
				return;
			r := Rect(Point(x,y), Point(x+colw[j],y+rowh[i]));
			if(dbg)
				sys->print("kid gets rect (%d,%d)(%d,%d)\n", r.min.x, r.min.y, r.max.x, r.max.y);
			kidki := hd l;
			l = tl l;
			kidf := Frame.newkid(f, kidki, r);
			if(!kidki.isframeset)
				f.kids = kidf :: f.kids;
			if(kidf.framebd != 0) {
				kidf.cr = kidf.r.inset(2);
				drawborder(kidf.cim, kidf.cr, 2, DarkGrey);
			}
			if(kidki.isframeset) {
				layframeset(kidf, kidki);
				for(al := kidf.kids; al != nil; al = tl al)
					f.kids = (hd al) :: f.kids;
			}
			x += colw[j];
		}
		y += rowh[i];
	}
}

# Use the dimension specs in dims to allocate total space t.
# Return (number of dimens, array of allocated space)
frdimens(dims: array of B->Dimen, t: int): (int, array of int)
{
	n := len dims;
	if(n == 1)
		return (1, array[] of {t});
	totpix := 0;
	totpcnt := 0;
	totrel := 0;
	for(i := 0; i < n; i++) {
		v := dims[i].spec();
		kind := dims[i].kind();
		if(v < 0) {
			v = 0;
			dims[i] = Dimen.make(kind, v);
		}
		case kind {
			B->Dpixels => totpix += v;
			B->Dpercent => totpcnt += v;
			B->Drelative => totrel += v;
			B->Dnone => totrel++;
		}
	}
	spix := 1.0;
	spcnt := 1.0;
	min_relu := 0;
	if(totrel > 0)
		min_relu = 30;	# allow for scrollbar (14) and a bit
	relu := real min_relu;
	tt := totpix + (t*totpcnt/100) + totrel*min_relu;
	# want
	#  t ==  totpix*spix + (totpcnt/100)*spcnt*t + totrel*relu
	if(tt < t) {
		# need to expand one of spix, spcnt, relu
		if(totrel == 0) {
			if(totpcnt != 0)
				# spix==1.0, relu==0, solve for spcnt
				spcnt = real ((t-totpix) * 100)/ real (t*totpcnt);
			else
				# relu==0, totpcnt==0, solve for spix
				spix = real t/ real totpix;
		}
		else
			# spix=1.0, spcnt=1.0, solve for relu
			relu += real (t-tt)/ real totrel;
	}
	else {
		# need to contract one or more of spix, spcnt, and have relu==min_relu
		totpixrel := totpix+totrel*min_relu;
		if(totpixrel < t) {
			# spix==1.0, solve for spcnt
			spcnt = real ((t-totpixrel) * 100)/ real (t*totpcnt);
		}
		else {
			# let spix==spcnt, solve
			trest := t - totrel*min_relu;
			if(trest > 0) {
				spcnt = real trest/real (totpix+(t*totpcnt/100));
			}
			else {
				spcnt = real t / real tt;
				relu = 0.0;
			}
			spix = spcnt;
		}
	}
	x := array[n] of int;
	tt = 0;
	for(i = 0; i < n-1; i++) {
		vr := real dims[i].spec();
		case dims[i].kind() {
			B->Dpixels => vr = vr * spix;
			B->Dpercent => vr = vr * real t * spcnt / 100.0;
			B->Drelative => vr = vr * relu;
			B->Dnone => vr = relu;
		}
		x[i] = int vr;
		tt += x[i];
	}
	x[n-1] = t - tt;
	return (n, x);
}

# Return last item of list of items, or nil if no items
lastitem(it: ref Item) : ref Item
{
	ans : ref Item = it;
	for( ; it != nil; it = it.next)
		ans = it;
	return ans;
}

# Lay out table if availw changed or tab changed
checktabsize(f: ref Frame, t: ref Item.Itable, availw: int)
{
	tab := t.table;
	if (dbgtab)
		sys->print("checktabsize %d, availw %d, tab.availw %d, changed %d\n", tab.tableid, availw, tab.availw, (tab.flags&Lchanged)>byte 0);
	if(availw != tab.availw || int (tab.flags&Lchanged)) {
		sizetable(f, tab, availw);
		t.width = tab.totw + 2*tab.border;
		t.height = tab.toth + 2*tab.border;
		t.ascent = t.height;
	}
}

widthfromspec(wspec: Dimen, availw: int) : int
{
	w := availw;
	spec := wspec.spec();
	case wspec.kind() {
		Dpixels => w = spec;
		Dpercent => w = spec*w/100;
	}
	return w;
}

# An image may have arrived for an image input field
checkffsize(f: ref Frame, i: ref Item, ff: ref Formfield)
{
	if(ff.ftype == Fimage && ff.image != nil) {
		pick imi := ff.image {
		Iimage =>
			if(imi.ci.mims != nil && len imi.ci.mims > 0 && imi.ci.mims[0] != nil && imi.ci.mims[0].im != nil && ff.ctlid >= 0) {
				pick b := f.controls[ff.ctlid] {
				Cbutton =>
					if(b.pic == nil) {
						b.pic = imi.ci.mims[0].im;
						b.picmask = imi.ci.mims[0].mask;
						w := b.pic.r.dx();
						h := b.pic.r.dy();
						b.r.max.x = b.r.min.x + w;
						b.r.max.y = b.r.min.y + h;
						i.width = w;
						i.height = h;
						i.ascent = h;
					}
				}
			}
		}
	}
	else if(ff.ftype == Fselect) {
		opts := ff.options;
		if(ff.ctlid >=0) {
			pick c := f.controls[ff.ctlid] {
			Cselect =>
				if(len opts != len c.options) {
					nc := Control.newff(f, ff);
					f.controls[ff.ctlid] = nc;
					i.width = nc.r.dx();
					i.height = nc.r.dy();
					i.ascent = lineascent + SELMARGIN;
				}
			}
		}
	}
}

drawall(f: ref Frame)
{
	if(display == nil)
		return;		# headless mode: no rendering
	if((CU->config).doacme && !(CU->config).dorender)
		return;		# in acme mode don't bother (unless render mode)
	oclipr := f.cim.clipr;
	origin := f.lptosp(zp);
	clipr := f.dirtyr.addpt(origin);
	f.cim.clipr = clipr;
	fillbg(f, clipr);
	if(dbg > 1)
		sys->print("drawall, cr=(%d,%d,%d,%d), viewr=(%d,%d,%d,%d), origin=(%d,%d)\n",
			f.cr.min.x, f.cr.min.y, f.cr.max.x, f.cr.max.y,
			f.viewr.min.x, f.viewr.min.y, f.viewr.max.x, f.viewr.max.y,
			origin.x, origin.y);
	if(f.layout != nil)
		drawlay(f, f.layout, origin);
	f.cim.clipr = oclipr;
	G->flush(f.cr);
	f.isdirty = 0;
}

drawlay(f: ref Frame, lay: ref Lay, origin: Point)
{
	for(l := lay.start.next; l != lay.end; l = l.next)
		drawline(f, origin, l, lay);
}

# Draw line l in frame f, assuming that content's (0,0)
# aligns with layorigin in f.cim.
drawline(f : ref Frame, layorigin : Point, l: ref Line, lay: ref Lay)
{
	im := f.cim;
	o := layorigin.add(l.pos);
	x := o.x;
	y := o.y;
	lr := Rect(zp, Point(l.width, l.height)).addpt(o);
	isdirty := f.isdirty && lr.Xrect(f.dirtyr.addpt(f.lptosp(zp)));
	inview := lr.Xrect(f.cr) && isdirty;

	# note: drawimg must always be called to update
	# draw point of animated images
	for(it := l.items; it != nil; it = it.next) {
		pick i := it {
		Itext =>
			if (!inview || i.s == nil)
				break;
			fnt := fonts[i.fnt];
			width := i.width;
			yy := y+l.ascent - fnt.f.ascent + (int i.voff) - Voffbias;
			if (f.prctxt != nil) {
				if (yy < f.cr.min.y)
					continue;
				endy := yy + fnt.f.height;
				if (endy > f.cr.max.y) {
					# do not draw
					if (yy < f.prctxt.endy)
						f.prctxt.endy = yy;
					continue;
				}
			}
			fgi := colorimage(i.fg);
			im.text(Point(x, yy), fgi, zp, fnt.f, i.s);
			if(i.ul != ULnone) {
				if(i.ul == ULmid)
					yy += 2*i.ascent/3;
				else
					yy += i.height - 1;
				# don't underline leading space
				# have already adjusted x pos in fixlinegeom()
				ulx := x;
				ulw := width;
				if (i.s[0] == ' ') {
					ulx += fnt.spw;
					ulw -= fnt.spw;
				}
				if (i.s[len i.s - 1] == ' ')
					ulw -= fnt.spw;
				if (ulw < 1)
					continue;
				im.drawop(Rect(Point(ulx,yy),Point(ulx+ulw,yy+1)), fgi, nil, zp, Draw->S);
			}
		Irule =>
			if (!inview)
				break;
			yy := y + RULESP;
			im.draw(Rect(Point(x,yy),Point(x+i.width,yy+i.size)),
					display.black, nil, zp);
		Iimage =>
			yy := y;
			if(i.align == Abottom)
				# bottom aligns with baseline
				yy += l.ascent - i.imheight;
			else if(i.align == Amiddle)
				yy += l.ascent - (i.imheight/2);
			drawimg(f, Point(x,yy), i);
		Iformfield =>
			ff := i.formfield;
			if(ff.ctlid >= 0 && ff.ctlid < len f.controls) {
				ctl := f.controls[ff.ctlid];
				dims := ctl.r.max.sub(ctl.r.min);
				# align as text
				yy := y + l.ascent - i.ascent;
				p := Point(x,yy);
				ctl.r = Rect(p, p.add(dims));
				if (!inview)
					break;
				if (f.prctxt != nil) {
					if (yy < f.cr.min.y)
						continue;
					if (ctl.r.max.y > f.cr.max.y) {
						# do not draw
						if (yy < f.prctxt.endy)
							f.prctxt.endy = yy;
						continue;
					}
				}
				ctl.draw(0);
			}
		Itable =>
			# don't check inview - table can contain images
			drawtable(f, lay, Point(x,y), i.table);
		Ibox =>
			# Draw box with CSS box model
			# Apply positioning offsets
			ox := x;
			oy := y;
			if(i.cstyle != nil) {
				case int i.cstyle.position {
				int POSrelative =>
					if(i.cstyle.rel_left != 0)
						ox += i.cstyle.rel_left;
					else if(i.cstyle.pos_right != STYLNONE)
						ox -= i.cstyle.pos_right;
					if(i.cstyle.rel_top != 0)
						oy += i.cstyle.rel_top;
					else if(i.cstyle.pos_bottom != STYLNONE)
						oy -= i.cstyle.pos_bottom;
				int POSabsolute =>
					# Position relative to containing block (frame content area)
					ox = f.cr.min.x;
					oy = f.cr.min.y;
					if(i.cstyle.rel_left != 0)
						ox += i.cstyle.rel_left;
					else if(i.cstyle.pos_right != STYLNONE)
						ox = f.cr.max.x - i.width - i.cstyle.pos_right;
					if(i.cstyle.rel_top != 0)
						oy += i.cstyle.rel_top;
					else if(i.cstyle.pos_bottom != STYLNONE)
						oy = f.cr.max.y - i.height - i.cstyle.pos_bottom;
				int POSfixed =>
					# Position relative to viewport (frame rect)
					ox = f.r.min.x;
					oy = f.r.min.y;
					if(i.cstyle.rel_left != 0)
						ox += i.cstyle.rel_left;
					else if(i.cstyle.pos_right != STYLNONE)
						ox = f.r.max.x - i.width - i.cstyle.pos_right;
					if(i.cstyle.rel_top != 0)
						oy += i.cstyle.rel_top;
					else if(i.cstyle.pos_bottom != STYLNONE)
						oy = f.r.max.y - i.height - i.cstyle.pos_bottom;
				int POSsticky =>
					# Sticky: like relative, but clamp to viewport top when scrolled past
					stickyoff := i.cstyle.rel_top;
					viewtop := f.viewr.min.y;
					if(oy < viewtop + stickyoff)
						oy = viewtop + stickyoff;
				}
			}
			if(inview)
				drawbox(f, lay, Point(ox,oy), i);
		Ifloat =>
			xx := layorigin.x + lay.margin;
			if(i.side == Aright) {
				xx -= i.x;
#				# for main layout of frame, floats hug
#				# right edge of frame, not layout
#				# (other browsers do that)
#				if(f.layout == lay)
					xx += lay.targetwidth;
#				else
#					xx += lay.width;
			}
			else
				xx += i.x;
			pick fi := i.item {
			Iimage =>
				drawimg(f, Point(xx, layorigin.y + i.y + (int fi.border + int fi.vspace)), fi);
			Itable =>
				drawtable(f, lay, Point(xx, layorigin.y + i.y), fi.table);
			Ibox =>
				# Offset by CSS margins (included in float dimensions)
				bxx := xx;
				byy := layorigin.y + i.y;
				if(fi.cstyle != nil) {
					if(fi.cstyle.margin[3] > 0)
						bxx += fi.cstyle.margin[3];
					if(fi.cstyle.margin[0] > 0)
						byy += fi.cstyle.margin[0];
				}
				drawbox(f, lay, Point(bxx, byy), fi);
			}
		}
		x += it.width;
	}
}

drawimg(f: ref Frame, iorigin: Point, i: ref Item.Iimage)
{
	ci := i.ci;
	im := f.cim;
	iorigin.x += int i.hspace + int i.border;
	# y coord is already adjusted for border and vspace
	if(ci.mims != nil) {
		r := Rect(iorigin, iorigin.add(Point(i.imwidth,i.imheight)));
		inview := r.Xrect(f.cr);
		if(i.ctlid >= 0) {
			# animated
			c := f.controls[i.ctlid];
			dims := c.r.max.sub(c.r.min);
			c.r = Rect(iorigin, iorigin.add(dims));
			if (inview) {
				pick ac := c {
				Canimimage =>
					ac.redraw = 1;
					ac.bg = f.layout.background;
				}
				c.draw(0);
			}
		}
		else if (inview) {
			mims := ci.mims;
			if(mims != nil) {
				mim := mims[0];
				if(mim != nil && mim.im != nil) {
					iorigin = iorigin.add(mim.origin);
					im.draw(r, mim.im, mim.mask, zp);
				}
			}
		}
		if(inview && i.border != byte 0) {
			if(i.anchorid != 0)
				bdcol := f.doc.link;
			else
				bdcol = Black;
			drawborder(im, r, int i.border, bdcol);
		}
	}
	else if((CU->config).imagelvl == CU->ImgNone && i.altrep != "") {
		fnt := fonts[DefFnt].f;
		yy := iorigin.y+(i.imheight-fnt.height)/2;
		xx := iorigin.x + (i.width-fnt.width(i.altrep))/2;
		if(i.anchorid != 0)
			col := f.doc.link;
		else
			col = DarkGrey;
		fgi := colorimage(col);
		im.text(Point(xx, yy), fgi, zp, fnt, i.altrep);
	}
}

drawtable(f : ref Frame, parentlay: ref Lay, torigin: Point, tab: ref Table)
{
	if (dbgtab)
		sys->print("drawtable %d\n", tab.tableid);
	if(tab.ncol == 0 || tab.nrow == 0)
		return;
	im := f.cim;
	(nil, vsp, pad, bd, nil, hsep, vsep) := tableparams(tab);
	x := torigin.x;
	y := torigin.y;
	capy := y;
	boxy := y;
	if(tab.caption_place == Abottom)
		capy = y+tab.toth-tab.caph+vsp;
	else
		boxy = y+tab.caph;
	if (tab.background.color != -1 && tab.background.color != parentlay.background.color) {
#	if(tab.background.image != parentlay.background.image ||
#	   tab.background.color != parentlay.background.color) {
		bgi := colorimage(tab.background.color);
		im.draw(((x,boxy),(x+tab.totw,boxy+tab.toth-tab.caph)),
			bgi, nil, zp);
	}
	if(bd != 0)
		drawborder(im, ((x+bd,boxy+bd),(x+tab.totw-bd,boxy+tab.toth-tab.caph-bd)),
			1, Black);
	for(cl := tab.cells; cl != nil; cl = tl cl) {
		c := hd cl;
		if (c.layid == -1 || c.layid >= len f.sublays) {
			# for some reason (usually scrolling)
			# we are drawing this cell before it has been layed out
			continue;
		}
		clay := f.sublays[c.layid];
		if(clay == nil)
			continue;
		# empty-cells: hide - skip border/background for empty cells
		if(tab.empty_cells == byte 1 && clay.height == 0)
			continue;
		cx := x + tab.cols[c.col].pos.x;
		cy := boxy + tab.rows[c.row].pos.y;
		wd := cellwidth(tab, c, hsep);
		ht := cellheight(tab, c, vsep);
		if(c.background.image != nil && c.background.image.ci != nil && c.background.image.ci.mims != nil) {
			cellr := Rect((cx-pad,cy-pad),(cx+wd+pad,cy+ht+pad));
			ci := c.background.image.ci;
			mims := ci.mims;
			if(mims != nil && mims[0] != nil && mims[0].im != nil) {
				bgi := mims[0].im;
				bgmask := mims[0].mask;
				im.draw(cellr, bgi, bgmask, bgi.r.min);
			} else if(c.background.color != -1 && c.background.color != tab.background.color) {
				bgi := colorimage(c.background.color);
				im.draw(cellr, bgi, nil, zp);
			}
		} else if(c.background.color != -1 && c.background.color != tab.background.color) {
			bgi := colorimage(c.background.color);
			im.draw(((cx-pad,cy-pad),(cx+wd+pad,cy+ht+pad)),
				bgi, nil, zp);
		}
		if(bd != 0)
			drawborder(im, ((cx-pad+1,cy-pad+1),(cx+wd+pad-1,cy+ht+pad-1)),
				1, Black);
		if(c.align.valign != Atop && c.align.valign != Abaseline) {
			n := ht - clay.height;
			if(c.align.valign == Amiddle)
				cy += n/2;
			else if(c.align.valign == Abottom)
				cy += n;
		}
		if(dbgtab)
			sys->print("drawtable %d cell %d at (%d,%d)\n",
				tab.tableid, c.cellid, cx, cy);
		drawlay(f, clay, Point(cx,cy));
	}
	if(tab.caption_lay >= 0) {
		caplay := f.sublays[tab.caption_lay];
		capx := x;
		if(caplay.width < tab.totw)
			capx += (tab.totw-caplay.width) / 2;
		drawlay(f, caplay, Point(capx,capy));
	}
}

# Draw border of width n just outside r, using src color
drawborder(im: ref Image, r: Rect, n, color: int)
{
	x := r.min.x-n;
	y := r.min.y - n;
	xr := r.max.x+n;
	ybi := r.max.y;
	src := colorimage(color);
	im.draw((Point(x,y),Point(xr,y+n)), src, nil, zp);				# top
	im.draw((Point(x,ybi),Point(xr,ybi+n)), src, nil, zp);			# bottom
	im.draw((Point(x,y+n),Point(x+n,ybi)), src, nil, zp);			# left
	im.draw((Point(xr-n,y+n),Point(xr,ybi)), src, nil, zp);			# right
}

# Draw flat border just outside r, width 1px, neutral gray.
# raised parameter retained for API compatibility but ignored.
drawrelief(im: ref Image, r: Rect, nil: int)
{
	col := colorimage(DarkGrey);
	x := r.min.x; x1 := x-1;
	xr := r.max.x; xr1 := xr+1;
	y := r.min.y; y1 := y-1;
	yb := r.max.y; yb1 := yb+1;
	im.draw((Point(x1,y1), Point(xr1,y)), col, nil, zp);		# top
	im.draw((Point(x1,y), Point(x,yb1)), col, nil, zp);		# left
	im.draw((Point(xr,y1),Point(xr1,yb1)), col, nil, zp);		# right
	im.draw((Point(x1,yb),Point(xr1,yb1)), col, nil, zp);		# bottom
}

# Fill r with color
drawfill(im: ref Image, r: Rect, color: int)
{
	im.draw(r, colorimage(color), nil, zp);
}

# Draw a CSS background image into the given rectangle with repeat and position
drawbgimage(im: ref Image, bgr: Rect, cs: ref ComputedStyle)
{
	if(cs.bgimage_ci == nil || cs.bgimage_ci.mims == nil)
		return;
	mims := cs.bgimage_ci.mims;
	if(mims == nil || mims[0] == nil || mims[0].im == nil)
		return;
	bgi := mims[0].im;

	# Image natural dimensions
	iw := bgi.r.dx();
	ih := bgi.r.dy();
	if(iw <= 0 || ih <= 0)
		return;

	bw := bgr.dx();
	bh := bgr.dy();

	# Apply background-size
	dw := iw;
	dh := ih;
	if(cs.bgsize_w == BGSZcover) {
		# Scale to cover entire box (maintaining aspect ratio)
		sx := bw * 100 / iw;
		sy := bh * 100 / ih;
		scale := sx;
		if(sy > scale)
			scale = sy;
		dw = iw * scale / 100;
		dh = ih * scale / 100;
	}
	else if(cs.bgsize_w == BGSZcontain) {
		# Scale to fit within box
		sx := bw * 100 / iw;
		sy := bh * 100 / ih;
		scale := sx;
		if(sy < scale)
			scale = sy;
		dw = iw * scale / 100;
		dh = ih * scale / 100;
	}
	else {
		if(cs.bgsize_w > 0)
			dw = cs.bgsize_w;
		if(cs.bgsize_h > 0)
			dh = cs.bgsize_h;
		# If one dimension specified and other is auto, maintain aspect ratio
		if(cs.bgsize_w > 0 && cs.bgsize_h == 0)
			dh = ih * dw / iw;
		else if(cs.bgsize_h > 0 && cs.bgsize_w == 0)
			dw = iw * dh / ih;
	}
	if(dw <= 0) dw = 1;
	if(dh <= 0) dh = 1;

	# Starting position with background-position offset
	sx := bgr.min.x + cs.bgposition_x;
	sy := bgr.min.y + cs.bgposition_y;

	# Draw based on repeat mode
	case int cs.bgrepeat {
	int BGRno_repeat =>
		dr := Rect(Point(sx, sy), Point(sx + dw, sy + dh));
		im.draw(dr, bgi, nil, bgi.r.min);
	int BGRrepeat_x =>
		for(x := sx - ((sx - bgr.min.x + dw - 1) / dw) * dw; x < bgr.max.x; x += dw) {
			dr := Rect(Point(x, sy), Point(x + dw, sy + dh));
			im.draw(dr, bgi, nil, bgi.r.min);
		}
	int BGRrepeat_y =>
		for(y := sy - ((sy - bgr.min.y + dh - 1) / dh) * dh; y < bgr.max.y; y += dh) {
			dr := Rect(Point(sx, y), Point(sx + dw, y + dh));
			im.draw(dr, bgi, nil, bgi.r.min);
		}
	* =>
		# BGRrepeat: tile both directions
		for(y := sy - ((sy - bgr.min.y + dh - 1) / dh) * dh; y < bgr.max.y; y += dh) {
			for(x := sx - ((sx - bgr.min.x + dw - 1) / dw) * dw; x < bgr.max.x; x += dw) {
				dr := Rect(Point(x, y), Point(x + dw, y + dh));
				im.draw(dr, bgi, nil, bgi.r.min);
			}
		}
	}
}

# Draw string in default font at p
drawstring(im: ref Image, p: Point, s: string)
{
	im.text(p, colorimage(Black), zp, fonts[DefFnt].f, s);
}

# Return (width, height) of string in default font
measurestring(s: string) : Point
{
	f := fonts[DefFnt].f;
	return (f.width(s), f.height);
}

# Mark as "changed" everything with change flags on the loc path
markchanges(loc: ref Loc)
{
	lastf : ref Frame = nil;
	for(i := 0; i < loc.n; i++) {
		case loc.le[i].kind {
		LEframe =>
			lastf = loc.le[i].frame;
			lastf.layout.flags |= Lchanged;
		LEline =>
			loc.le[i].line.flags |= Lchanged;
		LEitem =>
			pick it := loc.le[i].item {
			Itable =>
				it.table.flags |= Lchanged;
			Ibox =>
				# box sublayout will be redone on relayout
				;
			Ifloat =>
				# whole layout will be redone if layout changes
				# and there are any floats
				;
			}
		LEtablecell =>
			if(lastf == nil)
				CU->raisex("EXInternal: markchanges no lastf");
			c := loc.le[i].tcell;
			clay := lastf.sublays[c.layid];
			if(clay != nil)
				clay.flags |= Lchanged;
		}
	}
}

# one-item cache for colorimage
prevrgb := -1;
prevrgbimage : ref Image = nil;

colorimage(rgb: int) : ref Image
{
	if(rgb == prevrgb)
		return prevrgbimage;
	prevrgb = rgb;
	if(rgb == Black)
		prevrgbimage = display.black;
	else if(rgb == White)
		prevrgbimage = display.white;
	else {
		hv := rgb % NCOLHASH;
		if (hv < 0)
			hv = -hv;
		xhd := colorhashtab[hv];
		x := xhd;
		while(x != nil && x.rgb  != rgb)
			x = x.next;
		if(x == nil) {
#			pix := I->closest_rgbpix((rgb>>16)&255, (rgb>>8)&255, rgb&255);
#			im := display.color(pix);
			im := display.rgb((rgb>>16)&255, (rgb>>8)&255, rgb&255);
			if(im == nil)
				CU->raisex(sys->sprint("exLayout: can't allocate color #%8.8ux: %r", rgb));
			x = ref Colornode(rgb, im, xhd);
			colorhashtab[hv] = x;
		}
		prevrgbimage = x.im;
	}
	return prevrgbimage;
}

# Use f.background.image (if not nil) or f.background.color to fill r (in cim coord system)
# with background color.
fillbg(f: ref Frame, r: Rect)
{
	bgi: ref Image;
	ii := f.doc.background.image;
	if (ii != nil && ii.ci != nil && ii.ci.mims != nil && ii.ci.mims[0] != nil)
		bgi = ii.ci.mims[0].im;
	if(bgi == nil)
		bgi = colorimage(f.doc.background.color);
	f.cim.drawop(r, bgi, nil, f.viewr.min, Draw->S);
}

TRIup, TRIdown, TRIleft, TRIright: con iota;
# Assume r is a square
drawtriangle(im: ref Image, r: Rect, kind, style: int)
{
	drawfill(im, r, Grey);
	b := r.max.x - r.min.x;
	if(b < 4)
		return;
	b2 := b/2;
	bm2 := b-ReliefBd;
	p := array[3] of Point;
	col012, col20 : ref Image;
	d := colorimage(DarkGrey);
	l := colorimage(White);
	case kind {
	TRIup =>
		p[0] = Point(b2, ReliefBd);
		p[1] = Point(bm2,bm2);
		p[2] = Point(ReliefBd,bm2);
		col012 = d;
		col20 = l;
	TRIdown =>
		p[0] = Point(b2,bm2);
		p[1] = Point(ReliefBd,ReliefBd);
		p[2] = Point(bm2,ReliefBd);
		col012 = l;
		col20 = d;
	TRIleft =>
		p[0] = Point(bm2, ReliefBd);
		p[1] = Point(bm2, bm2);
		p[2] = Point(ReliefBd,b2);
		col012 = d;
		col20 = l;
	TRIright =>
		p[0] = Point(ReliefBd,bm2);
		p[1] = Point(ReliefBd,ReliefBd);
		p[2] = Point(bm2,b2);
		col012 = l;
		col20 = d;
	}
	if(style == ReliefSunk) {
		t := col012;
		col012 = col20;
		col20 = t;
	}
	for(i := 0; i < 3; i++)
		p[i] = p[i].add(r.min);
	im.fillpoly(p, ~0, colorimage(Grey), zp);
	im.line(p[0], p[1], 0, 0, ReliefBd/2, col012, zp);
	im.line(p[1], p[2], 0, 0, ReliefBd/2, col012, zp);
	im.line(p[2], p[0], 0, 0, ReliefBd/2, col20, zp);
}

abs(a: int) : int
{
	if(a < 0)
		return -a;
	return a;
}

Frame.new() : ref Frame
{
	f := ref Frame;
	f.parent = nil;
	f.cim = nil;
	f.r = Rect(zp, zp);
	f.animpid = 0;
	f.reset();
	return f;
}

Frame.newkid(parent: ref Frame, ki: ref Kidinfo, r: Rect) : ref Frame
{
	f := ref Frame;
	f.parent = parent;
	f.cim = parent.cim;
	f.r = r;
	f.animpid = 0;
	f.reset();
	f.src = ki.src;
	f.name = ki.name;
	f.marginw = ki.marginw;
	f.marginh = ki.marginh;
	f.framebd = ki.framebd;
	f.flags = ki.flags;
	return f;
}

# Note: f.parent, f.cim and f.r should not be reset
# And if f.parent is true, don't reset params set in frameset.
Frame.reset(f: self ref Frame)
{
	f.id = ++frameid;
	f.doc = nil;
	if(f.parent == nil) {
		f.src = nil;
		f.name = "";
		f.marginw = FRMARGIN;
		f.marginh = FRMARGIN;
		f.framebd = 0;
		f.flags = FRvscrollauto | FRhscrollauto;
	}
	f.layout = nil;
	f.sublays = nil;
	f.sublayid = 0;
	f.controls = nil;
	f.controlid = 0;
	f.cr = f.r;
	f.isdirty = 1;
	f.dirtyr = f.cr;
	f.viewr = Rect(zp, zp);
	f.totalr = f.viewr;
	f.vscr = nil;
	f.hscr = nil;
	hadkids := (f.kids != nil);
	f.kids = nil;
	if(f.animpid != 0)
		CU->kill(f.animpid, 0);
	if(J != nil && hadkids)
		J->frametreechanged(f);
	f.animpid = 0;
}

Frame.dirty(f: self ref Frame, r: Draw->Rect)
{
	if (f.isdirty)
		f.dirtyr= f.dirtyr.combine(r);
	else {
		f.dirtyr = r;
		f.isdirty = 1;
	}
}

Frame.addcontrol(f: self ref Frame, c: ref Control) : int
{
	if(len f.controls <= f.controlid) {
		newcontrols := array[len f.controls + 30] of ref Control;
		newcontrols[0:] = f.controls;
		f.controls = newcontrols;
	}
	f.controls[f.controlid] = c;
	ans := f.controlid++;
	return ans;
}

Frame.xscroll(f: self ref Frame, kind, val: int)
{
	newx := f.viewr.min.x;
	case kind {
	CAscrollpage =>
		newx += val*(f.cr.dx()*8/10);
	CAscrollline =>
		newx += val*f.cr.dx()/10;
	CAscrolldelta =>
		newx += val;
	CAscrollabs =>
		newx = val;
	}
	f.scrollabs(Point(newx, f.viewr.min.y));
}

# Don't actually scroll by "page" and "line",
# But rather, 80% and 10%, which give more
# context in the first case, and more motion
# in the second.
Frame.yscroll(f: self ref Frame, kind, val: int)
{
	newy := f.viewr.min.y;
	case kind {
	CAscrollpage =>
		newy += val*(f.cr.dy()*8/10);
	CAscrollline =>
		newy += val*f.cr.dy()/20;
	CAscrolldelta =>
		newy += val;
	CAscrollabs =>
		newy = val;
	}
	f.scrollabs(Point(f.viewr.min.x, newy));
}

Frame.scrollrel(f : self ref Frame, p : Point)
{
	(x, y) := p;
	x += f.viewr.min.x;
	y += f.viewr.min.y;
	f.scrollabs(f.viewr.min.add(p));
}

Frame.scrollabs(f : self ref Frame, p : Point)
{
	(x, y) := p;
	lay := f.layout;
	margin := 0;
	if (lay != nil)
		margin = lay.margin;
	x = max(0, min(x, f.totalr.max.x + margin - f.cr.dx()));
	y = max(0, min(y, f.totalr.max.y + margin - f.cr.dy()));
	(oldx, oldy) := f.viewr.min;
	if (oldx != x || oldy != y) {
		f.viewr.min = (x, y);
		fixframegeom(f);
		# blit scroll
		dx := f.viewr.min.x - oldx;
		dy := f.viewr.min.y - oldy;
		origin := f.lptosp(zp);
		destr := f.viewr.addpt(origin);
		srcpt := destr.min.add((dx, dy));
		oclipr := f.cim.clipr;
		f.cim.clipr = f.cr;
		f.cim.drawop(destr, f.cim, nil, srcpt, Draw->S);
		if (dx > 0)
			f.dirty(Rect((f.viewr.max.x - dx, f.viewr.min.y), f.viewr.max));
		else if (dx < 0)
			f.dirty(Rect(f.viewr.min, (f.viewr.min.x - dx, f.viewr.max.y)));

		if (dy > 0)
			f.dirty(Rect((f.viewr.min.x, f.viewr.max.y-dy), f.viewr.max));
		else if (dy < 0)
			f.dirty(Rect(f.viewr.min, (f.viewr.max.x, f.viewr.min.y-dy)));
#f.cim.draw(destr, display.white, nil, zp);
		drawall(f);
		f.cim.clipr = oclipr;
	}
}

# Convert layout coords (where (0,0) is top left of layout)
# to screen coords (i.e., coord system of mouse, f.cr, etc.)
Frame.sptolp(f: self ref Frame, sp: Point) : Point
{
	return f.viewr.min.add(sp.sub(f.cr.min));
}

# Reverse translation of sptolp
Frame.lptosp(f: self ref Frame, lp: Point) : Point
{
	return lp.add(f.cr.min.sub(f.viewr.min));
}

# Return Loc of Item or Scrollbar containing p (p in screen coords)
# or item it, if that is not nil.
Frame.find(f: self ref Frame, p: Point, it: ref Item) : ref Loc
{
	return framefind(Loc.new(), f, p, it);
}

# Find it (if non-nil) or place where p is (known to be inside f's layout).
framefind(loc: ref Loc, f: ref Frame, p: Point, it: ref Item) : ref Loc
{
	loc.add(LEframe, f.r.min);
	loc.le[loc.n-1].frame = f;
	if(it == nil) {
		if(f.vscr != nil && p.in(f.vscr.r)) {
			loc.add(LEcontrol, f.vscr.r.min);
			loc.le[loc.n-1].control = f.vscr;
			loc.pos = p.sub(f.vscr.r.min);
			return loc;
		}
		if(f.hscr != nil && p.in(f.hscr.r)) {
			loc.add(LEcontrol, f.hscr.r.min);
			loc.le[loc.n-1].control = f.hscr;
			loc.pos = p.sub(f.hscr.r.min);
			return loc;
		}
	}
	if(it != nil || p.in(f.cr)) {
		lay := f.layout;
		if(f.kids != nil) {
			for(fl := f.kids; fl != nil; fl = tl fl) {
				kf := hd fl;
				try := framefind(loc, kf, p, it);
				if(try != nil)
					return try;
			}
		}
		else if(lay != nil)
			return layfind(loc, f, lay, f.lptosp(zp), p, it);
	}
	return nil;
}

# Find it (if non-nil) or place where p is (known to be inside f's layout).
# p (in screen coords), lay offset by origin also in screen coords
layfind(loc: ref Loc, f: ref Frame, lay: ref Lay, origin, p: Point, it: ref Item) : ref Loc
{
	for(flist := lay.floats; flist != nil; flist = tl flist) {
		fl := hd flist;
		fymin := fl.y+origin.y;
		fymax := fymin + fl.item.height;
		inside := 0;
		xx : int;
		if(it != nil || (fymin <= p.y && p.y < fymax)) {
			xx = origin.x + lay.margin;
			if(fl.side == Aright) {
				xx -= fl.x;
				xx += lay.targetwidth;
#				if(lay == f.layout)
#					xx = origin.x + (f.cr.dx() - lay.margin) - fl.x;
##					xx += f.cr.dx() - fl.x;
#				else
#					xx += lay.width - fl.x;
			}
			else
				xx += fl.x;
			if(p.x >= xx && p.x < xx+fl.item.width)
					inside = 1;
		}
		fp := Point(xx,fymin);
		match := 0;
		if(it != nil) {
			pick fi := fl.item {
			Itable =>
				loc.add(LEitem, fp);
				loc.le[loc.n-1].item = fl;
				loc.pos = p.sub(fp);
				lloc := tablefind(loc, f, fi, fp, p, it);
				if(lloc != nil)
					return lloc;
			Iimage =>
				match = (it == fl || it == fl.item);
			}
		}
		if(match || inside) {
			loc.add(LEitem, fp);
			loc.le[loc.n-1].item = fl;
			loc.pos = p.sub(fp);
			if(it == fl.item) {
				loc.add(LEitem, fp);
				loc.le[loc.n-1].item = fl.item;
			}
			if(inside) {
				pick fi := fl.item {
				Itable =>
					loc = tablefind(loc, f, fi, fp, p, it);
				}
			}
			return loc;
		}
	}
	for(l :=lay.start; l != nil; l = l.next) {
		o := origin.add(l.pos);
		if(it != nil || (o.y <= p.y && p.y < o.y+l.height)) {
			lloc := linefind(loc, f, l, o, p, it);
			if(lloc != nil)
				return lloc;
			if(it == nil && o.y + l.height >= p.y)
				break;
		}
	}
	return nil;
}

# p (in screen coords), line at o, also in screen coords
linefind(loc: ref Loc, f: ref Frame, l: ref Line, o, p: Point, it: ref Item) : ref Loc
{
	loc.add(LEline, o);
	loc.le[loc.n-1].line = l;
	x := o.x;
	y := o.y;
	for(i := l.items; i != nil; i = i.next) {
		if(it != nil || (x <= p.x && p.x < x+i.width)) {
			yy := y;
			h := 0;
			pick pi := i {
			Itext =>
				fnt := fonts[pi.fnt].f;
				yy += l.ascent - fnt.ascent + (int pi.voff) - Voffbias;
				h = fnt.height;
			Irule =>
				h = pi.size;
			Iimage =>
				yy = y;
				if(pi.align == Abottom)
					yy += l.ascent - pi.imheight;
				else if(pi.align == Amiddle)
					yy += l.ascent - (pi.imheight/2);
				h = pi.imheight;
			Iformfield =>
				h = pi.height;
				yy += l.ascent - pi.ascent;
				if(it != nil) {
					if(it == pi.formfield.image) {
						loc.add(LEitem, Point(x,yy));
						loc.le[loc.n-1].item = i;
						loc.add(LEitem, Point(x,yy));
						loc.le[loc.n-1].item = it;
						loc.pos = zp;	# doesn't matter, its an 'it' test
						return loc;
					}
				}
				else if(yy < p.y && p.y < yy+h && pi.formfield.ctlid >= 0) {
					loc.add(LEcontrol, Point(x,yy));
					loc.le[loc.n-1].control = f.controls[pi.formfield.ctlid];
					loc.pos = p.sub(Point(x,yy));
					return loc;
				}
			Itable =>
				lloc := tablefind(loc, f, pi, Point(x,y), p, it);
				if(lloc != nil)
					return lloc;
				# else leave h==0 so p test will fail

			# floats were handled separately. nulls can be picked by 'it' test
			# leave h==0, so p test will fail
			}
			if(it == i || (it == nil && yy <= p.y && p.y < yy+h)) {
				loc.add(LEitem, Point(x,yy));
				loc.le[loc.n-1].item = i;
				loc.pos = p.sub(Point(x,yy));
				return loc;
			}
			if(it == nil)
				return nil;
		}
		x += i.width;
		if(it == nil && x >= p.x)
			break;
	}
	loc.n--;
	return nil;
}

tablefind(loc: ref Loc, f: ref Frame, ti: ref Item.Itable, torigin: Point, p: Point, it: ref Item) : ref Loc
{
	loc.add(LEitem, torigin);
	loc.le[loc.n-1].item = ti;
	t := ti.table;
	(nil, vsp, nil, nil, nil, hsep, vsep) := tableparams(t);
	if(t.caption_lay >= 0) {
		caplay := f.sublays[t.caption_lay];
		capy := torigin.y;
		if(t.caption_place == Abottom)
			capy += t.toth-t.caph+vsp;
		lloc := layfind(loc, f, caplay, Point(torigin.x,capy), p, it);
		if(lloc != nil)
			return lloc;
	}
	for(cl := t.cells; cl != nil; cl = tl cl) {
		c := hd cl;
		if(c.layid == -1 || c.layid >= len f.sublays)
			continue;
		clay := f.sublays[c.layid];
		if(clay == nil)
			continue;
		cx := torigin.x + t.cols[c.col].pos.x;
		cy := torigin.y + t.rows[c.row].pos.y;
		wd := cellwidth(t, c, hsep);
		ht := cellheight(t, c, vsep);
		if(it == nil && !p.in(Rect(Point(cx,cy),Point(cx+wd,cy+ht))))
			continue;
		if(c.align.valign != Atop && c.align.valign != Abaseline) {
			n := ht - clay.height;
			if(c.align.valign == Amiddle)
				cy += n/2;
			else if(c.align.valign == Abottom)
				cy += n;
		}
		loc.add(LEtablecell, Point(cx,cy));
		loc.le[loc.n-1].tcell = c;
		lloc := layfind(loc, f, clay, Point(cx,cy), p, it);
		if(lloc != nil)
			return lloc;
		loc.n--;
		if(it == nil)
			return nil;
	}
	loc.n--;
	return nil;
}

# (called from jscript)
# 'it' is an Iimage item in frame f whose image is to be switched
# to come from the src URL.
#
# For now, assume this is called only after the entire build process
# has finished.  Also, only handle the case where the image has
# been preloaded and is in the cache now.  This isn't right (BUG), but will
# cover most of the cases of extant image swapping, and besides,
# image swapping is mostly cosmetic anyway.
# 
# For now, pay no attention to scaling issues or animation issues.
Frame.swapimage(f: self ref Frame, im: ref Item.Iimage, src: string)
{
	u := U->parse(src);
	if(u.scheme == "")
		return;
	u = U->mkabs(u, f.doc.base);
	# width=height=0 finds u if in cache
	newci := CImage.new(u, nil, 0, 0);
	if(CU->imcache == nil)
		return;
	cachedci := (CU->imcache).look(newci);
	if(cachedci == nil || cachedci.mims == nil)
		return;
	im.ci = cachedci;

	# we're assuming image will have same dimensions
	# as one that is replaced, so no relayout is needed;
	# otherwise need to call haveimage() instead of drawall()
	# Netscape scales replacement image to size of replaced image

	f.dirty(f.totalr);
	drawall(f);
}

Frame.focus(f : self ref Frame, focus, raisex : int)
{
	di := f.doc;
	if (di == nil || (CU->config).doscripts == 0)
		return;
	if (di.evmask && raisex) {
		kind := E->SEonfocus;
		if (!focus)
			kind = E->SEonblur;
		if(di.evmask & kind)
			; #se := ref E->ScriptEvent(kind, f.id, -1, -1, -1, -1, -1, -1, 0, nil, nil, 0);
	}
}

Control.newff(f: ref Frame, ff: ref B->Formfield) : ref Control
{
	ans : ref Control = nil;
	case ff.ftype {
	Ftext or Fpassword or Ftextarea
	or Femail or Furl or Fnumber or Ftel or Fsearch or Fdate or Ftime =>
		nh := ff.size;
		nv := 1;
		linewrap := 0;
		if(ff.ftype == Ftextarea) {
			nh = ff.cols;
			nv = ff.rows;
			linewrap = 1;
		}
		ans = Control.newentry(f, nh, nv, linewrap);
		if(ff.ftype == Fpassword)
			ans.flags |= CFsecure;
		ans.entryset(ff.value);
	Fcolor =>
		# Color input: render as a button with the current color value
		ans = Control.newbutton(f, nil, nil, ff.value, nil, 0, 1);
	Frange =>
		# Range input: render as a text entry showing the value
		ans = Control.newentry(f, ff.size, 1, 0);
		val := ff.value;
		if(val == "")
			val = "50";
		ans.entryset(val);
	Fcheckbox or Fradio =>
		ans = Control.newcheckbox(f, ff.ftype==Fradio);
		if((ff.flags&B->FFchecked) != byte 0)
			ans.flags |= CFactive;
	Fsubmit or Fimage or Freset or Fbutton =>
		if(ff.image == nil)
			ans = Control.newbutton(f, nil, nil, ff.value, nil, 0, 1);
		else {
			pick i := ff.image {
			Iimage =>
				pic, picmask : ref Image;
				if(i.ci.mims != nil && len i.ci.mims > 0 && i.ci.mims[0] != nil && i.ci.mims[0].im != nil) {
					pic = i.ci.mims[0].im;
					picmask = i.ci.mims[0].mask;
				}
				lab := "";
				if((CU->config).imagelvl == CU->ImgNone) {
					lab = i.altrep;
					i = nil;
				}
				ans = Control.newbutton(f, pic, picmask, lab, i, 0, 0);
			}
		}
	Fselect =>
		n := len ff.options;
		if(n > 0) {
			ao := array[n] of Option;
			l := ff.options;
			for(i := 0; i < n; i++) {
				o := hd l;
				# these are copied, so selected can be used for current state
				ao[i] = *o;
				l = tl l;
			}
			nvis := ff.size;
			ans = Control.newselect(f, nvis, ao);
		}
	Ffile =>
		if(dbg)
			sys->print("warning: unimplemented file form field\n");
	}
	if(ans != nil)
		ans.ff = ff;
	return ans;
}

Control.newscroll(f: ref Frame, isvert, length, breadth: int) : ref Control
{
	# need room for at least two squares and 2 borders of size 2
	if(length < 12) {
		breadth = 0;
		length = 0;
	}
	else if(breadth*2 + 4 > length)
		breadth = (length - 4) / 2;
	maxpt : Point;
	flags := CFenabled;
	if(isvert) {
		maxpt = Point(breadth, length);
		flags |= CFscrvert;
	}
	else
		maxpt = Point(length, breadth);
	return ref Control.Cscrollbar(f, nil, Rect(zp,maxpt), flags, nil, 0, 0, 1, 0, nil, (0, 0), nil);
}

Control.newentry(f: ref Frame, nh, nv, linewrap: int) : ref Control
{
	w := ctlcharspace*nh + 2*ENTHMARGIN;
	h := ctllinespace*nv + 2*ENTVMARGIN;
	scr : ref Control;
	if (linewrap) {
		scr = Control.newscroll(f, 1, h-4, SCRFBREADTH);
		scr.r.addpt(Point(w,0));
		w += SCRFBREADTH;
	}
	ans := ref Control.Centry(f, nil, Rect(zp,Point(w,h)), CFenabled, nil, scr, "", (0, 0), 0, linewrap, 0);
	if (scr != nil) {
		pick pscr := scr {
		Cscrollbar =>
			pscr.ctl = ans;
		}
		scr.scrollset(0, 1, 1, 0, 0);
	}
	return ans;
}

Control.newbutton(f: ref Frame, pic, picmask: ref Image, lab: string, it: ref Item.Iimage, candisable, dorelief: int) : ref Control
{
	dpic, dpicmask: ref Image;
	w := 0;
	h := 0;
	if(pic != nil) {
		w = pic.r.dx();
		h = pic.r.dy();
	}
	else if(it != nil) {
		w = it.imwidth;
		h = it.imheight;
	}
	else {
		w = fonts[CtlFnt].f.width(lab);
		h = ctllinespace;
	}
	if(dorelief) {
		# form image buttons are shown without margins in other browsers
		w += 2*BUTMARGIN;
		h += 2*BUTMARGIN;
	}
	r := Rect(zp, Point(w,h));
	if(candisable && pic != nil) {
		# make "greyed out" image:
		#	- convert pic to monochrome (ones where pic is non-white)
		#	- draw pic in White, then DarkGrey shifted (-1,-1) and use
		#	    union of those two areas as mask
		dpicmask = display.newimage(pic.r, Draw->GREY1, 0, D->White);
		dpic = display.newimage(pic.r, pic.chans, 0, D->White);
		dpic.draw(dpic.r, colorimage(White), pic, zp);
		dpicmask.draw(dpicmask.r, display.black, pic, zp);
		dpic.draw(dpic.r.addpt(Point(-1,-1)), colorimage(DarkGrey), pic, zp);
		dpicmask.draw(dpicmask.r.addpt(Point(-1,-1)), display.black, pic, zp);
	}
	b := ref Control.Cbutton(f, nil, r, CFenabled, nil, pic, picmask, dpic, dpicmask, lab, dorelief);
	return b;
}

Control.newcheckbox(f: ref Frame, isradio: int) : ref Control
{
	return ref Control.Ccheckbox(f, nil, Rect((0,0),(CBOXWID,CBOXHT)), CFenabled, nil, isradio);
}

Control.newselect(f: ref Frame, nvis: int, options: array of B->Option) : ref Control
{
	nvis = min(5, len options);
	if (nvis < 1)
		nvis = 1;
	fnt := fonts[CtlFnt].f;
	w := 0;
	first := -1;
	for(i := 0; i < len options; i++) {
		if (first == -1 && options[i].selected)
			first = i;
		w = max(w, fnt.width(options[i].display));
	}
	if (first == -1)
		first = 0;
	if (len options -nvis > 0 && len options - nvis < first)
		first = len options - nvis;
	w += 2*SELMARGIN;
	h := ctllinespace*nvis + 2*SELMARGIN;
	scr: ref Control;
	if (nvis > 1 && nvis < len options) {
		scr = Control.newscroll(f, 1, h, SCRFBREADTH);
		scr.r.addpt(Point(w,0));
	}
	if (nvis < len options)
		w += SCRFBREADTH;
	ans := ref Control.Cselect(f, nil, Rect(zp, Point(w,h)), CFenabled, nil, nil, scr, nvis, first, options);
	if(scr != nil) {
		pick pscr := scr {
		Cscrollbar =>
			pscr.ctl = ans;
		}
		scr.scrollset(first, first+nvis, len options, len options, 0);
	}
	return ans;
}

Control.newlistbox(f: ref Frame, nrow, ncol: int, options: array of B->Option) : ref Control
{
	fnt := fonts[CtlFnt].f;
	w := charspace*ncol + 2*SELMARGIN;
	h := fnt.height*nrow + 2*SELMARGIN;

	vscr: ref Control = nil;
	#if(nrow < len options) {
		vscr = Control.newscroll(f, 1, (h-4)+SCRFBREADTH, SCRFBREADTH);
		vscr.r.addpt(Point(w-SCRFBREADTH,0));
		w += SCRFBREADTH;
	#}

	maxw := 0;
	for(i := 0; i < len options; i++)
		maxw = max(maxw, fnt.width(options[i].display));

	hscr: ref Control = nil;
	#if(w < maxw) {
		# allow for border (inset(2))
		hscr = Control.newscroll(f, 0, (w-4)-SCRFBREADTH, SCRFBREADTH);
		hscr.r.addpt(Point(0, h-SCRBREADTH));
		h += SCRFBREADTH;
	#}

	ans := ref Control.Clistbox(f, nil, Rect(zp, Point(w,h)), CFenabled, nil, hscr, vscr, nrow, 0, 0, maxw/charspace, options, nil);
	if(vscr != nil) {
		pick pscr := vscr {
		Cscrollbar =>
			pscr.ctl = ans;
		}
		vscr.scrollset(0, nrow, len options, len options, 0);
	}
	if(hscr != nil) {
		pick pscr := hscr {
		Cscrollbar =>
			pscr.ctl = ans;
		}
		hscr.scrollset(0, w-SCRFBREADTH, maxw, 0, 0);
	}
	return ans;	
}

Control.newanimimage(f: ref Frame, cim: ref CU->CImage, bg: Background) : ref Control
{
	return ref Control.Canimimage(f, nil, Rect((0,0),(cim.width,cim.height)), 0, nil, cim, 0, 0, big 0, bg);
}

Control.newlabel(f: ref Frame, s: string) : ref Control
{
	w := fonts[DefFnt].f.width(s);
	h := ctllinespace + 2*ENTVMARGIN;	# give it same height as an entry box
	return ref Control.Clabel(f, nil, Rect(zp,Point(w,h)), 0, nil, s);
}

Control.disable(c: self ref Control)
{
	if(c.flags & CFenabled) {
		c.flags &= ~CFenabled;
		if(c.f.cim != nil)
			c.draw(1);
	}
}

Control.enable(c: self ref Control)
{
	if(!(c.flags & CFenabled)) {
		c.flags |= CFenabled;
		if(c.f.cim != nil)
			c.draw(1);
	}
}

changeevent(c: ref Control)
{
	onchange := 0;
	pick pc := c {
	Centry =>
		onchange = pc.onchange;
		pc.onchange = 0;
# this code reproduced Navigator 2 bug
# changes to Select Formfield selection only resulted in onchange event upon
# loss of focus.  Now handled by domouse() code so event can be raised
# immediately
#	Cselect =>
#		onchange = pc.onchange;
#		pc.onchange = 0;
	}
	if(onchange && (c.ff.evmask & E->SEonchange)) {
		se := ref E->ScriptEvent(E->SEonchange, c.f.id, c.ff.form.formid, c.ff.fieldid, -1, -1, -1, -1, 1, nil, nil, 0);
		J->jevchan <-= se;
	}
}

blurfocusevent(c: ref Control, kind, raisex: int)
{
	if((CU->config).doscripts && c.ff != nil && c.ff.evmask) {
		if(kind == E->SEonblur)
			changeevent(c);
		if (!raisex || !(c.ff.evmask & kind))
			return;
		se := ref E->ScriptEvent(kind, c.f.id, c.ff.form.formid, c.ff.fieldid, -1, -1, -1, -1, 0, nil, nil, 0);
		J->jevchan <-= se;
	}
}

Control.losefocus(c: self ref Control, raisex: int)
{
	if(c.flags & CFhasfocus) {
		c.flags &= ~CFhasfocus;
		if(c.f.cim != nil) {
			blurfocusevent(c, E->SEonblur, raisex);
			c.draw(1);
		}
	}
}

Control.gainfocus(c: self ref Control, raisex: int)
{
	if(!(c.flags & CFhasfocus)) {
		c.flags |= CFhasfocus;
		if(c.f.cim != nil) {
			blurfocusevent(c, E->SEonfocus, raisex);
			c.draw(1);
		}
		G->clientfocus();
	}
}

Control.scrollset(c: self ref Control, v1, v2, vmax, nsteps, draw: int)
{
	pick sc := c {
	Cscrollbar =>
		if(v1 < 0)
			v1 = 0;
		if(v2 > vmax)
			v2 = vmax;
		if(v1 > v2)
			v1 = v2;
		# Update widget.m scrollbar if present
		if(sc.wsb != nil) {
			sc.wsb.total = vmax;
			sc.wsb.visible = v2 - v1;
			sc.wsb.origin = v1;
		}
		if(v1 == 0 && v2 == vmax) {
			sc.mindelta = 1;
			sc.deltaval = 0;
			sc.top = 0;
			sc.bot = 0;
		}
		else {
			length: int;
			if(sc.flags&CFscrvert)
				length = sc.r.max.y - sc.r.min.y;
			else
				length = sc.r.max.x - sc.r.min.x;
			# Flat scrollbar: no arrow buttons, full track is trough
			l := length - MINSCR;
			if(l < 0)
				l = 0;
			sc.top = l*v1/vmax;
			sc.bot = l*(vmax-v2)/vmax;
			if (nsteps == 0)
				sc.mindelta = 1;
			else
				sc.mindelta = max(1, length/nsteps);
			sc.deltaval = max(1, vmax/(l/sc.mindelta))*SCRDELTASF;
		}
		if(sc.f.cim != nil && draw)
			sc.draw(1);
	}
}

SPECMASK : con 16rf000;
CTRLMASK : con 16r1f;
DEL : con 16r7f;
TAB : con '\t';
CR: con '\n';

Control.dokey(ctl: self ref Control, keychar: int) : int
{
	if(!(ctl.flags&CFenabled))
		return CAnone;
	ans := CAnone;
	pick c := ctl {
	Centry =>
		olds := c.s;
		slen := len c.s;
		(sels, sele) := normalsel(c.sel);
		modified := 0;
		(osels, osele) := (sels, sele);
		case keychar {
			('a' & CTRLMASK) or Keyboard->Home =>
				(sels, sele) = (0, 0);
			('e' & CTRLMASK) or Keyboard->End =>
				(sels, sele) = (slen, slen);
			'f' & CTRLMASK or Keyboard->Right =>
				if(sele < slen)
					(sels, sele) = (sele+1, sele+1);
			'b' & CTRLMASK or Keyboard->Left =>
				if(sels > 0)
					(sels, sele) = (sels-1, sels-1);
			Keyboard->Up =>
				if (c.linewrap)
					sels = sele = entryupdown(c, sels, -1);
			Keyboard->Down =>
				if (c.linewrap)
					sels = sele = entryupdown(c, sele, 1);
			'u' & CTRLMASK =>
				entrydelrange(c, 0, slen);
				modified = 1;
				(sels, sele) = c.sel;
			'c' & CTRLMASK =>
				entrysetsnarf(c);
			'v' & CTRLMASK =>
				entryinsertsnarf(c);
				modified = 1;
				(sels, sele) = c.sel;
			'h' & CTRLMASK or DEL=>
				if (sels != sele) {
					entrydelrange(c, sels, sele);
					modified = 1;
				} else if(sels > 0) {
					entrydelrange(c, sels-1, sels);
					modified = 1;
				}
				(sels, sele) = c.sel;
			Keyboard->Del =>
				if (sels != sele) {
					entrydelrange(c, sels, sele);
					modified = 1;
				} else if(sels < len c.s) {
					entrydelrange(c, sels, sels+1);
					modified = 1;
				}
				(sels, sele) = c.sel;
			TAB =>
				ans = CAtabkey;
			* =>
				if ((keychar & SPECMASK) == Keyboard->Spec)
					# ignore all other special keys
					break;
				if(keychar == CR) {
					if(c.linewrap)
						keychar = '\n';
					else
						ans = CAreturnkey;
				}
				if(keychar > CTRLMASK || (keychar == '\n' && c.linewrap)) {
					if (sels != sele) {
						entrydelrange(c, sels, sele);
						(sels, sele) = c.sel;
					}
					slen = len c.s;
					c.s[slen] = 0;	# expand string by 1 char
					for(k := slen; k > sels; k--)
						c.s[k] = c.s[k-1];
					c.s[sels] = keychar;
					(sels, sele) = (sels+1, sels+1);
					modified = 1;
				}
		}
		c.sel = (sels, sele);
		if(osels != sels || osele != sele || modified) {
			entryscroll(c);
			c.draw(1);
		}
		if (c.s != olds)
			c.onchange = 1;
	}
	return ans;
}

Control.domouse(ctl: self ref Control, p: Point, mtype: int, oldgrab : ref Control) : (int, ref Control)
{
	up := (mtype == E->Mlbuttonup || mtype == E->Mldrop);
	down := (mtype == E->Mlbuttondown);
	drag := (mtype == E->Mldrag);
	hold := (mtype == E->Mhold);
	move := (mtype == E->Mmove);

	# any button actions stop auto-repeat
	# it's up to the individual controls to re-instate it
	if (!move)
		E->autorepeat(nil, 0, 0);

	if(!(ctl.flags&CFenabled))
		return (CAnone, nil);
	ans := CAnone;
	changed := 0;
	newgrab : ref Control;
	grabbed := oldgrab != nil;
	pick c := ctl {
	Cbutton =>
		if(down) {
			c.flags |= CFactive;
			newgrab = c;
			changed = 1;
		}
		else if(move && c.ff == nil) {
			ans = CAflyover;
		}
		else if (drag && grabbed) {
			newgrab = c;
			active := 0;
			if (p.in(c.r))
				active = CFactive;
			if ((c.flags & CFactive) != active)
				changed = 1;
			c.flags = (c.flags & ~CFactive) | active;
		}
		else if(up) {
			if (c.flags & CFactive)
				ans = CAbuttonpush;
			c.flags &= ~CFactive;
			changed = 1;
		}
	Centry =>
		if(c.scr != nil && !grabbed && p.x >= c.r.max.x-SCRFBREADTH) {
			pick scr := c.scr {
			Cscrollbar =>
				return scr.domouse(p, mtype, oldgrab);
			}
		}
		(sels, sele) := c.sel;
		if(mtype == E->Mlbuttonup && grabbed) {
			if (sels != sele)
				ans = CAselected;
		}
		if(down || (drag && grabbed)) {
			newgrab = c;
			x := c.r.min.x+ENTHMARGIN;
			fnt := fonts[CtlFnt].f;
			s := c.s;
			if(c.flags&CFsecure) {
				for(i := 0; i < len s; i++)
					s[i] = '*';
			}
			(osels, osele) := c.sel;
			s1 := " ";
			i := 0;
			iend := len s - 1;
			if(c.linewrap) {
				(lines, linestarts, topline, nil) := entrywrapcalc(c);
				if(len lines > 1) {
					lineno := topline + (p.y - (c.r.min.y+ENTVMARGIN)) / ctllinespace;
					lineno = min(lineno, len lines -1);
					lineno = max(lineno, 0);

					i = linestarts[lineno];
					iend = i + len lines[lineno] -1;
				}
			} else
				x -= fnt.width(s[:c.left]);
			for(; i <= iend; i++) {
				s1[0] = s[i];
				cx := fnt.width(s1);
				if(p.x < x + cx)
					break;
				x += cx;
			}
			sele = i;

			if (down)
				sels = sele;
			c.sel = (sels, sele);

			if (sels != osels || sele != osele) {
				changed = 1;
				entryscroll(c);
				if (p.x < c.r.min.x + ENTHMARGIN || p.x > c.r.max.x - ENTHMARGIN
				|| p.y < c.r.min.y + ENTVMARGIN || p.y > c.r.max.y - ENTVMARGIN) {
					E->autorepeat(ref (Event.Emouse)(p, mtype), ARTICK, ARTICK);
				}
			}

			if(!(c.flags&CFhasfocus))
				ans = CAkeyfocus;
		}
	Ccheckbox=>
		if(up) {
			if(c.isradio) {
				if(!(c.flags&CFactive)) {
					c.flags |= CFactive;
					changed = 1;
					ans = CAbuttonpush;
					# turn off other radio button
					frm := c.ff.form;
					for(lf := frm.fields; lf != nil; lf = tl lf) {
						ff := hd lf;
						if(ff == c.ff)
							continue;
						if(ff.ftype == Fradio && ff.name==c.ff.name && ff.ctlid >= 0) {
							d := c.f.controls[ff.ctlid];
							if(d.flags&CFactive) {
								d.flags &= ~CFactive;
								d.draw(1);
								break;		# at most one other should be on
							}
						}
					}
				}
			}
			else {
				c.flags ^= CFactive;
				changed = 1;
			}
		}
	Cselect =>
		if (c.nvis == 1 && up && c.popup == nil && c.r.contains(p))
			return (CAdopopup, nil);
		if(c.scr != nil && (grabbed || p.x >= c.r.max.x-SCRFBREADTH)) {
			pick scr := c.scr {
			Cscrollbar =>
				(a, grab) := scr.domouse(p, mtype, oldgrab);
				if (grab != nil)
					grab = c;
				return (a, grab);
			}
			return (ans, nil);
		}
		n := (p.y - (c.r.min.y+SELMARGIN))/ctllinespace + c.first;
		if (n >= c.first && n < c.first+c.nvis) {
			if ((c.ff.flags&B->FFmultiple) != byte 0) {
				if (down) {
					c.options[n].selected ^= 1;
					changed = 1;
				}
			} else if (up || drag) {
				changed = c.options[n].selected == 0;
				c.options[n].selected = 1;
				for(i := 0; i < len c.options; i++) {
					if(i != n)
						c.options[i].selected = 0;
				}
			}
		}
		if (up) {
			if (c.popup != nil)
				ans = CAdonepopup;
			else
				ans = CAchanged;
		}
	Clistbox =>
		if(c.vscr != nil && (c.grab == c.vscr || (!grabbed && p.x >= c.r.max.x-SCRFBREADTH))) {
			c.grab = nil;
			pick vscr := c.vscr {
			Cscrollbar =>
				(a, grab) := vscr.domouse(p, mtype, oldgrab);
				if (grab != nil) {
					c.grab = c.vscr;
					grab = c;
				}
				return (a, grab);
			}
		}
		else if(c.hscr != nil && (c.grab == c.hscr || (!grabbed && p.y >= c.r.max.y-SCRFBREADTH))) {
			c.grab = nil;
			pick hscr := c.hscr {
			Cscrollbar =>
				(a, grab) := hscr.domouse(p, mtype, oldgrab);
				if (grab != nil) {
					c.grab = c.hscr;
					grab = c;
				}
				return (a, grab);
			}
		}
		else if(up) {
			fnt := fonts[CtlFnt].f;
			n := (p.y - (c.r.min.y+SELMARGIN))/fnt.height + c.first;
			if(n >= 0 && n < len c.options) {
				c.options[n].selected ^= 1;
				# turn off other selections
				for(i := 0; i < len c.options; i++) {
					if(i != n)
						c.options[i].selected = 0;
				}
				ans = CAchanged;
				changed = 1;
			}
		}
	Cscrollbar =>
		# Widget.m scrollbar for frame-level scrollbars
		if(c.wsb != nil && c.ctl == nil) {
			# Decode B2 events alongside B1
			b2down := (mtype == E->Mmbuttondown);
			b2drag := (mtype == E->Mmdrag);
			# Synthesize a Pointer with correct button mask
			buttons := 0;
			if(down || drag)
				buttons = 1;
			else if(b2down || b2drag)
				buttons = 2;
			ptr := ref Pointer(buttons, p, 0);
			newo := -1;
			if(c.wsb.isactive()) {
				newo = c.wsb.track(ptr);
				if(newo >= 0) {
					newgrab = c;
					changed = 1;
				}
			} else if(down || b2down) {
				newo = c.wsb.event(ptr);
				if(newo >= 0) {
					newgrab = c;
					changed = 1;
				}
			}
			if(newo >= 0) {
				if(c.flags&CFscrvert)
					c.f.yscroll(CAscrollabs, newo);
				else
					c.f.xscroll(CAscrollabs, newo);
				changed = 1;
			}
		} else {
		# Legacy scrollbar logic for form controls
		val := 0;
		v, vmin, vmax: int;
		if(c.flags&CFscrvert) {
			v = p.y;
			vmin = c.r.min.y;
			vmax = c.r.max.y;
		}
		else {
			v = p.x;
			vmin = c.r.min.x;
			vmax = c.r.max.x;
		}
		vsltop := vmin+c.top;
		vslbot := vmax-c.bot;
		actflags := 0;
		oldactflags := c.flags&CFscrallact;

		if ((down || drag) && !up && !hold)
			newgrab = c;

		if (down) {
			newgrab = c;
			holdval := 0;
			repeat := 1;
			if (v >= vsltop && v < vslbot) {
				holdval = v - vsltop;
				actflags = CFactive;
				repeat = 0;
			}
			else if(v < vsltop) {
				holdval = -1;
				actflags = CFscracttr1;
			}
			else if(v >= vslbot) {
				holdval = 1;
				actflags = CFscracttr2;
			}
			c.holdstate = (actflags, holdval);
			if (repeat) {
				E->autorepeat(ref (Event.Emouse)(p, E->Mhold), ARPAUSE, ARTICK);
			}
		}
		if (drag) {
			(actflags, val) = c.holdstate;
			if (actflags == CFactive) {
				val = (v - vsltop) - val;
				if(abs(val) >= c.mindelta) {
					ans = CAscrolldelta;
					val = (c.deltaval * (val / c.mindelta))/SCRDELTASF;
				}
			} else {
				E->autorepeat(ref (Event.Emouse)(p, E->Mhold), ARTICK, ARTICK);
			}
		}
		if (up || hold) {
			act := 0;
			(act, val) = c.holdstate;
			case act {
			CFscracta1 or
			CFscracta2 =>
				ans = CAscrollline;
			CFscracttr1 or
			CFscracttr2 =>
				ans = CAscrollpage;
			}
			if (up) {
				c.holdstate = (0, 0);
			} else {
				(actflags, nil) = c.holdstate;
				if (ans != CAnone) {
					E->autorepeat(ref (Event.Emouse)(p, E->Mhold), ARTICK, ARTICK);
					newgrab = c;
				}
			}
		}
		c.flags = (c.flags & ~CFscrallact) | actflags;
		if(ans != CAnone) {
			if(c.ctl != nil) {
				pick cff := c.ctl {
				Centry =>
					ny := (cff.r.dy() - 2 * ENTVMARGIN) / ctllinespace;
					(nil, linestarts, topline, nil) := entrywrapcalc(cff);
					nlines := len linestarts;
					case ans {
					CAscrollpage =>
						topline += val*ny;
					CAscrollline =>
						topline += val;
					CAscrolldelta =>
						topline += val;
					}
					if (topline+ny >= nlines)
						topline = (nlines-1) - ny;
					if (topline < 0)
						topline = 0;
					cff.left = linestarts[topline];
					c.scrollset(topline, topline+ny, nlines - 1, nlines, 1);
					cff.draw(1);
					return (ans, newgrab);
				Cselect =>
					newfirst := cff.first;
					case ans {
					CAscrollpage =>
						newfirst += val*cff.nvis;
					CAscrollline =>
						newfirst += val;
					CAscrolldelta =>
						newfirst += val;
					}
					newfirst = max(0, min(newfirst, len cff.options - cff.nvis));
					cff.first = newfirst;
					nopt := len cff.options;
					c.scrollset(newfirst, newfirst+cff.nvis, nopt, nopt, 0);
					cff.draw(1);
					return (ans, newgrab);
				Clistbox =>
					if(c.flags&CFscrvert) {
						newfirst := cff.first;
						case ans {
						CAscrollpage =>
							newfirst += val*cff.nvis;
						CAscrollline =>
							newfirst += val;
						CAscrolldelta =>
							newfirst += val;
						}
						newfirst = max(0, min(newfirst, len cff.options - cff.nvis));
						cff.first = newfirst;
						c.scrollset(newfirst, newfirst+cff.nvis, len cff.options, 0, 1);
					}
					else {
						hw := cff.maxcol;
						w := (c.r.max.x - c.r.min.x - SCRFBREADTH)/charspace;
						newstart := cff.start;
						case ans {
						CAscrollpage =>
								newstart += val*hw;
						CAscrollline =>
								newstart += val;
						CAscrolldelta =>
							if(val > 0)
								newstart++;
							else
								newstart--;
						}
						if(hw < w)
							newstart = 0;
						else
							newstart = max(0, min(newstart, hw - w));
						cff.start = newstart;
						c.scrollset(newstart, w+newstart, hw, 0, 1);
					}
					cff.draw(1);
					return (ans, newgrab);
				}
			}
			else {
				if(c.flags&CFscrvert)
					c.f.yscroll(ans, val);
				else
					c.f.xscroll(ans, val);
			}
			changed = 1;
		}
		else if(actflags != oldactflags) {
			changed = 1;
		}
		} # end legacy scrollbar
	}
	if(changed)
		ctl.draw(1);
	return (ans, newgrab);
}

# returns a new popup control
Control.dopopup(ctl: self ref Control): ref Control
{
	sel : ref Control.Cselect;
	pick c := ctl {
	Cselect =>
		if (c.nvis > 1)
			return nil;
		sel = c;
	* =>
		return nil;
	}

	w := sel.r.dx();
	nopt := len sel.options;
	nvis := min(nopt, POPUPLINES);
	first := sel.first;
	if (first + nvis > nopt)
		first = nopt - nvis;
	h := ctllinespace*nvis + 2*SELMARGIN;
	r := Rect(sel.r.min, sel.r.min.add(Point(w, h)));
	popup := G->getpopup(r);
	if (popup == nil)
		return nil;
	scr : ref Control;
	if (nvis < nopt) {
		scr = Control.newscroll(sel.f, 1, h, SCRFBREADTH);
		scr.r.addpt(Point(w,0));
	}
	newsel := ref Control.Cselect(sel.f, sel.ff, r, sel.flags, popup, sel, scr, nvis, first, sel.options);
	if(scr != nil) {
		pick pscr := scr {
		Cscrollbar =>
			pscr.ctl = newsel;
		}
		scr.popup = popup;
		scr.scrollset(first, first+nvis, nopt, nopt, 0);
	}
	newsel.draw(1);
	return newsel;
}

# returns original control for which this was a popup
Control.donepopup(ctl: self ref Control): ref Control
{
	owner: ref Control;
	pick c := ctl {
	Cselect =>
		if (c.owner == nil)
			return nil;
		owner = c.owner;
	* =>
		return nil;
	}
	G->cancelpopup();
	pick c := owner {
	Cselect =>
		for (first := 0; first < len c.options; first++)
			if (c.options[first].selected)
				break;
		if (first == len c.options)
			first = 0;
		c.first = first;
	}
	owner.draw(1);
	return owner;
}


Control.reset(ctl: self ref Control)
{
	pick c := ctl {
	Cbutton =>
		c.flags &= ~CFactive;
	Centry =>
		c.s = "";
		c.sel = (0, 0);
		c.left = 0;
		if(c.ff != nil && c.ff.value != "")
			c.s = c.ff.value;
		if (c.scr != nil)
			c.scr.scrollset(0, 1, 1, 0, 0);
	Ccheckbox=>
		c.flags &= ~CFactive;
		if(c.ff != nil && (c.ff.flags&B->FFchecked) != byte 0)
			c.flags |= CFactive;
	Cselect =>
		nopt := len c.options;
		if(c.ff != nil) {
			l := c.ff.options;
			for(i := 0; i < nopt; i++) {
				o := hd l;
				c.options[i].selected = o.selected;
				l = tl l;
			}
		}
		c.first = 0;
		if(c.scr != nil) {
			c.scr.scrollset(0, c.nvis, nopt, nopt, 0);
		}
	Clistbox =>
		c.first = 0;
		nopt := len c.options;
		if(c.vscr != nil) {
			c.vscr.scrollset(0, c.nvis, nopt, nopt, 0);
		}
		hw := 0;
		for(i := 0; i < len c.options; i++)
			hw = max(hw, fonts[DefFnt].f.width(c.options[i].display)); 
		if(c.hscr != nil) {
			c.hscr.scrollset(0, c.r.max.x, hw, 0, 0); 
		}
	Canimimage =>
		c.cur = 0;
	}
	ctl.draw(0);
}

Control.draw(ctl: self ref Control, flush: int)
{
	win := ctl.f.cim;
	if (win == nil)
		return;
	oclipr := win.clipr;
	clipr := oclipr;
	any: int;
	(clipr, any) = ctl.r.clip(ctl.f.cr);
	if(!any) {
		if(ctl != ctl.f.vscr && ctl != ctl.f.hscr)
			return;
		# Frame scrollbars are positioned outside f.cr (to its right/below).
		# Clip to the scrollbar's own rect so it draws in its correct column.
		clipr = ctl.r;
	}
	win.clipr = clipr;
	pick c := ctl {
	Cbutton =>
		if(c.ff != nil && c.ff.image != nil && c.pic == nil) {
			# check to see if image arrived
			# (dimensions will have been set by checkffsize, if needed;
			# this code is only for when the HTML specified the dimensions)
			pick imi := c.ff.image {
			Iimage =>
				if(imi.ci.mims != nil && len imi.ci.mims > 0 && imi.ci.mims[0] != nil && imi.ci.mims[0].im != nil) {
					c.pic = imi.ci.mims[0].im;
					c.picmask = imi.ci.mims[0].mask;
				}
			}
		}
		if(c.dorelief || c.pic == nil)
			win.draw(c.r, colorimage(Grey), nil, zp);
		if(c.pic != nil) {
			p, m: ref Image;
			if(c.flags & CFenabled) {
				p = c.pic;
				m = c.picmask;
			}
			else {
				p = c.dpic;
				m = c.dpicmask;
			}
			w := p.r.dx();
			h := p.r.dy();
			x := c.r.min.x + (c.r.dx() - w) / 2;
			y := c.r.min.y + (c.r.dy() - h) / 2;
			if((c.flags & CFactive) && c.dorelief) {
				x++;
				y++;
			}
			win.draw(Rect((x,y),(x+w,y+h)), p, m, zp);
		}
		else if(c.label != "") {
			p := c.r.min.add(Point(BUTMARGIN, BUTMARGIN));
			if(c.flags & CFactive)
				p = p.add(Point(1,1));
			win.text(p, colorimage(Black), zp, fonts[CtlFnt].f, c.label);
		}
		if(c.dorelief) {
			relief := ReliefRaised;
			if(c.flags & CFactive)
				relief = ReliefSunk;
			drawrelief(win, c.r.inset(2), relief);
		}
	Centry =>
		win.draw(c.r, colorimage(White), nil, zp);
		insetr := c.r.inset(2);
		drawrelief(win,insetr, ReliefSunk);
		eclipr := c.r;
		eclipr.min.x += ENTHMARGIN;
		eclipr.max.x -= ENTHMARGIN;
		eclipr.min.y += ENTVMARGIN;
		eclipr.max.y -= ENTVMARGIN;
#		if (c.scr != nil)
#			eclipr.max.x -= SCRFBREADTH;
		(eclipr, any) = clipr.clip(eclipr);
		win.clipr = eclipr;
		p := c.r.min.add(Point(ENTHMARGIN,ENTVMARGIN));
		s := c.s;
		fnt := fonts[CtlFnt].f;
		if(c.left > 0)
			s = s[c.left:];
		if(c.flags&CFsecure) {
			for(i := 0; i < len s; i++)
				s[i] = '*';
		}

		(sels, sele) := normalsel(c.sel);
		(sels, sele) = (sels-c.left, sele-c.left);

		lines : array of string;
		linestarts : array of int;
		textw := c.r.dx()-2*ENTHMARGIN;
		if (c.scr != nil) {
			textw -= SCRFBREADTH;
			c.scr.r = c.scr.r.subpt(c.scr.r.min);
			c.scr.r = c.scr.r.addpt(Point(insetr.max.x-SCRFBREADTH,insetr.min.y));
			c.scr.draw(0);
		}
		if (c.linewrap)
			(lines, linestarts) = wrapstring(fnt, s, textw);
		else
			(lines, linestarts) = (array [] of {s}, array [] of {0});

		q := p;
		black := colorimage(Black);
		white := colorimage(White);
		navy := colorimage(Navy);
		nlines := len lines;
		for (n := 0; n < nlines; n++) {
			segs : list of (int, int, int);
			# only show cursor or selection if we have focus
			if (c.flags & CFhasfocus)
				segs = selsegs(len lines[n], sels-linestarts[n], sele-linestarts[n]);
			else
				segs = (0, len lines[n], 0) :: nil;
			for (; segs != nil; segs = tl segs) {
				(ss, se, sel) := hd segs;
				txt := lines[n][ss:se];
				w := fnt.width(txt);
				txtcol : ref Image;
				if (!sel)
					txtcol = black;
				else {
					txtcol = white;
					bgcol := navy;
					if (n < nlines-1 && sele >= linestarts[n+1])
						w = (p.x-q.x) + textw;
					selr := Rect((q.x, q.y-1), (q.x+w, q.y+ctllinespace+1));
					if (selr.dx() == 0) {
						# empty selection - assume cursor
						bgcol = black;
						selr.max.x = selr.min.x + 2;
					}
					win.draw(selr, bgcol, nil, zp);
				}
				if (se > ss)
					win.text(q, txtcol, zp, fnt, txt);
				q.x += w;
			}
			q = (p.x, q.y + ctllinespace);
		}
		# HTML5 placeholder text: show when entry is empty and has no focus
		if(c.s == "" && c.ff != nil && c.ff.placeholder != "" && !(c.flags & CFhasfocus)) {
			phcolor := colorimage(DarkGrey);
			win.text(p, phcolor, zp, fnt, c.ff.placeholder);
		}
	Ccheckbox=>
		win.draw(c.r, colorimage(White), nil, zp);
		if(c.isradio) {
			a := CBOXHT/2;
			a1 := a-1;
			cen := Point(c.r.min.x+a,c.r.min.y+a);
			win.ellipse(cen, a1, a1, 1, colorimage(DarkGrey), zp);
			win.arc(cen, a, a, 0, colorimage(Black), zp, 45, 180);
			win.arc(cen, a, a, 0, colorimage(Grey), zp, 225, 180);
			if(c.flags&CFactive)
				win.fillellipse(cen, 2, 2, colorimage(Black), zp);
		}
		else {
			ir := c.r.inset(2);
			ir.min.x += CBOXWID-CBOXHT;
			ir.max.x -= CBOXWID-CBOXHT;
			drawrelief(win, ir, ReliefSunk);
			if(c.flags&CFactive) {
				p1 := Point(ir.min.x, ir.min.y);
				p2 := Point(ir.max.x, ir.max.y);
				p3 := Point(ir.max.x, ir.min.y);
				p4 := Point(ir.min.x, ir.max.y);
				win.line(p1, p2, D->Endsquare, D->Endsquare, 0, colorimage(Black), zp);
				win.line(p3, p4, D->Endsquare, D->Endsquare, 0, colorimage(Black), zp);
			}
		}
	Cselect =>
		black := colorimage(Black);
		white := colorimage(White);
		navy := colorimage(Navy);
		win.draw(c.r, white, nil, zp);
		drawrelief(win, c.r.inset(2), ReliefSunk);
		ir := c.r.inset(SELMARGIN);
		p := ir.min;
		fnt := fonts[CtlFnt].f;
		drawsel := c.nvis > 1;
		for(i := c.first; i < len c.options && i < c.first+c.nvis; i++) {
			if(drawsel && c.options[i].selected) {
				maxx := ir.max.x;
				if (c.scr != nil)
					maxx -= SCRFBREADTH;
				r := Rect((p.x-SELMARGIN,p.y),(maxx,p.y+ctllinespace));
				win.draw(r, navy, nil, zp);
				win.text(p, white, zp, fnt, c.options[i].display);
			}
			else {
				win.text(p, black, zp, fnt, c.options[i].display);
			}
			p.y += ctllinespace;
		}
		if (c.nvis == 1 && len c.options > 1) {
			# drop down select list - draw marker (must be same width as scroll bar)
			r := Rect((ir.max.x - SCRFBREADTH, ir.min.y), ir.max);
			drawtriangle(win, r, TRIdown, ReliefRaised);
		} 
		if(c.scr != nil) {
			c.scr.r = Rect((ir.max.x - SCRFBREADTH, ir.min.y), ir.max);
			c.scr.draw(0);
		}
	Clistbox =>
		black := colorimage(Black);
		white := colorimage(White);
		navy := colorimage(Navy);
		win.draw(c.r, white, nil, zp);
		insetr := c.r.inset(2);
		#drawrelief(win, c.r.inset(2), ReliefSunk);
		ir := c.r.inset(SELMARGIN);
		p := ir.min;
		fnt := fonts[CtlFnt].f;
		for(i := c.first; i < len c.options && i < c.first+c.nvis; i++) {
			txt := "";
			if (c.start < len c.options[i].display)
				txt = c.options[i].display[c.start:];
			if(c.options[i].selected) {
				r := Rect((p.x-SELMARGIN,p.y),(c.r.max.x-SCRFBREADTH,p.y+fnt.height));
				win.draw(r, navy, nil, zp);
				win.text(p, white, zp, fnt, txt);
			}
			else {
 				win.text(p, black, zp, fnt, txt);
			}
			p.y +=fnt.height;
		}
		if(c.vscr != nil) {
			c.vscr.r = c.vscr.r.subpt(c.vscr.r.min);
			c.vscr.r = c.vscr.r.addpt(Point(insetr.max.x-SCRFBREADTH,insetr.min.y));
			c.vscr.draw(0);
 		}
 		if(c.hscr != nil) {
			c.hscr.r = c.hscr.r.subpt(c.hscr.r.min);
			c.hscr.r = c.hscr.r.addpt(Point(insetr.min.x, insetr.max.y-SCRFBREADTH));
 			c.hscr.draw(0);
		}
		drawrelief(win, insetr, ReliefSunk);

	Cscrollbar =>
		if(c.wsb != nil) {
			# Delegate to widget.m scrollbar
			c.wsb.draw(win);
		} else {
			# Flat scrollbar fallback for form controls
			SCRTRACK: con 16rE8E8E8;
			SCRTHUMB: con 16rBBBBBB;
			x := c.r.min.x;
			y := c.r.min.y;
			rs: Rect;
			if(c.flags&CFscrvert) {
				l := c.r.max.y - c.r.min.y;
				b := c.r.max.x - c.r.min.x;
				win.draw(c.r, colorimage(SCRTRACK), nil, zp);
				if(l > MINSCR) {
					ys := y + c.top;
					yt2 := y + l - c.bot;
					rs = Rect(Point(x+2, ys), Point(x+b-2, yt2));
					if(rs.dy() >= MINSCR)
						win.draw(rs, colorimage(SCRTHUMB), nil, zp);
				}
			}
			else {
				l := c.r.max.x - c.r.min.x;
				b := c.r.max.y - c.r.min.y;
				win.draw(c.r, colorimage(SCRTRACK), nil, zp);
				if(l > MINSCR) {
					xs := x + c.top;
					xt2 := x + l - c.bot;
					rs = Rect(Point(xs, y+2), Point(xt2, y+b-2));
					if(rs.dx() >= MINSCR)
						win.draw(rs, colorimage(SCRTHUMB), nil, zp);
				}
			}
		}
	Canimimage =>
		i := c.cur;
		if(c.redraw)
			i = 0;
		else if(i > 0) {
			iprev := i-1;
			if(c.cim.mims[iprev].bgcolor != -1) {
				i = iprev;
				# get i back to before all "reset to previous"
				# images (which will be skipped in following
				# image drawing loop)
				while(i > 0 && c.cim.mims[i].bgcolor == -2)
					i--;
			}
		}
		bgi := colorimage(c.bg.color);
		if(c.bg.image != nil && c.bg.image.ci != nil && c.bg.image.ci.mims != nil && len c.bg.image.ci.mims > 0 && c.bg.image.ci.mims[0] != nil && c.bg.image.ci.mims[0].im != nil)
			bgi = c.bg.image.ci.mims[0].im;
		for( ; i <= c.cur; i++) {
			mim := c.cim.mims[i];
			if(i > 0 && i < c.cur && mim.bgcolor == -2)
				continue;
			p := c.r.min.add(mim.origin);
			r := mim.im.r;
			r = Rect(p, p.add(Point(r.dx(), r.dy())));

			# IE takes "clear-to-background" disposal method to mean
			# clear to background of HTML page, ignoring any background
			# color specified in the GIF.
			# IE clears to background before frame 0
			if(i == 0)
				win.draw(c.r, bgi, nil, zp);

			if(i != c.cur && mim.bgcolor >= 0)
				win.draw(r, bgi, nil, zp);
			else
				win.draw(r, mim.im, mim.mask, zp);
		}
	Clabel =>
		p := c.r.min.add(Point(0,ENTVMARGIN));
		win.text(p, colorimage(Black), zp, fonts[DefFnt].f, c.s);
	}
	if(flush) {
		G->flush(ctl.r);
	}
	win.clipr = oclipr;
}

# Break s up into substrings that fit in width availw
# when printing with font fnt.
# The second returned array contains the indexes into the original
# string where the corresponding line starts (which might not be simply
# the sum of the preceding lines because of cr/lf's in the original string
# which are omitted from the lines array.
# Empty lines (ending in cr) get put into the array as empty strings.
# The start indices array has an entry for the phantom next line, to avoid
# the need for special cases in the rest of the code.
wrapstring(fnt: ref Font, s: string, availw: int) : (array of string, array of int)
{
	sl : list of (string, int) = nil;
	sw := fnt.width(s);
	n := 0;
	k := 0;	# index into original s where current s starts
	origlen := len s;
	done := 0;
	while(!done) {
		kincr := 0;
		s1, s2: string;
		if(s == "") {
			s1 = s;
			done = 1;
		}
		else {
			# if any newlines in s1, it's a forced break
			# (and newlines aren't to appear in result)
			(s1, s2) = S->splitl(s, "\n");
			if(s2 != nil && fnt.width(s1) <= availw) {
				s = s2[1:];
				sw = fnt.width(s);
				kincr = (len s1) + 1;
			}
			else if(sw <= availw) {
				s1 = s;
				done = 1;
			}
			else {
				(s1, nil, s, sw) = breakstring(s, sw, fnt, availw, 0);
				kincr = len s1;
				if(s == "")
					done = 1;
			}
		}
		sl = (s1, k) :: sl;
		k += kincr;
		n++;
	}
	# reverse sl back to original order
	lines := array[n] of string;
	linestarts := array[n+1] of int;
	linestarts[n] = origlen;
	while(sl != nil) {
		(ss, nn) := hd sl;
		lines[--n] = ss;
		linestarts[n] = nn;
		sl = tl sl;
	}
	return (lines, linestarts);
}

normalsel(sel : (int, int)) : (int, int)
{
	(s, e) := sel;
	if (s > e)
		(e, s) = sel;
	return (s, e);
}

selsegs(n, s, e : int) : list of (int, int, int)
{
	if (e < 0 || s > n)
		# selection is not in 0..n
		return (0, n, 0) :: nil;

	if (e > n) {
		# second half of string is selected
		if (s <= 0)
			return (0, n, 1) :: nil;
		return (0, s, 0) :: (s, n, 1) :: nil;
	}

	if (s < 0) {
		# first half of string is selected
		if (e >= n)
			return (0, n, 1) :: nil;
		return (0, e, 1) :: (e, n, 0) :: nil;
	}
	# middle section of string is selected
	return (0, s, 0) :: (s, e, 1) :: (e, n, 0) :: nil;
}

# Figure out in which area of scrollbar, if any, p lies.
# Then use p and mtype from mouse event to return desired action.
Control.entryset(c: self ref Control, s: string)
{
	pick e := c {
	Centry =>
		e.s = s;
		e.sel = (0, 0);
		e.left = 0;
		# calculate scroll bar settings
		if (e.linewrap && e.scr != nil) {
			(lines, nil, nil, nil) := entrywrapcalc(e);
			nlines := len lines;
			ny := (e.r.dy() - 2 * ENTVMARGIN)/ctllinespace;
			e.scr.scrollset(0, ny, (nlines - 1), nlines, 0);
		}
	}
}

entryupdown(e: ref Control.Centry, cur : int, delta : int) : int
{
	e.sel = (cur, cur);
	(lines, linestarts, nil, cursline) := entrywrapcalc(e);
	newl := cursline + delta;
	if (newl < 0 || newl >= len lines)
		return cur;

	fnt := fonts[CtlFnt].f;
	x := cur - linestarts[cursline];
	w := fnt.width(lines[cursline][0:x]);
	l := lines[newl];
	if (len l == 0)
		return linestarts[newl];
	prevw := fnt.width(l);
	curw := prevw;
	for (ix := len l - 1; ix > 0 ; ix--) {
		prevw = curw;
		curw = fnt.width(l[:ix]);
		if (curw < w)
			break;
	}
	# decide on closest (curw <= w <= prevw)
	if (prevw-w <= w - curw)
		# closer to rhs
		ix++;
	return linestarts[newl]+ix;
}

# delete given range of characters, and redraw
entrydelrange(e: ref Control.Centry, istart, iend: int)
{
	n := iend - istart;
	(sels, sele) := normalsel(e.sel);
	if(n > 0) {
		e.s = e.s[0:istart] + e.s[iend:];

		if(sels > istart) {
			if(sels < iend)
				sels = istart;
			else
				sels -= n;
		}
		if (sele > istart) {
			if (sele < iend)
				sele = istart;
			else
				sele -= n;
		}

		if(e.left > istart)
			e.left = max(istart-1, 0);
		e.sel = (sels, sele);
		entryscroll(e);
	}
}

snarf : string;
entrysetsnarf(e: ref Control.Centry)
{
	if (e.s == nil)
		return;
	s := e.s;
	(sels, sele) := normalsel(e.sel);
	if (sels != sele)
		s = e.s[sels:sele];
		
	f := sys->open("/chan/snarf", sys->OWRITE);
	if (f == nil)
		snarf = s;
	else {
		data := array of byte s;
		sys->write(f, data, len data);
	}
}

entryinsertsnarf(e: ref Control.Centry)
{
	f := sys->open("/chan/snarf", sys->OREAD);
	if(f != nil) {
		buf := array[sys->ATOMICIO] of byte;
		n := sys->read(f, buf, len buf);
		if(n > 0) {
			# trim a trailing newline, as a service...
			if(buf[n-1] == byte '\n')
				n--;
		}
		snarf = "";
		if (n > 0)
			snarf = string buf[:n];
	}

	if (snarf != nil) {
		(sels, sele) := normalsel(e.sel);
		if (sels != sele) {
			entrydelrange(e, sels, sele);
			(sels, sele) = e.sel;
		}
		lhs, rhs : string;
		if (sels > 0)
			lhs = e.s[:sels];
		if (sels < len e.s)
			rhs  = e.s[sels:];
		e.entryset(lhs + snarf + rhs);
		e.sel = (len lhs, len lhs + len snarf);
	}
}

# make sure can see cursor and following char or two
entryscroll(e: ref Control.Centry)
{
	s := e.s;
	slen := len s;
	if(e.flags&CFsecure) {
		for(i := 0; i < slen; i++)
			s[i] = '*';
	}
	if(e.linewrap) {
		# For multiple line entries, c.left is the char
		# at the beginning of the topmost visible line,
		# and we just want to scroll to make sure that
		# the line with the cursor is visible
		(nil, linestarts, topline, cursline) := entrywrapcalc(e);
		vislines := (e.r.dy()-2*ENTVMARGIN) / ctllinespace;
		nlines := len linestarts;
		if(cursline < topline)
			topline = cursline;
		else {
			if(cursline >= topline+vislines)
				topline = cursline-vislines+1;
			if (topline + vislines >= nlines)
				topline = max(0, (nlines-1) - vislines);
		}
		e.left = linestarts[topline];
		if (e.scr != nil)
			e.scr.scrollset(topline, topline+vislines, nlines-1, nlines, 1);
	}
	else {
		(nil, sele) := e.sel;
		# sele is always the drag point
		if(sele < e.left)
			e.left = sele;
		else if(sele > e.left) {
			fnt := fonts[CtlFnt].f;
			wantw := e.r.dx() -2*ENTHMARGIN; # - 2*ctlspspace;
			while(e.left < sele-1) {
				w := fnt.width(e.s[e.left:sele]);
				if(w < wantw)
					break;
				e.left++;
			}
		}
	}
}

# Given e, a Centry with line wrapping,
# return (wrapped lines, line start indices, line# of top displayed line, line# containing cursor).
entrywrapcalc(e: ref Control.Centry) : (array of string, array of int, int, int)
{
	s := e.s;
	if(e.flags&CFsecure) {
		for(i := 0; i < len s; i++)
			s[i] = '*';
	}
	(nil, sele) := e.sel;
	textw := e.r.dx()-2*ENTHMARGIN;
	if (e.scr != nil)
		textw -= SCRFBREADTH;
	(lines, linestarts) := wrapstring(fonts[CtlFnt].f, s, textw);
	topline := 0;
	cursline := 0;
	for(i := 0; i < len lines; i++) {
		s = lines[i];
		i1 := linestarts[i];
		i2 := linestarts[i+1];
		if(e.left >= i1 && e.left < i2)
			topline = i;
		if(sele >= i1 && sele < i2)
			cursline = i;
	}
	if(sele == linestarts[len lines])
		cursline = len lines - 1;
	return (lines, linestarts, topline, cursline);
}

Lay.new(targwidth: int, just: byte, margin: int, bg: Background) : ref Lay
{
	ans := ref Lay(Line.new(), Line.new(),
			targwidth, 0, 0, margin, nil, bg, just, byte 0,
			0, STYLNONE, STYLNONE, STYLNONE, byte 0,
			WBnormal, TOclip);
	if(ans.targetwidth < 0)
		ans.targetwidth = 0;
	ans.start.pos = Point(margin, margin);
	ans.start.next = ans.end;
	ans.end.prev = ans.start;
	# dummy item at end so ans.end will have correct y coord
	it := Item.newspacer(ISPnull, 0);
	it.state = IFbrk|IFcleft|IFcright;
	ans.end.items = it;
	return ans;
}

Line.new() : ref Line
{
	return ref Line(
			nil, nil, nil,	# items, next, prev
			zp,		# pos
			0, 0, 0,	# width, height, ascent
			byte 0);	# flags
}

Loc.new() : ref Loc
{
	return ref Loc(array[10] of Locelem, 0, zp);	# le, n, pos
}

Loc.add(loc: self ref Loc, kind: int, pos: Point)
{
	if(loc.n == len loc.le) {
		newa := array[len loc.le + 10] of Locelem;
		newa[0:] = loc.le;
		loc.le = newa;
	}
	loc.le[loc.n].kind = kind;
	loc.le[loc.n].pos = pos;
	loc.n++;
}

# return last frame in loc's path
Loc.lastframe(loc: self ref Loc) : ref Frame
{
	if (loc == nil)
		return nil;
	for(i := loc.n-1; i >=0; i--)
		if(loc.le[i].kind == LEframe)
			return loc.le[i].frame;
	return nil;
}

Loc.print(loc: self ref Loc, msg: string)
{
	sys->print("%s: Loc with %d components, pos=(%d,%d)\n", msg, loc.n, loc.pos.x, loc.pos.y);
	for(i := 0; i < loc.n; i++) {
		case loc.le[i].kind {
		LEframe =>
			sys->print("frame %x\n",  loc.le[i].frame);
		LEline =>
			sys->print("line %x\n", loc.le[i].line);
		LEitem =>
			sys->print("item: %x", loc.le[i].item);
			loc.le[i].item.print();
		LEtablecell =>
			sys->print("tablecell: %x, cellid=%d\n", loc.le[i].tcell, loc.le[i].tcell.cellid);
		LEcontrol =>
			sys->print("control %x\n", loc.le[i].control);
		}
	}
}

Sources.new(m : ref Source) : ref Sources
{
	srcs := ref Sources;
	srcs.main = m;
	return srcs;
}

Sources.add(srcs: self ref Sources, s: ref Source, required: int)
{
	if (required) {
		CU->assert(srcs.reqd == nil);
		srcs.reqd = s;
	} else
		srcs.srcs = s :: srcs.srcs;
}

Sources.done(srcs: self ref Sources, s: ref Source)
{
	if (s == srcs.main) {
		if (srcs.reqd != nil) {
			sys->print("FREEING MAIN WHEN REQD != nil\n");
			if (s.bs == nil)
				sys->print("s.bs == nil\n");
			else
				sys->print("main.eof = %d main.lim = %d, main.edata = %d\n", s.bs.eof, s.bs.lim, s.bs.edata);
		}
		srcs.main = nil;
	}
	else if (s == srcs.reqd)
		srcs.reqd = nil;
	else {
		new : list of ref Source;
		for (old := srcs.srcs; old != nil; old = tl old) {
			src := hd old;
			if (src == s)
				continue;
			new = src :: new;
		}
		srcs.srcs = new;
	}
}

Sources.waitsrc(srcs: self ref Sources) : ref Source
{
	if (srcs == nil)
		return nil;

	bsl : list of ref ByteSource;

	if (srcs.reqd == nil && srcs.main != nil) {
		pick s := srcs.main {
		Shtml =>
			if (s.itsrc.toks != nil || s.itsrc.reqddata != nil)
				return s;
		}
	}

	# always check for subordinates
	for (sl := srcs.srcs; sl != nil; sl = tl sl)
		bsl = (hd sl).bs :: bsl;
	# reqd is taken in preference to main source as main
	# cannot be processed until we have the whole of reqd
	if (srcs.reqd != nil)
		bsl = srcs.reqd.bs :: bsl;
	else if (srcs.main != nil)
		bsl = srcs.main.bs :: bsl;
	if (bsl == nil)
		return nil;
	bs : ref ByteSource;
	for (;;) {
		bs = CU->waitreq(bsl);
		if (srcs.reqd == nil || srcs.reqd.bs != bs)
			break;
		# only interested in reqd if we have got it all
		if (bs.err != "" || bs.eof)
			return srcs.reqd;
	}
	if (srcs.main != nil && srcs.main.bs == bs)
		return srcs.main;
	found : ref Source;
	for(sl = srcs.srcs; sl != nil; sl = tl sl) {
		s := hd sl;
		if(s.bs == bs) {
			found = s;
			break;
		}
	}
	CU->assert(found != nil);
	return found;
}

# spawned to animate images in frame f
animproc(f: ref Frame)
{
	f.animpid = sys->pctl(0, nil);
	aits : list of ref Item = nil;
	# let del be millisecs to sleep before next frame change
	del := 10000000;
	d : int;
	for(il := f.doc.images; il != nil; il = tl il) {
		it := hd il;
		pick i := it {
		Iimage =>
			ms := i.ci.mims;
			if(ms != nil && len ms > 1) {
				loc := f.find(zp, it);
				if(loc == nil) {
					# could be background, I suppose -- don't animate it
					if(dbg)
						sys->print("couldn't find item for animated image\n");
					continue;
				}
				p := loc.le[loc.n-1].pos;
				p.x += int i.hspace + int i.border;
				# BUG: should get background from least enclosing layout
				ctl := Control.newanimimage(f, i.ci, f.layout.background);
				ctl.r = ctl.r.addpt(p);
				i.ctlid = f.addcontrol(ctl);
				d = ms[0].delay;
				if(dbg)
					sys->print("added anim ctl %d for image %s, initial delay %d\n",
						i.ctlid, i.ci.src.tostring(), d);
				aits = it :: aits;
				if(d < del)
					del = d;
			}
		}
	}
	if(aits == nil)
		return;
	tot := big 0;
	for(;;) {
		sys->sleep(del);
		tot = tot + big del;
		newdel := 10000000;
		for(al := aits; al != nil; al = tl al) {
			pick i := hd al {
			Iimage =>
				ms := i.ci.mims;
				pick c := f.controls[i.ctlid] {
				Canimimage =>
					m := ms[c.cur];
					d = m.delay;
					if(d > 0)
						d -= int (tot - c.ts);
					if(d == 0) {
						# advance to next frame and show it
						c.cur++;
						if(c.cur == len ms)
							c.cur = 0;
						d = ms[c.cur].delay;
						c.ts = tot;
						c.draw(1);
					}
					if(d < newdel)
						newdel = d;
				}
			}
		}
		del = newdel;
	}
}

# Apply CSS text-transform to all Itext items in an item list
applytexttransform(items: ref Item, tt: byte)
{
	for(it := items; it != nil; it = it.next) {
		pick t := it {
		Itext =>
			if(t.s == nil || len t.s == 0)
				continue;
			case int tt {
			int B->TTuppercase =>
				t.s = S->toupper(t.s);
			int B->TTlowercase =>
				t.s = S->tolower(t.s);
			int B->TTcapitalize =>
				s := t.s;
				capnext := 1;
				for(i := 0; i < len s; i++) {
					c := s[i];
					if(capnext && c >= 'a' && c <= 'z')
						s[i] = c - ('a' - 'A');
					capnext = (c == ' ' || c == '\t' || c == '\n');
				}
				t.s = s;
			}
		}
	}
}

# Size an Ibox item using a sublayout, similar to how table cells work.
# The box gets its own Lay where content is laid out.
# availwidth is the available line width for sizing (used for inline-block
# shrink-to-fit and percentage width calculations).
checkboxsize(f: ref Frame, it: ref Item, box: ref Item.Ibox, availwidth: int)
{
	cs := box.cstyle;
	padl := 0;
	padr := 0;
	padt := 0;
	padb := 0;
	bdl := 0;
	bdr := 0;
	bdt := 0;
	bdb := 0;
	if(cs != nil) {
		padl = cs.padding[3];
		padr = cs.padding[1];
		padt = cs.padding[0];
		padb = cs.padding[2];
		bdl = cs.border_width[3];
		bdr = cs.border_width[1];
		bdt = cs.border_width[0];
		bdb = cs.border_width[2];
	}
	extraw := padl + padr + bdl + bdr;
	extrah := padt + padb + bdt + bdb;

	# Calculate available width for content
	isinline := cs != nil && cs.display == DSPINLINEBLOCK;
	avail: int;
	if(isinline) {
		# inline-block: use available line width for shrink-to-fit
		avail = availwidth;
		if(avail <= 0)
			avail = 400;
	} else {
		avail = it.width;
		if(avail <= 0)
			avail = 600;	# reasonable default
	}
	contentw := avail - extraw;
	if(contentw < 10)
		contentw = 10;

	# Use width spec from computed style if present
	if(cs != nil && cs.width.kind() == Dpixels) {
		if(cs.box_sizing == BSZborder)
			contentw = cs.width.spec() - extraw;
		else
			contentw = cs.width.spec();
	}
	else if(cs != nil && cs.width.kind() == Dpercent && avail > 0)
		contentw = avail * cs.width.spec() / 100 - extraw;

	# Apply min/max width constraints to content width before sublayout
	if(cs != nil) {
		if(cs.max_width.kind() == Dpixels && contentw > cs.max_width.spec())
			contentw = cs.max_width.spec();
		if(cs.min_width.kind() == Dpixels && contentw < cs.min_width.spec())
			contentw = cs.min_width.spec();
	}

	# Create sublayout for box content
	bg := Background(nil, -1);
	if(cs != nil && cs.bgcolor != STYLNONE)
		bg.color = cs.bgcolor;
	if(box.layid < 0) {
		slay := Lay.new(contentw, Aleft, 0, bg);
		box.layid = f.sublayid++;
		if(box.layid >= len f.sublays) {
			newsublays := array[box.layid + 10] of ref Lay;
			newsublays[:] = f.sublays;
			f.sublays = newsublays;
		}
		f.sublays[box.layid] = slay;
	}
	slay := f.sublays[box.layid];
	slay.targetwidth = contentw;
	slay.background = bg;

	# Propagate CSS text properties from ComputedStyle to sublayout
	if(cs != nil) {
		slay.text_indent = cs.text_indent;
		slay.line_height = cs.line_height;
		slay.letter_spacing = cs.letter_spacing;
		slay.word_spacing = cs.word_spacing;
		slay.white_space = cs.white_space;
		slay.word_break = cs.word_break;
		slay.text_overflow = cs.text_overflow;
		if(cs.halign != Anone) {
			if(cs.halign == Acenter)
				slay.just = Acenter;
			else if(cs.halign == Aright)
				slay.just = Aright;
			else
				slay.just = Aleft;
		}
	}

	# CSS text-transform: transform text content before layout
	if(cs != nil && cs.text_transform != B->TTnone)
		applytexttransform(box.content, cs.text_transform);

	# Grid, flexbox, or normal flow layout
	if(cs != nil && (cs.display == DSPgrid || cs.display == DSPinline_grid))
		laygriditems(f, slay, box.content, cs);
	else if(cs != nil && (cs.display == DSPflex || cs.display == DSPinline_flex))
		layflexitems(f, slay, box.content, cs);
	else
		layalistitems(f, slay, box.content);

	it.width = slay.width + extraw;
	it.height = slay.height + extrah;
	it.ascent = it.height;

	# Apply height spec if present
	if(cs != nil && cs.height.kind() == Dpixels) {
		spech: int;
		if(cs.box_sizing == BSZborder)
			spech = cs.height.spec();
		else
			spech = cs.height.spec() + extrah;
		# When overflow is hidden/scroll/auto, clamp to spec height
		if(cs.overflow != OVvisible && cs.overflow != byte 0)
			it.height = spech;
		else if(spech > it.height)
			it.height = spech;
	}

	# Enforce min/max constraints on final dimensions
	if(cs != nil) {
		if(cs.min_width.kind() == Dpixels && it.width < cs.min_width.spec() + extraw)
			it.width = cs.min_width.spec() + extraw;
		if(cs.max_width.kind() == Dpixels && it.width > cs.max_width.spec() + extraw)
			it.width = cs.max_width.spec() + extraw;
		if(cs.min_height.kind() == Dpixels && it.height < cs.min_height.spec() + extrah)
			it.height = cs.min_height.spec() + extrah;
		if(cs.max_height.kind() == Dpixels && it.height > cs.max_height.spec() + extrah)
			it.height = cs.max_height.spec() + extrah;
	}
}

# Draw an Ibox item: box-shadow, background, borders, then content via sublayout
drawbox(f: ref Frame, nil: ref Lay, origin: Point, box: ref Item.Ibox)
{
	im := f.cim;
	cs := box.cstyle;
	bdt := 0; bdr := 0; bdb := 0; bdl := 0;
	padt := 0; padr := 0; padb := 0; padl := 0;
	if(cs != nil) {
		bdt = cs.border_width[0];
		bdr = cs.border_width[1];
		bdb = cs.border_width[2];
		bdl = cs.border_width[3];
		padt = cs.padding[0];
		padr = cs.padding[1];
		padb = cs.padding[2];
		padl = cs.padding[3];
	}

	# Skip rendering if visibility is hidden
	if(cs != nil && cs.visibility == VIShidden)
		return;

	# Draw box-shadow (behind everything)
	if(cs != nil && cs.box_shadow_color != STYLNONE) {
		sx := cs.box_shadow_x;
		sy := cs.box_shadow_y;
		blur := cs.box_shadow_blur;
		shadowr := Rect(
			Point(origin.x + sx, origin.y + sy),
			Point(origin.x + box.width + sx, origin.y + box.height + sy));
		# Approximate blur by expanding shadow rect
		if(blur > 0)
			shadowr = shadowr.inset(-blur/2);
		drawfill(im, shadowr, cs.box_shadow_color);
	}

	# Draw background (padding box) with border-radius support
	if(cs != nil && cs.bgcolor != STYLNONE && cs.bgcolor != -1) {
		bgr := Rect(
			Point(origin.x + bdl, origin.y + bdt),
			Point(origin.x + box.width - bdr, origin.y + box.height - bdb));
		hasradius := cs.border_radius[0] > 0 || cs.border_radius[1] > 0
			|| cs.border_radius[2] > 0 || cs.border_radius[3] > 0;
		if(hasradius)
			drawroundedfill(im, bgr, cs.bgcolor, cs.border_radius);
		else
			drawfill(im, bgr, cs.bgcolor);
	}

	# Draw background image (in padding box, after bgcolor, before borders)
	if(cs != nil && cs.bgimage_ci != nil && cs.bgimage_ci.mims != nil) {
		bgr := Rect(
			Point(origin.x + bdl, origin.y + bdt),
			Point(origin.x + box.width - bdr, origin.y + box.height - bdb));
		drawbgimage(im, bgr, cs);
	}

	# Draw borders
	if(cs != nil) {
		hasradius := cs.border_radius[0] > 0 || cs.border_radius[1] > 0
			|| cs.border_radius[2] > 0 || cs.border_radius[3] > 0;
		if(hasradius)
			drawroundedborders(im, origin, box.width, box.height, cs);
		else
			drawboxborders(im, origin, box.width, box.height, cs);
	}

	# Draw content via sublayout
	if(box.layid >= 0 && box.layid < len f.sublays) {
		slay := f.sublays[box.layid];
		if(slay != nil) {
			contentorigin := Point(origin.x + bdl + padl, origin.y + bdt + padt);
			# Clip content for overflow: hidden/scroll/auto
			if(cs != nil && cs.overflow != OVvisible && cs.overflow != byte 0) {
				oclipr := im.clipr;
				contentr := Rect(
					Point(origin.x + bdl + padl, origin.y + bdt + padt),
					Point(origin.x + box.width - bdr - padr, origin.y + box.height - bdb - padb));
				# Intersect with existing clip rect
				(cr, any) := contentr.clip(oclipr);
				if(any) {
					im.clipr = cr;
					drawlay(f, slay, contentorigin);
					im.clipr = oclipr;
				}
			}
			else
				drawlay(f, slay, contentorigin);
		}
	}

	# Draw outline (outside the border, doesn't affect layout)
	if(cs != nil && cs.outline_width > 0 && cs.outline_style != BSnone) {
		ow := cs.outline_width;
		ooff := cs.outline_offset;
		oc := cs.outline_color;
		if(oc == STYLNONE)
			oc = cs.color;
		if(oc == STYLNONE)
			oc = 16r000000;	# default to black
		outliner := Rect(
			Point(origin.x - ow - ooff, origin.y - ow - ooff),
			Point(origin.x + box.width + ow + ooff, origin.y + box.height + ow + ooff));
		drawborder(im, outliner, ow, oc);
	}
}

# Draw CSS box borders with per-side width, style, and color
drawboxborders(im: ref Image, origin: Point, w, h: int, cs: ref ComputedStyle)
{
	x := origin.x;
	y := origin.y;
	xr := x + w;
	yb := y + h;

	# Top border
	if(cs.border_width[0] > 0 && cs.border_style[0] != BSnone) {
		c := cs.border_color[0];
		if(c == STYLNONE)
			c = Black;
		n := cs.border_width[0];
		drawborderedge(im, Rect(Point(x,y), Point(xr,y+n)), c, cs.border_style[0]);
	}
	# Right border
	if(cs.border_width[1] > 0 && cs.border_style[1] != BSnone) {
		c := cs.border_color[1];
		if(c == STYLNONE)
			c = Black;
		n := cs.border_width[1];
		drawborderedge(im, Rect(Point(xr-n,y), Point(xr,yb)), c, cs.border_style[1]);
	}
	# Bottom border
	if(cs.border_width[2] > 0 && cs.border_style[2] != BSnone) {
		c := cs.border_color[2];
		if(c == STYLNONE)
			c = Black;
		n := cs.border_width[2];
		drawborderedge(im, Rect(Point(x,yb-n), Point(xr,yb)), c, cs.border_style[2]);
	}
	# Left border
	if(cs.border_width[3] > 0 && cs.border_style[3] != BSnone) {
		c := cs.border_color[3];
		if(c == STYLNONE)
			c = Black;
		n := cs.border_width[3];
		drawborderedge(im, Rect(Point(x,y), Point(x+n,yb)), c, cs.border_style[3]);
	}
}

# Draw a single border edge with style
drawborderedge(im: ref Image, r: Rect, color: int, style: byte)
{
	src := colorimage(color);
	case int style {
	int BSsolid or int BSinset or int BSoutset or int BSgroove or int BSridge =>
		im.draw(r, src, nil, zp);
	int BSdotted =>
		# Draw dotted by alternating filled/empty segments
		if(r.dx() > r.dy()) {
			# horizontal edge
			step := max(r.dy(), 2);
			for(x := r.min.x; x < r.max.x; x += step*2)
				im.draw(Rect(Point(x, r.min.y), Point(min(x+step, r.max.x), r.max.y)), src, nil, zp);
		}
		else {
			# vertical edge
			step := max(r.dx(), 2);
			for(y := r.min.y; y < r.max.y; y += step*2)
				im.draw(Rect(Point(r.min.x, y), Point(r.max.x, min(y+step, r.max.y))), src, nil, zp);
		}
	int BSdashed =>
		# Draw dashed by alternating segments (3:1 ratio)
		if(r.dx() > r.dy()) {
			step := max(r.dy()*3, 6);
			gap := max(r.dy(), 2);
			for(x := r.min.x; x < r.max.x; x += step+gap)
				im.draw(Rect(Point(x, r.min.y), Point(min(x+step, r.max.x), r.max.y)), src, nil, zp);
		}
		else {
			step := max(r.dx()*3, 6);
			gap := max(r.dx(), 2);
			for(y := r.min.y; y < r.max.y; y += step+gap)
				im.draw(Rect(Point(r.min.x, y), Point(r.max.x, min(y+step, r.max.y))), src, nil, zp);
		}
	int BSdouble =>
		# Draw double border: two lines with gap between
		if(r.dx() > r.dy()) {
			# horizontal: split height into thirds
			n := max(r.dy()/3, 1);
			im.draw(Rect(r.min, Point(r.max.x, r.min.y+n)), src, nil, zp);
			im.draw(Rect(Point(r.min.x, r.max.y-n), r.max), src, nil, zp);
		}
		else {
			n := max(r.dx()/3, 1);
			im.draw(Rect(r.min, Point(r.min.x+n, r.max.y)), src, nil, zp);
			im.draw(Rect(Point(r.max.x-n, r.min.y), r.max), src, nil, zp);
		}
	}
}

# Draw a filled rectangle with rounded corners using corner arcs
drawroundedfill(im: ref Image, r: Rect, color: int, radii: array of int)
{
	src := colorimage(color);
	# Fill the center rectangles (cross shape)
	rtl := radii[0]; rtr := radii[1]; rbr := radii[2]; rbl := radii[3];
	# Clamp radii to half the rect dimensions
	hw := r.dx() / 2;
	hh := r.dy() / 2;
	if(rtl > hw) rtl = hw;
	if(rtl > hh) rtl = hh;
	if(rtr > hw) rtr = hw;
	if(rtr > hh) rtr = hh;
	if(rbr > hw) rbr = hw;
	if(rbr > hh) rbr = hh;
	if(rbl > hw) rbl = hw;
	if(rbl > hh) rbl = hh;
	maxrt := max(rtl, rtr);
	maxrb := max(rbl, rbr);
	# Fill center horizontal band
	im.draw(Rect(Point(r.min.x, r.min.y+maxrt), Point(r.max.x, r.max.y-maxrb)), src, nil, zp);
	# Fill top band (between corners)
	im.draw(Rect(Point(r.min.x+rtl, r.min.y), Point(r.max.x-rtr, r.min.y+maxrt)), src, nil, zp);
	# Fill bottom band (between corners)
	im.draw(Rect(Point(r.min.x+rbl, r.max.y-maxrb), Point(r.max.x-rbr, r.max.y)), src, nil, zp);
	# Fill corner arcs using ellipse
	if(rtl > 0)
		im.fillellipse(Point(r.min.x+rtl, r.min.y+rtl), rtl, rtl, src, zp);
	if(rtr > 0)
		im.fillellipse(Point(r.max.x-rtr, r.min.y+rtr), rtr, rtr, src, zp);
	if(rbr > 0)
		im.fillellipse(Point(r.max.x-rbr, r.max.y-rbr), rbr, rbr, src, zp);
	if(rbl > 0)
		im.fillellipse(Point(r.min.x+rbl, r.max.y-rbl), rbl, rbl, src, zp);
}

# Draw rounded borders (outline arcs at corners + straight edges between)
drawroundedborders(im: ref Image, origin: Point, w, h: int, cs: ref ComputedStyle)
{
	x := origin.x;
	y := origin.y;
	xr := x + w;
	yb := y + h;
	rtl := cs.border_radius[0];
	rtr := cs.border_radius[1];
	rbr := cs.border_radius[2];
	rbl := cs.border_radius[3];
	# Clamp radii
	hw := w / 2;
	hh := h / 2;
	if(rtl > hw) rtl = hw;
	if(rtl > hh) rtl = hh;
	if(rtr > hw) rtr = hw;
	if(rtr > hh) rtr = hh;
	if(rbr > hw) rbr = hw;
	if(rbr > hh) rbr = hh;
	if(rbl > hw) rbl = hw;
	if(rbl > hh) rbl = hh;

	# Top border (between TL and TR corners)
	if(cs.border_width[0] > 0 && cs.border_style[0] != BSnone) {
		c := cs.border_color[0];
		if(c == STYLNONE) c = Black;
		n := cs.border_width[0];
		src := colorimage(c);
		im.draw(Rect(Point(x+rtl, y), Point(xr-rtr, y+n)), src, nil, zp);
		# Draw corner arcs
		if(rtl > 0)
			im.arc(Point(x+rtl, y+rtl), rtl, rtl, n-1, src, zp, 45, 90);
		if(rtr > 0)
			im.arc(Point(xr-rtr, y+rtr), rtr, rtr, n-1, src, zp, 0, 45);
	}
	# Right border
	if(cs.border_width[1] > 0 && cs.border_style[1] != BSnone) {
		c := cs.border_color[1];
		if(c == STYLNONE) c = Black;
		n := cs.border_width[1];
		src := colorimage(c);
		im.draw(Rect(Point(xr-n, y+rtr), Point(xr, yb-rbr)), src, nil, zp);
		if(rtr > 0)
			im.arc(Point(xr-rtr, y+rtr), rtr, rtr, n-1, src, zp, 315, 45);
		if(rbr > 0)
			im.arc(Point(xr-rbr, yb-rbr), rbr, rbr, n-1, src, zp, 270, 45);
	}
	# Bottom border
	if(cs.border_width[2] > 0 && cs.border_style[2] != BSnone) {
		c := cs.border_color[2];
		if(c == STYLNONE) c = Black;
		n := cs.border_width[2];
		src := colorimage(c);
		im.draw(Rect(Point(x+rbl, yb-n), Point(xr-rbr, yb)), src, nil, zp);
		if(rbr > 0)
			im.arc(Point(xr-rbr, yb-rbr), rbr, rbr, n-1, src, zp, 225, 45);
		if(rbl > 0)
			im.arc(Point(x+rbl, yb-rbl), rbl, rbl, n-1, src, zp, 180, 45);
	}
	# Left border
	if(cs.border_width[3] > 0 && cs.border_style[3] != BSnone) {
		c := cs.border_color[3];
		if(c == STYLNONE) c = Black;
		n := cs.border_width[3];
		src := colorimage(c);
		im.draw(Rect(Point(x, y+rtl), Point(x+n, yb-rbl)), src, nil, zp);
		if(rtl > 0)
			im.arc(Point(x+rtl, y+rtl), rtl, rtl, n-1, src, zp, 135, 45);
		if(rbl > 0)
			im.arc(Point(x+rbl, yb-rbl), rbl, rbl, n-1, src, zp, 180, 45);
	}
}

# Layout a list of items into a Lay (used for Ibox sublayouts)
layalistitems(f: ref Frame, lay: ref Lay, items: ref Item)
{
	measure(f, items);
	for(l := lay.start; l.next != lay.end; ) {
		nl := l.next;
		l.next = nl.next;
	}
	lay.start.next = lay.end;
	lay.end.prev = lay.start;
	lay.width = 0;
	lay.height = 0;
	for(it := items; it != nil; ) {
		nl := Line.new();
		nl.items = it;
		# Find end of this line (next break or end)
		lastit := it;
		nit := it.next;
		for(; nit != nil; nit = nit.next) {
			if(nit.state & IFbrk)
				break;
			lastit = nit;
		}
		lastit.next = nil;
		it = nit;
		# Insert line before lay.end
		nl.prev = lay.end.prev;
		nl.next = lay.end;
		lay.end.prev.next = nl;
		lay.end.prev = nl;
		nl.flags |= Lchanged;
		fixlinegeom(f, lay, nl);
	}
	# Calculate lay dimensions
	for(l = lay.start.next; l != lay.end; l = l.next) {
		if(l.pos.x + l.width > lay.width)
			lay.width = l.pos.x + l.width;
		h := l.pos.y + l.height;
		if(h > lay.height)
			lay.height = h;
	}
}

# Get flex-grow value for an item (from its Ibox cstyle, or 0)
flexgrow(it: ref Item) : int
{
	pick box := it {
	Ibox =>
		if(box.cstyle != nil && box.cstyle.flex_grow > 0)
			return box.cstyle.flex_grow;
	}
	return 0;
}

# Get flex-shrink value for an item (from its Ibox cstyle, default 100 = 1.0)
flexshrink(it: ref Item) : int
{
	pick box := it {
	Ibox =>
		if(box.cstyle != nil && box.cstyle.flex_shrink > 0)
			return box.cstyle.flex_shrink;
	}
	return 100;  # default flex-shrink: 1
}

# Get flex-basis value for an item (returns pixel value, or -1 for auto)
flexbasis(it: ref Item) : int
{
	pick box := it {
	Ibox =>
		if(box.cstyle != nil && box.cstyle.flex_basis.kind() == Dpixels)
			return box.cstyle.flex_basis.spec();
	}
	return -1;
}

# Get order value for an item (default 0)
flexorder(it: ref Item) : int
{
	pick box := it {
	Ibox =>
		if(box.cstyle != nil && box.cstyle.order != STYLNONE)
			return box.cstyle.order;
	}
	return 0;
}

# Flexbox layout: arrange items according to flex-direction, justify-content,
# flex-wrap, flex-grow/shrink, flex-basis, and order.
layflexitems(f: ref Frame, lay: ref Lay, items: ref Item, cs: ref ComputedStyle)
{
	measure(f, items);

	# Clear existing lines
	for(l := lay.start; l.next != lay.end; ) {
		nl := l.next;
		l.next = nl.next;
	}
	lay.start.next = lay.end;
	lay.end.prev = lay.start;
	lay.width = 0;
	lay.height = 0;

	# Collect items into array
	nitems := 0;
	for(it := items; it != nil; it = it.next)
		nitems++;
	if(nitems == 0)
		return;

	ia := array[nitems] of ref Item;
	i := 0;
	for(it = items; it != nil; it = it.next) {
		ia[i] = it;
		i++;
	}

	# Sort by order property (insertion sort — flex containers are typically small)
	for(i = 1; i < nitems; i++) {
		key := ia[i];
		ko := flexorder(key);
		j := i - 1;
		for(; j >= 0 && flexorder(ia[j]) > ko; j--)
			ia[j+1] = ia[j];
		ia[j+1] = key;
	}

	# Apply flex-basis: override natural width/height with basis if set
	isrow := cs.flex_direction == FDrow || cs.flex_direction == FDrow_reverse;
	for(i = 0; i < nitems; i++) {
		basis := flexbasis(ia[i]);
		if(basis >= 0) {
			if(isrow)
				ia[i].width = basis;
			else
				ia[i].height = basis;
		}
	}

	gap := cs.gap;
	avail := lay.targetwidth;

	if(isrow) {
		# --- ROW DIRECTION with flex-wrap ---
		# Partition items into flex lines
		lines: list of ref FlexLine;
		nlines := 0;
		linestart := 0;
		linew := 0;

		for(i = 0; i < nitems; i++) {
			w := ia[i].width;
			neww := linew + w;
			if(i > linestart)
				neww += gap;
			if(cs.flex_wrap != FWnowrap && i > linestart && neww > avail) {
				# Start new line
				fl := ref FlexLine(linestart, i - linestart, 0);
				lines = fl :: lines;
				nlines++;
				linestart = i;
				linew = w;
			}
			else
				linew = neww;
		}
		# Last line
		if(linestart < nitems) {
			fl := ref FlexLine(linestart, nitems - linestart, 0);
			lines = fl :: lines;
			nlines++;
		}

		# Reverse lines list to get correct order
		rlines := array[nlines] of ref FlexLine;
		li := nlines - 1;
		for(; lines != nil; lines = tl lines) {
			rlines[li] = hd lines;
			li--;
		}

		# Process each flex line
		y := 0;
		for(li = 0; li < nlines; li++) {
			fl := rlines[li];

			# Compute total width, max height, and flex-grow/shrink sums for this line
			totalw := 0;
			maxh := 0;
			totalgrow := 0;
			totalshrink := 0;
			for(i = fl.start; i < fl.start + fl.count; i++) {
				totalw += ia[i].width;
				if(ia[i].height > maxh)
					maxh = ia[i].height;
				totalgrow += flexgrow(ia[i]);
				totalshrink += flexshrink(ia[i]);
			}
			fl.maxh = maxh;
			totalgap := gap * (fl.count - 1);
			remaining := avail - totalw - totalgap;

			# flex-grow: distribute positive remaining space
			if(remaining > 0 && totalgrow > 0) {
				for(i = fl.start; i < fl.start + fl.count; i++) {
					fg := flexgrow(ia[i]);
					if(fg > 0) {
						extra := remaining * fg / totalgrow;
						ia[i].width += extra;
					}
				}
				remaining = 0;
			}

			# flex-shrink: shrink items when overflowing
			if(remaining < 0 && totalshrink > 0) {
				overflow := -remaining;
				for(i = fl.start; i < fl.start + fl.count; i++) {
					fs := flexshrink(ia[i]);
					if(fs > 0) {
						shrink := overflow * fs / totalshrink;
						if(shrink > ia[i].width)
							shrink = ia[i].width;
						ia[i].width -= shrink;
					}
				}
				remaining = 0;
			}
			if(remaining < 0)
				remaining = 0;

			# Re-layout Ibox items at adjusted widths
			for(i = fl.start; i < fl.start + fl.count; i++) {
				pick box := ia[i] {
				Ibox =>
					if(box.layid >= 0 && box.layid < len f.sublays) {
						slay := f.sublays[box.layid];
						slay.targetwidth = ia[i].width;
						bcs := box.cstyle;
						if(bcs != nil && (bcs.display == DSPflex || bcs.display == DSPinline_flex))
							layflexitems(f, slay, box.content, bcs);
						else if(bcs != nil && (bcs.display == DSPgrid || bcs.display == DSPinline_grid))
							laygriditems(f, slay, box.content, bcs);
						else
							layalistitems(f, slay, box.content);
						ia[i].height = slay.height;
						ia[i].ascent = ia[i].height;
						if(ia[i].height > maxh)
							maxh = ia[i].height;
					}
				* => ;
				}
			}
			fl.maxh = maxh;

			# Calculate starting x based on justify-content
			x := 0;
			spacing := 0;
			case int cs.justify_content {
			int JCflex_end =>
				x = remaining;
			int JCcenter =>
				x = remaining / 2;
			int JCspace_between =>
				if(fl.count > 1)
					spacing = remaining / (fl.count - 1);
			int JCspace_around =>
				if(fl.count > 0) {
					spacing = remaining / fl.count;
					x = spacing / 2;
				}
			int JCspace_evenly =>
				if(fl.count > 0) {
					spacing = remaining / (fl.count + 1);
					x = spacing;
				}
			}

			if(cs.flex_direction == FDrow_reverse)
				x = avail - x;

			# Place items in this line
			for(i = fl.start; i < fl.start + fl.count; i++) {
				it = ia[i];
				it.next = nil;

				nl := Line.new();
				nl.items = it;

				# Align item vertically
				iy := 0;
				case int cs.align_items {
				int AIcenter =>
					if(it.height < maxh)
						iy = (maxh - it.height) / 2;
				int AIflex_end =>
					if(it.height < maxh)
						iy = maxh - it.height;
				int AIstretch =>
					it.height = maxh;
					it.ascent = maxh;
				}

				if(cs.flex_direction == FDrow_reverse) {
					x -= it.width;
					nl.pos = Point(x, y + iy);
					x -= gap + spacing;
				}
				else {
					nl.pos = Point(x, y + iy);
					x += it.width + gap + spacing;
				}
				nl.width = it.width;
				nl.height = it.height;
				nl.ascent = it.ascent;
				nl.flags |= Lchanged;

				nl.prev = lay.end.prev;
				nl.next = lay.end;
				lay.end.prev.next = nl;
				lay.end.prev = nl;
			}

			y += maxh + gap;
		}

		lay.width = avail;
		if(y > gap)
			lay.height = y - gap;
		else
			lay.height = 0;

		# flex-wrap-reverse: reverse y positions of lines
		if(cs.flex_wrap == FWwrap_reverse && nlines > 1) {
			totalh := lay.height;
			for(l = lay.start.next; l != lay.end; l = l.next)
				l.pos.y = totalh - l.pos.y - l.height;
		}
	}
	else {
		# --- COLUMN DIRECTION ---
		y := 0;

		for(i = 0; i < nitems; i++) {
			it = ia[i];
			it.next = nil;

			nl := Line.new();
			nl.items = it;

			# Align item horizontally based on align-items
			ix := 0;
			case int cs.align_items {
			int AIcenter =>
				if(it.width < avail)
					ix = (avail - it.width) / 2;
			int AIflex_end =>
				if(it.width < avail)
					ix = avail - it.width;
			int AIstretch =>
				it.width = avail;
			}

			if(cs.flex_direction == FDcolumn_reverse)
				nl.pos = Point(ix, 0);
			else {
				nl.pos = Point(ix, y);
				y += it.height + gap;
			}
			nl.width = it.width;
			nl.height = it.height;
			nl.ascent = it.ascent;
			nl.flags |= Lchanged;

			nl.prev = lay.end.prev;
			nl.next = lay.end;
			lay.end.prev.next = nl;
			lay.end.prev = nl;
		}

		lay.width = avail;
		if(cs.flex_direction == FDcolumn_reverse) {
			totalh := 0;
			for(l = lay.start.next; l != lay.end; l = l.next)
				totalh += l.height + gap;
			if(totalh > 0)
				totalh -= gap;
			cy := 0;
			for(l = lay.end.prev; l != lay.start; l = l.prev) {
				l.pos.y = cy;
				cy += l.height + gap;
			}
			lay.height = totalh;
		}
		else {
			if(y > 0)
				lay.height = y - gap;
			else
				lay.height = 0;
		}
	}
}

# Get grid placement properties for an item (from Ibox cstyle)
# Returns (col_start, col_end, row_start, row_end) — 1-based, 0=auto
gridplacement(it: ref Item) : (int, int, int, int)
{
	pick box := it {
	Ibox =>
		if(box.cstyle != nil)
			return (box.cstyle.grid_column_start, box.cstyle.grid_column_end,
				box.cstyle.grid_row_start, box.cstyle.grid_row_end);
	}
	return (0, 0, 0, 0);
}

# CSS Grid layout: arrange items into a grid defined by grid-template-columns/rows.
# Supports fr units, auto, fixed (px) track sizes, and explicit item placement.
laygriditems(f: ref Frame, lay: ref Lay, items: ref Item, cs: ref ComputedStyle)
{
	measure(f, items);

	# Clear existing lines
	for(l := lay.start; l.next != lay.end; ) {
		nl := l.next;
		l.next = nl.next;
	}
	lay.start.next = lay.end;
	lay.end.prev = lay.start;
	lay.width = 0;
	lay.height = 0;

	# Count items
	nitems := 0;
	for(it := items; it != nil; it = it.next)
		nitems++;
	if(nitems == 0)
		return;

	avail := lay.targetwidth;
	colgap := cs.grid_gap_col;
	rowgap := cs.grid_gap_row;

	# Parse column tracks
	ncols := 0;
	colwidths: array of int;
	if(cs.grid_template_columns != nil && cs.grid_template_columns != "")
		colwidths = parsegridtracks(cs.grid_template_columns, avail, colgap, items);
	if(colwidths == nil)
		colwidths = array[1] of { * => avail };
	ncols = len colwidths;

	# Collect items into array
	itemarray := array[nitems] of ref Item;
	i := 0;
	for(it = items; it != nil; it = it.next) {
		itemarray[i] = it;
		i++;
	}

	# Determine grid dimensions considering explicit placements
	# First pass: find max explicit row/col to size the grid
	maxrow := (nitems + ncols - 1) / ncols;
	for(i = 0; i < nitems; i++) {
		(cs2, ce2, rs2, re2) := gridplacement(itemarray[i]);
		if(rs2 > 0 && rs2 > maxrow) maxrow = rs2;
		if(re2 > 0 && re2 - 1 > maxrow) maxrow = re2 - 1;
		# Column spanning might need more rows
		if(cs2 > 0 && ce2 > 0 && ce2 - cs2 > 1) {
			# spanning item takes fewer grid cells
			;
		}
	}
	nrows := maxrow;

	# Build placement grid: grid_cells[row][col] = item index, -1 = empty
	grid_cells := array[nrows] of { * => array[ncols] of { * => -1 } };

	# Item placement: (row, col) for each item, and (colspan, rowspan)
	item_row := array[nitems] of { * => -1 };
	item_col := array[nitems] of { * => -1 };
	item_colspan := array[nitems] of { * => 1 };
	item_rowspan := array[nitems] of { * => 1 };

	# Pass 1: Place explicitly-positioned items
	for(i = 0; i < nitems; i++) {
		(cs1, ce1, rs1, re1) := gridplacement(itemarray[i]);
		if(cs1 <= 0 && rs1 <= 0)
			continue;  # auto-placed, handle in pass 2

		# Determine column (1-based to 0-based)
		c := 0;
		if(cs1 > 0) c = cs1 - 1;
		if(c >= ncols) c = ncols - 1;

		# Column span
		colspan := 1;
		if(ce1 > cs1 && cs1 > 0) {
			colspan = ce1 - cs1;
			if(c + colspan > ncols)
				colspan = ncols - c;
		}

		# Determine row
		r := 0;
		if(rs1 > 0) r = rs1 - 1;
		# Grow grid if needed
		if(r >= nrows) {
			nrows = r + 1;
			ngrid := array[nrows] of array of int;
			ri := 0;
			for(ri = 0; ri < len grid_cells; ri++)
				ngrid[ri] = grid_cells[ri];
			for(ri = len grid_cells; ri < nrows; ri++)
				ngrid[ri] = array[ncols] of { * => -1 };
			grid_cells = ngrid;
		}

		# Row span
		rowspan := 1;
		if(re1 > rs1 && rs1 > 0) {
			rowspan = re1 - rs1;
			if(r + rowspan > nrows) {
				nrows = r + rowspan;
				ngrid := array[nrows] of array of int;
				ri := 0;
				for(ri = 0; ri < len grid_cells; ri++)
					ngrid[ri] = grid_cells[ri];
				for(ri = len grid_cells; ri < nrows; ri++)
					ngrid[ri] = array[ncols] of { * => -1 };
				grid_cells = ngrid;
			}
		}

		# Mark cells as occupied
		for(ri := r; ri < r + rowspan && ri < nrows; ri++)
			for(ci := c; ci < c + colspan && ci < ncols; ci++)
				grid_cells[ri][ci] = i;

		item_row[i] = r;
		item_col[i] = c;
		item_colspan[i] = colspan;
		item_rowspan[i] = rowspan;
	}

	# Pass 2: Auto-place remaining items
	autorow := 0;
	autocol := 0;
	for(i = 0; i < nitems; i++) {
		if(item_row[i] >= 0)
			continue;  # already placed

		# Find next empty cell
		for(;;) {
			if(autorow >= nrows) {
				# Add a new row
				nrows++;
				ngrid := array[nrows] of array of int;
				for(ri := 0; ri < nrows - 1; ri++)
					ngrid[ri] = grid_cells[ri];
				ngrid[nrows-1] = array[ncols] of { * => -1 };
				grid_cells = ngrid;
			}
			if(grid_cells[autorow][autocol] == -1)
				break;
			autocol++;
			if(autocol >= ncols) {
				autocol = 0;
				autorow++;
			}
		}

		grid_cells[autorow][autocol] = i;
		item_row[i] = autorow;
		item_col[i] = autocol;

		autocol++;
		if(autocol >= ncols) {
			autocol = 0;
			autorow++;
		}
	}

	# Layout each item at its column width to get actual heights
	rowheights := array[nrows] of { * => 0 };
	for(i = 0; i < nitems; i++) {
		col := item_col[i];
		row := item_row[i];
		colspan := item_colspan[i];
		if(col < 0 || row < 0)
			continue;

		# Compute item width (sum of spanned columns + gaps)
		iw := 0;
		for(ci := col; ci < col + colspan && ci < ncols; ci++) {
			if(ci > col)
				iw += colgap;
			iw += colwidths[ci];
		}

		it = itemarray[i];
		pick box := it {
		Ibox =>
			if(box.layid >= 0 && box.layid < len f.sublays) {
				slay := f.sublays[box.layid];
				slay.targetwidth = iw;
				bcs := box.cstyle;
				if(bcs != nil && (bcs.display == DSPflex || bcs.display == DSPinline_flex))
					layflexitems(f, slay, box.content, bcs);
				else if(bcs != nil && (bcs.display == DSPgrid || bcs.display == DSPinline_grid))
					laygriditems(f, slay, box.content, bcs);
				else
					layalistitems(f, slay, box.content);
				it.width = iw;
				it.height = slay.height;
				it.ascent = it.height;
			}
		* =>
			it.width = iw;
		}

		if(it.height > rowheights[row])
			rowheights[row] = it.height;
	}

	# Parse row tracks if specified
	if(cs.grid_template_rows != nil && cs.grid_template_rows != "") {
		totalh := 0;
		r: int;
		for(r = 0; r < nrows; r++)
			totalh += rowheights[r];
		totalh += rowgap * (nrows - 1);
		specrows := parsegridtracks(cs.grid_template_rows, totalh, rowgap, nil);
		if(specrows != nil) {
			for(r = 0; r < len specrows && r < nrows; r++)
				if(specrows[r] > rowheights[r])
					rowheights[r] = specrows[r];
		}
	}

	# Compute cumulative row y-positions
	rowy := array[nrows] of { * => 0 };
	y := 0;
	row := 0;
	for(row = 0; row < nrows; row++) {
		rowy[row] = y;
		y += rowheights[row] + rowgap;
	}

	# Compute cumulative column x-positions
	colx := array[ncols] of { * => 0 };
	x := 0;
	col := 0;
	for(col = 0; col < ncols; col++) {
		colx[col] = x;
		x += colwidths[col] + colgap;
	}

	# Position each item and create lines
	for(i = 0; i < nitems; i++) {
		row = item_row[i];
		col = item_col[i];
		if(row < 0 || col < 0)
			continue;
		colspan := item_colspan[i];
		rowspan := item_rowspan[i];

		it = itemarray[i];
		it.next = nil;

		# Compute spanned dimensions
		spanw := 0;
		for(ci := col; ci < col + colspan && ci < ncols; ci++) {
			if(ci > col) spanw += colgap;
			spanw += colwidths[ci];
		}
		spanh := 0;
		for(ri := row; ri < row + rowspan && ri < nrows; ri++) {
			if(ri > row) spanh += rowgap;
			spanh += rowheights[ri];
		}

		nl := Line.new();
		nl.items = it;
		nl.pos = Point(colx[col], rowy[row]);
		nl.width = spanw;
		nl.height = spanh;
		nl.ascent = it.ascent;
		nl.flags |= Lchanged;

		it.height = spanh;
		it.ascent = spanh;
		it.width = spanw;

		nl.prev = lay.end.prev;
		nl.next = lay.end;
		lay.end.prev.next = nl;
		lay.end.prev = nl;
	}

	lay.width = avail;
	if(y > rowgap)
		lay.height = y - rowgap;
	else
		lay.height = 0;
}

# Parse a CSS grid track list like "1fr 300px auto 2fr" and return pixel widths.
# Handles: fixed px values, fr fractional units, auto (min-content from items), percentages.
parsegridtracks(spec: string, available, gap: int, items: ref Item) : array of int
{
	# Expand repeat() functions: repeat(3, 1fr) => 1fr 1fr 1fr
	spec = expandrepeat(spec);

	# Split spec by whitespace
	parts: list of string;
	nparts := 0;
	i := 0;
	for(;;) {
		# Skip whitespace
		for(; i < len spec && (spec[i] == ' ' || spec[i] == '\t'); i++)
			;
		if(i >= len spec)
			break;
		# Read token (handle repeat() and minmax() by tracking parens)
		start := i;
		depth := 0;
		for(; i < len spec; i++) {
			if(spec[i] == '(')
				depth++;
			else if(spec[i] == ')')
				depth--;
			else if((spec[i] == ' ' || spec[i] == '\t') && depth == 0)
				break;
		}
		parts = spec[start:i] :: parts;
		nparts++;
	}

	# Reverse parts list into array
	tracks := array[nparts] of string;
	j := nparts - 1;
	for(; parts != nil; parts = tl parts) {
		tracks[j] = hd parts;
		j--;
	}

	if(nparts == 0)
		return nil;

	widths := array[nparts] of { * => 0 };
	totalfr := 0;
	fixedtotal := 0;
	totalgap := gap * (nparts - 1);

	# First pass: resolve fixed sizes and count fr units
	for(i = 0; i < nparts; i++) {
		t := tracks[i];
		if(len t > 2 && t[len t - 2:] == "fr") {
			# fr unit: parse the number before "fr"
			frval := parsefloatstr(t[:len t - 2]);
			if(frval <= 0)
				frval = 1;
			# Store fr*100 temporarily as negative to distinguish
			widths[i] = -(frval);
			totalfr += frval;
		} else if(t == "auto") {
			# Auto: use item's natural width if available
			w := 0;
			if(items != nil) {
				# Find the item in this column
				it := items;
				for(k := 0; k < i && it != nil; k++)
					it = it.next;
				if(it != nil)
					w = it.width;
			}
			if(w == 0)
				w = 50;	# minimum auto width
			widths[i] = w;
			fixedtotal += w;
		} else if(len t > 1 && t[len t - 1] == '%') {
			pct := parsefloatstr(t[:len t - 1]);
			widths[i] = (available * pct) / 100;
			fixedtotal += widths[i];
		} else {
			# Fixed size (px, em, etc.)
			widths[i] = parsepxval(t);
			fixedtotal += widths[i];
		}
	}

	# Second pass: distribute remaining space among fr tracks
	if(totalfr > 0) {
		remaining := available - fixedtotal - totalgap;
		if(remaining < 0)
			remaining = 0;
		for(i = 0; i < nparts; i++) {
			if(widths[i] < 0) {
				frval := -widths[i];
				widths[i] = (remaining * frval) / totalfr;
			}
		}
	}

	return widths;
}

# Parse a float-like string and return integer value (for fr units and percentages)
parsefloatstr(s: string) : int
{
	if(s == nil || s == "")
		return 0;
	neg := 0;
	i := 0;
	if(i < len s && s[i] == '-') {
		neg = 1;
		i++;
	}
	n := 0;
	for(; i < len s && s[i] >= '0' && s[i] <= '9'; i++)
		n = n * 10 + s[i] - '0';
	# Handle decimal part
	if(i < len s && s[i] == '.') {
		i++;
		# Just get first digit after decimal for rounding
		if(i < len s && s[i] >= '0' && s[i] <= '9') {
			if(s[i] >= '5')
				n++;
		}
	}
	if(n == 0 && neg == 0)
		n = 1;	# minimum 1 for fr values
	if(neg)
		return -n;
	return n;
}

# Parse a pixel value from a track size string
parsepxval(s: string) : int
{
	if(s == nil || s == "")
		return 0;
	neg := 0;
	i := 0;
	if(i < len s && s[i] == '-') {
		neg = 1;
		i++;
	}
	n := 0;
	for(; i < len s && s[i] >= '0' && s[i] <= '9'; i++)
		n = n * 10 + s[i] - '0';
	# Handle decimal
	if(i < len s && s[i] == '.') {
		i++;
		if(i < len s && s[i] >= '0' && s[i] <= '9') {
			if(s[i] >= '5')
				n++;
		}
	}
	# em/rem: approximate at 16px/em
	if(i < len s - 1 && (s[i] == 'e' || s[i] == 'r'))
		n = n * 16;
	if(neg)
		return -n;
	return n;
}

# Expand repeat() in grid track specifications.
# repeat(3, 1fr) => "1fr 1fr 1fr"
# repeat(2, 100px 1fr) => "100px 1fr 100px 1fr"
expandrepeat(spec: string) : string
{
	# Quick check: no repeat() means nothing to do
	hasrepeat := 0;
	for(k := 0; k + 6 < len spec; k++) {
		if(spec[k:k+7] == "repeat(") {
			hasrepeat = 1;
			break;
		}
	}
	if(hasrepeat == 0)
		return spec;

	result := "";
	i := 0;
	for(; i < len spec; ) {
		# Check for "repeat("
		if(i + 7 <= len spec && spec[i:i+7] == "repeat(") {
			i += 7;
			# Parse count
			count := 0;
			for(; i < len spec && spec[i] >= '0' && spec[i] <= '9'; i++)
				count = count * 10 + spec[i] - '0';
			if(count <= 0)
				count = 1;
			if(count > 20)
				count = 20;	# sanity limit
			# Skip comma and whitespace
			for(; i < len spec && (spec[i] == ',' || spec[i] == ' ' || spec[i] == '\t'); i++)
				;
			# Read until closing paren
			start := i;
			depth := 0;
			for(; i < len spec; i++) {
				if(spec[i] == '(')
					depth++;
				else if(spec[i] == ')') {
					if(depth == 0)
						break;
					depth--;
				}
			}
			pattern := spec[start:i];
			if(i < len spec)
				i++;	# skip ')'
			# Expand
			for(c := 0; c < count; c++) {
				if(len result > 0)
					result += " ";
				result += pattern;
			}
		} else {
			result += spec[i:i+1];
			i++;
		}
	}
	return result;
}
