implement Stackv;

include "sys.m";
	sys: Sys;
include "draw.m";
include "debug.m";
	debug: Debug;
	Prog, Module, Exp: import debug;
	Tadt, Tarray, Tbig, Tbyte, Treal,
	Tfn, Tint, Tlist,
	Tref, Tstring, Tslice: import Debug;
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

stderr: ref Sys->FD;
stdout: ref Iobuf;

hasht := array[97] of (int, array of int);

Stackv: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

maxrecur := 16r7ffffffe;

badmodule(p: string)
{
	sys->fprint(stderr, "stackv: cannot load %q: %r\n", p);
	raise "fail:bad module";
}

currp: ref Prog;
showtypes := 1;
showsource := 0;
showmodule := 0;

init(nil: ref Draw->Context, argv: list of string)
{

	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	debug = load Debug Debug->PATH;
	if(debug == nil)
		badmodule(Debug->PATH);
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		badmodule(Bufio->PATH);
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);
	stdout = bufio->fopen(sys->fildes(1), Sys->OWRITE);

	arg->init(argv);
	arg->setusage("stackv [-Tlm] [-r maxdepth] [-s dis sbl]... [pid[.sym]...] ...");
	sblfile := "";
	while((opt := arg->opt()) != 0){
		case opt {
		's' =>
			arg->earg();	# XXX make it a list of maps from dis to sbl later
			sblfile = arg->earg();
		'l' =>
			showsource = 1;
		'm' =>
			showmodule = 1;
		'r' =>
			maxrecur = int arg->earg();
		'T' =>
			showtypes = 0;
		* =>
			arg->usage();
		}
	}
	debug->init();
	argv = arg->argv();
	printpids := len argv > 1;
	if(printpids)
		maxrecur++;
	for(; argv != nil; argv = tl argv)
		db(sys->tokenize(hd argv, ".").t1, printpids);
}

db(toks: list of string, printpid: int): int
{
	if(toks == nil){
		sys->fprint(stderr, "stackv: bad pid\n");
		return -1;
	}
	if((pid := int hd toks) <= 0){
		sys->fprint(stderr, "stackv: bad pid %q\n", hd toks);
		return -1;
	}
	err: string;
	p: ref Prog;

	# reuse process if possible
	if(currp == nil || currp.id != pid){
		(currp, err) = debug->prog(pid);
		if(err != nil){
			sys->fprint(stderr, "stackv: %s\n", err);
			return -1;
		}
		if(currp == nil){
			sys->fprint(stderr, "stackv: nil prog from pid %d\n", pid);
			return -1;
		}
	}
	p = currp;
	stk: array of ref Exp;
	(stk, err) = p.stack();
	if(err != nil){
		sys->fprint(stderr, "stackv: %s\n", err);
		return -1;
	}
	for (i := 0; i < len stk; i++) {
		stk[i].m.stdsym();
		stk[i].findsym();
	}
	depth := 0;
	if(printpid){
		stdout.puts(sys->sprint("prog %d {\n", pid));	# }
		depth++;
	}
	pexp(stk, tl toks, depth);
	if(printpid)
		stdout.puts("}\n");
	stdout.flush();
	return 0;
}

pexp(stk: array of ref Exp, toks: list of string, depth: int)
{
	if(toks == nil){
		for (i := 0; i < len stk; i++)
			pfn(stk[i], depth);
	}else{
		exp := stackfindsym(stk, toks, depth);
		if(exp == nil)
			return;
		pname(exp, depth, nil);
		stdout.putc('\n');
	}
}

stackfindsym(stk: array of ref Exp, toks: list of string, depth: int): ref Exp
{
	fname := hd toks;
	toks = tl toks;
	for(i := 0; i < len stk; i++){
		s := stk[i].name;
		if(s == fname)
			break;
		if(hasdot(s) && toks != nil && s == fname+"."+hd toks){
			fname += "."+hd toks;
			toks = tl toks;
			break;
		}
	}
	if(i == len stk){
		indent(depth);
		stdout.puts("function not found\n");
		return nil;
	}
	if(toks == nil)
		return stk[i];
	stk = stk[i].expand();
	if(hd toks == "module"){
		if((e := getname(stk, "module")) == nil){
			indent(depth);
			stdout.puts(sys->sprint("no module declarations in function %q\n", fname));
		}else if((e = symfindsym(e, tl toks, depth)) != nil)
			return e;
		return nil;
	}
	for(t := "locals" :: "args" :: "module" :: nil; t != nil; t = tl t){
		if((e := getname(stk, hd t)) == nil)
			continue;
		if((e = symfindsym(e, toks, depth)) != nil)
			return e;
	}
	indent(depth);
	stdout.puts(sys->sprint("symbol %q not found in function %q\n", hd toks, fname));
	return nil;
}

hasdot(s: string): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == '.')
			return 1;
	return 0;
}

symfindsym(e: ref Exp, toks: list of string, depth: int): ref Exp
{
	if(toks == nil)
		return e;
	exps := e.expand();
	for(i := 0; i < len exps; i++)
		if(exps[i].name == hd toks)
			return symfindsym(exps[i], tl toks, depth);
	return nil;
}

pfn(exp: ref Exp, depth: int)
{
	(v, w) := exp.val();
	if(!w || v == nil){
		indent(depth);
		stdout.puts(sys->sprint("no value for fn %q\n", exp.name));
		return;
	}
	exps := exp.expand();
	indent(depth);
	stdout.puts("["+exp.srcstr()+"]\n");
	indent(depth);
	stdout.puts(symname(exp)+"(");
	if((e := getname(exps, "args")) != nil){
		args := e.expand();
		for(i := 0; i < len args; i++){
			pname(args[i], depth+1, nil);
			if(i != len args - 1)
				stdout.puts(", ");
		}
	}
	stdout.puts(")\n");
	indent(depth);
	stdout.puts("{\n");	# }
	if((e = getname(exps, "locals")) != nil){
		locals := e.expand();
		for(i := 0; i < len locals; i++){
			indent(depth+1);
			pname(locals[i], depth+1, nil);
			stdout.puts("\n");
		}
	}
	if(showmodule && (e = getname(exps, "module")) != nil){
		mvars := e.expand();
		for(i := 0; i < len mvars; i++){
			indent(depth+1);
			pname(mvars[i], depth+1, "module.");
			stdout.puts("\n");
		}
	}
	indent(depth);
	stdout.puts("}\n");
}

getname(exps: array of ref Exp, name: string): ref Exp
{
	for(i := 0; i < len exps; i++)
		if(exps[i].name == name)
			return exps[i];
	return nil;
}

strval(v: string): string
{
	for(i := 0; i < len v; i++)
		if(v[i] == '"')
			break;
	if(i < len v)
		v = v[i:];
	return v;
}

pname(exp: ref Exp, depth: int, prefix: string)
{
	name := prefix+symname(exp);
	(v, w) := exp.val();
	if (!w && v == nil) {
		stdout.puts(sys->sprint("%s: %s = novalue", symname(exp), exp.typename()));
		return;
	}
	case exp.kind() {
	Tfn =>
		pfn(exp, depth);
	Tint =>
		stdout.puts(sys->sprint("%s := %s", name, v));
	Tstring =>
		stdout.puts(sys->sprint("%s := %s", name, strval(v)));
	Tbyte or
	Tbig or
	Treal =>
		stdout.puts(sys->sprint("%s := %s %s", name, exp.typename(), v));
	* =>
		if(showtypes)
			stdout.puts(sys->sprint("%s: %s = ", name, exp.typename()));
		else
			stdout.puts(sys->sprint("%s := ", name));
		pval(exp, v, w, depth);
	}
}

srcstr(src: ref Debug->Src): string
{
	if(src == nil)
		return nil;
	if(src.start.file != src.stop.file)
		return sys->sprint("%q:%d.%d,%q:%d.%d", src.start.file, src.start.line, src.start.pos, src.stop.file, src.stop.line, src.stop.pos);
	if(src.start.line != src.stop.line)
		return sys->sprint("%q:%d.%d,%d.%d", src.start.file, src.start.line, src.start.pos, src.stop.line, src.stop.pos);
	return sys->sprint("%q:%d.%d,%d", src.start.file, src.start.line, src.start.pos, src.stop.pos);
}

pval(exp: ref Exp, v: string, w: int, depth: int)
{
	if(depth >= maxrecur){
		stdout.puts(v);
		return;
	}
	case exp.kind() {
	Tarray =>
		if(pref(v)){
			if(depth+1 >= maxrecur)
				stdout.puts(v+"{...}");
			else{
				stdout.puts(v+"{\n");
				indent(depth+1);
				parray(exp, depth+1);
				stdout.puts("\n");
				indent(depth);
				stdout.puts("}");
			}
		}
	Tlist =>
		if(v == "nil")
			stdout.puts("nil");
		else
		if(depth+1 >= maxrecur)
			stdout.puts(v+"{...}");
		else{
			stdout.puts("{\n");
			indent(depth+1);
			plist(exp, v, w, depth+1);
			stdout.puts("\n");
			indent(depth);
			stdout.puts("}");
		}
	Tadt =>
		pgenval(exp, nil, w, depth);
	Tref =>
		if(pref(v))
			pgenval(exp, v, w, depth);
	Tstring =>
		stdout.puts(strval(v));
	* =>
		pgenval(exp, v, w, depth);
	}
}

parray(exp: ref Exp, depth: int)
{
	exps := exp.expand();
	for(i := 0; i < len exps; i++){
		e := exps[i];
		(v, w) := e.val();
		if(e.kind() == Tslice)
			parray(e, depth);
		else{
			pval(e, v, w, depth);
			stdout.puts(", ");
		}
	}
}

plist(exp: ref Exp, v: string, w: int, depth: int)
{
	while(w && v != "nil"){
		exps := exp.expand();
		h := getname(exps, "hd");
		if(h == nil)
			break;
		(hv, vw) := h.val();
		if(pref(v) == 0)
			return;
		stdout.puts(v+"(");
		pval(h, hv, vw, depth);
		stdout.puts(") :: ");
		h = nil;
		exp = getname(exps, "tl");
		(v, w) = exp.val();
	}
	stdout.puts("nil");
}

pgenval(exp: ref Exp, v: string, w: int, depth: int)
{
	if(w){
		exps := exp.expand();
		if(len exps == 0)
			stdout.puts(v);
		else{
			stdout.puts(v+"{\n");		# }
			if (len exps > 0){
				if(depth >= maxrecur){
					indent(depth);
					stdout.puts(sys->sprint("...[%d]\n", len exps));
				}else{
					for (i := 0; i < len exps; i++){
						indent(depth+1);
						pname(exps[i], depth+1, nil);
						stdout.puts("\n");
					}
				}
			}
			indent(depth);		# {
			stdout.puts("}");
		}
	}else
		stdout.puts(v);
}

symname(exp: ref Exp): string
{
	if(showsource == 0)
		return exp.name;
	return exp.name+"["+srcstr(exp.src())+"]";
}

indent(n: int)
{
	while(n-- > 0)
		stdout.putc('\t');
}

ref2int(v: string): int
{
	if(v == nil)
		error("bad empty value for ref");
	i := 0;
	n := len v;
	if(v[0] == '@')
		i = 1;
	else{
		# skip array bounds
		if(v[0] == '['){
			for(; i < n && v[i] != ']'; i++)
				;
			if(i >= n - 2 || v[i+1] != ' ' || v[i+2] != '@')
				error("bad value for ref: "+v);
			i += 3;
		}
	}
	if(n - i > 8)
		error("64-bit pointers?");
	p := 0;
	for(; i < n; i++){
		c := v[i];
		case c {
		'0' to '9' =>
			p = (p << 4) + (c - '0');
		'a' to 'f' =>
			p = (p << 4) + (c - 'a' + 10);
		* =>
			error("bad value for ref: "+v);
		}
	}
	return p;
}

pref(v: string): int
{
	if(v == "nil"){
		stdout.puts("nil");
		return 0;
	}
	if(addref(ref2int(v)) == 0){
		stdout.puts(v);
		stdout.puts("(qv)");
		return 0;
	}
	return 1;
}

# hash table implementation that tries to be reasonably
# parsimonious on memory usage.
addref(v: int): int
{
	slot := (v & 16r7fffffff) % len hasht;
	(n, a) := hasht[slot];
	for(i := 0; i < n; i++)
		if(a[i] == v)
			return 0;
	if(n == len a){
		if(n == 0)
			n = 3;
		t := array[n*3/2] of int;
		t[0:] = a;
		hasht[slot].t1 = t;
	}
	a[hasht[slot].t0++] = v;
	return 1;
}

error(e: string)
{
	sys->fprint(sys->fildes(2), "stackv: error: %s\n", e);
	raise "fail:error";
}
