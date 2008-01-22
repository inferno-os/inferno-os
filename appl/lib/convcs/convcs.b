implement Convcs;

include "sys.m";
include "cfg.m";
include "convcs.m";

DEFCSFILE : con "/lib/convcs/charsets";

sys : Sys;
cfg : Cfg;

Record, Tuple : import cfg;

init(csfile : string) : string
{
	sys = load Sys Sys->PATH;
	cfg = load Cfg Cfg->PATH;
	if (cfg == nil)
		return sys->sprint("cannot load module %s: %r", Cfg->PATH);
	if (csfile == nil)
		csfile = DEFCSFILE;
	err := cfg->init(csfile);
	if (err != nil) {
		cfg = nil;
		return err;
	}
	return nil;
}

getbtos(cs : string) : (Btos, string)
{
	cs = normalize(cs);
	(rec, err) := csalias(cs);
	if (err != nil)
		return (nil, err);

	(path, btostup) := rec.lookup("btos");
	if (path == nil)
		return (nil, sys->sprint("no converter for %s", cs));
	arg := btostup.lookup("arg");

	btos := load Btos path;
	if (btos == nil)
		return (nil, sys->sprint("cannot load converter: %r"));
	err = btos->init(arg);
	if (err != nil)
		return (nil, err);
	return (btos, nil);
}

getstob(cs : string) : (Stob, string)
{
	cs = normalize(cs);
	(rec, err) := csalias(cs);
	if (err != nil)
		return (nil, err);

	(path, stobtup) := rec.lookup("stob");
	if (path == nil)
		return (nil, sys->sprint("no converter for %s", cs));
	arg := stobtup.lookup("arg");

	stob := load Stob path;
	if (stob == nil)
		return (nil, sys->sprint("cannot load converter: %r"));
	err = stob->init(arg);
	if (err != nil)
		return (nil, err);
	return (stob, nil);
}

csalias(cs : string) : (ref Cfg->Record, string)
{
	# search out charset record - allow for one level of renaming
	for (i := 0; i < 2; i++) {
		recs := cfg->lookup(cs);
		if (recs == nil)
			return (nil, sys->sprint("unknown charset %s", cs));
		(val, rec) := hd recs;
		if (val != nil) {
			cs = val;
			continue;
		}
		return (rec, nil);
	}
	return (nil, sys->sprint("too man aliases for %s\n", cs));
}

enumcs() : list of (string, string, int)
{
	d : list of (string, string, int);
	for (csl := cfg->getkeys(); csl != nil; csl = tl csl) {
		cs := hd csl;
		recs := cfg->lookup(cs);
		if (recs == nil)
			continue;	# shouldn't happen!
		(val, rec) := hd recs;
		if (val != nil)
			# an alias - ignore
			continue;

		(btos, nil) := rec.lookup("btos");
		(stob, nil) := rec.lookup("stob");

		if (btos == nil && stob == nil)
			continue;
		mode := 0;
		if (btos != nil)
			mode = BTOS;
		if (stob != nil)
			mode |= STOB;

		(desc, nil) := rec.lookup("desc");
		if (desc == nil)
			desc = cs;

		d = (cs, desc, mode) :: d;
	}
	# d is in reverse order to that in the csfile file
	l : list of (string, string, int);
	for (; d != nil; d = tl d)
		l = hd d :: l;
	return l;
}

aliases(cs : string) : (string, list of string)
{
	cs = normalize(cs);
	(mainrec, err) := csalias(cs);
	if (err != nil)
		return (err, nil);

	cs = (hd (hd mainrec.tuples).attrs).name;

	(desc, nil) := mainrec.lookup("desc");
	if (desc == nil)
		desc = cs;

	al := cs :: nil;
	for (csl := cfg->getkeys(); csl != nil; csl = tl csl) {
		name := hd csl;
		recs := cfg->lookup(name);
		if (recs == nil)
			continue;	# shouldn't happen!
		(val, nil) := hd recs;
		if (val != cs)
			continue;
		al = name :: al;
	}

	r : list of string;
	for (; al != nil; al = tl al)
		r = hd al :: r;
	return (desc, r);
}

normalize(s : string) : string
{
	for (i := 0; i < len s; i++) {
		r := s[i];
		if (r >= 'A' && r <= 'Z')
			s[i] = r + ('a' - 'A');
	}
	return s;
}
