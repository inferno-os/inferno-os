implement OEBpackage;

include "sys.m";
	sys: Sys;

include "bufio.m";

include "url.m";
	url: Url;
	ParsedUrl: import url;

include "xml.m";
	xml: Xml;
	Attributes, Locator, Parser: import xml;

include "oebpackage.m";

OEBpkgtype: con "http://openebook.org/dtds/oeb-1.0.1/oebpkg101.dtd";
OEBdoctype: con "http://openebook.org/dtds/oeb-1.0.1/oebdoc101.dtd";

OEBpkg, OEBdoc: con iota;
Laxchecking: con 1;

init(xmlm: Xml)
{
	sys = load Sys Sys->PATH;
	url = load Url Url->PATH;
	if(url != nil)
		url->init();
	xml = xmlm;
}

open(f: string, warnings: chan of (Xml->Locator, string)): (ref Package, string)
{
	(x, e) := xml->open(f, warnings, nil);
	if(x == nil)
		return (nil, e);
	xi := x.next();
	if(xi == nil)
		return (nil, "not valid XML");
	pick d := xi {
	Process =>
		if(d.target != "xml")
			return (nil, "not an XML file");
	* =>
		return (nil, "unexpected file structure");
	}
	# XXX i don't understand this 3-times loop...
	# seems to me that something like the following (correct) document
	# will fail:
	# <?xml><!DOCTYPE ...><package> ....</package>
	# i.e. no space between the doctype declaration and the
	# start of the package tag.
	for(i := 0; i < 3; i++){
		xi = x.next();
		if(xi == nil)
			return (nil, "not OEB package");
		pick d := xi {
		Text =>
			;	# usual XML extraneous punctuation cruft
		Doctype =>
			if(!d.public || len d.params < 2)
				return (nil, "not an OEB document or package");
			case doctype(hd tl d.params, Laxchecking) {
			OEBpkg =>
				break;
			OEBdoc =>
				# it's a document; make it into a simple package
				p := ref Package;
				p.file = f;
				p.uniqueid = d.name;
				p.manifest = p.spine = ref Item("doc", f, "text/x-oeb1-document", nil, f, nil) :: nil;
				return (p, nil);
			* =>
				return (nil, "unexpected DOCTYPE for OEB package: " + hd tl d.params  );
			}
		* =>
			return (nil, "not OEB package (no DOCTYPE)");
		}
	}
	p := ref Package;
	p.file = f;

	# package[@unique-identifier[IDREF], Metadata, Manifest, Spine, Tours?, Guide?]
	if((tag := next(x, "package")) == nil)
		return (nil, "can't find OEB package");
	p.uniqueid = tag.attrs.get("unique-identifier");
	spine: list of string;
	fallbacks: list of (ref Item, string);
	x.down();
	while((tag = next(x, nil)) != nil){
		x.down();
		case tag.name {
		"metadata" =>
			while((tag = next(x, nil)) != nil)
				if(tag.name == "dc-metadata"){
					x.down();
					while((tag = next(x, nil)) != nil && (s := text(x)) != nil)
						p.meta = (tag.name, tag.attrs, s) :: p.meta;
					x.up();
				}
		"manifest" =>
			while((tag = next(x, "item")) != nil){
				a := tag.attrs;
				p.manifest = ref Item(a.get("id"), a.get("href"), a.get("media-type"), nil, nil, nil) :: p.manifest;
				fallback := a.get("fallback");
				if (fallback != nil)
					fallbacks = (hd p.manifest, fallback) :: fallbacks;
			}
		"spine" =>
			while((tag = next(x, "itemref")) != nil)
				if((id := tag.attrs.get("idref")) != nil)
					spine = id :: spine;
		"guide" =>
			while((tag = next(x, "reference")) != nil){
				a := tag.attrs;
				p.guide = ref Reference(a.get("type"), a.get("title"), a.get("href")) :: p.guide;
			}
		"tours" =>
			;	# ignore for now
		}
		x.up();
	}
	x.up();

	# deal with fallbacks, and make sure they're not circular.
	
	for (; fallbacks != nil; fallbacks = tl fallbacks) {
		(item, fallbackid) := hd fallbacks;
		fallback := lookitem(p.manifest, fallbackid);
		for (fi := fallback; fi != nil; fi = fi.fallback)
			if (fi == item)
				break;
		if (fi == nil)
			item.fallback = fallback;
		else
			sys->print("warning: circular fallback reference\n");
	}

	# we'll assume it doesn't require a hash table
	for(; spine != nil; spine = tl spine)
		if((item := lookitem(p.manifest, hd spine)) != nil)
			p.spine = item :: p.spine;
		else
			p.spine = ref Item(hd spine, nil, nil, nil, nil, "item in OEB spine but not listed in manifest") :: p.spine;
	guide := p.guide;
	for(p.guide = nil; guide != nil; guide = tl guide)
		p.guide = hd guide :: p.guide;
	return (p, nil);
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
	

lookitem(items: list of ref Item, id: string): ref Item
{
	for(; items != nil; items = tl items){
		item := hd items;
		if(item.id == id)
			return item;
	}
	return nil;
}

next(x: ref Parser, s: string): ref Xml->Item.Tag
{
	while ((t0 := x.next()) != nil) {
		pick t1 := t0 {
		Error =>
			sys->print("oebpackage: error: %s:%d: %s\n", t1.loc.systemid, t1.loc.line, t1.msg);
		Tag =>
			if (s == nil || s == t1.name)
				return t1;
		}
	}
	return nil;
}

text(x: ref Parser): string
{
	s: string;
	x.down();
loop:
	while ((t0 := x.next()) != nil) {
		pick t1 := t0 {
		Error =>
			sys->print("oebpackage: error: %s:%d: %s\n", t1.loc.systemid, t1.loc.line, t1.msg);
		Text =>
			s = t1.ch;
			break loop;
		}
	}
	x.up();
	return s;
}	

Package.getmeta(p: self ref Package, n: string): list of (Xml->Attributes, string)
{
	r: list of (Xml->Attributes, string);
	for(meta := p.meta; meta != nil; meta = tl meta){
		(name, a, value) := hd meta;
		if(name == n)
			r = (a, value) :: r;
	}
	# r is in file order because p.meta is reversed
	return r;
}

Package.locate(p: self ref Package): int
{
	dir := "./";
	for(n := len p.file; --n >= 0;)
		if(p.file[n] == '/'){
			dir = p.file[0:n+1];
			break;
		}
	nmissing := 0;
	for(items := p.manifest; items != nil; items = tl items){
		item := hd items;
		err := "";
		if(item.href != nil){
			u := url->makeurl(item.href);
			if(u.scheme != Url->FILE && u.scheme != Url->NOSCHEME)
				err = sys->sprint("URL scheme %s not yet supported", url->schemes[u.scheme]);
			else if(u.host != "localhost" && u.host != nil)
				err = "non-local URLs not supported";
			else{
				path := u.path;
				if(u.pstart != "/")
					path = dir+path;	# TO DO: security
				(ok, d) := sys->stat(path);
				if(ok >= 0)
					item.file = path;
				else
					err = sys->sprint("%r");
			}
		}else
			err = "no location specified (missing HREF)";
		if(err != nil)
			nmissing++;
		item.missing = err;
	}
	return nmissing;
}
