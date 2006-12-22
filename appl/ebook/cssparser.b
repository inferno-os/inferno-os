implement CSSparser;

include "sys.m";
	sys: Sys;
include "string.m";
	str: String;
include "css.m";
	css: CSS;
	Stylesheet, Statement, Select, Value: import css;
include "cssparser.m";

init()
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	css = load CSS CSS->PATH;
	if (css == nil) {
		sys->fprint(sys->fildes(2), "cssparser: cannot load %s: %r\n", CSS->PATH);
		raise "fail:bad module";
	}
	css->init(1);
}

parse(s: string): list of (string, list of Decl)
{
	(stylesheet, e) := css->parse(s);
	if (stylesheet == nil) {
		warning("error parsing stylesheet: " + e);
		return nil;
	}
	rules, r: list of (string, list of Decl);
	for (stl := stylesheet.statements; stl != nil; stl = tl stl) {
		pick st := hd stl {
		Ruleset =>
			rules = ruleset2rule(st, rules);
		}
	}
	for (; rules != nil; rules = tl rules)
		r = hd rules :: r;
	return r;
}

ruleset2rule(statement: ref Statement.Ruleset, onto: list of (string, list of Decl)): list of (string, list of Decl)
{
	d := makedecls(statement.decls);
	
	names: list of string;
	for (sels := statement.selectors; sels != nil; sels = tl sels) {
		csel := hd sels;
		if (len csel != 1) {
			warning("context-specific selectors not allowed");
			continue;
		}
		(nil, l) := hd csel;
		if ((name := selector2name(l)) != nil)
			names = name :: names;
	}
	for (; names != nil; names = tl names)
		onto = (hd names, d) :: onto;
	
	return onto;
}

makedecls(decls: list of ref CSS->Decl): list of Decl
{
	d: list of Decl;
	for (; decls != nil; decls = tl decls) {
		nd: Decl;
		nd.name = (hd decls).property;
		nd.important = (hd decls).important;
		s := "";
		for (vals := (hd decls).values; vals != nil; vals = tl vals) {
			vs: string;
			pick v := hd vals {
			Percentage =>
				vs = v.value + "%";
			String or
			Number or
			Url or
			Unicoderange =>
				vs = v.value;
			Hexcolour =>
				vs = rgb2s(v.rgb);
			RGB =>
				vs = rgb2s(v.rgb);
			Ident =>
				vs = v.name;
			Unit =>
				vs = v.value + v.units;
			}
			if (s != nil)
				s[len s] = (hd vals).sep;
			s += vs;
		}
		nd.val = s;
		d = nd :: d;
	}
	return d;
}

rgb2s(rgb: (int, int, int)): string
{
	(r, g, b) := rgb;
	return sys->sprint("#%.2x%.2x%.2x", r, g, b);
}

warning(s: string)
{
	sys->fprint(sys->fildes(2), "cssparser: %s\n", s);
}

selector2name(sel: list of ref Select): string
{
	tag: string;
	class: string;
	pseudo: string;

	for (; sel != nil; sel = tl sel) {
		pick v := hd sel {
		Element =>
			tag = v.name;
		Class =>
			class = "." + v.name;
		Pseudo =>
			class = ":" + v.name;
		* =>
			warning("unknown selector type " + string tagof(hd sel));
		}
	}
	return tag + class + pseudo;
}

parsedecl(s: string): list of Decl
{
	if (s == nil)
		return nil;
	(d, e) := css->parsedecl(s);
	if (d == nil) {
		warning(e);
		return nil;
	}
	return makedecls(d);
}
