implement Stylesheet;

include "sys.m";
	sys: Sys;
include "stylesheet.m";
include "strmap.m";
	strmap: Strmap;
	Map: import strmap;
include "cssparser.m";
	Decl: import CSSparser;

stylemap: ref Map;
numstyles: int;

RULEHASH:	con 23;

# specificity:
# bits 0-26	declaration order
# bit 27		class count	(0 or 1)
# bit 28		tagname count	(0 or 1)
# bit 28		id count		(0 or 1)	(inline style only)
# bit 29-30	origin		(0, 1 or 2 - default, reader, author)	
# bit 31		importance

# order of these as implied by CSS1 §3.2
TAG,
CLASS,
ID:			con 1 << (iota + 26);
ORIGINSHIFT:	con 29;
IMPORTANCE:	con 1<<30;

init(a: array of string)
{
	sys = load Sys Sys->PATH;
	strmap = load Strmap Strmap->PATH;
	if (strmap == nil) {
		sys->fprint(sys->fildes(2), "stylesheet: cannot load %s: %r\n", Strmap->PATH);
		raise "fail:bad module";
	}
	stylemap = Map.new(a);
	numstyles = len a;
}

Sheet.new(): ref Sheet
{
	return ref Sheet(array[RULEHASH] of list of Rule, 0);
}

Sheet.addrules(sheet: self ref Sheet, rules: list of (string, list of Decl), origin: int)
{
	origin <<= ORIGINSHIFT;
	for (; rules != nil; rules = tl rules) {
		(sel, decls) := hd rules;
		(tag, class) := selector(sel);
		(key, sub) := (tag, "");
		specificity := sheet.ruleid++;
		if (tag != nil)
			specificity |= TAG;
		if (class != nil) {
			specificity |= CLASS;
			(key, sub) = ("." + class, tag);
		}
		specificity |= origin;

		attrs: list of (int, int, string);
		for (; decls != nil; decls = tl decls) {
			d := mkdecl(hd decls, specificity);
			if (d.attrid != -1)
				attrs = d :: attrs;
		}

		n := hashfn(key, RULEHASH);
		sheet.rules[n] = (key, sub, attrs) :: sheet.rules[n];
	}
}

# assume selector is well-formed, having been previously parsed.
selector(s: string): (string, string)
{
	for (i := 0; i < len s; i++)
		if (s[i] == '.')
			break;
	if (i == len s)
		return (s, nil);
	return (s[0:i], s[i + 1:]);
}


Sheet.newstyle(sheet: self ref Sheet): ref Style
{
	return ref Style(sheet, array[numstyles] of string, array[numstyles] of {* => 0});
}

adddecl(style: ref Style, d: Ldecl)
{
	if (d.specificity > style.spec[d.attrid]) {
		style.attrs[d.attrid]  = d.val;
		style.spec[d.attrid] = d.specificity;
	}
}

Style.add(style: self ref Style, tag, class: string)
{
	rules := style.sheet.rules;
	if (class != nil) {
		key := "." + class;
		v := hashfn(key, RULEHASH);
		for (r := rules[v]; r != nil; r = tl r)
			if ((hd r).key == key && ((hd r).sub == nil || (hd r).sub == tag))
				for (decls := (hd r).decls; decls != nil; decls = tl decls)
					adddecl(style, hd decls);
	}
	v := hashfn(tag, RULEHASH);
	for (r := rules[v]; r != nil; r = tl r)
		if ((hd r).key == tag)
			for (decls := (hd r).decls; decls != nil; decls = tl decls)
				adddecl(style, hd decls);
}

# add a specific set of attributes to a style;
# attrs is list of (attrname, important, val).
Style.adddecls(style: self ref Style, decls: list of Decl)
{
	specificity := ID | (AUTHOR << ORIGINSHIFT);
	for (; decls != nil; decls = tl decls) {
		d := mkdecl(hd decls, specificity);
		if (d.attrid != -1)
			adddecl(style, d);
	}
}

Style.addone(style: self ref Style, attrid: int, origin: int, val: string)
{
	# XXX specificity is probably wrong here.
	adddecl(style, (attrid, origin << ORIGINSHIFT, val));
}

# convert a declaration from extern (attrname, important, val) form
# to intern (attrid, specificity, val) form.
# XXX could warn for unknown attribute here...
mkdecl(d: Decl, specificity: int): Ldecl
{
	if (d.important)
		specificity |= IMPORTANCE;
	return (stylemap.i(d.name), specificity, d.val);
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
