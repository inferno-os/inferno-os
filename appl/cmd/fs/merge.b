implement Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "fslib.m";
	fslib: Fslib;
	Report, Value, type2s: import fslib;
	Fschan, Fsdata, Entrychan, Cmpchan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fslib;

# e.g....
# fs select {mode -d} {merge -c {compose -d AoutB} {filter {not {path /chan /dev /usr/rog /n/local /net}} /} {merge {proto FreeBSD} {proto Hp} {proto Irix} {proto Linux} {proto MacOSX} {proto Nt} {proto Nt.ti} {proto Nt.ti925} {proto Plan9} {proto Plan9.ti} {proto Plan9.ti925} {proto Solaris} {proto authsrv} {proto dl} {proto dlsrc} {proto ep7} {proto inferno} {proto inferno.ti} {proto ipaqfs} {proto minitel} {proto os} {proto scheduler.client} {proto scheduler.server} {proto sds} {proto src} {proto src.ti} {proto sword} {proto ti925.ti} {proto ti925bin} {proto tipaq} {proto umec} {proto utils} {proto utils.ti}}} >[2] /dev/null

types(): string
{
	return "xxxx*-1-cm";
}

init()
{
	sys = load Sys Sys->PATH;
	fslib = load Fslib Fslib->PATH;
	if(fslib == nil){
		sys->fprint(sys->fildes(2), "fs: cannot load %s: %r\n", Fslib->PATH);
		raise "fail:bad module";
	}
}

run(nil: ref Draw->Context, nil: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	recurse := 1;
	cmp: Cmpchan;
	for(; opts != nil; opts = tl opts){
		case (hd opts).opt {
		'1' =>
			recurse = 0;
		'c' =>
			cmp = (hd (hd opts).args).m().i;
		}
	}
	dst := chan of (Fsdata, chan of int);
	spawn mergeproc((hd args).x().i, (hd tl args).x().i, dst, recurse, cmp, tl tl args == nil);
	for(args = tl tl args; args != nil; args = tl args){
		dst1 := chan of (Fsdata, chan of int);
		spawn mergeproc(dst, (hd args).x().i, dst1, recurse, cmp, tl args == nil);
		dst = dst1;
	}
	return ref Value.X(dst);
}

# merge two trees; assume directories are alphabetically sorted.
mergeproc(c0, c1, dst: Fschan, recurse: int, cmp: Cmpchan, killcmp: int)
{
	myreply := chan of int;
	((d0, nil), reply0) := <-c0;
	((d1, nil), reply1) := <-c1;

	if(compare(cmp, d0, d1) == 2r10)
		dst <-= ((d1, nil), myreply);
	else
		dst <-= ((d0, nil), myreply);
	r := <-myreply;
	reply0 <-= r;
	reply1 <-= r;
	if(r == Down){
		{
			mergedir(c0, c1, dst, recurse, cmp);
		} exception {"exit" =>;}
	}
	if(cmp != nil && killcmp)
		cmp <-= (nil, nil, nil);
}

mergedir(c0, c1, dst: Fschan, recurse: int, cmp: Cmpchan)
{
	myreply := chan of int;
	reply0, reply1: chan of int;
	d0, d1: ref Sys->Dir;
	eof0 := eof1 := 0;
	for(;;){
		if(!eof0 && d0 == nil){
			((d0, nil), reply0) = <-c0;
			if(d0 == nil){
				reply0 <-= Next;
				eof0 = 1;
			}
		}
		if(!eof1 && d1 == nil){
			((d1, nil), reply1) = <-c1;
			if(d1 == nil){
				reply1 <-= Next;
				eof1 = 1;
			}
		}
		if(eof0 && eof1)
			break;

		(wd0, wd1) := (d0, d1);
		if(d0 != nil && d1 != nil && d0.name != d1.name){
			if(d0.name < d1.name)
				wd1 = nil;
			else
				wd0 = nil;
		}

		wc0, wc1: Fschan;
		wreply0, wreply1: chan of int;
		weof0, weof1: int;

		c := compare(cmp, wd0, wd1);
		if(wd0 != nil && wd1 != nil){
			if(c != 0 && recurse && (wd0.mode & wd1.mode & Sys->DMDIR) != 0){
				dst <-= ((wd0, nil), myreply);
				r := <-myreply;
				reply0 <-= r;
				reply1 <-= r;
				d0 = d1 = nil;
				case r {
				Quit =>
					raise "exit";
				Skip =>
					return;
				Down =>
					mergedir(c0, c1, dst, 1, cmp);
				}
				continue;
			}
			# when we can't merge and there's a clash, choose c0 over c1, unless cmp says otherwise
			if(c == 2r10){
				reply0 <-= Next;
				d0 = nil;
			}else{
				reply1 <-= Next;
				d1 = nil;
			}
		}
		if(c & 2r01){
			(wd0, wc0, wreply0, weof0) = (d0, c0, reply0, eof0);
			(wd1, wc1, wreply1, weof1) = (d1, c1, reply1, eof1);
			d0 = nil;
		}else if(c & 2r10){
			(wd0, wc0, wreply0, weof0) = (d1, c1, reply1, eof1);
			(wd1, wc1, wreply1, weof1) = (d0, c0, reply0, eof0);
			d1 = nil;
		}else{
			if(wd0 == nil){
				reply1 <-= Next;
				d1 = nil;
			}else{
				reply0 <-= Next;
				d0 = nil;
			}
			continue;
		}
		dst <-= ((wd0, nil), myreply);
		r := <-myreply;
		wreply0 <-= r;
		if(r == Down)
			r = fslib->copy(wc0, dst);		# XXX hmm, maybe this should be a mergedir()
		case r {
		Quit or
		Skip =>
			if(wd1 == nil && !weof1)
				(nil, wreply1) = <-wc1;
			wreply1 <-= r;
			if(r == Quit)
				raise "exit";
			return;
		}
	}
	dst <-= ((nil, nil), myreply);
	if(<-myreply == Quit)
		raise "exit";
}

compare(cmp: Cmpchan, d0, d1: ref Sys->Dir): int
{
	mask := (d0 != nil) | (d1 != nil) << 1;
	if(cmp == nil)
		return mask;
	reply := chan of int;
	cmp <-= (d0, d1, reply);
	return <-reply & mask;
}
