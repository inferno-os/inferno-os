implement Reader;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Image, Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "wmlib.m";
	wmlib: Wmlib;
include "string.m";
	str:	String;
include "imagefile.m";
include "xml.m";
	xml: Xml;
	Attributes, Locator, Parser, Item: import xml;
include "strmap.m";
	strmap: Strmap;
	Map: import strmap;
include "hash.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "mimeimage.m";
	mimeimage: Mimeimage;
include "cssparser.m";
	cssparser: CSSparser;
include "cssfont.m";
	cssfont: CSSfont;
include "stylesheet.m";
	stylesheet: Stylesheet;
	Style, Sheet: import stylesheet;
include "table.m";
	table: Table;
include "url.m";
	url: Url;
	ParsedUrl: import url;
include "units.m";
	units: Units;
include "reader.m";

# TO DO:
# - image links.
# - client-side image maps
# - subscript, superscript (which css attributes do they correspond to?)
# - limit the size of the image cache.

stderr: ref Sys->FD;
maxblockid := 0;		# assume that increments of this are atomic

OEBpkgtype: con "http://openebook.org/dtds/oeb-1.0.1/oebpkg101.dtd";
OEBdoctype: con "http://openebook.org/dtds/oeb-1.0.1/oebdoc101.dtd";
OEBpkg, OEBdoc: con iota;
Laxchecking: con 1;

RULE: con 'r';
TABLE: con 'b';
TEXT: con 't';
IMAGE: con 'i';
MARK: con 'm';
VSPACE: con 'v';

INDENT: con 20;

Sbackground_color,
Sborder,			# none, solid, dotted, dashed, double, groove, ridge, inset, outset, [thin, medium, thick, <abs size>]
#Sclear,			# none, left, right, both
Scolor,
#Sdisplay,			# block, inline, none, oeb-page-head, oeb-page-foot
#Sfloat,			# left, right, none
Sfont_family,		# serif, sans-serif, monospace
Sfont_size,		# xx-small...xx-large, smaller, larger, <abs size>
Sfont_style,		# normal, italic
Sfont_weight,		# normal, bold
Sheight,
Sline_height,		# normal, <number>, <length>
Slist_style_type,	# decimal, lower-roman, upper-roman, lower-alpha, upper-alpha, none
Smargin_bottom,
Smargin_top,
Smargin_left,
Smargin_right,
# Soeb_column_number,	# auto, 1
# Spage_break_before,	# auto, always, left, right
# Spage_break_inside,	# auto, avoid
Stext_align,		# left, right, center, justify
Stext_decoration,		# none, underline, line-through
Stext_indent,
Svertical_align,		# top, middle, bottom
Swidth,
Snumstyles: con iota;

stylenames := array[] of {
	Sbackground_color => "background-color",
	Sborder => "border",
#	Sclear => "clear",
	Scolor => "color",
#	Sdisplay => "display",
#	Sfloat => "float",
	Sfont_family => "font-family",
	Sfont_size => "font-size",
	Sfont_style => "font-style",
	Sfont_weight => "font-weight",
	Sheight => "height",
	Sline_height => "line-height",
	Slist_style_type => "list-style-type",
	Smargin_bottom => "margin-bottom",
	Smargin_left => "margin-left",
	Smargin_right => "margin-right",
	Smargin_top => "margin-top",
#	Soeb_column_number => "oeb-column-number",
#	Spage_break_before => "page-break-before",
#	Spage_break_inside => "page-break-inside",
	Stext_align => "text-align",
	Stext_decoration => "text-decoration",
	Stext_indent => "text-indent",
	Svertical_align => "vertical-align",
	Swidth => "width",
};

# constants for %flow elements
Ea, Eb, Ebig, Eblockquote, Ebr, Ecenter, Ecite, Ecode, Edfn,
Ediv, Edl, Eem, Efont, Eh1, Eh2, Eh3, Eh4, Eh5, Eh6, Ehr, Ei, Eimg,
Einput, Ekbd, Elabel, Emap, Eobject, Eol, Ep, Epre, Eq, Es, Esamp,
Escript, Eselect, Esmall, Espan, Estrike, Estrong, Esub, Esup, Etable,
Ett, Eu, Eul, Evar, Ent, Enumflowtags: con iota;

flownames := array[] of {
	Ea => "a",
	Eb => "b",
	Ebig => "big",
	Eblockquote => "blockquote",
	Ebr => "br",
	Ecenter => "center",
	Ecite => "cite",
	Ecode => "code",
	Edfn => "dfn",
	Ediv => "div",
	Edl => "dl",
	Eem => "em",
	Efont => "font",
	Eh1 => "h1",
	Eh2 => "h2",
	Eh3 => "h3",
	Eh4 => "h4",
	Eh5 => "h5",
	Eh6 => "h6",
	Ehr => "hr",
	Ei => "i",
	Eimg => "img",
	Einput => "input",
	Ekbd => "kbd",
	Elabel => "label",
	Emap => "map",
	Eobject => "object",
	Eol => "ol",
	Ep => "p",
	Epre => "pre",
	Eq => "q",
	Es => "s",
	Esamp => "samp",
	Escript => "script",
	Eselect => "select",
	Esmall => "small",
	Espan => "span",
	Estrike => "strike",
	Estrong => "strong",
	Esub => "sub",
	Esup => "sup",
	Etable => "table",
	Ett => "tt",
	Eu => "u",
	Eul => "ul",
	Evar => "var",
};
tagmap: ref Map;

isblocklevel := array[Enumflowtags] of {
	* => byte 0,
	Eul => byte 1,
	Eol => byte 1,
	Eh1 => byte 1,
	Eh2 => byte 1,
	Eh3 => byte 1,
	Eh4 => byte 1,
	Eh5 => byte 1,
	Eh6 => byte 1,
	Epre => byte 1,
	Edl => byte 1,
	Ediv => byte 1,
	Ecenter => byte 1,
	Eblockquote => byte 1,
	Ehr => byte 1,
	Etable => byte 1,
	Ep => byte 1,
};

inherited := array[Snumstyles] of {
	Scolor => byte 1,
	Sfont_family => byte 1,
	Sfont_size => byte 1,
	Sfont_style => byte 1,
	Sfont_weight => byte 1,
	Sline_height => byte 1,
	Slist_style_type => byte 1,
#	Soeb_column_number => byte 1,
#	Spage_break_before => byte 1,
#	Spage_break_inside => byte 1,
	Stext_align => byte 1,
	Stext_decoration => byte 1,
	Stext_indent => byte 1,
};

defaults := array[] of {
	Sborder => "solid",
	Scolor => "black",
	Sfont_family => "sans-serif",
	Sfont_size => "medium",
	Sfont_weight => "normal",
	Sfont_style => "normal",
	Sheight => "normal",
	Sline_height => "normal",
	Slist_style_type => "none",
#	Soeb_column_number => "auto",	# ?
#	Spage_break_before => "auto",	# ?
	Stext_decoration => "none",
};

badmodule(p: string)
{
	sys->fprint(stderr, "reader: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init(displ: ref Draw->Display)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	tk = load Tk Tk->PATH;
	draw = load Draw Draw->PATH;

	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil)
		badmodule(Wmlib->PATH);

	str = load String String->PATH;
	if (str == nil)
		badmodule(String->PATH);

	xml = load Xml Xml->PATH;
	if (xml == nil)
		badmodule(Xml->PATH);
	xml->init();

	mimeimage = load Mimeimage Mimeimage->PATH;
	if (mimeimage == nil)
		badmodule(Mimeimage->PATH);
	mimeimage->init(displ);

	url = load Url Url->PATH;
	if (url == nil)
		badmodule(Url->PATH);
	url->init();

	cssparser = load CSSparser CSSparser->PATH;
	if (cssparser == nil)
		badmodule(CSSparser->PATH);
	cssparser->init();

	cssfont = load CSSfont CSSfont->PATH;
	if (cssfont == nil)
		badmodule(CSSfont->PATH);
	cssfont->init(displ);

	stylesheet = load Stylesheet Stylesheet->PATH;
	if (stylesheet == nil)
		badmodule(Stylesheet->PATH);
	stylesheet->init(stylenames);

	table = load Table Table->PATH;
	if (table == nil)
		badmodule(Table->PATH);
	table->init();

	units = load Units Units->PATH;
	if (units == nil)
		badmodule(Units->PATH);
	units->init();

	strmap = load Strmap Strmap->PATH;
	if (strmap == nil)
		badmodule(Strmap->PATH);

	tagmap = Map.new(flownames);
}

blankdatasource: Datasource;

Datasource.new(f: string, fallbacks: list of (string, string), win: ref Tk->Toplevel, width: int, evch: string,
		warningch: chan of (Locator, string)): (ref Datasource, string)
{
	d := ref blankdatasource;
	(x, e) := xml->open(f, warningch, "pre");
	if (x == nil)
		return (nil, e);
	d.x = x;
	d.warningch = warningch;
	d.fallbacks = fallbacks;
	d.win = win;
	d.width = width;
	d.filename = f;
	d.evch = evch;
	d.stylesheet = Sheet.new();
	style := d.stylesheet.newstyle();
	style.attrs[0:] = defaults;
	d.styles = style :: nil;
	d.fontinfo = ref Fontinfo(nil, 0, 0) :: nil;
	rules := cssparser->parse(readfile("/lib/ebook/default.css"));
	d.stylesheet.addrules(rules, Stylesheet->DEFAULT);
	{
		if ((e = startdocument(d)) != nil)
			return (nil, e);
		d.startmark = d.mark();
		return (d, nil);
	}
	exception{
		"error" =>
			return (nil, d.error);
	}
}

# make an independent copy of a datasource and rewind it to the beginning.
Datasource.copy(d: self ref Datasource): ref Datasource
{
	newd := ref *d;
	(x, e) := xml->open(d.filename, d.warningch, "pre");
	if (x == nil)
		error(d, "cannot copy " + d.filename + ": " + e);
	newd.x = x;
	newd.goto(d.startmark);
	return newd;
}

readfile(f: string): string
{
	if ((fd := sys->open(f, Sys->OREAD)) == nil)
		return nil;
	(ok, d) := sys->fstat(fd);
	if(ok < 0)
		return nil;
	if(d.length > big (128*1024))	# let's keep within bounds
		return nil;
	l := int d.length;
	buf := array[l] of byte;
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return nil;
	return string buf[0:n];
}

error(d: ref Datasource, e: string)
{
	d.error = sys->sprint("%s:%d: %s", d.x.loc.systemid, d.x.loc.line, e);
	raise "error";
}

warning(d: ref Datasource, e: string)
{
	if (d.warningch != nil)
		d.warningch <-= (d.x.loc, e);
	else
		sys->print("(nil warningch) %s\n", e);
}

Datasource.next(d: self ref Datasource, linkch: chan of (string, string, string)): (Block, string)
{
	{
		w := ".t" + string maxblockid++;
		d.t = Text.new(d.win, w, d.width, d.evch);
		d.t.style = hd d.styles;
		d.t.fontinfo = hd d.fontinfo;
		d.linkch = linkch;
		m := d.imark;
		if ((gi := d.item) == nil) {
			m = d.x.mark();
			gi = nextitem(d, 1);
		}
		d.item = nil;
		d.imark = nil;
		if (gi == nil) {
			cmd(d.win, "destroy " + w);
			return ((nil, 0, 0), d.error);
		}
		first := 1;
		for (;;) {
			pick i := gi {
			Text =>
				e_inline_text(d, i);
			Tag =>
				tagid := tagmap.i(i.name);
				if (tagid == -1) {
					warning(d, "unknown tag '" + i.name + "'; expected %flow");
					continue;
				}
				if (int isblocklevel[tagid]) {
					if (!first) {
						d.t.finalise(0);
						d.item = i;
						d.imark = m;
						b := Block(w, d.t.outertmargin, d.t.outerbmargin);
						d.t = nil;
						return (b, nil);
					}
					e_block(d, tagid, i);
				} else
					e_inline(d, tagid, i);
			}
			# XXX sending links when getting an item here is not correct,
			# as if it's a block level item with an id, then the link marker
			# will go at the end of the current block rather than the
			# beginning of the next block as it should.
			m = d.x.mark();
			gi = nextitem(d, 1);
			if (gi == nil) {
				d.t.finalise(0);
				b := Block(w, d.t.outertmargin, d.t.outerbmargin);
				d.t = nil;
				return (b, nil);
			}
			first = 0;
		}
	}
	exception{
		"error" =>
			return ((nil, 0, 0), d.error);
	}
}

Datasource.linestart(d: self ref Datasource, w: string, y: int): int
{
	if (w[1] == 't') {
		# given a text widget and a y-coord inside it, adjust the
		# y-coord so it refers to the start of the line holding the y-coord.
		(n, toks) := sys->tokenize(cmd(d.win, w + " dlineinfo @0," + string y), " ");
		if (n >= 5) {
			# dlineinfo gives fields: x y width height baseline
			return int hd tl toks;
		}
	}
	return y;
}

Datasource.linkoffset(d: self ref Datasource, w: string, m: string): int
{
	(n, toks) := sys->tokenize(cmd(d.win, w + " dlineinfo " + m), " ");
	if (n >= 5)
		return int hd tl toks;
	return -1;
}

# return a "best-effort" file offset 
#Datasource.fileoffsetnearyoffset(t: self ref Datasource, w: string, yoffset: int): int
Datasource.fileoffsetnearyoffset(nil: self ref Datasource, nil: string, nil: int): int
{
	# as we can't find out what embedded widget is at a given index,
	# we'll go first through all the embedded widgets checking to see which
	# ones are hit by the y-coord.
	return 0;
}

Datasource.rectforfileoffset(d: self ref Datasource, w: string, fileoffset: int): (int, Draw->Rect)
{
	r := Rect((0, 0), (0, 0));
	case widgettype(w) {
	IMAGE or
	MARK or
	RULE =>
		return (0, r);
	TABLE =>
#sys->print("rectforfileoffset requested for table...\n");
		return (0, r);
	TEXT =>
		# find greatest fileoffset in text less than fileoffset
		(nil, toks) := sys->tokenize(cmd(d.win, w + " tag names"), " ");
		max := -1;
		for (; toks != nil; toks = tl toks) {
			if ((hd toks)[0] == 'o') {
				o := int (hd toks)[1:];
				if (o <= fileoffset && o > max)
					max = o;
			}
		}
		if (max == -1)
			return (0, r);

		idx := cmd(d.win, w + " index o" + string max + ".first");

		# check whether we've hit an embedded widget.
		ew := tk->cmd(d.win, w + " window cget " + idx + " -window");
		if (ew[0] != '!') {
			(ok, t) := d.rectforfileoffset(ew, fileoffset);
			if (ok)
				t = t.addpt(s2r(cmd(d.win, w + " bbox " + idx)).min);
			return (ok, t);
		}

		idx = cmd(d.win, sys->sprint("%s index {%s + %d chars}",
				w, idx, fileoffset - max));
	
		# check that the offset index isn't beyond the end of the
		# range (in which case the offset we're looking for isn't
		# contained in this text widget.)
		if (int cmd(d.win, sys->sprint("%s compare %s >= o%d.last", w, idx, max)))
			return (0, ((0, 0), (0, 0)));

		r = s2r(cmd(d.win, w + " bbox " + idx));
		r.max = r.min.add(r.max);
		return (1, r);
	* =>
		sys->print("unknown widget type %s\n", w);
		return (0, r);
	}
}

# get file offset 
#Datasource.fileoffsetat(d: self ref Datasource, y: int): int
#{
#}	

Datasource.event(d: self ref Datasource, e: string): ref Event
{
	case e[0] {
	'l' =>
		return ref Event.Link(e[2:]);
	't' =>
		(nil, toks) := sys->tokenize(e, " ");
		toks = tl toks;
		w := hd toks;
		bd := int cmd(d.win, w + " cget -borderwidth");
		p := Point(int hd tl toks, int hd tl tl toks).
			sub((int cmd(d.win, w + " cget -actx") + bd, int cmd(d.win, w + " cget -acty") + bd));;
		i := cmd(d.win, sys->sprint("%s index @%d,%d", w, p.x, p.y));
		tags := cmd(d.win, w + " tag names " + i);
		(nil, toks) = sys->tokenize(tags, " ");
		for (; toks != nil; toks = tl toks)
			if ((hd toks)[0] == 'o')
				break;
		if (toks != nil && hd toks != "o-1") {
			idx := rangestart(d.win, w, hd toks, i);
			if (idx == nil)
				sys->print("couldn't find range start of %s\n", hd toks);
			else
				return ref Event.Texthit(
						int (hd toks)[1:] +
						len cmd(d.win, w + " get " + idx + " " + i)
					);
		}
	}
	return nil;
}

Datasource.mark(d: self ref Datasource): ref Mark
{
	if (d.item != nil) {
		if (d.imark == nil) {
			sys->print("oops, imark shouldn't be nil\n");
		}
		return ref Mark(d.imark);
	} else
		return ref Mark(d.x.mark());
}

Datasource.goto(d: self ref Datasource, m: ref Mark)
{
	d.x.goto(m.xmark);
	d.item = nil;
	d.imark = nil;
}

Datasource.fileoffset(d: self ref Datasource): int
{
	if (d.item != nil)
		return d.item.fileoffset;
	else
		return d.x.fileoffset;
}

# XXX this might not be correct in the presence of Mark.item
Datasource.atmark(d: self ref Datasource, m: ref Mark): int
{
	if (m == nil)
		return 0;
	return m.fileoffset() == d.fileoffset();
}

Datasource.str2mark(d: self ref Datasource, s: string): ref Mark
{
	m := d.x.str2mark(s);
	if (m == nil)
		return nil;
	return ref Mark(m);
}

Datasource.mark2str(nil: self ref Datasource, m: ref Mark): string
{
	return xml->m.xmark.str();
}

Mark.eq(m1: self ref Mark, m2: ref Mark): int
{
	if (m1 == nil || m2 == nil)
		return 0;
	return m1.fileoffset() == m2.fileoffset();
}

Mark.fileoffset(m: self ref Mark): int
{
	return m.xmark.offset;
}

rangestart(win: ref Tk->Toplevel, w: string, tag: string, idx: string): string
{
	# find the start of the range of _tag_ covering _idx_.

	# first find the end of the tag range.
	(nil, toks) := sys->tokenize(cmd(win, w + " tag nextrange " + tag + " " + idx), " ");
	if (toks == nil)
		return nil;

	# find the start of the tag range
	(nil, toks) = sys->tokenize(cmd(win, w + " tag prevrange " + tag + " " + hd tl toks), " ");
	if (toks == nil)
		return nil;
	return hd toks;
}

startdocument(d: ref Datasource): string
{
	(item, dtype, err) := xmldocument(d);
	if (err != nil)
		error(d, err);
	if (doctype(dtype, Laxchecking) != OEBdoc)
		error(d, "invalid document type: " + dtype);
	if (item == nil)
		error(d, "unexpected EOF");
	i: ref Item.Tag;
	pick xi := item {
	Tag =>
		i = xi;
	* =>
		i = nexttag(d, 0);
	}
	if (i == nil || i.name != "html")
		error(d, "no html body");
		
	down(d, i, 0);
	return starthtml(d);
}

# mostly pinched from oebpackage.b;
# return (item, dtd, error) where item is the first item that's not part of
# the prolog.
xmldocument(d: ref Datasource): (ref Item, string, string)
{
	dtd := "";
	x := d.x;
	for (xi := x.next(); xi != nil; xi = x.next()) {
		pick i := xi {
		Process =>
			if (i.target != "xml")
				return (nil, nil, "not an XML file");		# XXX actually according to spec, this declaration is optional.
		Text =>
			if (i.ch != nil)
				return (i, dtd, nil);
		Doctype =>
			if (!i.public || len i.params < 2)
				return (nil, nil, "invalid document type");
			dtd = hd tl i.params;
		Stylesheet =>
# XXX			etc etc.
		Error =>
			error(d, i.msg);		# XXX should show locator held in i, not as added by error()
		* =>
			return (xi, dtd, nil);
		}
	}
	return (nil, dtd, nil);
}
#
#	xi := x.next();
#	if(xi == nil)
#		return (nil, "not valid XML");
#	pick i := xi {
#	Process =>
#		if(i.target != "xml")
#			return (nil, "not an XML file");		# XXX actually according to spec, this declaration is optional.
#	* =>
#		return (nil, "unexpected file structure");
#	}
#
#	xi = x.next();
#	if (xi == nil)
#		return (nil, "invalid document");
#	if (tagof(xi) == tagof(Item.Text)) {		# XXX limbo compiler bug: tagof(Xml->Item.Text) is invalid.
#		xi = x.next();
#		if (xi == nil)
#			return (nil, "invalid document");
#	}
#	pick i := xi {
#	Doctype =>
#		if (!i.public || len i.params < 2)
#			return (nil, "invalid document type");
#		return (hd tl i.params, nil);
#	}
#	return (nil, "not OEB document (no DOCTYPE)");
#}

starthtml(d: ref Datasource): string
{
	# both <head> and <body> tags are optional, so if we
	# get something that's neither of them, then we assume
	# that we're in <body> and therefore need do no header processing.
	# that's probably wrong... how *can* <head> be optional
	# without arbitrary lookahead?

	# question: if a tag isn't explicitly there, but implied because it's
	# optional, does it still have style attributes applied to it?

	item: ref Item.Tag;
	startitem := nextnonblank(d, 0);
	if (startitem == nil)
		return nil;
	pick i := startitem {
	Tag =>
		if (i.name == "head" || i.name == "body")
			item = i;
	}
	if (item == nil) {
		d.item = startitem;
		return nil;
	}
	if (item.name == "body") {
		down(d, item, 0);
		return nil;
	}
	e_head(d, item);
	startitem = nextnonblank(d, 0);
	if (startitem == nil)
		return nil;
	pick i := startitem {
	Tag =>
		if (i.name == "body") {
			down(d, i, 0);
			return nil;
		}
	}
	d.item = startitem;
	return nil;
}

e_head(d: ref Datasource, i: ref Item.Tag)
{
	down(d, i, 0);
	while ((t0 := nexttag(d, 0)) != nil) {
		case t0.name {
		"title" =>
			e_title(d, t0);
		"link" =>
			e_link(d, t0);
		"style" =>
			e_style(d, t0);
		}
	}
	up(d, 0);
}

e_title(d: ref Datasource, i: ref Item.Tag)
{
	down(d, i, 0);
	t0 := nextnonblank(d, 0);
	if (t0 != nil) {
		pick t := t0 {
		Text =>
			d.title = t.ch;
		* =>
			warning(d, "invalid tag in title");
		}
	}
	up(d, 0);
}

e_style(d: ref Datasource, i: ref Item.Tag)
{
	ltype := i.attrs.get("type");
	if (ltype != "text/x-oeb1-css" && ltype != "text/css") {
		warning(d, "unknown stylesheet type " + ltype);
		return;
	}
	down(d, i, 0);
	t0 := nextnonblank(d, 0);
	if (t0 != nil) {
		pick t := t0 {
		Text =>
			d.stylesheet.addrules(cssparser->parse(t.ch), Stylesheet->AUTHOR);
		* =>
			warning(d, "invalid tag in style");
		}
	}
	up(d, 0);
}

e_link(d: ref Datasource, i: ref Item.Tag)
{
	rel := i.attrs.get("rel");
	ltype := i.attrs.get("type");
	where := i.attrs.get("href");

	if (rel != "stylesheet")
		return;
	if (ltype != "text/x-oeb1-css" && ltype != "text/css") {
		warning(d, "unknown stylesheet type " + ltype);
		return;
	}
	file := href(d.filename, where);
	if (file == nil) {
		warning(d, "cannot find stylesheet " + where);
		return;
	}
	
	rules := cssparser->parse(readfile(file));
	d.stylesheet.addrules(rules, Stylesheet->AUTHOR);
}
	

e_block(d: ref Datasource, tagid: int, i: ref Item.Tag)
{
	down(d, i, 1);

	case tagid {
	# %list
	Eul or
	Eol =>
		e_list(d, i);

	# %heading
	Eh1 or Eh2 or Eh3 or Eh4 or Eh5 or Eh6 =>
		e_inline_flow(d);

	Ediv or
	Ecenter or
	Eblockquote =>
		while ((fi := nextitem(d, 1)) != nil)
			e_flow(d, fi);

	# %preformatted
	Epre =>
		e_inline_flow(d);
	Edl =>
		e_dl(d, i);
	Ehr =>
		w := d.t.widgetname(RULE);
		width: int;
		a := (hd d.styles).attrs;
		if (a[Swidth] != nil)
			width = length(hd d.fontinfo, a[Swidth]);
		else
			width = d.width;
		cmd(d.win, "frame " + w + " -bg " + a[Scolor] +
				" -width " + string width + " -height 3");
		d.t.addwidget(w, i.fileoffset, 0);
	Etable =>
		e_table(d, i);
	Ep =>
		e_inline_flow(d);
	* =>
		warning(d, "unknown tag '" + i.name+ "'");
	}
	up(d, 1);
}

length(fi: ref Fontinfo, s: string): int
{
	return units->length(s, fi.em, fi.ex, nil).t0;
}

e_table(d: ref Datasource, i: ref Item.Tag)
{
	si := nexttag(d, 1);

	# optional caption (ignore)
	if (si != nil && si.name == "caption")
		si = nexttag(d, 1);

	if (si == nil) {
		warning(d, "empty table");
		return;
	}
	dim := Point(0, 0);		# table dimensions
	pos := Point(0, 0);		# current position in table
	celllist: list of (Point, ref Table->Cell);
	# XXX BUG table rows with ids all get marked at the top of the table.
	# would need to change the sendlink() scheme in order to fix that.
	# something like: datasource has a current "marking scheme";
	# in the case of the table widget the marking scheme creates a canvas
	# widget tagged after the id and the row/col numbers; this is then
	# placed into position when the table is laid out.
	rspan := array[10] of {* => 0};
	for (; si != nil; si = nexttag(d, 1)) {
		if (si.name != "tr") {
			warning(d, "non-tr tag <" + si.name + "> found in table body");
			continue;
		}
		down(d, si, 0);
		pos.x = 0;
		for (ti := nexttag(d, 1); ti != nil; ti = nexttag(d, 1)) {
			if (ti.name != "td" && ti.name != "th") {
				warning(d, "invalid cell <" + ti.name + "> in table");
				continue;
			}
			down(d, ti, 0);
			oldt := d.t;

			# XXX what do we do about text widget widths in table cells
			# where no width is specified?
			d.t = Text.new(d.t.win, oldt.widgetname(TEXT), 0, d.t.evch);
			d.t.style = oldt.style;
			d.t.fontinfo = oldt.fontinfo;
			for (t0 := nextitem(d, 1); t0 != nil; t0 = nextitem(d, 1))
				e_flow(d, t0);
			up(d, 0);
			d.t.finalise(1);

			span := Point(int ti.attrs.get("colspan"), int ti.attrs.get("rowspan"));
			if (span.x < 1)
				span.x = 1;
			if (span.y < 1)
				span.y = 1;

			# find a column it can go in.
			for (; pos.x < len rspan; pos.x++)
				if (rspan[pos.x] <= 0)
					break;
			celllist = (pos, table->newcell(d.t.w, span)) :: celllist;
			if (span.y > 1) {
				if (len rspan < pos.x + span.x)
					rspan = (array[pos.x + span.x] of int)[0:] = rspan;
				for (x := pos.x; x < pos.x + span.x; x++)
					rspan[x] = span.y;
			}
			pos.x += span.x;
			if (pos.y + span.y > dim.y)
				dim.y = pos.y + span.y;
			d.t = oldt;
		}
		if (pos.x > dim.x)
			dim.x = pos.x;
		pos.y++;
		for (x := 0; x < len rspan; x++)
			rspan[x]--;
		up(d, 0);
	}

	if (dim.y == 0 || dim.x == 0) {
		warning(d, "empty table");
		return;
	}
	cells := array[dim.x] of {* => array[dim.y] of ref Table->Cell};
	for (; celllist != nil; celllist = tl celllist) {
		(p, cell) := hd celllist;
		cells[p.x][p.y] = cell;
	}
	w := d.t.widgetname(TABLE);
	table->layout(cells, d.t.win, w);
	d.t.addwidget(w, i.fileoffset, 0);
}

e_flow(d: ref Datasource, gi: ref Item)
{
	pick i := gi {
	Text =>
		e_inline_text(d, i);
	Tag =>
		tagid := tagmap.i(i.name);
		if (tagid == -1)
			warning(d, "unkown tag '" + i.name + "'; expected %flow");
		else if (int isblocklevel[tagid])
			e_block(d, tagid, i);
		else
			e_inline(d, tagid, i);
	}
}

# (%inline;)*
e_inline_flow(d: ref Datasource)
{
	while ((gi := nextitem(d, 1)) != nil) {
		pick i := gi {
		Text =>
			e_inline_text(d, i);
		Tag =>
			e_inline(d, -1, i);
		}
	}
}

e_inline(d: ref Datasource, tagid: int, i: ref Item.Tag)
{
	if (tagid == -1)
		tagid = tagmap.i(i.name);
	case tagid {
	# %phrase
	Eem or
	Estrong or
	Edfn or
	Ecode or
	Esamp or
	Ekbd or
	Evar or
	Ecite or

	# %fontstyle
	Ett or
	Ei or
	Eb or
	Eu or
	Es or
	Estrike or
	Ebig or
	Esmall or
	Espan or
	Eq or
	Esub or
	Esup =>
		down(d, i, 0);
		e_inline_flow(d);
		up(d, 0);
	# %special
	Ea =>
		down(d, i, 0);
		if ((href := i.attrs.get("href")) != nil)
			d.t.href = " " + href;
		if ((name := i.attrs.get("name")) != nil)
			sendlink(d, name);
		e_inline_flow(d);
		d.t.href = nil;		# nesting of <a> not allowed so it's ok.
		up(d, 0);
	Eimg =>
		e_image(d, i);
	Eobject =>
		if (e_object(d, i) == -1) {
			down(d, i, 0);
			e_object_contents(d, i);
			up(d, 0);
		}
	Efont =>		
		;

	Ebr =>
		d.t.linebreak();	
	Escript or
	Emap =>
		sys->fprint(stderr, "script or map unimplemented\n");
		d.t.addtext("e_special", 1, 1, i.fileoffset);
	* =>
		warning(d, "invalid inline element '" + i.name + "'");
	}
}

e_image(d: ref Datasource, i: ref Item.Tag)
{
	file := href(d.filename, i.attrs.get("src"));
	if (file == nil) {
		warning(d, "cannot display image " + i.attrs.get("src"));
		return;
	}
	if ((w := image(d, nil, file)) == nil)
		return;
	d.t.addwidget(w, i.fileoffset, 0);
}

e_object(d: ref Datasource, i: ref Item.Tag): int
{
	(class, mtype) := mimetype(i.attrs.get("type"));
	if (class != "image")
		return -1;

	data := i.attrs.get("data");
	if (data == nil)
		return -1;

	file := href(d.filename, data);
	if (file == nil)
		return -1;

	if ((w := image(d, mtype, file)) == nil)
		return -1;
	d.t.addwidget(w, i.fileoffset, 0);
	return 0;
}

e_object_contents(d: ref Datasource, nil: ref Item.Tag)
{
	# PARAM tags should be before any data, according to comment in the dtd.
loop:
	while ((t0 := nextitem(d, 1)) != nil) {
		pick t1 := t0 {
		Tag =>
			if (t1.name != "param")
				break loop;
		* =>
			break loop;
		}
	}
	for (; t0 != nil; t0 = nextitem(d, 1))
		e_flow(d, t0);
}

# XXX this has not been implemented from the standard so it's probably wrong.
mimetype(s: string): (string, string)
{
	for (i := 0; i < len s; i++)
		if (s[i] == '/')
			break;
	if (i >= len s)
		return (s, nil);
	return (s[0:i], s[i+1:]);
}

# read an image and return it as a widgetname
image(d: ref Datasource, mediatype, f: string): string
{
	t := d.t;
	# XXX could make a special case here for pic images, as
	# they can be read directly by tk, hence faster & less space.
	if (tk->cmd(t.win, "image width " + f)[0] == '!') {
		# if it's not cached, create it.
		(img, e) := mimeimage->image(mediatype, f);
		if (img == nil) {
			# try fallback
			for (fall := d.fallbacks; fall != nil; fall = tl fall)
				if ((hd fall).t0 == f)
					return image(d, nil, (hd fall).t1);

			warning(d, sys->sprint("cannot read image %s: %s", f, e));
			return nil;
		}
		tk->cmd(t.win, "image create bitmap " + f);
		if ((e = tk->putimage(t.win, f, img, nil)) != nil) {
			warning(d, sys->sprint("imageput on %s failed: %s", f, e));
			return nil;
		}
	}
	w := t.widgetname(IMAGE);
	cmd(t.win, "label " + w + " -image " + f);
	if (t.href != nil) {
		cmd(t.win, "bind " + w + " <ButtonRelease-1> " +
			tk->quote("send " + t.evch + " ds l" + t.href));
	}
	return w;
}

sendlink(d: ref Datasource, name: string)
{
	if (d.linkch != nil) {
		# this won't work when we're embedded in a canvas.
		# N.B. it's crucial that name is non-nil!
		d.linkch <-= (name, d.t.w, d.t.addmark());
	} else {
		# you might not think that a zero-sized widget could make any
		# difference to the text layout, but you'd be wrong.
		d.t.addmark();
	}
}

e_inline_text(d: ref Datasource, i: ref Item.Text)
{
	d.t.addtext(i.ch, i.ws1, i.ws2, i.fileoffset);
}

# attributes that have percentage values that refer to the width of
# their enclosing block.  the whole thing is inevitably a crock.
# text-indent for example is supposed to take the width from its
# immediate ancestor...  whose width is probably determined by the
# assigned width.  eurgh.
blocksizerelative := array[] of {
	Sheight,
	Smargin_left,
	Smargin_right,
#	Smargin_top,
#	Smargin_bottom,
	Swidth,
	Stext_indent,
};

down(d: ref Datasource, i: ref Item.Tag, isblock: int)
{
#sys->print("down('%s', %d)\n", i.name, isblock);
	if (i == nil) {
		sys->print("nil tag\n");
		raise "oops";
	}
	d.x.down();
	d.tags = i :: d.tags;

	style := getstyle(d);
	a := style.attrs;
	fi := *(hd d.fontinfo);

	# make relative units into absolute units so that the derived
	#  values are inherited as per the standard.

	# font size is relative to the parent font size, not the current font size.
	fontsize := a[Sfont_size];
	if (units->isrelative(fontsize)) {
		(nil, fontsize) = units->length(fontsize, fi.em, fi.ex,
			(hd d.styles).attrs[Sfont_size]);
		a[Sfont_size] = fontsize;
	}

	# XXX later
	#	Sborder

	(path, em, ex) := cssfont->getfont((a[Sfont_family], a[Sfont_style],
			a[Sfont_weight], a[Sfont_size]), fi.em, fi.ex);
	# symbolic font names are turned into their size so we only
	# have to do the work once.
	if (fontsize != nil && (fontsize[0] < '0' || fontsize[0] > '9'))
		a[Sfont_size] = fontsize = string em + "px";

	# de-relativise widths
	for (j := 0; j < len blocksizerelative; j++) {
		attr := blocksizerelative[j];
		if (units->isrelative(a[attr]))
			(nil, a[attr]) = units->length(a[attr], em, ex, string d.width);
	}

	d.fontinfo = ref Fontinfo(path, em, ex) :: d.fontinfo;
	d.styles = style :: d.styles;
	if (d.t != nil) {
		d.t.fontinfo = hd d.fontinfo;
		d.t.style = style;
		if (isblock)
			d.t.startblock();
	}
}

up(d: ref Datasource, isblock: int)
{
	oldstyle: ref Stylesheet->Style;
	d.x.up();
#sys->print("up('%s', %d)\n", (hd d.tags).name, isblock);
	d.tags = tl d.tags;

	(oldstyle, d.styles) = (hd d.styles, tl d.styles);
	d.fontinfo = tl d.fontinfo;

	if (d.t != nil) {
		d.t.style = hd d.styles;
		d.t.fontinfo = hd d.fontinfo;
		if (isblock)
			d.t.endblock();
	}
}

# definition list
e_dl(d: ref Datasource, nil: ref Item.Tag)
{
	while ((li := nexttag(d, 1)) != nil) {
		if (li.name == "dt") {
			down(d, li, 1);
			e_inline_flow(d);
			up(d, 1);
		} else if (li.name == "dd") {
			down(d, li, 1);
			while ((i := nextitem(d, 1)) != nil)
				e_flow(d, i);
			up(d, 1);
		} else
			warning(d, "unexpected list element '" + li.name + "', expected <dt>");
	}
}

nexttag(d: ref Datasource, sendid: int): ref Item.Tag
{
	while ((gi := nextitem(d, sendid)) != nil) {
		pick i := gi {
		Tag =>
			return i;
		}
	}
	return nil;
}

nextnonblank(d: ref Datasource, sendid: int): ref Item
{
	while ((gi := nextitem(d, sendid)) != nil) {
		pick i := gi {
		Text =>
			if (i.ch != nil)
				return i;
		Tag =>
			return i;
		}
	}
	return nil;
}

nextitem(d: ref Datasource, sendid: int): ref Xml->Item
{
	for (;;) {
		if ((gi := d.x.next()) == nil)
			return nil;
		pick i := gi {
		Tag =>
			if (sendid && (id := i.attrs.get("id")) != nil)
				sendlink(d, id);
			return i;
		Text =>
			return i;
		Error =>
			error(d, i.msg);		# XXX should show locator held in i, not as added by error()
		Process =>
			sys->print("processing request: target: '%s'; data: '%s'\n",
				i.target, i.data);
			# XXX recognise some types of processing (e.g. stylesheets) here?
		Stylesheet =>
			# ignore it outside the prolog
		Doctype =>
			# ignore it outside the prolog
		* =>
			sys->print("reader: unknown tag of type %d\n", tagof(gi));
		}
	}
}

e_list(d: ref Datasource, nil: ref Item.Tag)
{
	n := 0;
	while ((li := nexttag(d, 1)) != nil) {
		if (li.name != "li") {
			warning(d, "unexpected list element '" + li.name + "'");
			continue;
		}
		down(d, li, 1);
		listheader(d.t, hd d.styles, n);
		while ((fi := nextitem(d, 1)) != nil)
			e_flow(d, fi);
		up(d, 1);
		n++;
	}
}

#what about inheritance vs. units.
#	e.g.
#	<ul style="font-size: 150%"><li style="font-size: 150%">hello</li></ul>
#	"hello" should come out 2.25 times the size of the font outside <ul>;
#
#	therefore all units must be resolved properly for each tag;
#	we can't just let them be lazy until the properties are actually needed.
#	hmm.
#
#	actually we only need to resolve relative elements, and those
#	measured with respect to current font size.
#
#	e.g. 150%, 10em, larger

listheader(t: ref Text, style: ref Style, n: int)
{
	s: string;
	case ty := style.attrs[Slist_style_type] {
	* or
	"disc" =>
		s = "•";
	"square" =>
		s = "∎";
	"circle" =>
		s = "∘";
	"decimal" =>
		s = string (n + 1) + ".";
	"lower-alpha" or
	"upper-alpha" =>
		let := 'A';
		if(ty[0] == 'l')
			let = 'a';
		a := ".";
		for(; n > 25; n /= 26)
			a[len a] = n%26 + let;
		for(i := len a; --i >= 0;)
			s[len s] = a[i];
	"lower-roman" or
	"upper-roman" =>
		if((s = roman(n)) == nil)
			s = sys->sprint("%d", n);	# better arabic than nothing
		s += ".";
		if (ty[0] == 'l')
			s = str->tolower(s);
	}
	s[len s] = ' ';
	t.addtext(s, 0, 0, -1);
}

#
# derived from Python function by Mark Pilgrim
#	``do ut des''
#
roman(n: int): string
{
	if(n <= 0 || n > 3999)
		return nil;
	map := array[] of {
			(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"),
			(90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"),
			(5, "V"), (4, "IV"), (1, "I")};
	s := "";
	for(i := 0; i < len map; i++){
		(m, v) := map[i];
		while(n >= m){
			s += v;
			n -= m;
		}
	}
	return s;
}

blanktext: Text;
Text.new(win: ref Tk->Toplevel, w: string, width: int, evch: string): ref Text
{
	t := ref blanktext;
	t.win = win;
	t.w = w;
	t.tags = array[23] of list of (string, int);
	t.startofline = 1;
	t.evch = evch;
	t.margins = t.margin :: nil;
	cmd(win, "text " + t.w +
		" -relief flat -bd 0 -propagate 1 " +
		" -wrap word -bg white");
	if (width > 0)
		cmd(win, t.w + " configure -width " + string width);
	cmd(win, t.w + " tag bind t <ButtonRelease-1> {send " + t.evch + " ds t %W %X %Y}");
#sys->print("****** new text %s\n", w);
	return t;
}

Text.addtext(t: self ref Text, text: string, ws1, ws2: int, fileoffset: int)
{
	if (text != nil) {
		if (t.needspace) {
			t.vspace(t.margin.b);
			t.margin.b = 0;
			t.needspace = 0;
		}
#sys->print("%s addtext '%s'\n", t.w, sanitise(text));
		s := t.w + " insert end ";

		# we add some leading whitespace if the last text added finished with whitespace
		# or this text starts with whitespace and this isn't the first item
		# on the line.
		if (ws1 && !t.startofline)
			text = " " + text;			# XXX might be faster to do two inserts.
		if (ws2)
			text += " ";
		s += tk->quote(text) + " {";
		s += t.gettag(textattrs(t)) + " o" + string fileoffset;
		if (t.href != nil)
			s += " " + t.gettag(t.href);
		else
			s += " t";
		s += "}";
		cmd(t.win, s);
		t.startofline = 0;
	}
	t.lastwhite = ws2;
}

sanitise(s: string): string
{
	if (len s > 30)
		s = s[0:30] + "...";
	return s;
}

Text.linebreak(t: self ref Text)
{
	cmd(t.win, t.w + " insert end {\n}");
	t.startofline = 1;
#sys->print("linebreak: startofline == 1\n");
	t.lastwhite = 0;
}

Text.startblock(t: self ref Text)
{
	a := t.style.attrs;
	m: Margin;
	m.b = length(t.fontinfo, a[Smargin_bottom]);
	m.l = length(t.fontinfo, a[Smargin_left]);
	m.r = length(t.fontinfo, a[Smargin_right]);
	m.textindent = length(t.fontinfo, a[Stext_indent]);

	tmargin := length(t.fontinfo, t.style.attrs[Smargin_top]);
	if (tl t.margins != nil) {
		# merge top and bottom margins
		if (t.margin.b > tmargin)
			tmargin = t.margin.b;
		t.vspace(tmargin);
	} else
		t.outertmargin = tmargin;

	t.margins = m :: t.margins;
	t.margin.l += m.l;
	t.margin.r += m.r;
	t.margin.textindent = m.textindent;
	t.margin.b = 0;
#	XXX check for margin overflow
# MINWIDTH: con 40;
#	if (t.lmargin + t.rmargin >= t.width)
}

Text.endblock(t: self ref Text)
{
	# spit out any left-over bottom margin
	if (t.needspace) {
		t.vspace(t.margin.b);
		t.needspace = 0;
	}
	m: Margin;
	(m, t.margins) = (hd t.margins, tl t.margins);
#sys->print("%s end block; bottom: %d, previous bottom: %d\n", t.w, m.b, t.margin.b);
	t.margin.l -= m.l;
	t.margin.r -= m.r;
	t.margin.b = m.b;
	t.margin.textindent = (hd t.margins).textindent;
	t.needspace = 1;
}

Text.finalise(t: self ref Text, addvspace: int)
{
	if (addvspace) {
		t.vspace(t.margin.b);
		t.margin.b = 0;
	}
	# get rid of any trailing newline (this doesn't work for null-sized text widgets.
	if (tk->cmd(t.win, t.w + " get {end - 1 chars} end") == "\n") {
#		sys->print("deleting last newline\n");
		cmd(t.win, t.w + " delete {end - 1 chars} end");
	}
	t.outerbmargin = t.margin.b;
}

Text.vspace(t: self ref Text, h: int)
{
#sys->print("vspace %d (startofline: %d)\n", h, t.startofline);
	if (!t.startofline)
		cmd(t.win, t.w + " insert end {\n}");
	if (h > 0) {
		# XXX this is unfortunately inefficient for something that's used so
		# much, but i can't think of another way of creating a line
		# of arbitrary height without adding a trailing newline
		# (which mucks things up at the end of the text widget).
		w := t.widgetname(VSPACE);
		cmd(t.win, "frame " + w + " -height " + string h); # + " -width 100 -bg red");
		tag :=  t.gettag("-lineheight " + string h);
		t.addwidget(w, -1, 1);
		cmd(t.win, t.w + " tag add " + tag + " {end - 1 chars}");
		cmd(t.win, t.w + " insert end {\n} " + tag);
	}
#sys->print("vspace: start of line: 1\n");
	t.startofline = 1;
	t.lastwhite = 0;
}

# add zero sized, invisible item to mark a place
# that can then be retrieved with linkoffset when
# the text widget has actually been rendered.
Text.addmark(t: self ref Text): string
{
	w := t.widgetname(MARK);
	cmd(t.win, "frame " + w);
	t.addwidget(w, -1, 1);
	return w;
}

widgettype(w: string): int
{
	for (i := len w - 1; i >= 0; i--) {
		c := w[i];
		if (c < '0' || c > '9')
			return c;
	}
	return '.';
}

Text.widgetname(t: self ref Text, c: int): string
{
	s := t.w + ".";
	s[len s] = c;
	return s + string t.max++;
}

Text.addwidget(t: self ref Text, w: string, fileoffset: int, invisible: int)
{
	align: string;
#	case t.style.attrs[Svertical_align] {
#	"top" =>
#		align = " -align top";
#	"bottom =>
#		align = " -align bottom";
#	"middle" =>
#		align = "-align center";
#	}
	cmd(t.win, t.w + " window create end -window " + w + align);
	# apparently no way to add tags to an embedded window when it's created.
	cmd(t.win, t.w + " tag add o" + string fileoffset + " " + w);
	t.startofline = !invisible;
#sys->print("addwidget: startofline %d\n", t.startofline);
}

getstyle(d: ref Datasource): ref Style
{
	style := d.stylesheet.newstyle();
	style.attrs[0:] = defaults;
	parent := hd d.styles;
	for (i := 0; i < len stylenames; i++)
		if (int inherited[i])
			style.attrs[i] = parent.attrs[i];

	# push inline style information here
	tag := hd d.tags;
	style.add(tag.name, tag.attrs.get("class"));
	style.adddecls(cssparser->parsedecl(tag.attrs.get("style")));
	return style;
}

# N.B. Text.gettag() relies on the fact that the string this returns
# starts with '-'
textattrs(t: ref Text): string
{
	a := t.style.attrs;
	s := "-font " + t.fontinfo.path +
		" -fg " + a[Scolor] +
		" -lmargin1 " + string (t.margin.textindent + t.margin.l) +
		" -lmargin2 " + string t.margin.l +
		" -rmargin " + string t.margin.r;
	v := a[Stext_decoration];
	if (v == "underline")
		s += " -underline 1";
	else if (v == "line-through")
		s += " -overstrike 1";
	v = a[Sline_height];
	if (v != "normal") {
		# special case: when line height is an unadorned number,
		# it is relative, but is inherited as is, not as derived, so we
		# need to derive the value here.
		# it's not clear whether the size should be proportional to the derived or
		# the specified font size; using the derived font size seems more reasonable.
		(l, nil) := units->length(v, 0, 0, string t.fontinfo.em + "px");
		s += " -lineheight " + string l;
	}

	v = a[Sbackground_color];
	if (v != nil)
		s += " -bg " + a[Sbackground_color];
	v = a[Stext_align];
	if (v != nil && v != "justify")
		s += " -justify " + v;
	return s;
}

# get a tag for a particular sort of text; if s begins with a '-', then it's a set
# of configuration options; otherwise it's a URL link (prefixed with a space)
Text.gettag(t: self ref Text, s: string): string
{
	v := hashfn(s, len t.tags);
	for (l := t.tags[v]; l != nil; l = tl l)
		if ((hd l).t0 == s)
			return "t" + string (hd l).t1;
	t.tags[v] = (s, t.max) :: t.tags[v];
	tag := "t" + string t.max++;
	if (s[0] == '-') {
		cmd(t.win, t.w + " tag configure " + tag + " " + s);
	} else {
		cmd(t.win, t.w + " tag bind " + tag + " <ButtonRelease-1> " +
			tk->quote("send " + t.evch + " ds l" + s));
	}
	return tag;
}

# XXX this isn't sufficient, in the presence of the object tag's codebase attribute.
href(fromfile: string, href: string): string
{
	(u, e) := makerelativeurl(fromfile, href);
	if (u == nil)
		return nil;
	return u.path;
}

# copied from ebook.b; XXX what module should implement this,
makerelativeurl(fromfile: string, href: string): (ref ParsedUrl, string)
{
	dir := "./";
	for(n := len fromfile; --n >= 0;) {
		if(fromfile[n] == '/') {
			dir = fromfile[0:n+1];
			break;
		}
	}
	u := url->makeurl(href);
	if(u.scheme != Url->FILE && u.scheme != Url->NOSCHEME)
		return (nil, sys->sprint("URL scheme %s not yet supported", url->schemes[u.scheme]));
	if(u.host != "localhost" && u.host != nil)
		return (nil, "non-local URLs not supported");
	path := u.path;
	if (path == nil)
		u.path = fromfile;
	else {
		if(u.pstart == "/")
			path = "/" + path;
		else
			path = dir+path;	# TO DO: security
		(ok, d) := sys->stat(path);
		if(ok < 0)
			return (nil, sys->sprint("'%s': %r", path));
		u.path = path;
	}
	return (u, nil);
}

s2r(s: string): Draw->Rect
{
	(n, toks) := sys->tokenize(s, " ");
	if (n != 4)
		return ((0, 0), (0, 0));
	r: Draw->Rect;
	(r.min.x, toks) = (int hd toks, tl toks);
	(r.min.y, toks) = (int hd toks, tl toks);
	(r.max.x, toks) = (int hd toks, tl toks);
	(r.max.y, toks) = (int hd toks, tl toks);
	return r;
}

doctype(s: string, lax: int): int
{
	case s {
	OEBpkgtype =>
		return OEBpkg;
	OEBdoctype =>
		return OEBdoc;
	* =>
		if (!lax)
			return -1;
		if (contains(s, "oebpkg1"))
			return OEBpkg;
		if (contains(s, "oebdoc1"));
			return OEBdoc;
		sys->print("'%s' doesn't contain '%s' or ''%s'\n", s, "oebpkg1", "oebdoc1");
		return -1;
	}
}

# does s1 contain s2
contains(s1, s2: string): int
{
	if (len s2 > len s1)
		return 0;
	n := len s1 - len s2 + 1;
search:
	for (i := 0; i < n ; i++) {
		for (j := 0; j < len s2; j++)
			if (s1[i + j] != s2[j])
				continue search;
		return 1;
	}
	return 0;
}
	

cmd(win: ref Tk->Toplevel, s: string): string
{
#	sys->print("	%s\n", s);
	r := tk->cmd(win, s);
#	sys->print("		-> %s\n", r);
	if (len r > 0 && r[0] == '!') {
		sys->fprint(stderr, "error executing '%s': %s\n", s, r);
		raise "tk error";
	}
	return r;
}

hashfn(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i:=0; i<m; i++){
		h = 65599*h+s[i];
	}
	return (h & 16r7fffffff) % n;
}
