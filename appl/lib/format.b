implement Format;
include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "sexprs.m";
	sexprs: Sexprs;
	Sexp: import sexprs;
include "format.m";

# possible addition?
# se2spec(se: list of ref Sexp): (array of Fmtspec, string)

init()
{
	sys = load Sys Sys->PATH;
	sexprs = load Sexprs Sexprs->PATH;
	sexprs->init();
	bufio = load Bufio Bufio->PATH;
}

spec2se(spec: array of Fmtspec): list of ref Sexp
{
	l: list of ref Sexp;
	for(i := len spec - 1; i >= 0; i--){
		if((sp := spec[i]).fields != nil)
			l = ref Sexp.List(ref Sexp.String(sp.name, nil) :: spec2se(sp.fields)) :: l;
		else if(sp.name != nil)
			l = ref Sexp.String(sp.name, nil) :: l;
	}
	return l;
}

spec2fmt(specs: array of Fmtspec): array of Fmt
{
	if(specs == nil)
		return nil;
	f := array[len specs] of Fmt;
	for(i := 0; i < len specs; i++){
		if(specs[i].name == nil)
			f[i].kind = -1;
		else
			f[i] = (i, spec2fmt(specs[i].fields));
	}
	return f;
}


se2fmt(spec: array of Fmtspec, se: ref Sexp): (array of Fmt, string)
{
	if(!se.islist())
		return (nil, "format must be a list");
	return ses2fmt(spec, se.els());
}

ses2fmt(spec: array of Fmtspec, els: list of ref Sexp): (array of Fmt, string)
{
	a := array[len els] of Fmt;
	for(i := 0; els != nil; els = tl els){
		name := (hd els).op();
		for(j := 0; j < len spec; j++)
			if(spec[j].name == name)
				break;
		if(j == len spec)
			return (nil, sys->sprint("format name %#q not found", name));
		sp := spec[j];
		if((hd els).islist() == 0)
			a[i++] = Fmt(j, spec2fmt(sp.fields));
		else if(sp.fields == nil)
			return (nil, sys->sprint("unexpected list %#q", name));
		else{
			(f, err) := ses2fmt(sp.fields, (hd els).args());
			if(f == nil)
				return (nil, err);
			a[i++] = Fmt(j, f);
		}
	}
	return (a, nil);
}

rec2val(spec: array of Fmtspec, se: ref Sexprs->Sexp): (array of Fmtval, string)
{
	if(se.islist() == 0)
		return (nil, "expected list of fields; got "+se.text());
	els := se.els();
	if(len els > len spec)
		return (nil, sys->sprint("too many fields found, expected %d, got %s", len spec, se.text()));
	a := array[len spec] of Fmtval;
	err: string;
	for(i := 0; i < len spec; i++){
		f := spec[i];
		if(f.name == nil)
			continue;
		if(els == nil)
			return (nil, sys->sprint("too few fields found, expected %d, got %s", len spec, se.text()));
		el := hd els;
		if(f.fields == nil)
			a[i].val = el;
		else{
			if(el.islist() == 0)
				return (nil, "expected list of elements; got "+el.text());
			vl := el.els();
			a[i].recs = recs := array[len vl] of array of Fmtval;
			for(j := 0; vl != nil; vl = tl vl){
				(recs[j++], err) = rec2val(spec[i].fields, hd vl);
				if(err != nil)
					return (nil, err);
			}
		}
		els = tl els;
	}
	return (a, nil);
}

Fmtval.text(v: self Fmtval): string
{
	return v.val.astext();
}			

Fmtfile.new(spec: array of Fmtspec): Fmtfile
{
	return (spec, (ref Sexp.List(spec2se(spec))).pack());
}

Fmtfile.open(f: self Fmtfile, name: string): ref Bufio->Iobuf
{
	fd := sys->open(name, Sys->ORDWR);
	if(fd == nil){
		sys->werrstr(sys->sprint("open failed: %r"));
		return nil;
	}
	if(sys->write(fd, f.descr, len f.descr) == -1){
		sys->werrstr(sys->sprint("format write failed: %r"));
		return nil;
	}
	sys->seek(fd, big 0, Sys->SEEKSTART);
	return bufio->fopen(fd, Sys->OREAD);
}

Fmtfile.read(f: self Fmtfile, iob: ref Iobuf): (array of Fmtval, string)
{
	(se, err) := Sexp.read(iob);
	if(se == nil)
		return (nil, err);
	return rec2val(f.spec, se);
}
