implement Profile;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "workdir.m";
	workdir: Workdir;
include "debug.m";
	debug: Debug;
	Sym: import debug;
include "dis.m";
	dism: Dis;
include "profile.m";

# merge common code

PROF: con "/prof";
CTL: con "ctl";
NAME: con "name";
MPATH: con "path";
HISTOGRAM: con "histogram";

inited: int;
modl: string;
lasterr: string;

bspath := array[] of
{
	("/dis/",		"/appl/cmd/"),
	("/dis/",		"/appl/"),
};

error(s: string)
{
	lasterr = sys->sprint("%s: %r", s);
}

error0(s: string)
{
	lasterr = s;
}

cleare()
{
	lasterr = nil;
}

lasterror(): string
{
	return lasterr;
}

init(): int
{
	cleare();
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	debug = load Debug Debug->PATH;
	if(debug == nil){
		error("cannot load Debug module");
		return -1;
	}
	debug->init();
	(ok, nil) := sys->stat(PROF + "/ctl");
	if (ok == -1) {
		if(sys->bind("#P", PROF, Sys->MREPL|Sys->MCREATE) < 0){
			error(sys->sprint("cannot bind prof device to /prof"));
			return -1;
		}
	}
	inited = 1;
	return 0;
}

end(): int
{
	cleare();
	inited = 0;
	modl = nil;
	if(write(mkpath(PROF, CTL), "end") < 0)
		return -1;
	return 0;
}

start(): int
{
	cleare();
	if(!inited && init() < 0)
		return -1;
	if(write(mkpath(PROF, CTL), "module " + modl) < 0)
		return -1;
	if(write(mkpath(PROF, CTL), "start") < 0)
		return -1;
	return 0;
}

cpstart(pid: int): int
{
	cleare();
	if(!inited && init() < 0)
		return -1;
	if(write(mkpath(PROF, CTL), "module " + modl) < 0)
		return -1;
	if(write(mkpath(PROF, CTL), "startcp " + string pid) < 0)
		return -1;
	return 0;
}

memstart(m: int): int
{
	cleare();
	if(!inited && init() < 0)
		return -1;
	if(modl != nil && write(mkpath(PROF, CTL), "module " + modl) < 0)
		return -1;
	start := "startmp";
	if(m == 0)
		m = MAIN|HEAP|IMAGE;
	if(m&MAIN)
		start += "1";
	if(m&HEAP)
		start += "2";
	if(m&IMAGE)
		start += "3";
	if(write(mkpath(PROF, CTL), start) < 0)
		return -1;
	return 0;
}

stop(): int
{
	cleare();
	if(!inited && init() < 0)
		return -1;
	if(write(mkpath(PROF, CTL), "stop") < 0)
		return -1;
	return 0;
}

sample(i: int): int
{
	cleare();
	if(i <= 0){
		error0(sys->sprint("bad sample rate %d", i));
		return -1;
	}
	if(write(mkpath(PROF, CTL), "interval " + string i) < 0)
		return -1;
	return 0;
}

profile(m: string): int
{
	cleare();
	modl = m + " " + modl;
	return 0;
}

stats(): Prof
{
	mp: Modprof;
	p: Prof;
	mpl: list of Modprof;

	cleare();
	fd := sys->open(PROF, Sys->OREAD);
	if(fd == nil){
		error(sys->sprint("cannot open %s for reading", PROF));
		return (nil, 0, nil);
	}
	total := 0;
	for(;;){
		(nr, d) := sys->dirread(fd);
		if(nr <= 0)
			break;
		for(i := 0; i < nr; i++){
			if(d[i].name == CTL)
				continue;
			dn := mkpath(PROF, d[i].name);
			mp.name = read(mkpath(dn, NAME));
			mp.path = read(mkpath(dn, MPATH));
			fdh := sys->open(mkpath(dn, HISTOGRAM), Sys->OREAD);
			if(fdh == nil)
				continue;
			(mp.srcpath, mp.linetab, mp.funtab, mp.total) = tprofile(fdh, mp.path);
			if((sp := getb(mp.path)) != nil)
				mp.srcpath = sp;
			if(mp.total != 0){
				mpl = mp :: mpl;
				total += mp.total;
			}
		}
	}
	p.mods = mpl;
	p.total = total;
	return p;
}

cpstats(rec: int, v: int): Prof
{
	m: string;
	mp: Modprof;
	p: Prof;
	mpl: list of Modprof;

	cleare();
	fd := sys->open(PROF, Sys->OREAD);
	if(fd == nil){
		error(sys->sprint("cannot open %s for reading", PROF));
		return (nil, 0, nil);
	}
	total := 0;
	for(;;){
		(nr, d) := sys->dirread(fd);
		if(nr <= 0)
			break;
		for(i:=0; i<nr; i++){
			if(d[i].name == CTL)
				continue;
			dn := mkpath(PROF, d[i].name);
			mp.name = read(mkpath(dn, NAME));
			mp.path = read(mkpath(dn, MPATH));
			fdh := sys->open(mkpath(dn, HISTOGRAM), Sys->OREAD);
			if(fdh == nil)
				continue;
			(m, mp.srcpath, mp.rawtab, mp.linetab, mp.rngtab, mp.total, mp.coverage) = cprofile(fdh, mp.path, rec, v);
			if(mp.name == nil)
				mp.name = m;
			if((sp := getb(mp.path)) != nil)
				mp.srcpath = sp;
			if(len mp.rawtab > 0){
				mpl = mp :: mpl;
				total += mp.total;
			}
		}
	}
	p.mods = mpl;
	p.total = total;
	return p;
}

cpfstats(v: int): Prof
{
	mp: Modprof;
	p: Prof;
	mpl: list of Modprof;

	cleare();
	total := 0;
	(nil, l) := sys->tokenize(modl, " ");
	for( ; l != nil; l = tl l){
		s := hd l;
		suf := suff(s);
		if(suf == nil)
			s += ".dis";
		else
			s = repsuff(s, "."+suf, ".dis");
		if(!exists(s) && s[0] != '/' && s[0:2] != "./")
			s = "/dis/"+s;
		mp.path = s;
		(mp.name, mp.srcpath, mp.rawtab, mp.linetab, mp.rngtab, mp.total, mp.coverage) = cprofile(nil, mp.path, 1, v);
		if((sp := getb(mp.path)) != nil)
			mp.srcpath = sp;
		if(len mp.rawtab > 0){
			mpl = mp :: mpl;
			total += mp.total;
		}
	}
	p.mods = mpl;
	p.total = total;
	return p;
}

memstats(): Prof
{
	mp: Modprof;
	p: Prof;
	mpl: list of Modprof;

	cleare();
	fd := sys->open(PROF, Sys->OREAD);
	if(fd == nil){
		error(sys->sprint("cannot open %s for reading", PROF));
		return (nil, 0, nil);
	}
	total := totale := 0;
	for(;;){
		(nr, d) := sys->dirread(fd);
		if(nr <= 0)
			break;
		for(i:=0; i<nr; i++){
			if(d[i].name == CTL)
				continue;
			dn := mkpath(PROF, d[i].name);
			mp.name = read(mkpath(dn, NAME));
			mp.path = read(mkpath(dn, MPATH));
			fdh := sys->open(mkpath(dn, HISTOGRAM), Sys->OREAD);
			if(fdh == nil)
				continue;
			mp.totals = array[1] of int;
			(mp.srcpath, mp.linetab, mp.funtab, mp.total, mp.totals[0]) = mprofile(fdh, mp.path);
			if((sp := getb(mp.path)) != nil)
				mp.srcpath = sp;
			if(mp.total != 0 || mp.totals[0] != 0){
				mpl = mp :: mpl;
				total += mp.total;
				totale += mp.totals[0];
			}
		}
	}
	p.mods = mpl;
	p.total = total;
	p.totals = array[1] of int;
	p.totals[0] = totale;
	return p;
}

tprofile(fd: ref Sys->FD, dis: string): (string, array of int, array of Funprof, int)
{
	sbl := findsbl(dis);
	if(sbl == nil){
		error0(sys->sprint("cannot locate symbol table file for %s", dis));
		return (nil, nil, nil, 0);
	}
	(sym, err) := debug->sym(sbl);
	if(sym == nil){
		error0(sys->sprint("bad symbol table file: %s", err));
		return (nil, nil, nil, 0);
	}
	nlines := 0;
	nl := len sym.src;
	for(i := 0; i < nl; i++){
		if((l := sym.src[i].stop.line) > nlines)
			nlines = l;
	}
	name := sym.src[0].start.file;
	line := array[nlines+1] of int;
	for(i = 0; i <= nlines; i++)
		line[i] = 0;
	nf := len sym.fns;
	fun := array[nf] of Funprof;
	for(i = 0; i < nf; i++){
		fun[i].name = sym.fns[i].name;
		# src seems to be always nil
		# fun[i].file = sym.fns[i].src.start.file;
		# fun[i].line = (sym.fns[i].src.start.line+sym.fns[i].src.stop.line)/2;
		src := sym.pctosrc(sym.fns[i].offset);
		if(src != nil)
			fun[i].line = src.start.line;
		else
			fun[i].line = 0;
		fun[i].count = 0;
	}
	buf := array[32] of byte;
	# pc := 0;
	tot := 0;
	fi := 0;
# for(i=0; i < nl; i++) sys->print("%d -> %d\n", i, sym.pctosrc(i).start.line);
	while((m := sys->read(fd, buf, len buf)) > 0){
		(nw, lw) := sys->tokenize(string buf[0:m], " ");
		if(nw != 2){
			error0("bad histogram data");
			return  (nil, nil, nil, 0);
		}
		pc := int hd lw;
		f := int hd tl lw;
		rpc := pc-1;
		src := sym.pctosrc(rpc);
		if(src == nil)
			continue;
		l1 := src.start.line;
		l2 := src.stop.line;
		if(l1 == 0 || l2 == 0)
			continue;
		if((nl = l2-l1+1) == 1)
			line[l1] += f;
		else{
			q := f/nl;
			r := f-q*nl;
			for(i = l1; i <= l2; i++)
				line[i] += q+(r-->0);
		}
		if(fi < nf){
			if(rpc >= sym.fns[fi].offset && rpc < sym.fns[fi].stoppc)
				fun[fi].count += f;
			else{
				while(fi < nf && rpc >= sym.fns[fi].stoppc)
					fi++;
				# fi++;
				if(fi >= nf && f != 0)
					error0(sys->sprint("bad fn index"));
				if(fi < nf)
					fun[fi].count += f;
			}
		}
		tot += f;
# sys->print("pc %d count %d l1 %d l2 %d\n", rpc, f, l1, l2);
	}
	return (name, line, fun, tot);
}

cprofile(fd: ref Sys->FD, dis: string, rec: int, v: int): (string, string, array of (int, int), array of int, array of ref Range, int, int)
{
	freq := v&FREQUENCY;
	sbl := findsbl(dis);
	if(sbl == nil){
		error0(sys->sprint("cannot locate symbol table file for %s", dis));
		return (nil, nil, nil, nil, nil, 0, 0);
	}
	(sym, err) := debug->sym(sbl);
	if(sym == nil){
		error0(sys->sprint("bad symbol table file: %s", err));
		return (nil, nil, nil, nil, nil, 0, 0);
	}
	nlines := 0;
	nl := len sym.src;
	for(i := 0; i < nl; i++){
		if((l := sym.src[i].start.line) > nlines)
			nlines = l;
		if((l = sym.src[i].stop.line) > nlines)
			nlines = l;
	}
	name := sym.src[0].start.file;
	line := array[nlines+1] of int;
	for(i = 0; i <= nlines; i++){
		if(freq)
			line[i] = -1;
		else
			line[i] = 0;
	}
	rng := array[nlines+1] of ref Range;
	for(i = 0; i < nl; i++)
		cover(i, -1, sym, line, rng, freq);
	buf := array[32] of byte;
	nr := 0;
	r := array[1024] of (int, int);
	while((m := sys->read(fd, buf, len buf)) > 0){
		(nw, lw) := sys->tokenize(string buf[0:m], " ");
		if(nw != 2){
			error0("bad histogram data");
			return  (nil, nil, nil, nil, nil, 0, 0);
		}
		(r, nr) = add(r, nr, int hd lw, int hd tl lw);
	}
	r = clip(r, nr);
	if(rec){
		wt := nr > 0;
		prf := repsuff(sbl, ".sbl", ".prf");
		if(exists(prf)){
			if(stamp(sbl) > stamp(prf)){
				error0(sys->sprint("%s later than %s", sbl, prf));
				return (nil, nil, nil, nil, nil, 0, 0);
			}
			r = mergeprof(r, readprof(prf));
			nr = len r;
		}
		if(wt && writeprof(prf, r) < 0){
			error0(sys->sprint("cannot write profile file %s", prf));
			return (nil, nil, nil, nil, nil, 0, 0);
		}
	}
	tot := 0;
	lpc := 0;
	dise := dist := 0;
	for(i = 0; i < nr; i++){
		(pc, f) := r[i];
		for( ; lpc < pc; lpc++){
			cover(lpc, 0, sym, line, rng, freq);
			dist++;
		}
		cover(pc, f, sym, line, rng, freq);
		dist++;
		if(f != 0)
			dise++;
		tot += f;
		lpc = pc+1;
	}
	for( ; lpc < nl; lpc++){
		cover(lpc, 0, sym, line, rng, freq);
		dist++;
	}
	if(dist == 0)
		dist = 1;
	return (sym.name, name, r, line, rng, tot, (100*dise)/dist);
}

show(p: Prof, v: int): int
{
	i: int;

	cleare();
	tot := p.total;
	if(tot == 0)
		return 0;
	verbose := v&VERBOSE;
	fullhdr := v&FULLHDR;
	for(ml := p.mods; ml != nil; ml = tl ml){
		mp := hd ml;
		if(mp.total == 0)
			continue;
		if((b := getb(mp.path)) == nil)
			continue;
		sys->print("\nModule: %s(%s)\n\n", mp.name, mp.path);
		line := mp.linetab;
		if(v&FUNCTION){
			fun := mp.funtab;
			nf := len fun;
			for(i = 0; i < nf; i++)
				if(verbose || fun[i].count != 0){
					if(fullhdr)
						sys->print("%s:", b);
					sys->print("%d\t%.2f\t%s()\n", fun[i].line, 100.0*(real fun[i].count)/(real tot), fun[i].name);
			}
			sys->print("\n**** module sampling points %d ****\n\n", mp.total);
			if(v&LINE)
				sys->print("\n");
		}
		if(v&LINE){
			bio := bufio->open(b, Bufio->OREAD);
			if(bio == nil){
				error(sys->sprint("cannot open %s for reading", b));
				continue;
			}
			i = 1;
			ll := len line;
			while((s := bio.gets('\n')) != nil){
				f := 0;
				if(i < ll)
					f = line[i];
				if(verbose || f != 0){
					if(fullhdr)
						sys->print("%s:", b);
					sys->print("%d\t%.2f\t%s", i, 100.0*(real f)/(real tot), s);
				}
				i++;
			}
			sys->print("\n**** module sampling points %d ****\n\n", mp.total);
		}
	}
	if(p.mods != nil && tl p.mods != nil)
		sys->print("\n**** total sampling points %d ****\n\n", p.total);
	return 0;
}

cpshow(p: Prof, v: int): int
{
	i: int;

	cleare();
	tot := p.total;
	fullhdr := v&FULLHDR;
	freq := v&FREQUENCY;
	for(ml := p.mods; ml != nil; ml = tl ml){
		mp := hd ml;
		if((b := getb(mp.path)) == nil)
			continue;
		sys->print("\nModule: %s(%s)", mp.name, mp.path);
		sys->print("\t%d%% coverage\n\n", mp.coverage);
		if(mp.coverage == 100 && !freq)
			continue;
		line := mp.linetab;
		rng := mp.rngtab;
		bio := bufio->open(b, Bufio->OREAD);
		if(bio == nil){
			error(sys->sprint("cannot open %s for reading", b));
			continue;
		}
		i = 1;
		ll := len line;
		while((s := bio.gets('\n')) != nil){
			f := 0;
			if(i < ll)
				f = line[i];
			if(fullhdr)
				sys->print("%s:", b);
			sys->print("%d\t", i);
			if(rng != nil && i < ll && (r := rng[i]) != nil && multirng(r)){
				for( ; r != nil; r = r.n){
					sys->print("%s", trans(r.f, freq));
					if(r.n != nil)
						sys->print("|");
				}
			}
			else
				sys->print("%s", trans(f, freq));
			sys->print("\t%s", s);
			i++;
		}
		sys->print("\n**** module dis instructions %d ****\n\n", mp.total);
	}
	if(p.mods != nil && tl p.mods != nil)
		sys->print("\n**** total number dis instructions %d ****\n\n", p.total);
	return 0;
}

coverage(p: Prof, v: int): Coverage
{
	i: int;
	clist: Coverage;

	cleare();
	freq := v&FREQUENCY;
	for(ml := p.mods; ml != nil; ml = tl ml){
		mp := hd ml;
		if((b := getb(mp.path)) == nil)
			continue;
		line := mp.linetab;
		rng := mp.rngtab;
		bio := bufio->open(b, Bufio->OREAD);
		if(bio == nil){
			error(sys->sprint("cannot open %s for reading", b));
			continue;
		}
		i = 1;
		ll := len line;
		llist: list of (list of (int, int, int), string);
		while((s := bio.gets('\n')) != nil){
			f := 0;
			if(i < ll)
				f = line[i];
			rlist: list of (int, int, int);
			if(rng != nil && i < ll && (r := rng[i]) != nil){
				for( ; r != nil; r = r.n){
					if(r.u == ∞)
						r.u = len s - 1;
					if(freq){
						if(r.f > 0)
							rlist = (r.l, r.u, r.f) :: rlist;
					}
					else{
						if(r.f&NEX)
							rlist = (r.l, r.u, (r.f&EXE)==EXE) :: rlist;
					}
				}
			}
			else{
				if(freq){
					if(f > 0)
						rlist = (0, len s - 1, f) :: rlist;
				}
				else{
					if(f&NEX)
						rlist = (0, len s - 1, (f&EXE)==EXE) :: nil;
				}
			}
			llist = (rlist, s) :: llist;
			i++;
		}
		if(freq)
			n := mp.total;
		else
			n = mp.coverage;
		clist = (b, n, rev(llist)) :: clist;
	}
	return clist;
}

∞: con 1<<30;

DIS: con 1;
EXE: con 2;
NEX: con 4;

cover(pc: int, f: int, sym: ref Debug->Sym, line: array of int, rng: array of ref Range, freq: int)
{
	v: int;

	src := sym.pctosrc(pc);
	if(src == nil)
		return;
	l1 := src.start.line;
	l2 := src.stop.line;
	if(l1 == 0 || l2 == 0)
		return;
	c1 := src.start.pos;
	c2 := src.stop.pos;
	if(freq){
		v = 0;
		if(f > 0)
			v = f;
	}
	else{
		v = DIS;
		if(f > 0)
			v = EXE;
		else if(f == 0)
			v = NEX;
	}
	for(i := l1; i <= l2; i++){
		r1 := 0;
		r2 := ∞;
		if(i == l1)
			r1 = c1;
		if(i == l2)
			r2 = c2;
		if(rng != nil)
			rng[i] = mrgrng(addrng(rng[i], r1, r2, v, freq));
		if(freq){
			if(v > line[i])
				line[i] = v;
		}
		else
			line[i] |= v;
		# if(i==123) sys->print("%d %d-%d %d %d\n", i, r1, r2, v, pc);
	}
}

arng(c1: int, c2: int, f: int, tr: ref Range, lr: ref Range, r: ref Range): ref Range
{
	nr := ref Range(c1, c2, f, tr);
	if(lr == nil)
		r = nr;
	else
		lr.n = nr;
	return r;
}

addrng(r: ref Range, c1: int, c2: int, f: int, freq: int): ref Range
{
	lr: ref Range;

	if(c1 > c2)
		return r;
	for(tr := r; tr != nil; tr = tr.n){
		r1 := tr.l;
		r2 := tr.u;
		if(c1 < r1){
			if(c2 < r1)
				return arng(c1, c2, f, tr, lr, r);
			else if(c2 <= r2){
				r = addrng(r, c1, r1-1, f, freq);
				return addrng(r, r1, c2, f, freq);
			}
			else{
				r = addrng(r, c1, r1-1, f, freq);
				r = addrng(r, r1, r2, f, freq);
				return addrng(r, r2+1, c2, f, freq);
			}		
		}
		else if(c1 <= r2){
			if(c2 <= r2){
				v := tr.f;
				tr.l = c1;
				tr.u = c2;
				if(freq){
					if(f > tr.f)
						tr.f = f;
				}
				else
					tr.f |= f;
				r = addrng(r, r1, c1-1, v, freq);
				return addrng(r, c2+1, r2, v, freq);
			}
			else{
				r = addrng(r, c1, r2, f, freq);
				return addrng(r, r2+1, c2, f, freq);
			}
		}
		lr = tr;
	}
	return arng(c1, c2, f, nil, lr, r);
}

mrgrng(r: ref Range): ref Range
{
	lr: ref Range;

	for(tr := r; tr != nil; tr = tr.n){
		if(lr != nil && lr.u >= tr.l)
			sys->print("ERROR %d %d\n", lr.u, tr.l);
		if(lr != nil && lr.f == tr.f && lr.u+1 == tr.l){
			lr.u = tr.u;
			lr.n = tr.n;
		}
		else
			lr = tr;
	}
	return r;
}

multirng(r: ref Range): int
{
	f := r.f;
	for(tr := r; tr != nil; tr = tr.n)
		if(tr.f != f)
			return 1;
	return 0;
}

add(r: array of (int, int), nr: int, pc: int, f: int): (array of (int, int), int)
{
	l := len r;
	if(nr == l){
		s := array[2*l] of (int, int);
		s[0:] = r[0: nr];
		r = s;
	}
	r[nr++] = (pc, f);
	return (r, nr);
}

clip(r: array of (int, int), nr: int): array of (int, int)
{
	l := len r;
	if(nr < l){
		s := array[nr] of (int, int);
		s[0:] = r[0: nr];
		r = s;
	}
	return r;
}

readprof(f: string): array of (int, int)
{
	b := bufio->open(f, Bufio->OREAD);
	if(b == nil)
		return nil;
	nr := 0;
	r := array[1024] of (int, int);
	while((buf := b.gets('\n')) != nil){
		(nw, lw) := sys->tokenize(buf, " ");
		if(nw != 2){
			error0("bad raw data");
			return  nil;
		}
		(r, nr) = add(r, nr, int hd lw, int hd tl lw);
	}
	r = clip(r, nr);
	return r;
}

mergeprof(r1, r2: array of (int, int)): array of (int, int)
{
	nr := 0;
	r := array[1024] of (int, int);
	l1 := len r1;
	l2 := len r2;
	for((i, j) := (0, 0); i < l1 || j < l2; ){
		if(i < l1)
			(pc1, f1) := r1[i];
		else
			pc1 = ∞;
		if(j < l2)
			(pc2, f2) := r2[j];
		else
			pc2 = ∞;
		if(pc1 < pc2){
			(r, nr) = add(r, nr, pc1, f1);
			i++;
		}
		else if(pc1 > pc2){
			(r, nr) = add(r, nr, pc2, f2);
			j++;
		}
		else{
			(r, nr) = add(r, nr, pc1, f1+f2);
			i++;
			j++;
		}
	}
	r = clip(r, nr);
	return r;
}

writeprof(f: string, r: array of (int, int)): int
{
	fd := sys->create(f, Sys->OWRITE, 8r664);
	if(fd == nil)
		return -1;
	l := len r;
	for(i := 0; i < l; i++){
		(pc, fr) := r[i];
		sys->fprint(fd, "%d %d\n", pc, fr);
	}
	return 0;
}

trans(f: int, freq: int): string
{
	if(freq)
		return transf(f);
	else
		return transc(f);
}

transf(f: int): string
{
	if(f < 0)
		return " ";
	return string f;
}

transc(f: int): string
{
	c := "";
	case(f){
		0 => c = " ";
		DIS|EXE => c = "+";
		DIS|NEX => c = "-";
		DIS|EXE|NEX => c = "?";
		* =>
			error(sys->sprint("bad code %d\n", f));
	}
	return c;
}

getb(dis: string): string
{
	b := findb(dis);
	if(b == nil){
		error0(sys->sprint("cannot locate source file for %s\n", dis));
		return nil;
	}
	if(stamp(b) > stamp(dis)){
		error0(sys->sprint("%s later than %s", b, dis));
		return nil;
	}
	return b;
}

mkpath(d: string, f: string): string
{
	return d+"/"+f;
}

suff(s: string): string
{
	(n, l) := sys->tokenize(s, ".");
	if(n > 1){
		while(tl l != nil)
			l = tl l;
		return hd l;
	}
	return nil;
}
	
repsuff(s: string, old: string, new: string): string
{
	lo := len old;
	ls := len s;
	if(lo <= ls && s[ls-lo:ls] == old)
		return s[0:ls-lo]+new;
	return s;
}

read(f: string): string
{
	if((fd := sys->open(f, Sys->OREAD)) == nil){
		error(sys->sprint("cannot open %s for reading", f));
		return nil;
	}
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	return string buf[0:n];
}

write(f: string, s: string): int
{
	if((fd := sys->open(f, Sys->OWRITE)) == nil){
		error(sys->sprint("cannot open %s for writing", f));
		return -1;
	}
	b := array of byte s;
	if((n := sys->write(fd, b, len b)) != len b){
		error(sys->sprint("cannot write %s to file %s", s, f));
		return -1;
	}
	return 0;
}

exists(f: string): int
{
	return sys->open(f, Sys->OREAD) != nil;
}

stamp(f: string): int
{
	(ok, d) := sys->stat(f);
	if(ok < 0)
		return 0;
	return d.mtime;
}

findb(dis: string): string
{
	if(dism == nil){
		dism = load Dis Dis->PATH;
		if(dism != nil)
			dism->init();
	}
	if(dism != nil && (b := dism->src(dis)) != nil && exists(b))
		return b;
	return findfile(repsuff(dis, ".dis", ".b"));
}

findsbl(dis: string): string
{
	b := findb(dis);
	if(b != nil){
		sbl := repsuff(b, ".b", ".sbl");
		if(exists(sbl))
			return sbl;
		return findfile(sbl);
	}
	return findfile(repsuff(dis, ".dis", ".sbl"));
}

findfile(s: string): string
{
	if(exists(s))
		return s;
	if(s != nil && s[0] != '/'){
		if(workdir == nil)
			workdir = load Workdir Workdir->PATH;
		if(workdir == nil){
			error("cannot load Workdir module");
			return nil;
		}
		s = workdir->init() + "/" + s;
	}
	(d, f) := split(s, '/');
	(fp, nil) := split(f, '.');
	if(fp != nil)
		fp = fp[0: len fp - 1];
	for(k := 0; k < 2; k++){
		if(k == 0)
			str := s;
		else
			str = d;
		ls := len str;
		for(i := 0; i < len bspath; i++){
			(dis, src) := bspath[i];
			ld := len dis;
			if(ls >= ld && str[:ld] == dis){
				if(k == 0)
					ns := src + str[ld:];
				else
					ns = src + str[ld:] + fp + "/" + f;
				if(exists(ns))
					return ns;
			}
		}
	}
	return nil;
}

split(s: string, c: int): (string, string)
{
	for(i := len s - 1; i >= 0; --i)
		if(s[i] == c)
			break;
	return (s[0:i+1], s[i+1:]);
}

rev(llist: list of (list of (int, int, int), string)): list of (list of (int, int, int), string)
{
	r: list of (list of (int, int, int), string);

	for(l := llist; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

mprofile(fd: ref Sys->FD, dis: string): (string, array of int, array of Funprof, int, int)
{
	sbl := findsbl(dis);
	if(sbl == nil){
		error0(sys->sprint("cannot locate symbol table file for %s", dis));
		return (nil, nil, nil, 0, 0);
	}
	(sym, err) := debug->sym(sbl);
	if(sym == nil){
		error0(sys->sprint("bad symbol table file: %s", err));
		return (nil, nil, nil, 0, 0);
	}
	nlines := 0;
	nl := len sym.src;
	for(i := 0; i < nl; i++){
		if((l := sym.src[i].stop.line) > nlines)
			nlines = l;
	}
	name := sym.src[0].start.file;
	nl0 := 2*(nlines+1);
	line := array[nl0] of int;
	for(i = 0; i < nl0; i++)
		line[i] = 0;
	nf := len sym.fns;
	fun := array[nf] of Funprof;
	for(i = 0; i < nf; i++){
		fun[i].name = sym.fns[i].name;
		# src seems to be always nil
		# fun[i].file = sym.fns[i].src.start.file;
		# fun[i].line = (sym.fns[i].src.start.line+sym.fns[i].src.stop.line)/2;
		src := sym.pctosrc(sym.fns[i].offset);
		if(src != nil)
			fun[i].line = src.start.line;
		else
			fun[i].line = 0;
		fun[i].count = fun[i].counte = 0;
	}
	buf := array[32] of byte;
	# pc := 0;
	ktot := ktot1 := 0;
	fi := 0;
# for(i=0; i < nl; i++) sys->print("%d -> %d\n", i, sym.pctosrc(i).start.line);
	while((m := sys->read(fd, buf, len buf)) > 0){
		(nw, lw) := sys->tokenize(string buf[0:m], " ");
		if(nw != 2){
			error0("bad histogram data");
			return  (nil, nil, nil, 0, 0);
		}
		pc := int hd lw;
		f := int hd tl lw;
		if(pc == 0){
			ktot = f;
			continue;
		}
		if(pc == 1){
			ktot1 = f;
			continue;
		}
		pc -= 2;
		t := pc&1;
		pc /= 2;
		rpc := pc-1;
		src := sym.pctosrc(rpc);
		if(src == nil)
			continue;
		l1 := src.start.line;
		l2 := src.stop.line;
		if(l1 == 0 || l2 == 0)
			continue;
		if((nl = l2-l1+1) == 1)
			line[2*l1+t] += f;
		else{
			q := f/nl;
			r := f-q*nl;
			for(i = l1; i <= l2; i++)
				line[2*i+t] += q+(r-->0);
		}
		if(fi < nf){
			if(rpc >= sym.fns[fi].offset && rpc < sym.fns[fi].stoppc){
				if(t)
					fun[fi].counte += f;
				else
					fun[fi].count += f;
			}
			else{
				while(fi < nf && rpc >= sym.fns[fi].stoppc)
					fi++;
				# fi++;
				if(fi >= nf && f != 0)
					error0(sys->sprint("bad fn index"));
				if(fi < nf){
					if(t)
						fun[fi].counte += f;
					else
						fun[fi].count += f;
				}
			}
		}
# sys->print("pc %d count %d l1 %d l2 %d\n", rpc, f, l1, l2);
	}
	return (name, line, fun, ktot, ktot1);
}

memshow(p: Prof, v: int): int
{
	i: int;

	cleare();
	tot := p.total;
	if(p.total == 0 && p.totals[0] == 0)
		return 0;
	verbose := v&VERBOSE;
	fullhdr := v&FULLHDR;
	for(ml := p.mods; ml != nil; ml = tl ml){
		mp := hd ml;
		if(mp.total == 0 && mp.totals[0] == 0)
			continue;
		if((b := getb(mp.path)) == nil)
			continue;
		sys->print("\nModule: %s(%s)\n\n", mp.name, mp.path);
		line := mp.linetab;
		if(v&LINE){
			bio := bufio->open(b, Bufio->OREAD);
			if(bio == nil){
				error(sys->sprint("cannot open %s for reading", b));
				continue;
			}
			i = 1;
			ll := len line/2;
			while((s := bio.gets('\n')) != nil){
				f := g := 0;
				if(i < ll){
					f = line[2*i];
					g = line[2*i+1];
				}
				if(verbose || f != 0 || g != 0){
					if(fullhdr)
						sys->print("%s:", b);
					sys->print("%d\t%d\t%d\t%s", i, f, g, s);
				}
				i++;
			}
			if(v&(FUNCTION|MODULE))
				sys->print("\n");
		}
		if(v&FUNCTION){
			fun := mp.funtab;
			nf := len fun;
			for(i = 0; i < nf; i++)
				if(verbose || fun[i].count != 0 || fun[i].counte != 0){
					if(fullhdr)
						sys->print("%s:", b);
					sys->print("%d\t%d\t%d\t%s()\n", fun[i].line, fun[i].count, fun[i].counte, fun[i].name);
			}
			if(v&MODULE)
				sys->print("\n");
		}
		if(v&MODULE)
			sys->print("Module totals\t%d\t%d\n\n", mp.total, mp.totals[0]);
	}
	if(p.mods != nil && tl p.mods != nil)
		sys->print("Grand totals\t%d\t%d\n\n", p.total, p.totals[0]);
	return 0;
}
