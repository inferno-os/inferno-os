implement Sh;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	myself: Shellbuiltin;
	mysh: Sh;

Namespace: adt {
	name: string;
	madecmd: array of int;
	mods: list of (string, Shellbuiltin);
	builtins: array of list of (string, Shellbuiltin);
};
Builtin, Sbuiltin: con iota;

namespaces: list of ref Namespace;
pending: list of (string, int, Shellbuiltin);
lock: chan of int;
BUILTINPATH: con "/dis/sh";

initbuiltin(c: ref Sh->Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;
	mysh = load Sh "$self";
	myself = load Shellbuiltin "$self";
	sh->c.addbuiltin("mload", myself);
	sh->c.addbuiltin("munload", myself);
	lock = chan[1] of int;
	return nil;
}

runbuiltin(ctxt: ref Sh->Context, nil: Sh,
			argv: list of ref Sh->Listnode, last: int): string
{
	cmd := (hd argv).word;
	case cmd {
	"mload" or "munload" =>
		if(tl argv == nil)
			ctxt.fail("usage", "usage: "+cmd+" name [module...]");

		# by doing this lock, we're relying on modules not to invoke a command
		# in initbuiltin that calls back into mload. since they shouldn't be running
		# any commands in initbuiltin anyway, this seems like a reasonable assumption.
		lock <-= 1;
		{
			name := (hd tl argv).word;
			for(argv = tl tl argv; argv != nil; argv = tl argv){
				if((hd argv).cmd != nil)
					ctxt.fail("usage", "usage: "+cmd+" namespace [module...]");
				if(cmd == "mload")
					mload(ctxt, name, (hd argv).word);
				else
					munload(ctxt, name, (hd argv).word);
			}
		}exception{
		"fail:*" =>
			<-lock;
			raise;
		}
		<-lock;
		return nil;
	* =>
		if(len argv < 2)
			ctxt.fail("usage", sys->sprint("usage: %s command", (hd argv).word));

		b := lookup(ctxt, (hd argv).word, (hd tl argv).word, Builtin, nil);
		return b->runbuiltin(ctxt, mysh, tl argv, last);
	}
}

mload(ctxt: ref Sh->Context, name, modname: string): string
{
	ns := nslookup(name);
	if(ns == nil){
		ns = ref Namespace(name, array[2] of {* => 0}, nil, array[2] of list of (string, Shellbuiltin));
		namespaces = ns :: namespaces;
	}
	for(nsm := ns.mods; nsm != nil; nsm = tl nsm)
		if((hd nsm).t0 == modname)
			return nil;
	path := modname;
	if (len path < 4 || path[len path-4:] != ".dis")
		path += ".dis";
	if (path[0] != '/' && path[0:2] != "./")
		path = BUILTINPATH + "/" + path;
	mod := load Shellbuiltin path;
	if (mod == nil)
		ctxt.fail("bad module", sys->sprint("load: cannot load %s: %r", path));
	s := mod->initbuiltin(ctxt, mysh);
	if(s != nil){
		munload(ctxt, name, modname);
		pending = nil;
		ctxt.fail("init", "mload: init "+modname+" failed: "+s);
	}
	mod = mod->getself();
	ns.mods = (modname, mod) :: ns.mods;
	for(; pending != nil; pending = tl pending){
		(cmd, which, pmod) := hd pending;
		if(pmod != mod)
			sys->fprint(sys->fildes(2), "mload: unexpected module when loading %#q", name);
		else
			lookup(ctxt, name, cmd, which, mod);
	}
		
	return nil;
}

munload(ctxt: ref Sh->Context, name, modname: string): string
{
	ns := nslookup(name);
	if(ns == nil){
		sys->fprint(sys->fildes(2), "munload: no such namespace %#q\n", name);
		return "fail";
	}
	nm: list of (string, Shellbuiltin);
	mod: Shellbuiltin;
	for(m := ns.mods; m != nil; m = tl m)
		if((hd m).t0 == modname)
			mod = (hd m).t1;
		else
			nm = hd m :: nm;
	if(mod == nil){
		sys->fprint(sys->fildes(2), "munload: no such module %#q\n", modname);
		return "fail";
	}
	ns.mods = nm;
	for(i := 0; i < 2; i++){
		nb: list of (string, Shellbuiltin) = nil;
		for(b := ns.builtins[i]; b != nil; b = tl b)
			if((hd b).t1 != mod)
				nb = hd b :: nb;
		ns.builtins[i] = nb;
		if(ns.builtins[i] == nil){
			if(i == Builtin)
				sh->ctxt.removebuiltin(name, myself);
			else
				sh->ctxt.removesbuiltin(name, myself);
		}
			
	}
	return nil;
}


runsbuiltin(ctxt: ref Sh->Context, nil: Sh,
			argv: list of ref Sh->Listnode): list of ref Sh->Listnode
{
	if(len argv < 2)
		ctxt.fail("usage", sys->sprint("usage: %s command", (hd argv).word));
	b := lookup(ctxt, (hd argv).word, (hd tl argv).word, Sbuiltin, nil);
	return b->runsbuiltin(ctxt, mysh, tl argv);
}

searchns(mod: Shellbuiltin): string
{
	for(m := namespaces; m != nil; m = tl m)
		for(b := (hd m).mods; b != nil; b = tl b)
			if((hd b).t1 == mod)
				return (hd m).name;
	return nil;
}

lookup(ctxt: ref Sh->Context, name, cmd: string, which: int, sb: Shellbuiltin): Shellbuiltin
{
	for(m := namespaces; m != nil; m = tl m)
		if((hd m).name == name)
			break;
	if(m == nil)
		ctxt.fail("unknown", sys->sprint("unknown namespace %q", name));
	ns := hd m;
	for(b := ns.builtins[which]; b != nil; b = tl b)
			if((hd b).t0 == cmd)
				break;
	if(b == nil){
		if(sb != nil){
			ns.builtins[which] = (cmd, sb) :: ns.builtins[which];
			if(!ns.madecmd[which]){
				if(which == Builtin)
					sh->ctxt.addbuiltin(name, myself);
				else
					sh->ctxt.addsbuiltin(name, myself);
				ns.madecmd[which] = 1;
			}
			return sb;
		}
		ctxt.fail("unknown cmd", sys->sprint("unknown command %q", cmd));
	}
	return (hd b).t1;
}

Context.addbuiltin(c: self ref Context, modname: string, mod: Shellbuiltin)
{
	name := searchns(mod);
	if(name == nil)
		pending = (modname, Builtin, mod) :: pending;
	else
		lookup(c, name, modname, Builtin, mod);
}

Context.addsbuiltin(c: self ref Context, modname: string, mod: Shellbuiltin)
{
	name := searchns(mod);
	if(name == nil)
		pending = (modname, Sbuiltin, mod) :: pending;
	else
		lookup(c, name, modname, Sbuiltin, mod);
}

Context.removebuiltin(c: self ref Context, nil: string, nil: Shellbuiltin)
{
	c.fail("nope", "mload: remove builtin not implemented");
}

Context.removesbuiltin(c: self ref Context, nil: string, nil: Shellbuiltin)
{
	c.fail("nope", "mload: remove sbuiltin not implemented");
}

Context.addmodule(nil: self ref Context, name: string, nil: Shellbuiltin)
{
	sys->fprint(sys->fildes(2), "mload: addmodule not allowed (%s)\n", name);
}

nslookup(name: string): ref Namespace
{
	for(m := namespaces; m != nil; m = tl m)
		if((hd m).name == name)
			return hd m;
	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}

initialise()
{
	return sh->initialise();
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	return sh->init(ctxt, argv);
}

system(ctxt: ref Draw->Context, cmd: string): string
{
	return sh->system(ctxt, cmd);
}

run(ctxt: ref Draw->Context, argv: list of string): string
{
	return sh->run(ctxt, argv);
}
	
parse(s: string): (ref Cmd, string)
{
	return sh->parse(s);
}

cmd2string(c: ref Cmd): string
{
	return sh->cmd2string(c);
}

list2stringlist(nl: list of ref Listnode): list of string
{
	return sh->list2stringlist(nl);
}

stringlist2list(sl: list of string): list of ref Listnode
{
	return sh->stringlist2list(sl);
}

quoted(val: list of ref Listnode, quoteblocks: int): string
{
	return sh->quoted(val, quoteblocks);
}

Context.new(drawcontext: ref Draw->Context): ref Context
{
	return sh->Context.new(drawcontext);
}

Context.get(c: self ref Context, name: string): list of ref Listnode
{
	return sh->c.get(name);
}

Context.set(c: self ref Context, name: string, val: list of ref Listnode)
{
	return sh->c.set(name, val);
}

Context.setlocal(c: self ref Context, name: string, val: list of ref Listnode)
{
	return sh->c.setlocal(name, val);
}

Context.envlist(c: self ref Context): list of (string, list of ref Listnode)
{
	return sh->c.envlist();
}

Context.push(c: self ref Context)
{
	return sh->c.push();
}

Context.pop(c: self ref Context)
{
	return sh->c.pop();
}

Context.copy(c: self ref Context, copyenv: int): ref Context
{
	return sh->c.copy(copyenv);
}

Context.run(c: self ref Context, args: list of ref Listnode, last: int): string
{
	return sh->c.run(args, last);
}

Context.fail(c: self ref Context, ename, msg: string)
{
	return sh->c.fail(ename, msg);
}

Context.options(c: self ref Context): int
{
	return sh->c.options();
}

Context.setoptions(c: self ref Context, flags, on: int): int
{
	return sh->c.setoptions(flags, on);
}
