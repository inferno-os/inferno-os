implement Build;

include "common.m";

# local copies from CU
sys: Sys;
CU: CharonUtils;
	ByteSource, CImage, ImageCache, color, Nameval: import CU;

D: Draw;
	Point, Rect, Image: import D;
S: String;
T: StringIntTab;
C: Ctype;
LX: Lex;
	RBRA, Token, TokenSource: import LX;
U: Url;
	Parsedurl: import U;
J: Script;

ctype: array of byte;

whitespace :  con " \t\n\r";
notwhitespace :  con "^ \t\n\r";

# These tables must be sorted
align_tab := array[] of { T->StringInt
	("baseline",	int Abaseline),
	("bottom",	int Abottom),
	("center",	int Acenter),
	("char",	int Achar),
	("justify",	int Ajustify),
	("left",	int Aleft),
	("middle",	int Amiddle),
	("right",	int Aright),
	("top",	int Atop),
};

input_tab := array[] of { T->StringInt
	("button",		Fbutton),
	("checkbox",	Fcheckbox),
	("file",		Ffile),
	("hidden",		Fhidden),
	("image",		Fimage),
	("password",	Fpassword),
	("radio",		Fradio),
	("reset",		Freset),
	("submit",		Fsubmit),
	("text",		Ftext),
};

clear_tab := array[] of { T->StringInt
	("all",	IFcleft|IFcright),
	("left",	IFcleft),
	("right",	IFcright),
};

fscroll_tab := array[] of { T->StringInt
	("auto",	FRhscrollauto|FRvscrollauto),
	("no",	FRnoscroll),
	("yes",	FRhscroll|FRvscroll),
};

# blockbrk[tag] is break info for a block level element, or one
# of a few others that get the same treatment re ending open paragraphs
# and requiring a line break / vertical space before them.
# If we want a line of space before the given element, SPBefore is OR'd in.
# If we want a line of space after the given element, SPAfter is OR'd in.
SPBefore: con byte 2;
SPAfter: con byte 4;
BL: con byte 1;
BLBA: con BL|SPBefore|SPAfter;
blockbrk := array[LX->Numtags] of {
	LX->Taddress => BLBA, LX->Tblockquote => BLBA, LX->Tcenter => BL,
	LX->Tdir => BLBA, LX->Tdiv => BL, LX->Tdd => BL, LX->Tdl => BLBA,
	LX->Tdt => BL, LX->Tform => BLBA,
	# headings and tables get breaks added manually
	LX->Th1 => BL, LX->Th2 => BL, LX->Th3 => BL,
	LX->Th4 => BL, LX->Th5 => BL, LX->Th6 => BL,
	LX->Thr => BL, LX->Tisindex => BLBA, LX->Tli => BL, LX->Tmenu => BLBA,
	LX->Tol => BLBA, LX->Tp => BLBA, LX->Tpre => BLBA,
	LX->Tul => BLBA, LX->Txmp => BLBA,
	* => byte 0
};

# attrinfo is information about attributes.
# The AGEN value means that the attribute is generic (applies to almost all elements)
AGEN: con byte 1;
attrinfo := array[LX->Numattrs] of {
	LX->Aid => AGEN, LX->Aclass => AGEN, LX->Astyle => AGEN, LX->Atitle => AGEN,
	LX->Aonabort => AGEN, LX->Aonblur => AGEN, LX->Aonchange => AGEN,
	LX->Aonclick => AGEN, LX->Aondblclick => AGEN, LX->Aonerror => AGEN,
	LX->Aonfocus => AGEN, LX->Aonkeydown => AGEN, LX->Aonkeypress => AGEN, LX->Aonkeyup => AGEN,
	LX->Aonload => AGEN, LX->Aonmousedown => AGEN, LX->Aonmousemove => AGEN,
	LX->Aonmouseout => AGEN, LX->Aonmouseover => AGEN,
	LX->Aonmouseup => AGEN, LX->Aonreset => AGEN, LX->Aonresize => AGEN, LX->Aonselect => AGEN,
	LX->Aonsubmit => AGEN, LX->Aonunload => AGEN,
	* => byte 0
};

# Some constants
FRKIDMARGIN: con 6;	# default margin around kid frames
IMGHSPACE: con 0;		# default hspace for images (0 matches IE, Netscape)
IMGVSPACE: con 0;		# default vspace for images
FLTIMGHSPACE: con 2;	# default hspace for float images
TABSP: con 2;			# default cellspacing for tables
TABPAD: con 2;		# default cell padding for tables
LISTTAB: con 1;		# number of tabs to indent lists
BQTAB: con 1;			# number of tabs to indent blockquotes
HRSZ: con 2;			# thickness of horizontal rules
SUBOFF: con 4;			# vertical offset for subscripts
SUPOFF: con 6;			# vertical offset for superscripts
NBSP: con ' ';			# non-breaking space character

dbg := 0;
warn := 0;
doscripts := 0;

utf8 : Btos;
latin1 : Btos;

init(cu: CharonUtils)
{
	CU = cu;
	sys = load Sys Sys->PATH;
	D = load Draw Draw->PATH; 
	S = load String String->PATH;;
	T = load StringIntTab StringIntTab->PATH;
	U = load Url Url->PATH;
	if (U != nil)
		U->init();
	C = cu->C;
	J = cu->J;
	LX = cu->LX;
	ctype = C->ctype;
	utf8 = CU->getconv("utf8");
	latin1 = CU->getconv("latin1");
	if (utf8 == nil || latin1 == nil) {
		sys->print("cannot load utf8 or latin1 charset converter\n");
		raise "EXinternal:build init";
	}
	dbg = int (CU->config).dbg['h'];
	warn = (int (CU->config).dbg['w']) || dbg;
	doscripts = (CU->config).doscripts && J != nil;
}

# Assume f has been reset, and then had any values from HTTP headers
# filled in (e.g., base, chset).
ItemSource.new(bs: ref ByteSource, f: ref Layout->Frame, mtype: int) : ref ItemSource
{
	di := f.doc;
# sys->print("chset = %s\n", di.chset);
	chset := CU->getconv(di.chset);
	if (chset == nil)
		chset = latin1;
	ts := TokenSource.new(bs, chset, mtype);
	psstk := list of { Pstate.new() };
	if(mtype != CU->TextHtml) {
		ps := hd psstk;
		ps.curstate &= ~IFwrap;
		ps.literal = 1;
		pushfontstyle(ps, FntT);
	}
	return ref ItemSource(ts, mtype, di, f, psstk, 0, 0, 0, 0, nil, nil, nil, nil, nil, nil, nil);
}

ItemSource.getitems(is: self ref ItemSource) : ref Item
{
	psstk := is.psstk;
	ps := hd psstk;		# ps is always same as hd psstk
	curtab: ref Table = nil;	# curtab is always same as hd is.tabstk
	if(is.tabstk != nil)
		curtab = hd is.tabstk;
	toks := is.toks;
	is.toks = nil;
	tokslen := len toks;
	toki := 0;
	di := is.doc;
TokLoop:
	for(;; toki++) {
		if(toki >= tokslen) {
			outerps := lastps(psstk);
			if(outerps.items.next != nil)
				break;
			toks = is.ts.gettoks();
			tokslen = len toks;
			if(dbg)
				sys->print("build: got %d tokens from token source\n", tokslen);
			if(tokslen == 0)
				break;
			toki = 0;
		}
		tok := toks[toki];
		if(dbg > 1)
			sys->print("build: curstate %ux, token %s\n", ps.curstate, tok.tostring());
		tag := tok.tag;
		brk := byte 0;
		brksp := 0;
		if(tag < LX->Numtags) {
			brk = blockbrk[tag];
			if((brk&SPBefore) != byte 0)
				brksp = 1;
		}
		else if(tag < LX->Numtags+RBRA) {
			brk = blockbrk[tag-RBRA];
			if((brk&SPAfter) != byte 0)
				brksp = 1;
		}
		if(brk != byte 0) {
			addbrk(ps, brksp, 0);
			if(ps.inpar) {
				popjust(ps);
				ps.inpar = 0;
			}
		}
		# check common case first (Data), then case statement on tag
		if(tag == LX->Data) {
			# Lexing didn't pay attention to SGML record boundary rules:
			# \n after start tag or before end tag to be discarded.
			# (Lex has already discarded all \r's).
			# Some pages assume this doesn't happen in <PRE> text,
			# so we won't do it if literal is true.
			# BUG: won't discard \n before a start tag that begins
			# the next bufferful of tokens.
			s := tok.text;
			if(!ps.literal) {
				i := 0;
				j := len s;
				if(toki > 0) {
					pt := toks[toki-1].tag;
					# IE and Netscape both ignore this rule (contrary to spec)
					# if previous tag was img
					if(pt < LX->Numtags && pt != LX->Timg && j>0 && s[0]=='\n')
						i++;
				}
				if(toki < tokslen-1) {
					nt := toks[toki+1].tag;
					if(nt >= RBRA && nt < LX->Numtags+RBRA && j>i && s[j-1]=='\n')
						j--;
				}
				if(i>0 || j <len s)
					s = s[i:j];
			}
			if(ps.skipwhite) {
				s = S->drop(s, whitespace);
				if(s != "")
					ps.skipwhite = 0;
			}
			if(s != "")
				addtext(ps, s);
		}
		else case tag {
		# Some abbrevs used in following DTD comments
		# %text = #PCDATA
		#		| TT | I | B | U | STRIKE | BIG | SMALL | SUB | SUP
		#		| EM | STRONG | DFN | CODE | SAMP | KBD | VAR | CITE
		#		| A | IMG | APPLET | FONT | BASEFONT | BR | SCRIPT | MAP
		#		| INPUT | SELECT | TEXTAREA
		# %block = P | UL | OL | DIR | MENU | DL | PRE | DL | DIV | CENTER
		#		| BLOCKQUOTE | FORM | ISINDEX | HR | TABLE
		# %flow = (%text | %block)*
		# %body.content = (%heading | %text | %block | ADDRESS)*

		# <!ELEMENT A - - (%text) -(A)>
		# Anchors are not supposed to be nested, but you sometimes see
		# href anchors inside destination anchors.
		LX->Ta =>
			if(ps.curanchor != 0) {
				if(warn)
					sys->print("warning: nested <A> or missing </A>\n");
				endanchor(ps, di.text);
			}
			name := aval(tok, LX->Aname);
			href := aurlval(tok, LX->Ahref, nil, di.base);
			target := astrval(tok, LX->Atarget, di.target);
			ga := getgenattr(tok);
			evl : list of Lex->Attr = nil;
			if(ga != nil) {
				evl = ga.events;
				if(evl != nil && doscripts)
					di.hasscripts = 1;
			}
			# ignore rel, rev, and title attrs
			if(href != nil) {
				di.anchors = ref Anchor(++is.nanchors, name, href, target, evl, 0) :: di.anchors;
				ps.curanchor = is.nanchors;
				ps.curfg = di.link;
				ps.fgstk = ps.curfg :: ps.fgstk;
				# underline, too
				ps.ulstk = ULunder :: ps.ulstk;
				ps.curul = ULunder;
			}
			if(name != nil) {
				# add a null item to be destination
				brkstate := ps.curstate & IFbrk;
				additem(ps, Item.newspacer(ISPnull, 0), tok);
				ps.curstate |= brkstate;	# not quite right
				di.dests = ref DestAnchor(++is.nanchors, name, ps.lastit) :: di.dests;
			}

		LX->Ta+RBRA =>
			endanchor(ps, di.text);

		# <!ELEMENT APPLET - - (PARAM | %text)* >
		# We can't do applets, so ignore PARAMS, and let
		# the %text contents appear for the alternative rep
		LX->Tapplet or LX->Tapplet+RBRA =>
			if(warn && tag == LX->Tapplet)
				sys->print("warning: <APPLET> ignored\n");

		# <!ELEMENT AREA - O EMPTY>
		LX->Tarea =>
			map := is.curmap;
			if(map == nil) {
				if(warn)
					sys->print("warning: <AREA> not inside <MAP>\n");
				continue;
			}
			map.areas = Area(S->tolower(astrval(tok, LX->Ashape, "rect")),
						aurlval(tok, LX->Ahref, nil, di.base),
						astrval(tok, LX->Atarget, di.target),
						dimlist(tok, LX->Acoords)) :: map.areas;

		# <!ELEMENT (B|STRONG) - - (%text)*>
		LX->Tb or LX->Tstrong =>
			pushfontstyle(ps, FntB);

		LX->Tb+RBRA or LX->Tcite+RBRA
		  or LX->Tcode+RBRA or LX->Tdfn+RBRA
		  or LX->Tem+RBRA or LX->Tkbd+RBRA
		  or LX->Ti+RBRA or LX->Tsamp+RBRA
		  or LX->Tstrong+RBRA or LX->Ttt+RBRA
		  or LX->Tvar+RBRA or LX->Taddress+RBRA =>
			popfontstyle(ps);

		# <!ELEMENT BASE - O EMPTY>
		LX->Tbase =>
			di.base = aurlval(tok, LX->Ahref, di.base, di.base);
			di.target = astrval(tok, LX->Atarget, di.target);

		# <!ELEMENT BASEFONT - O EMPTY>
		LX->Tbasefont =>
			ps.adjsize = aintval(tok, LX->Asize, 3) - 3;

		# <!ELEMENT (BIG|SMALL) - - (%text)*>
		LX->Tbig or LX->Tsmall =>
			sz := ps.adjsize;
			if(tag == LX->Tbig)
				sz += Large;
			else
				sz += Small;
			pushfontsize(ps, sz);

		LX->Tbig+RBRA or  LX->Tsmall+RBRA =>
			popfontsize(ps);

		# <!ELEMENT BLOCKQUOTE - - %body.content>
		LX->Tblockquote =>
			changeindent(ps, BQTAB);

		LX->Tblockquote+RBRA =>
			changeindent(ps, -BQTAB);

		# <!ELEMENT BODY O O %body.content>
		LX->Tbody =>
			ps.skipping = 0;
			bg := Background(nil, color(aval(tok, LX->Abgcolor), di.background.color));
			bgurl := aurlval(tok, LX->Abackground, nil, di.base);
			if(bgurl != nil) {
				pick ni := Item.newimage(di, bgurl, nil,"", Anone, 0, 0, 0, 0, 0, 0, 1, nil, nil, nil){
				Iimage =>
					bg.image = ni;
				}
				di.images = bg.image :: di.images;
			}
			di.background = ps.curbg = bg;
			ps.curbg.image = nil;
			di.text = color(aval(tok, LX->Atext), di.text);
			di.link = color(aval(tok, LX->Alink), di.link);
			di.vlink = color(aval(tok, LX->Avlink), di.vlink);
			di.alink = color(aval(tok, LX->Aalink), di.alink);
			if(doscripts) {
				ga := getgenattr(tok);
				if(ga != nil && ga.events != nil) {
					di.events = ga.events;
					di.hasscripts = 1;
				}
			}
			if(di.text != ps.curfg) {
				ps.curfg = di.text;
				ps.fgstk = nil;
			}

		LX->Tbody+RBRA =>
			# HTML spec says ignore things after </body>,
			# but IE and Netscape don't
			# ps.skipping = 1;
			;

		# <!ELEMENT BR - O EMPTY>
		LX->Tbr =>
			addlinebrk(ps, atabval(tok, LX->Aclear, clear_tab, 0));

		# <!ELEMENT CAPTION - - (%text;)*>
		LX->Tcaption =>
			if(curtab == nil) {
				if(warn)
					sys->print("warning: <CAPTION> outside <TABLE>\n");
				continue;
			}
			if(curtab.caption != nil) {
				if(warn)
					sys->print("warning: more than one <CAPTION> in <TABLE>\n");
				continue;
			}
			ps = Pstate.new();
			psstk = ps :: psstk;
			curtab.caption_place =atabbval(tok, LX->Aalign, align_tab, Atop);

		LX->Tcaption+RBRA =>
			if(curtab == nil || tl psstk == nil) {
				if(warn)
					sys->print("warning: unexpected </CAPTION>\n");
				continue;
			}
			curtab.caption = ps.items.next;
			psstk = tl psstk;
			ps = hd psstk;

		LX->Tcenter or LX->Tdiv =>
			if(tag == LX->Tcenter)
				al := Acenter;
			else
				al = atabbval(tok, LX->Aalign, align_tab, ps.curjust);
			pushjust(ps, al);

		LX->Tcenter+RBRA or LX->Tdiv+RBRA =>
			popjust(ps);

		# <!ELEMENT DD - O  %flow >
		LX->Tdd =>
			if(ps.hangstk == nil) {
				if(warn)
					sys->print("warning: <DD> not inside <DL\n");
				continue;
			}
			h := hd ps.hangstk;
			if(h != 0)
				changehang(ps, -10*LISTTAB);
			else
				addbrk(ps, 0, 0);
			ps.hangstk = 0 :: ps.hangstk;

		#<!ELEMENT (DIR|MENU) - - (LI)+ -(%block) >
		#<!ELEMENT (OL|UL) - - (LI)+>
		LX->Tdir or LX->Tmenu or LX->Tol or LX->Tul =>
			changeindent(ps, LISTTAB);
			if(tag == LX->Tol)
				tydef := LT1;
			else
				tydef = LTdisc;
			start := aintval(tok, LX->Astart, 1);
			ps.listtypestk = listtyval(tok, tydef) :: ps.listtypestk;
			ps.listcntstk = start :: ps.listcntstk;

		LX->Tdir+RBRA or LX->Tmenu+RBRA
		or LX->Tol+RBRA or LX->Tul+RBRA =>
			if(ps.listtypestk == nil) {
				if(warn)
					sys->print("warning: %s ended no list\n", tok.tostring());
				continue;
			}
			addbrk(ps, 0, 0);
			ps.listtypestk = tl ps.listtypestk;
			ps.listcntstk = tl ps.listcntstk;
			changeindent(ps, -LISTTAB);

		# <!ELEMENT DL - - (DT|DD)+ >
		LX->Tdl =>
			changeindent(ps, LISTTAB);
			ps.hangstk = 0 :: ps.hangstk;

		LX->Tdl+RBRA =>
			if(ps.hangstk == nil) {
				if(warn)
					sys->print("warning: unexpected </DL>\n");
				continue;
			}
			changeindent(ps, -LISTTAB);
			if(hd ps.hangstk != 0)
				changehang(ps, -10*LISTTAB);
			ps.hangstk = tl ps.hangstk;

		# <!ELEMENT DT - O (%text)* >
		LX->Tdt =>
			if(ps.hangstk == nil) {
				if(warn)
					sys->print("warning: <DT> not inside <DL>\n");
				continue;
			}
			h := hd ps.hangstk;
			ps.hangstk = tl ps.hangstk;
			if(h != 0)
				changehang(ps, -10*LISTTAB);
			changehang(ps, 10*LISTTAB);
			ps.hangstk = 1 :: ps.hangstk;

		# <!ELEMENT FONT - - (%text)*>
		LX->Tfont =>
			sz := stackhd(ps.fntsizestk, Normal);
			(szfnd, nsz) := tok.aval(LX->Asize);
			if(szfnd) {
				if(S->prefix("+", nsz))
					sz = Normal + int (nsz[1:]) + ps.adjsize;
				else if(S->prefix("-", nsz))
					sz = Normal - int (nsz[1:]) + ps.adjsize;
				else if(nsz != "")
					sz = Normal + ( int nsz - 3);
			}
			ps.curfg = color(aval(tok, LX->Acolor), ps.curfg);
			ps.fgstk = ps.curfg :: ps.fgstk;
			pushfontsize(ps, sz);

		LX->Tfont+RBRA =>
			if(ps.fgstk == nil) {
				if(warn)
					sys->print("warning: unexpected </FONT>\n");
				continue;
			}
			ps.fgstk = tl ps.fgstk;
			if(ps.fgstk == nil)
				ps.curfg = di.text;
			else
				ps.curfg = hd ps.fgstk;
			popfontsize(ps);

		# <!ELEMENT FORM - - %body.content -(FORM) >
		LX->Tform =>
			if(is.curform != nil) {
				if(warn)
					sys->print("warning: <FORM> nested inside another\n");
				continue;
			}
			action := aurlval(tok, LX->Aaction, di.base, di.base);
			name := astrval(tok, LX->Aname, aval(tok, LX->Aid));
			target := astrval(tok, LX->Atarget, di.target);
			smethod := S->tolower(astrval(tok, LX->Amethod, "get"));
			method := CU->HGet;
			if(smethod == "post")
				method = CU->HPost;
			else if(smethod != "get") {
				if(warn)
					sys->print("warning: unknown form method %s\n", smethod);
			}
			(ecfnd, enctype) := tok.aval(LX->Aenctype);
			if(warn && ecfnd && enctype != "application/x-www-form-urlencoded")
				sys->print("form enctype %s not handled\n", enctype);
			ga := getgenattr(tok);
			evl : list of Lex->Attr = nil;
			if(ga != nil) {
				evl = ga.events;
				if(evl != nil && doscripts)
					di.hasscripts = 1;
			}
			frm := Form.new(++is.nforms, name, action, target, method, evl);
			di.forms = frm :: di.forms;
			is.curform = frm;

		LX->Tform+RBRA =>
			if(is.curform == nil) {
				if(warn)
					sys->print("warning: unexpected </FORM>\n");
				continue;
			}
			# put fields back in input order
			fields : list of ref Formfield = nil;
			for(fl := is.curform.fields; fl != nil; fl = tl fl)
				fields = hd fl :: fields;
			is.curform.fields = fields;
			is.curform.state = FormDone;
			is.curform = nil;

		# HTML 4
		# <!ELEMENT FRAME - O EMPTY>
		LX->Tframe =>
			if(is.kidstk == nil) {
				if(warn)
					sys->print("warning: <FRAME> not in <FRAMESET>\n");
				continue;
			}
			ks := hd is.kidstk;
			kd := Kidinfo.new(0);
			kd.src = aurlval(tok, LX->Asrc, nil, di.base);
			kd.name = aval(tok, LX->Aname);
			if(kd.name == "")
				kd.name = "_fr" + string (++is.nframes);
			kd.marginw = aintval(tok, LX->Amarginwidth, 0);
			kd.marginh = aintval(tok, LX->Amarginheight, 0);
			kd.framebd = aintval(tok, LX->Aframeborder, ks.framebd);
			kd.flags = atabval(tok, LX->Ascrolling, fscroll_tab, kd.flags);
			norsz := aboolval(tok, LX->Anoresize);
			if(norsz)
				kd.flags |= FRnoresize;
			ks.kidinfos = kd :: ks.kidinfos;

		# HTML 4
		# <!ELEMENT FRAMESET - - (FRAME|FRAMESET)+>
		LX->Tframeset =>
			ks := Kidinfo.new(1);
			if(is.kidstk == nil)
				di.kidinfo = ks;
			else {
				pks := hd is.kidstk;
				pks.kidinfos = ks :: pks.kidinfos;
			}
			is.kidstk = ks :: is.kidstk;
			ks.framebd = aintval(tok, LX->Aborder, 1);
			ks.rows = dimlist(tok, LX->Arows);
			if(ks.rows == nil)
				ks.rows = array[] of {Dimen.make(Dpercent,100)};
			ks.cols = dimlist(tok, LX->Acols);
			if(ks.cols == nil)
				ks.cols = array[] of {Dimen.make(Dpercent,100)};
			if(doscripts) {
				ga := getgenattr(tok);
				if(ga != nil && ga.events != nil) {
					di.events = ga.events;
					di.hasscripts = 1;
				}
			}

		LX->Tframeset+RBRA =>
			if(is.kidstk == nil) {
				if(warn)
					sys->print("warning: unexpected </FRAMESET>\n");
				continue;
			}
			ks := hd is.kidstk;
			# put kids back in original order
			# and add blank frames to fill out cells
			n := (len ks.rows) * (len ks.cols);
			nblank := n - len ks.kidinfos;
			while(nblank-- > 0)
				ks.kidinfos = Kidinfo.new(0) :: ks.kidinfos;
			kids : list of ref Kidinfo = nil;
			for(kl := ks.kidinfos; kl != nil; kl = tl kl)
				kids = hd kl :: kids;
			ks.kidinfos= kids;
			is.kidstk = tl is.kidstk;
			if(is.kidstk == nil) {
				for(;;) {
					toks = is.ts.gettoks();
					if(len toks == 0)
						break;
				}
				tokslen = 0;
			}

		# <!ELEMENT H1 - - (%text;)*>, etc.
		LX->Th1 or  LX->Th2 or LX->Th3
		or LX->Th4 or LX->Th5 or LX->Th6 =>
			# don't want extra space if this is first addition
			# to this item list (BUG: problem if first of bufferful)
			bramt := 1;
			if(ps.items == ps.lastit)
				bramt = 0;
			addbrk(ps, bramt, IFcleft|IFcright);
			# assume Th2 = Th1+1, etc.
			sz := Verylarge - (tag - LX->Th1);
			if(sz < Tiny)
				sz = Tiny;
			pushfontsize(ps, sz);
			sty := stackhd(ps.fntstylestk, FntR);
			if(tag == LX->Th1)
				sty = FntB;
			pushfontstyle(ps, sty);
			pushjust(ps, atabbval(tok, LX->Aalign, align_tab, ps.curjust));
			ps.skipwhite = 1;

		LX->Th1+RBRA or LX->Th2+RBRA
		    or LX->Th3+RBRA or LX->Th4+RBRA
		    or LX->Th5+RBRA or LX->Th6+RBRA =>
			addbrk(ps, 1, IFcleft|IFcright);
			popfontsize(ps);
			popfontstyle(ps);
			popjust(ps);

		LX->Thead =>
			# HTML spec says ignore regular markup in head,
			# but Netscape and IE don't
			# ps.skipping = 1;
			;

		LX->Thead+RBRA =>
			ps.skipping = 0;

		# <!ELEMENT HR - O EMPTY>
		LX->Thr =>
			al := atabbval(tok, LX->Aalign, align_tab, Acenter);
			sz := aintval(tok, LX->Asize, HRSZ);
			wd := makedimen(tok, LX->Awidth);
			if(wd.kind() == Dnone)
				wd = Dimen.make(Dpercent, 100);
			nosh := aboolval(tok, LX->Anoshade);
			additem(ps, Item.newrule(al, sz, nosh, wd), tok);
			addbrk(ps, 0, 0);

		# <!ELEMENT (I|CITE|DFN|EM|VAR) - - (%text)*>
		LX->Ti  or LX->Tcite or LX->Tdfn
		or LX->Tem or LX->Tvar or LX->Taddress =>
			pushfontstyle(ps, FntI);

		# <!ELEMENT IMG - O EMPTY>
		LX->Timage or		# common html error supported by other browsers
		LX->Timg =>
			tok.tag = LX->Timg;
			map : ref Map = nil;
			usemap := aval(tok, LX->Ausemap);
			oldcuranchor := ps.curanchor;
			if(usemap != "") {
				# can't handle non-local maps
				if(!S->prefix("#", usemap)) {
					if(warn)
						sys->print("warning: can't handle non-local map %s\n", usemap);
				}
				else {
					map = getmap(di, usemap[1:]);
					if(ps.curanchor == 0) {
						# make an anchor so charon's easy test for whether
						# there's an action for the item works
						di.anchors = ref Anchor(++is.nanchors, "", nil, di.target, nil, 0) :: di.anchors;
						ps.curanchor = is.nanchors;
					}
				}
			}
			align := atabbval(tok, LX->Aalign, align_tab, Abottom);
			dfltbd := 0;
			if(ps.curanchor != 0)
				dfltbd = 2;
			src := aurlval(tok, LX->Asrc, nil, di.base);
			if(src == nil) {
				if(warn)
					sys->print("warning: <img> has no src attribute\n");
				ps.curanchor = oldcuranchor;
				continue;
			}
			img := Item.newimage(di, src,
				aurlval(tok, LX->Alowsrc, nil, di.base),
				aval(tok, LX->Aalt),
				align,
				aintval(tok, LX->Awidth, 0),
				aintval(tok, LX->Aheight, 0),
				aintval(tok, LX->Ahspace, IMGHSPACE),
				aintval(tok, LX->Avspace, IMGVSPACE),
				aintval(tok, LX->Aborder, dfltbd),
				aboolval(tok, LX->Aismap),
				0, # not a background image
				map,
				aval(tok, LX->Aname),
				getgenattr(tok));
			if(align == Aleft || align == Aright) {
				additem(ps, Item.newfloat(img, align), tok);
				# if no hspace specified, use FLTIMGHSPACE
				(fnd,nil) := tok.aval(LX->Ahspace);
				if(!fnd) {
					pick ii := img {
					Iimage =>
						ii.hspace = byte FLTIMGHSPACE;
					}
				}
			} else {
				ps.skipwhite = 0;
				additem(ps, img, tok);
			}
			if(!ps.skipping)
				di.images = img :: di.images;
			ps.curanchor = oldcuranchor;

		# <!ELEMENT INPUT - O EMPTY>
		LX->Tinput =>
			if (ps.skipping)
				continue;
			ps.skipwhite = 0;
			if(is.curform ==nil) {
				if(warn)
					sys->print("<INPUT> not inside <FORM>\n");
					continue;
			}
			field := Formfield.new(atabval(tok, LX->Atype, input_tab, Ftext),
					++is.curform.nfields,	# fieldid
					is.curform,	# form
					aval(tok, LX->Aname),
					aval(tok, LX->Avalue),
					aintval(tok, LX->Asize, 0),
					aintval(tok, LX->Amaxlength, 1000));
			if(aboolval(tok, LX->Achecked))
				field.flags = FFchecked;

			case field.ftype {
				Ftext or Fpassword or Ffile =>
					if(field.size == 0)
						field.size = 20;
				Fcheckbox =>
					if(field.name == "") {
						if(warn)
							sys->print("warning: checkbox form field missing name\n");
#						continue;
					}
					if(field.value == "")
						field.value = "1";
				Fradio =>
					if(field.name == "" || field.value == "") {
						if(warn)
							sys->print("warning: radio form field missing name or value\n");
#						continue;
					}
				Fsubmit =>
					if(field.value == "")
						field.value = "Submit";
					if(field.name == "")
						field.name = "_no_name_submit_";
				Fimage =>
					src := aurlval(tok, LX->Asrc, nil, di.base);
					if(src == nil) {
						if(warn)
							sys->print("warning: image form field missing src\n");
#						continue;
					} else {
						# width and height attrs aren't specified in HTML 3.2,
						# but some people provide them and they help avoid
						# a relayout
						field.image = Item.newimage(di, src,
							aurlval(tok, LX->Alowsrc, nil, di.base),
							astrval(tok, LX->Aalt, "Submit"),
							atabbval(tok, LX->Aalign, align_tab, Abottom),
							aintval(tok, LX->Awidth, 0),
							aintval(tok, LX->Aheight, 0),
							0, 0, 0, 0, 0, nil, field.name, nil);
						di.images = field.image :: di.images;
					}
				Freset =>
					if(field.value == "")
						field.value = "Reset";
				Fbutton =>
					if(field.value == "")
						field.value = " ";
			}
			is.curform.fields = field :: is.curform.fields;
			ffit := Item.newformfield(field);
			additem(ps, ffit, tok);
			if(ffit.genattr != nil) {
				field.events = ffit.genattr.events;
				if(field.events != nil && doscripts)
					di.hasscripts = 1;
			}

		# <!ENTITY ISINDEX - O EMPTY>
		LX->Tisindex =>
			ps.skipwhite = 0;
			prompt := astrval(tok, LX->Aprompt, "Index search terms:");
			target := astrval(tok, LX->Atarget, di.target);
			additem(ps, textit(ps, prompt), tok);
			frm := Form.new(++is.nforms, "", di.base, target, CU->HGet, nil);
			ff := Formfield.new(Ftext, 1, frm, "_ISINDEX_", "", 50, 1000);
			frm.fields =  ff :: nil;
			frm.nfields = 1;
			di.forms = frm :: di.forms;
			additem(ps, Item.newformfield(ff), tok);
			addbrk(ps, 1, 0);

		# <!ELEMENT LI - O %flow>
		LX->Tli =>
			if(ps.listtypestk == nil) {
				if(warn)
					sys->print("<LI> not in list\n");
				continue;
			}
			ty := hd ps.listtypestk;
			ty2 := listtyval(tok, ty);
			if(ty != ty2) {
				ty = ty2;
				ps.listtypestk = ty2 :: tl ps.listtypestk;
			}
			v := aintval(tok, LX->Avalue, hd ps.listcntstk);
			if(ty == LTdisc || ty == LTsquare || ty == LTcircle)
				hang := 10*LISTTAB - 3;
			else
				hang = 10*LISTTAB - 1;
			changehang(ps, hang);
			addtext(ps, listmark(ty, v));
			ps.listcntstk = (v+1) :: (tl ps.listcntstk);
			changehang(ps, -hang);
			ps.skipwhite = 1;

		# <!ELEMENT MAP - - (AREA)+>
		LX->Tmap =>
			is.curmap = getmap(di, aval(tok, LX->Aname));

		LX->Tmap+RBRA =>
			map := is.curmap;
			if(map == nil) {
				if(warn)
					sys->print("warning: unexpected </MAP>\n");
				continue;
			}
			# put areas back in input order
			areas : list of Area = nil;
			for(al := map.areas; al != nil; al = tl al)
				areas = hd al :: areas;
			map.areas = areas;
			is.curmap = nil;

		LX->Tmeta =>
			if(ps.skipping)
				continue;
			(fnd, equiv) := tok.aval(LX->Ahttp_equiv);
			if(fnd) {
				v := aval(tok, LX->Acontent);
				case S->tolower(equiv) {
				"set-cookie" =>
					if((CU->config).docookies > 0) {
						url := di.src;
						CU->setcookie(v, url.host, url.path);
					}
				"refresh" =>
					di.refresh = v;
				"content-script-type" =>
					if(v == "javascript" || v == "javascript1.1" || v == "jscript")
						di.scripttype = CU->TextJavascript;
					# TODO: other kinds
					else {
						if(warn)
							sys->print("unimplemented script type %s\n", v);
						di.scripttype = CU->UnknownType;
					}
				"content-type" =>
					(nil, parms) := S->splitl(v, ";");
					if (parms != nil) {
						nvs := Nameval.namevals(parms[1:], ';');
						(got, s) := Nameval.find(nvs, "charset");
						if (got) {
# sys->print("HTTP-EQUIV charset: %s\n", s);
							btos := CU->getconv(s);
							if (btos != nil)
								is.ts.setchset(btos);
							else if (warn)
								sys->print("cannot set charset %s\n", s);
						}
					}
				}
			}

		# Nobr is NOT in HMTL 4.0, but it is ubiquitous on the web
		LX->Tnobr =>
			ps.skipwhite = 0;
			ps.curstate &= ~IFwrap;

		LX->Tnobr+RBRA =>
			ps.curstate |= IFwrap;

		# We do frames, so skip stuff in noframes
		LX->Tnoframes =>
			ps.skipping = 1;

		LX->Tnoframes+RBRA =>
			ps.skipping = 0;

		# We do scripts (if enabled), so skip stuff in noscripts
		LX->Tnoscript =>
			if(doscripts)
				ps.skipping = 1;

		LX->Tnoscript+RBRA =>
			if(doscripts)
				ps.skipping = 0;

		# <!ELEMENT OPTION - O (#PCDATA)>
		LX->Toption =>
			if(is.curform == nil || is.curform.fields == nil) {
				if(warn)
					sys->print("warning: <OPTION> not in <SELECT>\n");
				continue;
			}
			field := hd is.curform.fields;
			if(field.ftype != Fselect) {
				if(warn)
					sys->print("warning: <OPTION> not in <SELECT>\n");
				continue;
			}
			val := aval(tok, LX->Avalue);
			option := ref Option(aboolval(tok, LX->Aselected),
						val, "");
			field.options = option :: field.options;
			(option.display, toki) = getpcdata(toks, toki);
			option.display = optiontext(option.display);
			if(val == "")
				option.value = option.display;

		# <!ELEMENT P - O (%text)* >
		LX->Tp =>
			pushjust(ps, atabbval(tok, LX->Aalign, align_tab, ps.curjust));
			ps.inpar = 1;
			ps.skipwhite = 1;
			
		LX->Tp+RBRA =>
			;

		# <!ELEMENT PARAM - O EMPTY>
		# Do something when we do applets...
		LX->Tparam =>
			;

		# <!ELEMENT PRE - - (%text)* -(IMG|BIG|SMALL|SUB|SUP|FONT) >
		LX->Tpre =>
			ps.curstate &= ~IFwrap;
			ps.literal = 1;
			ps.skipwhite = 0;
			pushfontstyle(ps, FntT);

		LX->Tpre+RBRA =>
			ps.curstate |= IFwrap;
			if(ps.literal) {
				popfontstyle(ps);
				ps.literal = 0;
			}

		# <!ELEMENT SCRIPT - - CDATA>
		LX->Tscript =>
			if(!doscripts) {
				if(warn)
					sys->print("warning: <SCRIPT> ignored\n");
				ps.skipping = 1;
				break;
			}
			script := "";
			scripttoki := toki;
			(script, toki) = getpcdata(toks, toki);

			# check language version
			lang :=  astrval(tok, LX->Alanguage, "javascript");
			lang = S->tolower(lang);
			lang = trim_white(lang);
			
			# should give preference to type
			supported := 0;
			for (v := 0; v < len J->versions; v++)
				if (J->versions[v] == lang) {
					supported = 1;
					break;
			}
			if (!supported)
				break;

			di.hasscripts = 1;
			scriptsrc := aurlval(tok, LX->Asrc, nil, di.base);
			if(scriptsrc != nil && is.reqdurl == nil) {
				is.reqdurl = scriptsrc;
				toki = scripttoki;
				# is.reqddata will contain script next time round
				break TokLoop;
			}
			if (is.reqddata != nil) {
				script = CU->stripscript(string is.reqddata);
				is.reqddata = nil;
				is.reqdurl = nil;
			}

			if(script == "")
				break;
#sys->print("SCRIPT (ver %s)\n%s\nENDSCRIPT\n", lang, script);
			(err, replace, nil) := J->evalscript(is.frame, script);
			if(err != "") {
				if(warn)
					sys->print("Javascript error: %s\n", err);
			} else {
				# First, worry about possible transfer back of new values
				if(di.text != ps.curfg) {
					# The following isn't nearly good enough
					# (if the fgstk isn't nil, need to replace bottom of stack;
					# and need to do similar things for all other pstates).
					# But Netscape 4.0 doesn't do anything at all if change
					# foreground in a script!
					if(ps.fgstk == nil)
						ps.curfg = di.text;
				}
				scripttoks := lexstring(replace);
				ns := len scripttoks;
				if(ns > 0) {
					# splice scripttoks into toks, replacing <SCRIPT>...</SCRIPT>
					if(toki+1 < tokslen && toks[toki+1].tag == LX->Tscript+RBRA)
						toki++;
					newtokslen := tokslen - (toki+1-scripttoki) + ns;
					newtoks := array[newtokslen] of ref Token;
					newtoks[0:] = toks[0:scripttoki];
					newtoks[scripttoki:] = scripttoks;
					if(toki+1 < tokslen)
						newtoks[scripttoki+ns:] = toks[toki+1:tokslen];
					toks = newtoks;
					tokslen = newtokslen;
					toki = scripttoki-1;
					scripttoks = nil;
				}
			}

		LX->Tscript+RBRA =>
			ps.skipping = 0;

		# <!ELEMENT SELECT - - (OPTION+)>
		LX->Tselect =>
			if(is.curform ==nil) {
				if(warn)
					sys->print("<SELECT> not inside <FORM>\n");
					continue;
			}
			field := Formfield.new(Fselect,
					++is.curform.nfields,	# fieldid
					is.curform,	# form
					aval(tok, LX->Aname),
					"", 			# value
					aintval(tok, LX->Asize, 1),
					0);			# maxlength
			if(aboolval(tok, LX->Amultiple))
				field.flags = FFmultiple;
			is.curform.fields = field :: is.curform.fields;
			ffit := Item.newformfield(field);
			additem(ps, ffit, tok);
			if(ffit.genattr != nil) {
				field.events = ffit.genattr.events;
				if(field.events != nil && doscripts)
					di.hasscripts = 1;
			}
			# throw away stuff until next tag (should be <OPTION>)
			(nil, toki) = getpcdata(toks, toki);

		LX->Tselect+RBRA =>
			if(is.curform == nil || is.curform.fields == nil) {
				if(warn)
					sys->print("warning: unexpected </SELECT>\n");
				continue;
			}
			field := hd is.curform.fields;
			if(field.ftype != Fselect)
				continue;
			# put options back in input order
			opts : list of ref Option = nil;
			select := 0;
			for(ol := field.options; ol != nil; ol = tl ol) {
				o := hd ol;
				if (o.selected)
					select = 1;
				opts = o :: opts;
			}
			# Single-choice select fields preselect the first option if none explicitly selected
			if (!select && !int(field.flags & FFmultiple) && opts != nil)
				(hd opts).selected = 1;
			field.options = opts;

		# <!ELEMENT (STRIKE|U) - - (%text)*>
		LX->Tstrike or LX->Tu =>
			if(tag == LX->Tstrike)
				ulty := ULmid;
			else
				ulty = ULunder;
			ps.ulstk = ulty :: ps.ulstk;
			ps.curul = ulty;

		LX->Tstrike+RBRA or LX->Tu+RBRA =>
			if(ps.ulstk == nil) {
				if(warn)
					sys->print("warning: unexpected %s\n", tok.tostring());
				continue;
			}
			ps.ulstk = tl ps.ulstk;
			if(ps.ulstk != nil)
				ps.curul = hd ps.ulstk;
			else
				ps.curul = ULnone;

		# <!ELEMENT STYLE - - CDATA>
		LX->Tstyle =>
			if(warn)
				sys->print("warning: unimplemented <STYLE>\n");
			ps.skipping = 1;

		LX->Tstyle+RBRA =>
			ps.skipping = 0;

		# <!ELEMENT (SUB|SUP) - - (%text)*>
		LX->Tsub or LX->Tsup =>
			if(tag == LX->Tsub)
				ps.curvoff += SUBOFF;
			else
				ps.curvoff -= SUPOFF;
			ps.voffstk = ps.curvoff :: ps.voffstk;
			sz := stackhd(ps.fntsizestk, Normal);
			pushfontsize(ps, sz-1);

		LX->Tsub+RBRA or LX->Tsup+RBRA =>
			if(ps.voffstk == nil) {
				if(warn)
					sys->print("warning: unexpected %s\n", tok.tostring());
				continue;
			}
			ps.voffstk = tl ps.voffstk;
			if(ps.voffstk != nil)
				ps.curvoff = hd ps.voffstk;
			else
				ps.curvoff = 0;
			popfontsize(ps);

		# <!ELEMENT TABLE - - (CAPTION?, TR+)>
		LX->Ttable =>
			if (ps.skipping)
				continue;
			ps.skipwhite = 0;
			# Handle an html error (seen on deja.com)
			# ... sometimes see a nested <table> outside of a cell
			# imitate observed behaviour of IE/Navigator
			if (curtab != nil && curtab.cells == nil) {
				curtab.align = makealign(tok);
				curtab.width = makedimen(tok, LX->Awidth);
				curtab.border = aflagval(tok, LX->Aborder);
				curtab.cellspacing = aintval(tok, LX->Acellspacing, TABSP);
				curtab.cellpadding = aintval(tok, LX->Acellpadding, TABPAD);
				curtab.background = Background(nil, color(aval(tok, LX->Abgcolor), -1));
				curtab.tabletok = tok;
				continue;
			}
			tab := Table.new(++is.ntables,	# tableid
					makealign(tok),	# align
					makedimen(tok, LX->Awidth),
					aflagval(tok, LX->Aborder),
					aintval(tok, LX->Acellspacing, TABSP),
					aintval(tok, LX->Acellpadding, TABPAD),
#					Background(nil, color(aval(tok, LX->Abgcolor), ps.curbg.color)),
					Background(nil, color(aval(tok, LX->Abgcolor), -1)),
					tok);
			is.tabstk = tab :: is.tabstk;
			di.tables = tab :: di.tables;
			curtab = tab;
			# HTML spec says:
			# don't add items to outer state (until </table>)
			# but IE and Netscape don't do that

		LX->Ttable+RBRA =>
			if (ps.skipping)
				continue;
			if(curtab == nil) {
				if(warn)
					sys->print("warning: unexpected </TABLE>\n");
				continue;
			}
			isempty := (curtab.cells == nil);
			if(isempty) {
				if(warn)
					sys->print("warning: <TABLE> has no cells\n");
			}
			else {
				(ps, psstk) = finishcell(curtab, psstk);
				if(curtab.currows != nil)
					(hd curtab.currows).flags = byte 0;
				finish_table(curtab);
			}
			ps.skipping = 0;
			if(!isempty) {
				tabitem := Item.newtable(curtab);
				al := int curtab.align.halign;
				case al {
				int Aleft or int Aright =>
					additem(ps, Item.newfloat(tabitem, byte al), tok);
				* =>
					if(al == int Acenter)
						pushjust(ps, Acenter);
					addbrk(ps, 0, 0);
					if(ps.inpar) {
						popjust(ps);
						ps.inpar = 0;
					}
					additem(ps, tabitem, curtab.tabletok);
					if(al == int Acenter)
						popjust(ps);
				}
			}
			if(is.tabstk == nil) {
				if(warn)
					sys->print("warning: table stack is wrong\n");
			}
			else
				is.tabstk = tl is.tabstk;
			if(is.tabstk == nil)
				curtab = nil;
			else
				curtab = hd is.tabstk;
			if(!isempty) {
				# the code at the beginning to add a break after table
				# changed the nested ps, not the current one
				addbrk(ps, 0, 0);
			}

		# <!ELEMENT (TH|TD) - O %body.content>
		# Cells for a row are accumulated in reverse order.
		# We push ps on a stack, and use a new one to accumulate
		# the contents of the cell.
		LX->Ttd or LX->Tth =>
			if (ps.skipping)
				continue;
			if(curtab == nil) {
				if(warn)
					sys->print("%s outside <TABLE>\n", tok.tostring());
				continue;
			}
			if(ps.inpar) {
				popjust(ps);
				ps.inpar = 0;
			}
			(ps, psstk) = finishcell(curtab, psstk);
			tr : ref Tablerow = nil;
			if(curtab.currows != nil)
				tr = hd curtab.currows;
			if(tr == nil || tr.flags == byte 0) {
				if(warn)
					sys->print("%s outside row\n", tok.tostring());
				tr = Tablerow.new(Align(Anone,Anone), curtab.background, TFparsing);
				curtab.currows = tr :: curtab.currows;
			}
			ps = cell_pstate(ps, tag == LX->Tth);
			psstk = ps :: psstk;
			flags := TFparsing;
			width := makedimen(tok, LX->Awidth);
	
			# nowrap only applies if no width has been specified
			if(width.kind() == Dnone && aboolval(tok, LX->Anowrap)) {
				flags |= TFnowrap;
				ps.curstate &= ~IFwrap;
			}
			if(tag == LX->Tth)
				flags |= TFisth;
			bg := Background(nil, color(aval(tok, LX->Abgcolor), tr.background.color));
			c := Tablecell.new(len curtab.cells + 1, # cell id
				aintval(tok, LX->Arowspan, 1),
				aintval(tok, LX->Acolspan, 1),
				makealign(tok),
				width,
				aintval(tok, LX->Aheight, 0),
				bg,
				flags);

			bgurl := aurlval(tok, LX->Abackground, nil, di.base);
			if(bgurl != nil) {
				pick ni := Item.newimage(di, bgurl, nil,"", Anone, 0, 0, 0, 0, 0, 0, 1, nil, nil, nil){
				Iimage =>
					bg.image = ni;
				}
				di.images = bg.image :: di.images;
			}
			c.background = ps.curbg = bg;
			ps.curbg.image = nil;
			if(c.align.halign == Anone) {
				if(tr.align.halign != Anone)
					c.align.halign = tr.align.halign;
				else if(tag == LX->Tth)
					c.align.halign = Acenter;
				else
					c.align.halign = Aleft;
			}
			if(c.align.valign == Anone) {
				if(tr.align.valign != Anone)
					c.align.valign = tr.align.valign;
				else
					c.align.valign = Amiddle;
			}
			curtab.cells = c :: curtab.cells;
			tr.cells = c :: tr.cells;

		LX->Ttd+RBRA or LX->Tth+RBRA =>
			if (ps.skipping)
				continue;
			if(curtab == nil || curtab.cells == nil) {
				if(warn)
					sys->print("unexpected %s\n", tok.tostring());
				continue;
			}
			(ps, psstk) = finishcell(curtab, psstk);

		# <!ELEMENT TEXTAREA - - (#PCDATA)>
		LX->Ttextarea =>
			if(is.curform ==nil) {
				if(warn)
					sys->print("<TEXTAREA> not inside <FORM>\n");
					continue;
			}
			nrows := aintval(tok, LX->Arows, 3);
			ncols := aintval(tok, LX->Acols, 50);
			ft := Ftextarea;
			if (ncols == 0 || nrows == 0)
				ft = Fhidden;
			field := Formfield.new(ft,
					++is.curform.nfields,	# fieldid
					is.curform,	# form
					aval(tok, LX->Aname),
					"",				# value
					0, 0);				# size, maxlength
			field.rows = nrows;
			field.cols = ncols;
			is.curform.fields = field :: is.curform.fields;
			(field.value, toki) = getpcdata(toks, toki);
			if(warn && toki < tokslen-1 && toks[toki+1].tag != LX->Ttextarea+RBRA)
				sys->print("warning: <TEXTAREA> data ended by %s\n", toks[toki+1].tostring());
			ffit :=  Item.newformfield(field);
			additem(ps, ffit, tok);
			if(ffit.genattr != nil) {
				field.events = ffit.genattr.events;
				if(field.events != nil && doscripts)
					di.hasscripts = 1;
			}

		# <!ELEMENT TITLE - - (#PCDATA)* -(%head.misc)>
		LX->Ttitle =>
			(di.doctitle, toki) = getpcdata(toks, toki);
			if(warn && toki < tokslen-1 && toks[toki+1].tag != LX->Ttitle+RBRA)
				sys->print("warning: <TITLE> data ended by %s\n", toks[toki+1].tostring());

		# <!ELEMENT TR - O (TH|TD)+>
		# rows are accumulated in reverse order in curtab.currows
		LX->Ttr =>
			if (ps.skipping)
				continue;
			if(curtab == nil) {
				if(warn)
					sys->print("warning: <TR> outside <TABLE>\n");
				continue;
			}
			if(ps.inpar) {
				popjust(ps);
				ps.inpar = 0;
			}
			(ps, psstk) = finishcell(curtab, psstk);
			if(curtab.currows != nil)
				(hd curtab.currows).flags = byte 0;
			tr := Tablerow.new(makealign(tok),
					Background(nil, color(aval(tok, LX->Abgcolor), curtab.background.color)),
					TFparsing);
			curtab.currows = tr :: curtab.currows;

		LX->Ttr+RBRA =>
			if (ps.skipping)
				continue;
			if(curtab == nil || curtab.currows == nil) {
				if(warn)
					sys->print("warning: unexpected </TR>\n");
				continue;
			}
			(ps, psstk) = finishcell(curtab, psstk);
			tr := hd curtab.currows;
			if(tr.cells == nil) {
				if(warn)
					sys->print("warning: empty row\n");
				curtab.currows = tl curtab.currows;
			}
			else
				tr.flags = byte 0;		# done parsing

		# <!ELEMENT (TT|CODE|KBD|SAMP) - - (%text)*>
		LX->Ttt or LX->Tcode or LX->Tkbd	or LX->Tsamp =>
			pushfontstyle(ps, FntT);

		# <!ELEMENT (XMP|LISTING) - - %literal >
		# additional support exists in LX to ignore character escapes etc.
		LX->Txmp =>
			ps.curstate &= ~IFwrap;
			ps.literal = 1;
			ps.skipwhite = 0;
			pushfontstyle(ps, FntT);

		LX->Txmp+RBRA =>
			ps.curstate |= IFwrap;
			if(ps.literal) {
				popfontstyle(ps);
				ps.literal = 0;
			}

		# Tags that have empty action

		LX->Tabbr or LX->Tabbr+RBRA
		or LX->Tacronym or LX->Tacronym+RBRA
		or LX->Tarea+RBRA
		or LX->Tbase+RBRA
		or LX->Tbasefont+RBRA
		or LX->Tbr+RBRA
		or LX->Tdd+RBRA
		or LX->Tdt+RBRA
		or LX->Tframe+RBRA
		or LX->Thr+RBRA
		or LX->Thtml
		or LX->Thtml+RBRA
		or LX->Timg+RBRA
		or LX->Tinput+RBRA
		or LX->Tisindex+RBRA
		or LX->Tli+RBRA
		or LX->Tlink or LX->Tlink+RBRA
		or LX->Tmeta+RBRA
		or LX->Toption+RBRA
		or LX->Tparam+RBRA
		or LX->Ttextarea+RBRA
		or LX->Ttitle+RBRA
		=>
			;

		# Tags not implemented
		LX->Tbdo or LX->Tbdo+RBRA
		or LX->Tbutton or LX->Tbutton+RBRA
		or LX->Tdel or LX->Tdel+RBRA
		or LX->Tfieldset or LX->Tfieldset+RBRA
		or LX->Tiframe or LX->Tiframe+RBRA
		or LX->Tins or LX->Tins+RBRA
		or LX->Tlabel or LX->Tlabel+RBRA
		or LX->Tlegend or LX->Tlegend+RBRA
		or LX->Tobject or LX->Tobject+RBRA
		or LX->Toptgroup or LX->Toptgroup+RBRA
		or LX->Tspan or LX->Tspan+RBRA
		=>
			if(warn) {
				if(tag > RBRA)
					tag -= RBRA;
				sys->print("warning: unimplemented HTML tag: %s\n", LX->tagnames[tag]);
			}

		* =>
			if(warn)
				sys->print("warning: unknown HTML tag: %s\n", tok.text);
		}
	}
	if (toki < tokslen)
		is.toks = toks[toki:];
	if(tokslen == 0) {
		# we might have hit eof from lexer
		# some pages omit trailing </table>
		bs := is.ts.b;
		if(bs.eof && bs.lim == bs.edata) {
			while(curtab != nil) {
				if(warn)
					sys->print("warning: <TABLE> not closed\n");
				if(curtab.cells != nil) {
					(ps, psstk) = finishcell(curtab, psstk);
					if(curtab.currows != nil)
						(hd curtab.currows).flags = byte 0;
					finish_table(curtab);
					ps.skipping = 0;
					additem(ps, Item.newtable(curtab), curtab.tabletok);
					addbrk(ps, 0, 0);
				}
				if(is.tabstk != nil)
					is.tabstk = tl is.tabstk;
				if(is.tabstk == nil)
					curtab = nil;
				else
					curtab = hd is.tabstk;
			}
		}
	}
	outerps := lastps(psstk);
	ans := outerps.items.next;
	# note: ans may be nil and di.kids not nil, if there's a frameset!
	outerps.items = Item.newspacer(ISPnull, 0);
	outerps.lastit = outerps.items;
	is.psstk = psstk;

	if(dbg) {
		if(ans == nil)
			sys->print("getitems returning nil\n");
		else
			ans.printlist("getitems returning:");
	}
	return ans;
}

endanchor(ps: ref Pstate, docfg: int)
{
	if(ps.curanchor != 0) {
		if(ps.fgstk != nil) {
			ps.fgstk = tl ps.fgstk;
			if(ps.fgstk == nil)
				ps.curfg = docfg;
			else
				ps.curfg = hd ps.fgstk;
		}
		ps.curanchor = 0;
		if(ps.ulstk != nil) {
			ps.ulstk = tl ps.ulstk;
			if(ps.ulstk == nil)
				ps.curul = ULnone;
			else
				ps.curul = hd ps.ulstk;
		}
	}
}

lexstring(s: string) : array of ref Token
{
	bs := ByteSource.stringsource(s);
	ts := TokenSource.new(bs, utf8, CU->TextHtml);
	ans : array of ref Token = nil;
	# gettoks might return answer in several hunks
	for(;;) {
		toks := ts.gettoks();
		if(toks == nil)
			break;
		if(ans != nil) {
			newans := array[len ans + len toks] of ref Token;
			newans[0:] = ans;
			newans[len ans:] = toks;
			ans = newans;
		}
		else
			ans = toks;
	}
	return ans;
}

lastps(psl: list of ref Pstate) : ref Pstate
{
	if(psl == nil)
		CU->raisex("EXInternal: empty pstate stack");
	while(tl psl != nil)
		psl = tl psl;
	return hd psl;
}

# Concatenate together maximal set of Data tokens, starting at toks[toki+1].
# Lexer has ensured that there will either be a following non-data token or
# we will be at eof.
# Return (trimmed concatenation, last used toki).
getpcdata(toks: array of ref Token, toki: int) : (string, int)
{
	ans := "";
	tokslen := len toks;
	toki++;
	for(;;) {
		if(toki >= tokslen)
			break;
		tok := toks[toki];
		if(tok.tag == LX->Data) {
			toki++;
			ans = ans + tok.text;
		}
		else
			break;
	}
	return (trim_white(ans),  toki-1);
}

optiontext(str : string) : string
{
	ans := "";
	lastc := 0;
	for (i := 0; i < len str; i++) {
		if (str[i] > 16r20)
			ans[len ans] = str[i];
		else if (lastc > 16r20)
			ans[len ans] = ' ';
		lastc = str[i];
	}
	return ans;
}

finishcell(curtab: ref Table, psstk: list of ref Pstate) : (ref Pstate, list of ref Pstate)
{
	if(curtab.cells != nil) {
		c := hd curtab.cells;
		if((c.flags&TFparsing) != byte 0) {
			if(tl psstk == nil) {
				if(warn)
					sys->print("warning: parse state stack is wrong\n");
			}
			else {
				ps := hd psstk;
				c.content = ps.items.next;
				c.flags &= ~TFparsing;
				psstk = tl psstk;
			}
		}
	}
	return (hd psstk, psstk);
}

Pstate.new() : ref Pstate
{
	ps := ref Pstate (
			0, 0, DefFnt,	# skipping, skipwhite, curfont
			CU->Black,	# curfg
			Background(nil, CU->White),
			0,			# curvoff
			ULnone, Aleft,	# curul, curjust
			0, IFwrap,		# curanchor, curstate
			0, 0, 0,		# literal, inpar, adjsize
			nil, nil, nil,		# items, lastit, prelastit
			nil, nil, nil, nil,	# fntstylestk, fntsizestk, fgstk, ulstk
			nil, nil, nil, nil,	# voffstk, listtypestk, listcntstk, juststk
			nil);			# hangstk
	ps.items = Item.newspacer(ISPnull, 0);
	ps.lastit = ps.items;
	ps.prelastit = nil;
	return ps;
}

cell_pstate(oldps: ref Pstate, ishead: int) : ref Pstate
{
	ps := Pstate.new();
	ps.skipwhite = 1;
	ps.curanchor = oldps.curanchor;
	ps.fntstylestk = oldps.fntstylestk;
	ps.fntsizestk = oldps.fntsizestk;
	ps.curfont = oldps.curfont;
	ps.curfg = oldps.curfg;
	ps.curbg = oldps.curbg;
	ps.fgstk = oldps.fgstk;
	ps.adjsize = oldps.adjsize;
	if(ishead) {
		# make bold
		sty := ps.curfont%NumSize;
		ps.curfont = FntB*NumSize + sty;
	}
	return ps;
}

trim_white(data: string): string
{
	data = S->drop(data, whitespace);
	(l,r) := S->splitr(data, notwhitespace);
	return l;
}

# Add it to end of ps item chain, adding in current state from ps.
# Also, if tok is not nil, scan it for generic attributes and assign
# the genattr field of the item accordingly.
additem(ps: ref Pstate, it: ref Item, tok: ref LX->Token)
{
	if(ps.skipping) {
		if(warn) {
			sys->print("warning: skipping item:\n");
			it.print();
		}
		return;
	}
	it.anchorid = ps.curanchor;
	it.state |= ps.curstate;
	if(tok != nil)
		it.genattr = getgenattr(tok);
	ps.curstate &= ~(IFbrk|IFbrksp|IFnobrk|IFcleft|IFcright);
	ps.prelastit = ps.lastit;
	ps.lastit.next = it;
	ps.lastit = it;
}

getgenattr(tok: ref LX->Token) : ref Genattr
{
	any := 0;
	i, c, s, t: string;
	e: list of LX->Attr = nil;
	for(al := tok.attr; al != nil; al = tl al) {
		a := hd al;
		aid := a.attid;
		if(attrinfo[aid] == byte 0)
			continue;
		case aid {
		LX->Aid =>
			i = a.value;
			any = 1;
		LX->Aclass =>
			c = a.value;
			any = 1;
		LX->Astyle =>
			s = a.value;
			any = 1;
		LX->Atitle =>
			t = a.value;
			any = 1;
		* =>
			CU->assert(aid >= LX->Aonabort && aid <= LX->Aonunload);
			e = a :: e;
			any = 1;
		}
	}
	if(any)
		return ref Genattr(i, c, s, t, e, 0);
	return nil;
}

textit(ps: ref Pstate, s: string) : ref Item
{
	return Item.newtext(s, ps.curfont, ps.curfg, ps.curvoff+Voffbias, ps.curul);
}

# Add text item or items for s, paying attention to
# current font, foreground, baseline offset, underline state,
# and literal mode.  Unless we're in literal mode, compress
# whitespace to single blank, and, if curstate has a break,
# trim any leading whitespace.  Whether in literal mode or not,
# turn nonbreaking spaces into spacer items with IFnobrk set.
#
# In literal mode, break up s at newlines and add breaks instead.
# Also replace tabs appropriate number of spaces.
# In nonliteral mode, break up the items every 100 or so characters
# just to make the layout algorithm not go quadratic.
#
# This code could be written much shorter using the String module
# split and drop functions, but we want this part to go fast.
addtext(ps: ref Pstate, s: string)
{
	n := len s;
	i := 0;
	j := 0;
	if(ps.literal) {
		col := 0;
		while(i < n) {
			if(s[i] == '\n') {
				if(i > j) {
					# trim trailing blanks from line
					for(k := i; k > j; k--)
						if(s[k-1] != ' ')
							break;
					if(k > j)
						additem(ps, textit(ps, s[j:k]), nil);
				}
				addlinebrk(ps, 0);
				j = i+1;
				col = 0;
			}
			else {
				if(s[i] == '\t') {
					col += i-j;
					nsp := 8 - (col % 8);
					additem(ps, textit(ps, s[j:i] + "        "[0:nsp]), nil);
					col += nsp;
					j = i+1;
				}
				else if(s[i] == NBSP) {
					if(i > j)
						additem(ps, textit(ps, s[j:i]), nil);
					addnbsp(ps);
					col += (i-j) + 1;
					j = i+1;
				}
			}
			i++;
		}
		if(i > j)
			additem(ps, textit(ps, s[j:i]), nil);
	}
	else {
		if((ps.curstate&IFbrk) || ps.lastit == ps.items)
			while(i < n) {
				c := s[i];
				if(c >= C->NCTYPE || ctype[c] != C->W)
					break;
				i++;
			}
		ss := "";
		j = i;
		for( ; i < n; i++) {
			c := s[i];
			if(c == NBSP) {
				if(i > j)
					ss += s[j:i];
				if(ss != "")
					additem(ps, textit(ps, ss), nil);
				ss = "";
				addnbsp(ps);
				j = i + 1;
				continue;
			}
			if(c < C->NCTYPE && ctype[c] == C->W) {
				ss += s[j:i] + " ";
				while(i < n-1) {
					c = s[i+1];
					if(c >= C->NCTYPE || ctype[c] != C->W)
						break;
					i++;
				}
				j = i + 1;
			}
			if(i - j >= 100) {
				ss += s[j:i+1];
				j = i + 1;
			}
			if(len ss >= 100) {
				additem(ps, textit(ps, ss), nil);
				ss = "";
			}
		}
		if(i > j && j < n)
			ss += s[j:i];
		# don't add a space if previous item ended in a space
		if(ss == " " && ps.lastit != nil) {
			pick t := ps.lastit {
			Itext =>
				sp := t.s;
				nsp := len sp;
				if(nsp > 0 && sp[nsp-1] == ' ')
					ss = "";
			}
		}
		if(ss != "")
			additem(ps, textit(ps, ss), nil);
	}
}

# Add a break to ps.curstate, with extra space if sp is true.
# If there was a previous break, combine this one's parameters
# with that to make the amt be the max of the two and the clr
# be the most general. (amt will be 0 or 1)
# Also, if the immediately preceding item was a text item,
# trim any whitespace from the end of it, if not in literal mode.
# Finally, if this is at the very beginning of the item list
# (the only thing there is a null spacer), then don't add the space.
addbrk(ps: ref Pstate, sp: int, clr: int)
{
	state := ps.curstate;
	clr = clr | (state&(IFcleft|IFcright));
	if(sp && !(ps.lastit == ps.items))
		sp = IFbrksp;
	else
		sp = 0;
	ps.curstate = IFbrk | sp | (state&~(IFcleft|IFcright)) | clr;
	if(ps.lastit != ps.items) {
		if(!ps.literal && tagof ps.lastit == tagof Item.Itext) {
			pick t := ps.lastit {
			Itext =>
				(l,nil) := S->splitr(t.s, notwhitespace);
				# try to avoid making empty items
				# (but not crucial if the occasional one gets through)
				if(l == "" && ps.prelastit != nil) {
					ps.lastit = ps.prelastit;
					ps.lastit.next = nil;
					ps.prelastit = nil;
				}
				else
					t.s = l;
			}
		}
	}
}

# Add break due to a <br> or a newline within a preformatted section.
# We add a null item first, with current font's height and ascent, to make
# sure that the current line takes up at least that amount of vertical space.
# This ensures that <br>s on empty lines cause blank lines, and that
# multiple <br>s in a row give multiple blank lines.
# However don't add the spacer if the previous item was something that
# takes up space itself. [[ I think this is not what we want; see
# MR inf983435. --Ravi ]]
addlinebrk(ps: ref Pstate, clr: int)
{
	# don't want break before our null item unless the previous item
	# was also a null item for the purposes of line breaking
	obrkstate := ps.curstate & (IFbrk|IFbrksp);
	b := IFnobrk;
	if(ps.lastit != nil) {
		pick pit := ps.lastit {
		Ispacer =>
			if(pit.spkind == ISPvline)
				b = IFbrk;
		}
	}
	ps.curstate = (ps.curstate & ~(IFbrk|IFbrksp)) | b;
	additem(ps, Item.newspacer(ISPvline, ps.curfont), nil);
	ps.curstate = (ps.curstate & ~(IFbrk|IFbrksp)) | obrkstate;
	addbrk(ps, 0, clr);
}

# Add a nonbreakable space
addnbsp(ps: ref Pstate)
{
	# if nbsp comes right where a break was specified,
	# do the break anyway (nbsp is being used to generate undiscardable
	# space rather than to prevent a break)
	if((ps.curstate&IFbrk) == 0)
		ps.curstate |=  IFnobrk;
	additem(ps, Item.newspacer(ISPhspace, ps.curfont), nil);
	# but definitely no break on next item
	ps.curstate |= IFnobrk;
}

# Change hang in ps.curstate by delta.
# The amount is in 1/10ths of tabs, and is the amount that
# the current contiguous set of items with a hang value set
# is to be shifted left from its normal (indented) place.
changehang(ps: ref Pstate, delta: int)
{
	amt := (ps.curstate&IFhangmask) + delta;
	if(amt < 0) {
		if(warn)
			sys->print("warning: hang went negative\n");
		amt = 0;
	}
	ps.curstate = (ps.curstate&~IFhangmask) | amt;
}

# Change indent in ps.curstate by delta.
changeindent(ps: ref Pstate, delta: int)
{
	amt := ((ps.curstate&IFindentmask)>>IFindentshift) + delta;
	if(amt < 0) {
		if(warn)
			sys->print("warning: indent went negative\n");
		amt = 0;
	}
	ps.curstate = (ps.curstate&~IFindentmask) | (amt<<IFindentshift);
}

stackhd(stk: list of int, dflt: int) : int
{
	if(stk == nil)
		return dflt;
	return hd stk;
}

popfontstyle(ps: ref Pstate)
{
	if(ps.fntstylestk != nil)
		ps.fntstylestk = tl ps.fntstylestk;
	setcurfont(ps);
}

pushfontstyle(ps: ref Pstate, sty: int)
{
	ps.fntstylestk = sty :: ps.fntstylestk;
	setcurfont(ps);
}

popfontsize(ps: ref Pstate)
{
	if(ps.fntsizestk != nil)
		ps.fntsizestk = tl ps.fntsizestk;
	setcurfont(ps);
}

pushfontsize(ps: ref Pstate, sz: int)
{
	ps.fntsizestk = sz :: ps.fntsizestk;
	setcurfont(ps);
}

setcurfont(ps: ref Pstate)
{
	sty := FntR;
	sz := Normal;
	if(ps.fntstylestk != nil)
		sty = hd ps.fntstylestk;
	if(ps.fntsizestk != nil)
		sz = hd ps.fntsizestk;
	if(sz < Tiny)
		sz = Tiny;
	if(sz > Verylarge)
		sz = Verylarge;
	ps.curfont = sty*NumSize + sz;
}

popjust(ps: ref Pstate)
{
	if(ps.juststk != nil)
		ps.juststk = tl ps.juststk;
	setcurjust(ps);
}

pushjust(ps: ref Pstate, j: byte)
{
	ps.juststk = j :: ps.juststk;
	setcurjust(ps);
}

setcurjust(ps: ref Pstate)
{
	if(ps.juststk != nil)
		j := hd ps.juststk;
	else
		j = Aleft;
	if(j != ps.curjust) {
		ps.curjust = j;
		state := ps.curstate;
		state &= ~(IFrjust|IFcjust);
		if(j == Acenter)
			state |= IFcjust;
		else if(j == Aright)
			state |= IFrjust;
		ps.curstate = state;
	}
}

# Do final rearrangement after table parsing is finished
# and assign cells to grid points
finish_table(t: ref Table)
{
	t.nrow = len t.currows;
	t.rows = array[t.nrow] of ref Tablerow;
	ncol := 0;
	r := t.nrow-1;
	for(rl := t.currows; rl != nil; rl = tl rl) {
		row := hd rl;
		t.rows[r--] = row;
		rcols := 0;
		cl := row.cells;
		# If rowspan is > 1 but this is the last row,
		# reset the rowspan
		if(cl != nil && (hd cl).rowspan > 1 && rl == t.currows)
			(hd cl).rowspan = 1;
		row.cells = nil;
		while(cl != nil) {
			c := hd cl;
			row.cells = c :: row.cells;
			rcols += c.colspan;
			cl = tl cl;
		}
		if(rcols > ncol)
			ncol = rcols;
	}
	t.currows = nil;
	t.ncol = ncol;
	t.cols = array[ncol] of { * => Tablecol(0, Align(Anone, Anone), (0,0)) };

	# Reverse cells just so they are drawn in source order.
	# Also, trim their contents so they don't end in whitespace.
	cells : list of ref Tablecell = nil;
	for(cl := t.cells; cl != nil; cl = tl cl) {
		c := hd cl;
		trim_cell(c);
		cells = c :: cells;
	}
	t.cells = cells;

	t.grid = array[t.nrow] of { * => array[t.ncol] of ref Tablecell };
	# The following arrays keep track of cells that are spanning
	# multiple rows;  rowspancnt[i] is the number of rows left
	# to be spanned in column i.
	# When done, cell's (row,col) is upper left grid point.
	rowspancnt := array[t.ncol] of { * => 0};
	rowspancell := array[t.ncol] of ref Tablecell;

	ri := 0;
	ci := 0;
	for(ri = 0; ri < t.nrow; ri++) {
		row := t.rows[ri];
		cl = row.cells;
		for(ci = 0; ci < t.ncol || cl != nil; ) {
			if(ci < t.ncol && rowspancnt[ci] > 0) {
				t.grid[ri][ci] = rowspancell[ci];
				rowspancnt[ci]--;
				ci++;
			}
			else {
				if(cl == nil) {
					ci++;
					continue;
				}
				c := hd cl;
				cl = tl cl;
				cspan := c.colspan;
				rspan := c.rowspan;
				if(ci+cspan > t.ncol) {
					# because of row spanning, we calculated
					# ncol incorrectly; adjust it
					newncol := ci+cspan;
					newcols := array[newncol] of Tablecol;
					newrowspancnt := array[newncol] of { * => 0};
					newrowspancell := array[newncol] of ref Tablecell;
					newcols[0:] = t.cols;
					newrowspancnt[0:] = rowspancnt;
					newrowspancell[0:] = rowspancell;
					for(k := t.ncol; k < newncol; k++)
						newcols[k] = Tablecol(0, Align(Anone, Anone), (0,0));
					t.cols = newcols;
					rowspancnt = newrowspancnt;
					rowspancell = newrowspancell;
					for(j := 0; j < t.nrow; j++) {
						newgrr := array[newncol] of ref Tablecell;
						newgrr[0:] = t.grid[j];
						for(k = t.ncol; k < newncol; k++)
							newgrr[k] = nil;
						t.grid[j] = newgrr;
					}
					t.ncol = newncol;
				}
				c.row = ri;
				c.col = ci;
				for(i := 0; i < cspan; i++) {
					t.grid[ri][ci] = c;
					if(rspan > 1) {
						rowspancnt[ci] = rspan-1;
						rowspancell[ci] = c;
					}
					ci++;
				}
			}
		}
	}
	t.flags |= Layout->Lchanged;
}

# Remove tail of cell content until it isn't whitespace.
trim_cell(c: ref Tablecell)
{
	dropping := 1;
	while(c.content != nil && dropping) {
		p := c.content;
		pprev : ref Item = nil;
		while(p.next != nil) {
			pprev = p;
			p = p.next;
		}
		dropping = 0;
		if(!(p.state&IFnobrk)) {
			pick q := p {
			Itext =>
				s := q.s;
				(x,y) := S->splitr(s, notwhitespace);
				if(x == nil)
					dropping = 1;
				else if(y != nil)
					q.s = x;
			}
		}
		if(dropping) {
			if(pprev == nil)
				c.content = nil;
			else
				pprev.next = nil;
		}
	}
}

roman := array[] of {"I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
	"XI", "XII", "XIII", "XIV", "XV"};

listmark(ty: byte, n: int) : string
{
	s := "";
	case int ty {
		int LTdisc =>
			s = "•";
		int LTsquare =>
			s = "∎";
		int LTcircle =>
			s = "∘";
		int LT1 =>
			s = string n + ".";
		int LTa or int LTA =>
			n--;
			i := 0;
			if(n < 0)
				n = 0;
			if(n > 25) {
				n2 := n / 26;
				n %= 26;
				if(n2 > 25)
					n2 = 25;
				s[i++] = n2 + 'A';
			}
			s[i++] = n + 'A';
			s[i++] = '.';
			if(ty == LTa)
				s = S->tolower(s);
		int LTi or int LTI =>
			if(n >= len roman) {
				if(warn)
					sys->print("warning: unimplemented roman number > %d\n", len roman);
				n = len roman;
			}
			s = roman[n-1];
			if(ty == LTi)
				s = S->tolower(s);
			s += ".";
	}
	return s;
}

# Find map with given name in di.maps.
# If not there, add one.
getmap(di: ref Docinfo, name: string) : ref Map
{
	m : ref Map;
	for(ml := di.maps; ml != nil; ml = tl ml) {
		m = hd ml;
		if(m.name == name)
			return m;
	}
	m = Map.new(name);
	di.maps = m :: di.maps;
	return m;
}

# attrvalue, when "found" status doesn't matter
# (because nil ans is sufficient indication)
aval(tok: ref Token, attid: int) : string
{
	(nil, ans) := tok.aval(attid);
	return ans;
}

# attrvalue, when ans is a string, but need default
astrval(tok: ref Token, attid: int, dflt: string) : string
{
	(fnd, ans) := tok.aval(attid);
	if(!fnd)
		return dflt;
	else
		return ans;
}

# attrvalue, when supposed to convert to int
# and have default for when not found
aintval(tok: ref Token, attid: int, dflt: int) : int
{
	(fnd, ans) := tok.aval(attid);
	if(!fnd || ans == "")
		return dflt;
	else
		return toint(ans);
}

# Like int conversion, but with possible error check (if warning)
toint(s: string) : int
{
	if(warn) {
		ok := 0;
		for(i := 0; i < len s; i++) {
			c := s[i];
			if(!(c < C->NCTYPE && ctype[c] == C->W))
				break;
		}
		for(; i < len s; i++) {
			c := s[i];
			if(c < C->NCTYPE && ctype[c] == C->D)
				ok = 1;
			else {
				ok = 0;
				break;
			}
		}
		if(!ok || i != len s)
			sys->print("warning: expected integer, got '%s'\n", s);
	}
	return int s;
}

# attrvalue when need a table to convert strings to ints
atabval(tok: ref Token, attid: int, tab: array of T->StringInt, dflt: int) : int
{
	(fnd, aval) := tok.aval(attid);
	ans := dflt;
	if(fnd) {
		name := S->tolower(aval);
		(fnd, ans) = T->lookup(tab, name);
		if(!fnd) {
			ans = dflt;
			if(warn)
				sys->print("warning: name not found in table lookup: %s\n", name);
		}
	}
	return ans;
}

# like atabval, but when want a byte answer
atabbval(tok: ref Token, attid: int, tab: array of T->StringInt, dflt: byte) : byte
{
	(fnd, aval) := tok.aval(attid);
	ans := dflt;
	if(fnd) {
		name := S->tolower(aval);
		ians : int;
		(fnd, ians) = T->lookup(tab, name);
		if(fnd)
			ans = byte ians;
		else if(warn)
			sys->print("warning: name not found in table lookup: %s\n", name);
	}
	return ans;
}

# special for list types, where "i" and "I" are different,
# but "square" and "SQUARE" are the same
listtyval(tok: ref Token, dflt: byte) : byte
{
	(fnd, aval) := tok.aval(LX->Atype);
	ans := dflt;
	if(fnd) {
		case aval {
		"1" => ans = LT1;
		"A" => ans = LTA;
		"I" => ans = LTI;
		"a" => ans = LTa;
		"i" => ans = LTi;
		* =>
			aval = S->tolower(aval);
			case aval {
			"circle" => ans = LTcircle;
			"disc" => ans = LTdisc;
			"square" => ans = LTsquare;
			* => if(warn)
				sys->print("warning: unknown list element type %s\n", aval);
			}
		}
	}
	return ans;
}

# attrvalue when value is a URL
aurlval(tok: ref Token, attid: int, dflt, base: ref Parsedurl) : ref Parsedurl
{
	ans := dflt;
	(fnd, url) := tok.aval(attid);
	if(fnd && url != nil) {
		url = S->drop(url, whitespace);
		ans = U->parse(url);
		case (ans.scheme) {
		"javascript" =>
			;	# don't strip whitespace from the URL
		* =>
			# sometimes people put extraneous whitespace in
			url = stripwhite(url);
			ans = U->parse(url);
			if(base != nil)
				ans = U->mkabs(ans, base);
		}
	}
	return ans;
}

# remove any whitespace characters from any part of s
# up to a '#' (assuming s is a url and '#' begins a fragment
# (can return s if there are no whitespace characters in it)
stripwhite(s: string) : string
{
	j := 0;
	n := len s;
	strip := 1;
	for(i := 0; i < n; i++) {
		c := s[i];
		if(c == '#')
			strip = 0;
		if(strip && c < C->NCTYPE && ctype[c]==C->W)
			continue;
		s[j++] = c;
	}
	if(j < n)
		s = s[0:j];
	return s;
}

# Presence of attribute implies true, omission implies false.
# Boolean attributes can have a value equal to their attribute name.
# HTML4.01 does not state whether the attribute is true or false
# if a value is given that doesn't match the attribute name.
aboolval(tok: ref Token, attid: int): int
{
	(fnd, nil) := tok.aval(attid);
	return fnd;
}

# attrvalue when mere presence of attr implies value of 1
aflagval(tok: ref Token, attid: int) : int
{
	val := 0;
	(fnd, sval) := tok.aval(attid);
	if(fnd) {
		val = 1;
		if(sval != "")
			val = toint(sval);
	}
	return val;
}

# Make an Align (two alignments, horizontal and vertical)
makealign(tok: ref Token) : Align
{
	h := atabbval(tok, LX->Aalign, align_tab, Anone);
	v := atabbval(tok, LX->Avalign, align_tab, Anone);
	return Align(h, v);
}

# Make a Dimen, based on value of attid attr
makedimen(tok: ref Token, attid: int) : Dimen
{
	kind := Dnone;
	spec := 0;
	(fnd, wd) := tok.aval(attid);
	if(fnd)
		return parsedim(wd);
	else
		return Dimen.make(Dnone, 0);
}

# Parse s as num[.[num]][unit][%|*]
parsedim(s: string) : Dimen
{
	kind := Dnone;
	spec := 0;
	(l,r) := S->splitl(s, "^0-9");
	if(l != "") {
		# accumulate 1000 * value (to work in fixed point)
		spec = 1000 * toint(l);
		if(S->prefix(".", r)) {
			f : string;
			(f,r) = S->splitl(r[1:], "^0-9");
			if(f != "") {
				mul := 100;
				for(i := 0; i < len f; i++) {
					spec = spec + mul * toint(f[i:i+1]);
					mul = mul / 10;
				}
			}
		}
		kind = Dpixels;
		if(r != "") {
			if(len r >= 2) {
				Tkdpi := 100;	# hack, but matches current tk
				units := r[0:2];
				r = r[2:];
				case units {
				"pt" => spec = (spec*Tkdpi)/72;
				"pi" => spec = (spec*12*Tkdpi)/72;
				"in" => spec = spec*Tkdpi;
				"cm" => spec = (spec*100*Tkdpi)/254;
				"mm" => spec = (spec*10*Tkdpi)/254;
				"em" => spec = spec * 15;	# hack, lucidasans 8pt is 15 pixels high
				* =>
					if(warn)
						sys->print("warning: unknown units %s\n", units);
				}
			}
			if(r == "%")
				kind = Dpercent;
			else if(r == "*")
				kind = Drelative;
		}
		spec = spec / 1000;
	}
	else if(r == "*") {
		spec = 1;
		kind = Drelative;
	}
	return Dimen.make(kind, spec);
}

dimlist(tok: ref Token, attid: int) : array of Dimen
{
	s := aval(tok, attid);
	if(s != "") {
		(nc, cl) := sys->tokenize(s, ", ");
		if(nc > 0) {
			d := array[nc] of Dimen;
			for(k := 0; k < nc; k++) {
				d[k] = parsedim(hd cl);
				cl = tl cl;
			}
			return d;
		}
	}
	return nil;
}

stringdim(d: Dimen) : string
{
	ans := string d.spec();
	k := d.kind();
	if(k == Dpercent)
		ans += "%";
	if(k == Drelative)
		ans += "*";
	return ans;
}

stringalign(a: byte) : string
{
	s := T->revlookup(align_tab, int a);
	if(s == nil)
		s = "none";
	return s;
}

stringstate(state: int) : string
{
	s := "";
	if(state&IFbrk) {
		c := state&(IFcleft|IFcright);
		clr := "";
		if(int c) {
			if(c == (IFcleft|IFcright))
				clr = " both";
			else if(c == IFcleft)
				clr = " left";
			else
				clr = " right";
		}
		amt := 0;
		if(state&IFbrksp)
			amt = 1;
		s = sys->sprint("brk(%d%s)", amt, clr);
	}
	if(state&IFnobrk)
		s += " nobrk";
	if(!(state&IFwrap))
		s += " nowrap";
	if(state&IFrjust)
		s += " rjust";
	if(state&IFcjust)
		s += " cjust";
	if(state&IFsmap)
		s += " smap";
	indent := (state&IFindentmask)>>IFindentshift;
	if(indent > 0)
		s += " indent=" + string indent;
	hang := state&IFhangmask;
	if(hang > 0)
		s += " hang=" + string hang;
	return s;
}

Item.newtext(s: string, fnt, fg, voff: int, ul: byte) : ref Item
{
	return ref Item.Itext(nil, 0, 0, 0, 0, 0, nil, s, fnt, fg, byte voff, ul);
}

Item.newrule(align: byte, size, noshade: int, wspec: Dimen) : ref Item
{
	return ref Item.Irule(nil, 0, 0, 0, 0, 0, nil, align, byte noshade, size, wspec);
}

Item.newimage(di: ref Docinfo, src: ref Parsedurl, lowsrc: ref Parsedurl, altrep: string,
	align: byte, width, height, hspace, vspace, border, ismap, isbkg: int,
	map: ref Map, name: string, genattr: ref Genattr) : ref Item
{
	ci := CImage.new(src, lowsrc, width, height);
	state := 0;
	if(ismap)
		state = IFsmap;
	if (isbkg)
		state = IFbkg;
	return ref Item.Iimage(nil, 0, 0, 0, 0, state, genattr, len di.images,
			ci, width, height, altrep, map, name, -1, align, byte hspace, byte vspace, byte border);
}

Item.newformfield(ff: ref Formfield) : ref Item
{
	return ref Item.Iformfield(nil, 0, 0, 0, 0, 0, nil, ff);
}

Item.newtable(t: ref Table) : ref Item
{
	return ref Item.Itable(nil, 0, 0, 0, 0, 0, nil, t);
}

Item.newfloat(it: ref Item, side: byte) : ref Item
{
	return ref Item.Ifloat(nil, 0, 0, 0, 0, IFwrap, nil, it, 0, 0, side, byte 0);
}

Item.newspacer(spkind, font: int) : ref Item
{
	return ref Item.Ispacer(nil, 0, 0, 0, 0, 0, nil, spkind, font);
}

Item.revlist(itl: list of ref Item) : list of ref Item
{
	ans : list of ref Item = nil;
	for( ;itl != nil; itl = tl itl)
		ans = hd itl :: ans;
	return ans;
}

Item.print(it: self ref Item)
{
	s := stringstate(it.state);
	if(s != "")
		sys->print("%s\n",s);
	pick a := it {
	Itext =>
		sys->print("Text '%s', fnt=%d, fg=%x", a.s, a.fnt, a.fg);
	Irule =>
		sys->print("Rule wspec=%s, size=%d, al=%s",
			stringdim(a.wspec), a.size, stringalign(a.align));
	Iimage =>
		src := "";
		if(a.ci.src != nil)
			src = a.ci.src.tostring();
		map := "";
		if(a.map != nil)
			map = a.map.name;
		sys->print("Image src=%s, alt=%s, al=%s, w=%d, h=%d hsp=%d, vsp=%d, bd=%d, map=%s, name=%s",
			src, a.altrep, stringalign(a.align), a.imwidth, a.imheight,
			int a.hspace, int a.vspace, int a.border, map, a.name);
	Iformfield =>
		ff := a.formfield;
		if(ff.ftype == Ftextarea)
			ty := "textarea";
		else if(ff.ftype == Fselect)
			ty = "select";
		else
			ty = T->revlookup(input_tab, int ff.ftype);
		sys->print("Formfield %s, fieldid=%d, formid=%d, name=%s, value=%s",
			ty, ff.fieldid, int ff.form.formid, ff.name, ff.value);
	Itable =>
		tab := a.table;
		sys->print("Table tableid=%d, width=%s, nrow=%d, ncol=%d, ncell=%d, totw=%d, toth=%d\n",
			tab.tableid, stringdim(tab.width), tab.nrow, tab.ncol, tab.ncell, tab.totw, tab.toth);
		for(cl := tab.cells; cl != nil; cl = tl cl) {
			c := hd cl;
			c.content.printlist(sys->sprint("Cell %d.%d, at (%d,%d)", tab.tableid, c.cellid, c.row, c.col));
		}
		sys->print("End of Table %d", tab.tableid);
	Ifloat =>
		sys->print("Float, x=%d y=%d, side=%s, it=", a.x, a.y, stringalign(a.side));
		a.item.print();
		sys->print("\n\t");
	Ispacer =>
		s = "";
		case a.spkind {
		ISPnull =>
			s = "null";
		ISPvline =>
			s = "vline";
		ISPhspace =>
			s = "hspace";
		}
		sys->print("Spacer %s ", s);
	}
	sys->print(" w=%d, h=%d, a=%d, anchor=%d\n", it.width, it.height, it.ascent, it.anchorid);
}

Item.printlist(items: self ref Item, msg: string)
{
	sys->print("%s\n", msg);
	il := items;
	while(il != nil) {
		il.print();
		il = il.next;
	}
}

Formfield.new(ftype, fieldid: int, form: ref Form, name, value: string, size, maxlength: int) : ref Formfield
{
	return ref Formfield(ftype, fieldid, form, name, value, size,
				maxlength, 0, 0, byte 0, nil, nil, -1, nil, 0);
}

Form.new(formid: int, name: string, action: ref Parsedurl, target: string, method: int, events: list of Lex->Attr) : ref Form
{
	return ref Form(formid, name, action, target, method, events, 0, 0, nil, FormBuild);
}

Table.new(tableid: int, align: Align, width: Dimen,
		border, cellspacing, cellpadding: int, bg: Background, tok: ref Lex->Token) : ref Table
{
	return ref Table(tableid,
			0, 0, 0,		# nrow, ncol, ncell
			align, width, border, cellspacing, cellpadding, bg,
			nil, Abottom, -1,	# caption, caption_place, caption_lay
			nil, nil, nil,	nil,	# currows, cols, rows, cells
			0, 0, 0, 0,		# totw, toth, caph, availw
			nil, tok, byte 0);	# grid, tabletok, flags
}

Tablerow.new(align: Align, bg: Background, flags: byte) : ref Tablerow
{
	return ref Tablerow(nil,	# cells
			0, 0,			# height, ascent
			align,		# align
			bg,			# background
			Point(0,0),		# pos
			flags);
}

Tablecell.new(cellid, rowspan, colspan: int, align: Align, wspec: Dimen,
			hspec: int, bg: Background, flags: byte) : ref Tablecell
{
	return ref Tablecell(cellid,
			nil, -1,		# content, layid
			rowspan, colspan, align, flags, wspec, hspec, bg,
			0, 0, 0,		# minw, maxw, ascent
			0, 0,			# row, col
			Point(0,0));	# pos
}

Dimen.kind(d: self Dimen) : int
{
	return (d.kindspec & Dkindmask);
}

Dimen.spec(d: self Dimen) : int
{
	return (d.kindspec & Dspecmask);
}

Dimen.make(kind, spec: int) : Dimen
{
	if(spec & Dkindmask) {
		if(warn)
			sys->print("warning: dimension spec too big: %d\n", spec);
		spec = 0;
	}
	return Dimen(kind | spec);
}

Map.new(name: string) : ref Map
{
	return ref Map(name, nil);
}

Docinfo.new() : ref Docinfo
{
	ans := ref Docinfo;
	ans.reset();
	return ans;
}

Docinfo.reset(d: self ref Docinfo)
{
	d.src = nil;
	d.base = nil;
	d.referrer = nil;
	d.doctitle = "";
	d.backgrounditem = nil;
	d.background = (nil, CU->White);
	d.text = CU->Black;
	d.link = CU->Blue;
	d.vlink = CU->Blue;
	d.alink = CU->Blue;
	d.target = "_self";
	d.refresh = "";
	d.chset = (CU->config).charset;
	d.lastModified = "";
	d.scripttype = CU->TextJavascript;
	d.hasscripts = 0;
	d.events = nil;
	d.evmask = 0;
	d.kidinfo = nil;
	d.frameid = -1;

	d.anchors = nil;
	d.dests = nil;
	d.forms = nil;
	d.tables = nil;
	d.maps = nil;
	d.images = nil;
}

Kidinfo.new(isframeset: int) : ref Kidinfo
{
	ki := ref Kidinfo(isframeset,
			nil,		# src
			"",		# name
			0, 0, 0,	# marginw, marginh, framebd
			0,		# flags
			nil, nil, nil	# rows, cols, kidinfos
			);
	if(!isframeset) {
		ki.flags = FRhscrollauto|FRvscrollauto;
		ki.marginw = FRKIDMARGIN;
		ki.marginh = FRKIDMARGIN;
		ki.framebd = 1;
	}
	return ki;
}
