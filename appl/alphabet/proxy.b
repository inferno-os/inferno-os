implement Proxy;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
include "alphabet.m";

Debug: con 0;

proxy[Ctxt,Cvt,M,V,EV](ctxt: Ctxt): (
		chan of ref Typescmd[EV],
		chan of (string, chan of ref Typescmd[V])
	) for {
		M =>
			typesig: fn(m: self M): string;
			run: fn(m: self M, ctxt: ref Draw->Context, r: ref Reports->Report, errorc: chan of string,
					opts: list of (int, list of V), args: list of V): V;
			quit: fn(m: self M);
		Ctxt =>
			loadtypes: fn(ctxt: self Ctxt, name: string): (chan of ref Proxy->Typescmd[V], string);
			type2s: fn(ctxt: self Ctxt, tc: int): string;
			alphabet: fn(ctxt: self Ctxt): string;
			modules: fn(ctxt: self Ctxt, r: chan of string);
			find: fn(ctxt: self Ctxt, s: string): (M, string);
			getcvt: fn(ctxt: self Ctxt): Cvt;
		Cvt =>
			int2ext: fn(cvt: self Cvt, v: V): EV;
			ext2int: fn(cvt: self Cvt, ev: EV): V;
			free: fn(cvt: self Cvt, v: EV, used: int);
			dup:	fn(cvt: self Cvt, v: EV): EV;
	}
{
	sys = load Sys Sys->PATH;
	t := chan of ref Typescmd[EV];
	newts := chan of (string, chan of ref Typescmd[V]);
	spawn proxyproc(ctxt, t, newts);
	return (t, newts);
}

proxyproc[Ctxt,Cvt,M,V,EV](
		ctxt: Ctxt,
		t: chan of ref Typescmd[EV],
		newts: chan of (string, chan of ref Typescmd[V])
	)
	for{
	M =>
		typesig: fn(m: self M): string;
		run: fn(m: self M, ctxt: ref Draw->Context, r: ref Reports->Report, errorc: chan of string,
				opts: list of (int, list of V), args: list of V): V;
		quit: fn(m: self M);
	Ctxt =>
		loadtypes: fn(ctxt: self Ctxt, name: string): (chan of ref Proxy->Typescmd[V], string);
		type2s: fn(ctxt: self Ctxt, tc: int): string;
		alphabet: fn(ctxt: self Ctxt): string;
		modules: fn(ctxt: self Ctxt, r: chan of string);
		find: fn(ctxt: self Ctxt, s: string): (M, string);
		getcvt: fn(ctxt: self Ctxt): Cvt;
	Cvt =>
		int2ext: fn(cvt: self Cvt, v: V): EV;
		ext2int: fn(cvt: self Cvt, ev: EV): V;
		free: fn(cvt: self Cvt, v: EV, used: int);
		dup:	fn(cvt: self Cvt, v: EV): EV;
	}
{
	typesets: list of (string, chan of ref Typescmd[V]);
	cvt := ctxt.getcvt();
	for(;;)alt{
	gr := <-t =>
		if(gr == nil){
			for(; typesets != nil; typesets = tl typesets)
				(hd typesets).t1 <-= nil;
			exit;
		}
		pick r := gr {
		Load =>
			(m, err) := ctxt.find(r.cmd);
			if(m == nil){
				r.reply <-= (nil, err);
			}else{
				c := chan of ref Modulecmd[EV];
				spawn modproxyproc(cvt, m, c);
				r.reply <-= (c, nil);
			}
		Alphabet =>
			r.reply <-= ctxt.alphabet();
		Free =>
			cvt.free(r.v, r.used);
			r.reply <-= 0;
		Dup =>
			r.reply <-= cvt.dup(r.v);
		Type2s =>
			r.reply <-= ctxt.type2s(r.tc);
		Loadtypes =>
			ts := typesets;
			typesets = nil;
			c: chan of ref Typescmd[V];
			for(; ts != nil; ts = tl ts){
				if((hd ts).t0 == r.name)
					c = (hd ts).t1;
				else
					typesets = hd ts :: typesets;
			}
			err: string;
			if(c == nil)
				(c, err) = ctxt.loadtypes(r.name);
			if(c == nil)
				r.reply <-= (nil, err);
			else{
				et := chan of ref Typescmd[EV];
				spawn extproxyproc(ctxt, ctxt.alphabet(), c, et);
				r.reply <-= (et, nil);
			}
		Modules =>
			spawn ctxt.modules(r.reply);
		* =>
			sys->fprint(sys->fildes(2), "unknown type of proxy request %d\n", tagof gr);
			raise "unknown type proxy request";
		}
	typesets = <-newts :: typesets =>
		;
	}
}

modproxyproc[Cvt,V,EV,M](cvt: Cvt, m: M, c: chan of ref Modulecmd[EV])
	for{
	M =>
		typesig: fn(m: self M): string;
		run: fn(m: self M, ctxt: ref Draw->Context, r: ref Reports->Report, errorc: chan of string,
				opts: list of (int, list of V), args: list of V): V;
		quit: fn(m: self M);
	Cvt =>
		int2ext: fn(cvt: self Cvt, v: V): EV;
		ext2int: fn(cvt: self Cvt, ev: EV): V;
		free: fn(cvt: self Cvt, ev: EV, used: int);
	}
{
	while((gr := <-c) != nil){
		pick r := gr {
		Typesig =>
			r.reply <-= m.typesig();
		Run =>
			# XXX could start (or invoke) a new process so that we don't potentially
			# block concurrency while we're starting the command.
			{
				iopts: list of (int, list of V);
				for(o := r.opts; o != nil; o = tl o){
					il := extlist2intlist(cvt, (hd o).t1);
					iopts = ((hd o).t0, il) :: iopts;
				}
				iopts = revip(iopts);
				v := cvt.int2ext(m.run(r.ctxt, r.report, r.errorc, iopts, extlist2intlist(cvt, r.args)));
				free(cvt, r.opts, r.args, v != nil);
				r.reply <-= v;
			} exception {
			"type error" =>
				if(Debug)
					sys->fprint(sys->fildes(2), "error: type conversion failed");
				if(r.errorc != nil)
					r.errorc <-= "error: type conversion failed";
				r.reply <-= nil;
			}
		}
	}
	m.quit();
}

extproxyproc[Ctxt,Cvt,V,EV](ctxt: Ctxt, alphabet: string, t: chan of ref Typescmd[V], et: chan of ref Typescmd[EV])
	for{
	Ctxt =>
		type2s: fn(ctxt: self Ctxt, tc: int): string;
		getcvt: fn(ctxt: self Ctxt): Cvt;
	Cvt =>
		int2ext: fn(cvt: self Cvt, v: V): EV;
		ext2int: fn(cvt: self Cvt, ev: EV): V;
		free: fn(cvt: self Cvt, ev: EV, used: int);
		dup: fn(cvt: self Cvt, ev: EV): EV;
	}
{
	cvt := ctxt.getcvt();
	for(;;){
		gr := <-et;
		if(gr == nil)
			break;
		pick r := gr {
		Load =>
			reply := chan of (chan of ref Modulecmd[V], string);
			t <-= ref Typescmd[V].Load(r.cmd, reply);
			(c, err) := <-reply;
			if(c == nil){
				r.reply <-= (nil, err);
			}else{
				ec := chan of ref Modulecmd[EV];
				spawn extmodproxyproc(cvt, c, ec);
				r.reply <-= (ec, nil);
			}
		Alphabet =>
			t <-= ref Typescmd[V].Alphabet(r.reply);
		Free =>
			cvt.free(r.v, r.used);
		Dup =>
			r.reply <-= cvt.dup(r.v);
		Type2s =>
			for(i := 0; i < len alphabet; i++)
				if(alphabet[i] == r.tc)
					break;
			if(i == len alphabet)
				t <-= ref Typescmd[V].Type2s(r.tc, r.reply);
			else
				r.reply <-= ctxt.type2s(r.tc);
		Loadtypes =>
			reply := chan of (chan of ref Typescmd[V], string);
			t <-= ref Typescmd[V].Loadtypes(r.name, reply);
			(c, err) := <-reply;
			if(c == nil)
				r.reply <-= (nil, err);
			else{
				t <-= ref Typescmd[V].Alphabet(areply := chan of string);
				ec := chan of ref Typescmd[EV];
				spawn extproxyproc(ctxt, <-areply, c, ec);
				r.reply <-= (ec, nil);
			}
		Modules =>
			t <-= ref Typescmd[V].Modules(r.reply);
		* =>
			sys->fprint(sys->fildes(2), "unknown type of proxy request %d\n", tagof gr);
			raise "unknown type proxy request";
		}
	}
	et <-= nil;
}
	
extmodproxyproc[Cvt,V,EV](cvt: Cvt, c: chan of ref Modulecmd[V], ec: chan of ref Modulecmd[EV])
	for{
	Cvt =>
		int2ext: fn(cvt: self Cvt, v: V): EV;
		ext2int: fn(cvt: self Cvt, ev: EV): V;
		free: fn(cvt: self Cvt, ev: EV, used: int);
	}
{
	while((gr := <-ec) != nil){
		pick r := gr {
		Typesig =>
			c <-= ref Modulecmd[V].Typesig(r.reply);
		Run =>
			{
				iopts: list of (int, list of V);
				for(o := r.opts; o != nil; o = tl o){
					il := extlist2intlist(cvt, (hd o).t1);
					iopts = ((hd o).t0, il) :: iopts;
				}
				iopts = revip(iopts);
				c <-= ref Modulecmd[V].Run(
					r.ctxt,
					r.report,
					r.errorc,
					iopts,
					extlist2intlist(cvt, r.args),
					reply := chan of V
				);
				v := cvt.int2ext(<-reply);
				free(cvt, r.opts, r.args, v != nil);
				r.reply <-= v;
			}
		}
	}
}


revip[V](l: list of (int, V)): list of (int, V)
{
	m: list of (int, V);
	for(; l != nil; l = tl l)
		m = hd l :: m;
	return m;
}

extlist2intlist[V,EV,Cvt](cvt: Cvt, vl: list of EV): list of V
	for{
	Cvt =>
		int2ext: fn(cvt: self Cvt, v: V): EV;
		ext2int: fn(cvt: self Cvt, ev: EV): V;
	}
{
	l, m: list of V;
	for(; vl != nil; vl = tl vl)
		l = cvt.ext2int(hd vl) :: l;
	for(; l != nil; l = tl l)
		m = hd l :: m;
	return m;
}

free[V,Cvt](cvt: Cvt, opts: list of (int, list of V), args: list of V, used: int)
	for{
	Cvt =>
		free: fn(cvt: self Cvt, ev: V, used: int);
	}
{
	for(; args != nil; args = tl args)
		cvt.free(hd args, used);
	for(; opts != nil; opts = tl opts)
		for(args = (hd opts).t1; args != nil; args = tl args)
			cvt.free(hd args, used);
}
