implement Factotum, Authio;

#
# Copyright © 2003-2004 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;
	Rread, Rwrite: import Sys;

include "draw.m";

include "string.m";
	str: String;

include "keyring.m";

include "authio.m";

include "arg.m";

Factotum: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

#confirm, log

Files: adt {
	ctl:	ref Sys->FileIO;
	rpc:	ref Sys->FileIO;
	proto:	ref Sys->FileIO;
	needkey:	ref Sys->FileIO;
};

Debug: con 0;
debug := Debug;

files: Files;
authio: Authio;

keymanc: chan of (list of ref Attr, int, chan of (ref Key, string));

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	authio = load Authio "$self";

	svcname := "#sfactotum";
	mntpt := "/mnt/factotum";
	arg := load Arg Arg->PATH;
	if(arg != nil){
		arg->init(args);
		arg->setusage("auth/factotum [-d] [-m /mnt/factotum] [-s factotum]");
		while((o := arg->opt()) != 0)
			case o {
			'd' =>	debug = 1;
			'm' =>	mntpt = arg->earg();
			's' =>		svcname = "#s"+arg->earg();
			* =>	arg->usage();
			}
		args = arg->argv();
		if(args != nil)
			arg->usage();
		arg = nil;
	}
	sys->unmount(nil, mntpt);
	if(sys->bind(svcname, mntpt, Sys->MREPL) < 0)
		err(sys->sprint("can't bind %s on %s: %r", svcname, mntpt));
	files.ctl = sys->file2chan(mntpt, "ctl");
	files.rpc = sys->file2chan(mntpt, "rpc");
	files.proto = sys->file2chan(mntpt, "proto");
	files.needkey = sys->file2chan(mntpt, "needkey");
	if(files.ctl == nil || files.rpc == nil || files.proto == nil || files.needkey == nil)
		err(sys->sprint("can't create %s/*: %r", mntpt));
	keymanc = chan of (list of ref Attr, int, chan of (ref Key, string));
	spawn factotumsrv();
}

user(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, b, len b);
	if(n <= 0)
		return nil;
	return string b[0:n];
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "factotum: %s\n", s);
	raise "fail:error";
}

rlist: list of ref Fid;

factotumsrv()
{
	sys->pctl(Sys->NEWPGRP|Sys->FORKFD|Sys->FORKENV, nil);
	if(!Debug)
		privacy();
	allkeys := array[0] of ref Key;
	pidc := chan of int;
	donec := chan of ref Fid;
#	keyc := chan of (list of ref Attr, chan of (ref Key, string));
	needfid := -1;
	needed, needy: list of (int, list of ref Attr, chan of (ref Key, string));
	needread: Sys->Rread;
	needtag := 0;
	for(;;) X: alt{
	r := <-donec =>
		r.pid = 0;
		cleanfid(r.fid);

	(off, nbytes, nil, rc) := <-files.ctl.read =>
		if(rc == nil)
			break;
		s := "";
		for(i := 0; i < len allkeys; i++)
			if((k := allkeys[i]) != nil)
				s += k.safetext()+"\n";
		rc <-= reads(s, off, nbytes);
	(nil, data, nil, wc) := <-files.ctl.write =>
		if(wc == nil)
			break;
		(nf, flds) := sys->tokenize(string data, "\n\r");
		if(nf > 1){
			# compatibility with plan 9; has the advantage you can tell which key is wrong
			wc <-= (0, "multiline write not allowed");
			break;
		}
		if(flds == nil || (hd flds)[0] == '#'){
			wc <-= (len data, nil);
			break;
		}
		s := hd flds;
		for(i := 0; i < len s && s[i] != ' '; i++){
			# skip
		}
		verb := s[0:i];
		if(i < len s)
			i++;
		s = s[i:];
		case verb {
		"key" =>
			k := Key.mk(parseline(s));
			if(k == nil){
				wc <-= (len data, nil);	# ignore it
				break;
			}
			if(lookattrval(k.attrs, "proto") == nil){
				wc <-= (0, "key without proto");
				break;
			}
			allkeys = addkey(allkeys, k);
			wc <-= (len data, nil);
		"delkey" =>
			attrs := parseline(s);
			for(al := attrs; al != nil; al = tl al){
				a := hd al;
				if(a.name[0] == '!' && (a.val != nil || a.tag != Aquery)){
					wc <-= (0, "cannot specify values for private fields");
					break X;
				}
			}
			if(delkey(allkeys, attrs) == 0)
				wc <-= (0, "no matching keys");
			else
				wc <-= (len data, nil);
		"debug" =>
			wc <-= (len data, nil);
		* =>
			wc <-= (0, "unknown verb");
		}

	(nil, nbytes, fid, rc) := <-files.rpc.read =>
		if(rc == nil)
			break;
		r := findfid(fid);
		if(r == nil){
			rc <-= (nil, "no rpc pending");
			break;
		}
		alt{
		r.read <-= (nbytes, rc) =>
			;
		* =>
			rc <-= (nil, "concurrent rpc read not allowed");
		}
	(nil, data, fid, wc) := <-files.rpc.write =>
		if(wc == nil){
			cleanfid(fid);
			break;
		}
		r := findfid(fid);
		if(r == nil){
			r = ref Fid(fid, 0, nil, nil, chan[1] of (array of byte, Rwrite), chan[1] of (int, Rread), 0, nil);
			spawn request(r, pidc, donec);
			r.pid = <-pidc;
			rlist = r :: rlist;
		}
		# this non-blocking write avoids a potential deadlock situation that
		# can happen when a proto module calls findkey at the same time
		# a client tries to write to the rpc file. this might not be the correct fix!
		alt{
		r.write <-= (data, wc) =>
			;
		* =>
			wc <-= (-1, "concurrent rpc write not allowed");
		}

	(off, nbytes, nil, rc) := <-files.proto.read =>
		if(rc == nil)
			break;
		rc <-= reads("pass\np9any\n", off, nbytes);	# TO DO
	(nil, nil, nil, wc) := <-files.proto.write =>
		if(wc != nil)
			wc <-= (0, "illegal operation");

	(nil, nil, fid, rc) := <-files.needkey.read =>
		if(rc == nil)
			break;
		if(needfid >= 0 && fid != needfid){
			rc <-= (nil, "file in use");
			break;
		}
		needfid = fid;
		if(needy != nil){
			(tag, attr, kc) := hd needy;
			needy = tl needy;
			needed = (tag, attr, kc) :: needed;
			rc <-= (sys->aprint("needkey tag=%ud %s", tag, attrtext(attr)), nil);
			break;
		}
		if(needread != nil){
			rc <-= (nil, "already reading");
			break;
		}
		needread = rc;
	(nil, data, fid, wc) := <-files.needkey.write =>
		if(wc == nil){
			if(needfid == fid){
				needfid = -1;	# TO DO? give needkey errors back to request
				needread = nil;
			}
			break;
		}
		if(needfid >= 0 && fid != needfid){
			wc <-= (0, "file in use");
			break;
		}
		needfid = fid;
		tagline := parseline(string data);
		if(len tagline != 1 || (t := lookattrval(tagline, "tag")) == nil){
			wc <-= (0, "no tag");
			break;
		}
		tag := int t;
		nl: list of (int, list of ref Attr, chan of (ref Key, string));
		found := 0;
		for(l := needed; l != nil; l = tl l){
			(ntag, attrs, kc) := hd l;
			if(tag == ntag){
				found = 1;
				k := findkey(allkeys, attrs);
				if(k != nil)
					kc <-= (k, nil);
				else
					kc <-= (nil, "needkey "+attrtext(attrs));
				while((l = tl l) != nil)
					nl = hd l :: nl;
				break;
			}
			nl = hd l :: nl;
		}
		if(found)
			wc <-= (len data, nil);
		else
			wc <-= (0, "tag not found");

	(attrs, required, kc) := <-keymanc =>
		# look for key and reply
		k := findkey(allkeys, attrs);
		if(k != nil){
			kc <-= (k, nil);
			break;
		}else if(!required || needfid == -1){
			kc <-= (nil, "needkey "+attrtext(attrs));
			break;
		}
		# query surrounding environment using needkey
		if(needread != nil){
			needed = (needtag, attrs, kc) :: needed;
			needread <-= (sys->aprint("needkey tag=%ud %s", needtag, attrtext(attrs)), nil);
			needread = nil;
			needtag++;
		}else
			needy = (needtag++, attrs, kc) :: needy;
	}
}

findfid(fid: int): ref Fid
{
	for(rl := rlist; rl != nil; rl = tl rl){
		r := hd rl;
		if(r.fid == fid)
			return r;
	}
	return nil;
}

cleanfid(fid: int)
{
	rl := rlist;
	rlist = nil;
	for(; rl != nil; rl = tl rl){
		r := hd rl;
		if(r.fid != fid)
			rlist = r :: rlist;
		else if(r.pid)
			kill(r.pid);
	}
}

kill(pid: int)
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill");
}

privacy()
{
	fd := sys->open("#p/"+string sys->pctl(0, nil)+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "private") < 0)
		sys->fprint(sys->fildes(2), "factotum: warning: unable to make memory private: %r\n");
}

reads(str: string, off, nbytes: int): (array of byte, string)
{
	bstr := array of byte str;
	slen := len bstr;
	if(off < 0 || off >= slen)
		return (nil, nil);
	if(off + nbytes > slen)
		nbytes = slen - off;
	if(nbytes <= 0)
		return (nil, nil);
	return (bstr[off:off+nbytes], nil);
}

Ogok, Ostart, Oread, Owrite, Oauthinfo, Oattr: con iota;

ops := array[] of {
	(Ostart, "start"),
	(Oread, "read"),
	(Owrite, "write"),
	(Oauthinfo, "authinfo"),
	(Oattr, "attr"),
};

request(r: ref Fid, pidc: chan of int, donec: chan of ref Fid)
{
	pidc <-= sys->pctl(0, nil);
	rpc := rio(r);
	while(rpc != nil){
		if(rpc.cmd == Ostart){
			(proto, attrs, e) := startproto(string rpc.arg);
			if(e != nil){
				reply(rpc, "error "+e);
				rpc = rio(r);
				continue;
			}
			r.attrs = attrs;	# saved for attr request
			ok(rpc);
			io := ref IO(r, nil);
			{
				err := proto->interaction(attrs, io);
				if(debug && err != nil)
					sys->fprint(sys->fildes(2), "factotum: failure: %s\n", err);
				if(r.err == nil)
					r.err = err;
				r.done = 1;
			}exception ex{
			"*" =>
				r.done = 0;
				r.err = "exception "+ex;
			}
			if(r.err != nil)
				io.error(r.err);
			rpc = finish(r);
			r.attrs = nil;
			r.err = nil;
			r.done = 0;
			r.ai = nil;
		}else
			reply(rpc, "no current protocol");
	}
	flushreq(r, donec);
}

startproto(request: string): (Authproto, list of ref Attr, string)
{
	attrs := parseline(request);
	if(Debug)
		sys->print("-> %s <-\n", attrtext(attrs));
	p := lookattrval(attrs, "proto");
	if(p == nil)
		return (nil, nil, "did not specify protocol");
	if(Debug)
		sys->print("proto=%s\n", p);
	if(any(p, "./"))	# avoid unpleasantness
		return (nil, nil, "illegal protocol: "+p);
	proto := load Authproto "/dis/auth/proto/"+p+".dis";
	if(proto == nil)
		return (nil, nil, sys->sprint("protocol %s: %r", p));
	if(Debug)
		sys->print("start %s\n", p);
	e: string;
	{
		e = proto->init(authio);
	}exception ex{
	"*" =>
		e = "exception "+ex;
	}
	if(e != nil)
		return (nil, nil, e);
	return (proto, attrs, nil);
}

finish(r: ref Fid): ref Rpc
{
	while((rpc := rio(r)) != nil)
		case rpc.cmd {
		Owrite =>
			phase(rpc, "protocol phase error");
		Oread =>
			if(r.err != nil)
				reply(rpc, "error "+r.err);
			else
				done(rpc, r.ai);
		Oauthinfo =>
			if(r.done){
				if(r.ai == nil)
					reply(rpc, "error no authinfo available");
				else{
					a := packai(r.ai);
					if(rpc.nbytes-3 < len a)
						reply(rpc, sys->sprint("toosmall %d", len a + 3));
					else
						okdata(rpc, a);
				}
			}else
				reply(rpc, "error authentication unfinished");
		Ostart =>
			return rpc;
		* =>
			reply(rpc, "error unexpected request");
		}
	return nil;
}

flushreq(r: ref Fid, donec: chan of ref Fid)
{
	for(;;) alt{
	donec <-= r =>
		exit;
	(nil, wc) := <-r.write =>
		wc <-= (0, "write rpc protocol error");
	(nil, rc) := <-r.read =>
		rc <-= (nil, "read rpc protocol error");
	}
}

rio(r: ref Fid): ref Rpc
{
	req: array of byte;
	for(;;) alt{
	(data, wc) := <-r.write =>
		if(req != nil){
			wc <-= (0, "rpc pending; read to clear");
			break;
		}
		req = data;
		wc <-= (len data, nil);

	(nbytes, rc) := <-r.read =>
		if(req == nil){
			rc <-= (nil, "no rpc pending");
			break;
		}
		(cmd, arg) := op(req, ops);
		req = nil;
		rpc := ref Rpc(r, cmd, arg, nbytes, rc);
		case cmd {
		Ogok =>
			reply(rpc, "error unknown rpc");
			break;
		Oattr =>
			if(r.attrs == nil)
				reply(rpc, "error no attributes");
			else
				reply(rpc, "ok "+attrtext(r.attrs));
			break;
		* =>
			return rpc;
		}
	}
}

ok(rpc: ref Rpc)
{
	reply(rpc, "ok");
}

okdata(rpc: ref Rpc, a: array of byte)
{
	b := array[len a + 3] of byte;
	b[0] = byte 'o';
	b[1] = byte 'k';
	b[2] = byte ' ';
	b[3:] = a;
	rpc.rc <-= (b, nil);
}

done(rpc: ref Rpc, ai: ref Authinfo)
{
	rpc.r.ai = ai;
	rpc.r.done = 1;
	if(ai != nil)
		reply(rpc, "done haveai");
	else
		reply(rpc, "done");
}

phase(rpc: ref Rpc, s: string)
{
	reply(rpc, "phase "+s);
}

needkey(rpc: ref Rpc, attrs: list of ref Attr)
{
	reply(rpc, "needkey "+attrtext(attrs));
}

reply(rpc: ref Rpc, s: string)
{
	rpc.rc <-= reads(s, 0, rpc.nbytes);
}

puta(a: array of byte, n: int, v: array of byte): int
{
	if(n < 0)
		return -1;
	c := len v;
	if(n+2+c > len a)
		return -1;
	a[n++] = byte c;
	a[n++] = byte (c>>8);
	a[n:] = v;
	return n + len v;
}

packai(ai: ref Authinfo): array of byte
{
	a := array[1024] of byte;
	i := puta(a, 0, array of byte ai.cuid);
	i = puta(a, i, array of byte ai.suid);
	i = puta(a, i, array of byte ai.cap);
	i = puta(a, i, ai.secret);
	if(i < 0)
		return nil;
	return a[0:i];
}

op(a: array of byte, ops: array of (int, string)): (int, array of byte)
{
	arg: array of byte;
	for(i := 0; i < len a; i++)
		if(a[i] == byte ' '){
			if(i+1 < len a)
				arg = a[i+1:];
			break;
		}
	s := string a[0:i];
	for(i = 0; i < len ops; i++){
		(cmd, name) := ops[i];
		if(s == name)
			return (cmd, arg);
	}
	return (Ogok, arg);
}

parseline(s: string): list of ref Attr
{
	fld := str->unquoted(s);
	rfld := fld;
	for(fld = nil; rfld != nil; rfld = tl rfld)
		fld = (hd rfld) :: fld;
	attrs: list of ref Attr;
	for(; fld != nil; fld = tl fld){
		n := hd fld;
		a := "";
		tag := Aattr;
		for(i:=0; i<len n; i++)
			if(n[i] == '='){
				a = n[i+1:];
				n = n[0:i];
				tag = Aval;
			}
		if(len n == 0)
			continue;
		if(tag == Aattr && len n > 1 && n[len n-1] == '?'){
			tag = Aquery;
			n = n[0:len n-1];
		}
		attrs = ref Attr(tag, n, a) :: attrs;
	}
	return attrs;
}

Attr.text(a: self ref Attr): string
{
	case a.tag {
	Aattr =>
		return a.name;
	Aval =>
		return a.name+"="+a.val;
	Aquery =>
		return a.name+"?";
	* =>
		return "??";
	}
}

attrtext(attrs: list of ref Attr): string
{
	s := "";
	sp := 0;
	for(; attrs != nil; attrs = tl attrs){
		if(sp)
			s[len s] = ' ';
		sp = 1;
		s += (hd attrs).text();
	}
	return s;
}

lookattr(attrs: list of ref Attr, n: string): ref Attr
{
	for(; attrs != nil; attrs = tl attrs)
		if((a := hd attrs).tag != Aquery && a.name == n)
			return a;
	return nil;
}

lookattrval(attrs: list of ref Attr, n: string): string
{
	if((a := lookattr(attrs, n)) != nil)
		return a.val;
	return nil;
}

anyattr(attrs: list of ref Attr, n: string): ref Attr
{
	for(; attrs != nil; attrs = tl attrs)
		if((a := hd attrs).name == n)
			return a;
	return nil;
}

reverse[T](l: list of T): list of T
{
	r: list of T;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

setattrs(lv: list of ref Attr, rv: list of ref Attr): list of ref Attr
{
	# new attributes
	nl: list of ref Attr;
	for(rl := rv; rl != nil; rl = tl rl)
		if(anyattr(lv, (hd rl).name) == nil)
			nl = ref(*hd rl) :: nl;

	# new values
	for(; lv != nil; lv = tl lv){
		a := lookattr(rv, (hd lv).name);	# won't take queries
		if(a != nil)
			nl = ref *a :: nl;
	}

	return reverse(nl);
}

delattrs(lv: list of ref Attr, rv: list of ref Attr): list of ref Attr
{
	nl: list of ref Attr;
	for(; lv != nil; lv = tl lv)
		if(anyattr(rv, (hd lv).name) == nil)
			nl = hd lv :: nl;
	return reverse(nl);
}

matchattr(attrs: list of ref Attr, pat: ref Attr): int
{
	return (b := lookattr(attrs, pat.name)) != nil && (pat.tag == Aquery || b.val == pat.val);
}

matchattrs(pub: list of ref Attr, secret: list of ref Attr, pats: list of ref Attr): int
{
	for(pl := pats; pl != nil; pl = tl pl)
		if(!matchattr(pub, hd pl) && !matchattr(secret, hd pl))
			return 0;
	return 1;
}

sortattrs(attrs: list of ref Attr): list of ref Attr
{
	a := array[len attrs] of ref Attr;
	i := 0;
	for(l := attrs; l != nil; l = tl l)
		a[i++] = hd l;
	shellsort(a);
	for(i = 0; i < len a; i++)
		l = a[i] :: l;
	return l;
}

# sort into decreasing order (we'll reverse the list)
shellsort(a: array of ref Attr)
{
	n := len a;
	for(gap := n; gap > 0; ) {
		gap /= 2;
		max := n-gap;
		ex: int;
		do{
			ex = 0;
			for(i := 0; i < max; i++) {
				j := i+gap;
				if(a[i].name > a[j].name || a[i].name == nil) {
					t := a[i]; a[i] = a[j]; a[j] = t;
					ex = 1;
				}
			}
		}while(ex);
	}
}

findkey(keys: array of ref Key, attrs: list of ref Attr): ref Key
{
	if(Debug)
		sys->print("findkey %q\n", attrtext(attrs));
	for(i := 0; i < len keys; i++)
		if((k := keys[i]) != nil && matchattrs(k.attrs, k.secrets, attrs))
			return k;
	return nil;
}

delkey(keys: array of ref Key, attrs: list of ref Attr): int
{
	nk := 0;
	for(i := 0; i < len keys; i++)
		if((k := keys[i]) != nil)
			if(matchattrs(k.attrs, k.secrets, attrs)){
				nk++;
				keys[i] = nil;
			}
	return nk;
}

Key.mk(attrs: list of ref Attr): ref Key
{
	k := ref Key;
	for(; attrs != nil; attrs = tl attrs){
		a := hd attrs;
		if(a.name != nil){
			if(a.name[0] == '!')
				k.secrets = a :: k.secrets;
			else
				k.attrs = a :: k.attrs;
		}
	}
	if(k.attrs != nil || k.secrets != nil)
		return k;
	return nil;
}

addkey(keys: array of ref Key, k: ref Key): array of ref Key
{
	for(i := 0; i < len keys; i++)
		if(keys[i] == nil){
			keys[i] = k;
			return keys;
		}
	n := array[len keys+1] of ref Key;
	n[0:] = keys;
	n[len keys] = k;
	return n;
}

Key.text(k: self ref Key): string
{
	s := attrtext(k.attrs);
	if(s != nil && k.secrets != nil)
		s[len s] = ' ';
	return s + attrtext(k.secrets);
}

Key.safetext(k: self ref Key): string
{
	s := attrtext(sortattrs(k.attrs));
	sp := s != nil;
	for(sl := k.secrets; sl != nil; sl = tl sl){
		if(sp)
			s[len s] = ' ';
		s += sys->sprint("%s?", (hd sl).name);
	}
	return s;
}

any(s: string, t: string): int
{
	for(i := 0; i < len s; i++)
		for(j := 0; j < len t; j++)
			if(s[i] == t[j])
				return 1;
	return 0;
}

IO.findkey(nil: self ref IO, attrs: list of ref Attr, extra: string): (ref Key, string)
{
	ea := parseline(extra);
	for(; ea != nil; ea = tl ea)
		attrs = hd ea :: attrs;
	kc := chan of (ref Key, string);
	keymanc <-= (attrs, 1, kc);	# TO DO: 1 => 0 for not needed
	return <-kc;
}

IO.needkey(nil: self ref IO, attrs: list of ref Attr, extra: string): (ref Key, string)
{
	ea := parseline(extra);
	for(; ea != nil; ea = tl ea)
		attrs = hd ea :: attrs;
	kc := chan of (ref Key, string);
	keymanc <-= (attrs, 1, kc);
	return <-kc;
}

IO.read(io: self ref IO): array of byte
{
	io.ok();
	while((rpc := rio(io.f)) != nil)
		case rpc.cmd {
		* =>
			phase(rpc, "protocol phase error");
		Oauthinfo =>
			reply(rpc, "error authentication unfinished");
		Owrite =>
			io.rpc = rpc;
			if(rpc.arg == nil)
				rpc.arg = array[0] of byte;
			return rpc.arg;
		}
	exit;
}

IO.readn(io: self ref IO, n: int): array of byte
{
	while((buf := io.read()) != nil && len buf < n)
		io.toosmall(n);
	return buf;
}

IO.write(io: self ref IO, buf: array of byte, n: int): int
{
	io.ok();
	while((rpc := rio(io.f)) != nil)
		case rpc.cmd {
		Oread =>
			if(rpc.nbytes-3 >= n){
				okdata(rpc, buf[0:n]);
				return n;
			}
			io.toosmall(n+3);
		Oauthinfo =>
			reply(rpc, "error authentication unfinished");
		* =>
			phase(rpc, "protocol phase error");
		}
	exit;
}

IO.ok(io: self ref IO)
{
	if(io.rpc != nil){
		reply(io.rpc, "ok");
		io.rpc = nil;
	}
}

IO.toosmall(io: self ref IO, n: int)
{
	if(io.rpc != nil){
		reply(io.rpc, sys->sprint("toosmall %d", n));
		io.rpc = nil;
	}
}

IO.error(io: self ref IO, s: string)
{
	if(io.rpc != nil){
		io.rpc.rc <-= (nil, "error "+s);
		io.rpc = nil;
	}
}

IO.done(io: self ref IO, ai: ref Authinfo)
{
	io.f.ai = ai;
	io.ok();
	while((rpc := rio(io.f)) != nil)
		case rpc.cmd {
		Oread or Owrite =>
			done(rpc, ai);
			return;
		* =>
			phase(rpc, "protocol phase error");
		}
}

memrandom(a: array of byte, n: int)
{
	if(0){
		# speed up testing
		for(i := 0; i < len a; i++)
			a[i] = byte i;
		return;
	}
	fd := sys->open("/dev/notquiterandom", Sys->OREAD);
	if(fd == nil)
		err("can't open /dev/notquiterandom");
	if(sys->read(fd, a, n) != n)
		err("can't read /dev/notquiterandom");
}

eqbytes(a, b: array of byte): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

netmkaddr(addr, net, svc: string): string
{
	if(net == nil)
		net = "net";
	(n, nil) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}
