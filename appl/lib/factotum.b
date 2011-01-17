implement Factotum;

#
# client interface to factotum
#
# this is a near transliteration of Plan 9 code, subject to the Lucent Public License 1.02
#

include "sys.m";
	sys: Sys;

include "string.m";

include "encoding.m";

include "factotum.m";

debug := 0;

init()
{
	sys = load Sys Sys->PATH;
}

setdebug(i: int)
{
	debug = i;
}

getaia(a: array of byte, n: int): (int, array of byte)
{
	if(len a - n < 2)
		return (-1, nil);
	c := (int a[n+1]<<8) | int a[n+0];
	n += 2;
	if(len a - n < c)
		return  (-1, nil);
	b := array[c] of byte;		# could avoid copy if known not to alias
	b[0:] = a[n: n+c];
	return (n+c, b);
}

getais(a: array of byte, n: int): (int, string)
{
	(n, a) = getaia(a, n);
	return (n, string a);
}

Authinfo.unpack(a: array of byte): (int, ref Authinfo)
{
	ai := ref Authinfo;
	n: int;
	(n, ai.cuid) = getais(a, 0);
	(n, ai.suid) = getais(a, n);
	(n, ai.cap) = getais(a, n);
	(n, ai.secret) = getaia(a, n);
	if(n < 0)
		return (-1, nil);
	return (n, ai);
}

open(): ref Sys->FD
{
	return sys->open("/mnt/factotum/rpc", Sys->ORDWR);
}

mount(fd: ref Sys->FD, mnt: string, flags: int, aname: string, keyspec: string): (int, ref Authinfo)
{
	ai: ref Authinfo;
	afd := sys->fauth(fd, aname);
	if(afd != nil){
		ai = proxy(afd, open(), "proto=p9any role=client "+keyspec);
		if(debug && ai == nil){
			sys->print("proxy failed: %r\n");
			return (-1, nil);
		}
	}
	return (sys->mount(fd, afd, mnt, flags, aname), ai);
}

dump(a: array of byte): string
{
	s := sys->sprint("[%d]", len a);
	for(i := 0; i < len a; i++){
		c := int a[i];
		if(c >= ' ' && c <= 16r7E)
			s += sys->sprint("%c", c);
		else
			s += sys->sprint("\\x%.2ux", c);
	}
	return s;
}

verbof(buf: array of byte): (string, array of byte)
{
	n := len buf;
	for(i:=0; i<n && buf[i] != byte ' '; i++)
		;
	s := string buf[0:i];
	if(i < n)
		i++;
	buf = buf[i:];
	case  s {
	"ok" or "error" or "done" or "phase" or
	"protocol" or "needkey" or "toosmall" or "internal" =>
		return (s, buf);
	* =>
		sys->werrstr(sys->sprint("malformed rpc response: %q", s));
		return ("rpc failure", buf);
	}
}

dorpc(fd: ref Sys->FD, verb: string, val: array of byte): (string, array of byte)
{
	(o, a) := rpc(fd, verb, val);
	if(o != "needkey" && o != "badkey")
		return (o, a);
	return ("no key", a);	# don't know how to get key
}

rpc(afd: ref Sys->FD, verb: string, a: array of byte): (string, array of byte)
{
	va := array of byte verb;
	l := len va;
	na := len a;
	if(na+l+1 > AuthRpcMax){
		sys->werrstr("rpc too big");
		return ("toobig", nil);
	}
	buf := array[na+l+1] of byte;
	buf[0:] = va;
	buf[l] = byte ' ';
	buf[l+1:] = a;
	if(debug)
		sys->print("rpc: ->%s %s\n", verb, dump(a));
	if((n:=sys->write(afd, buf, len buf)) != len buf){
		if(n >= 0)
			sys->werrstr("rpc short write");
		return ("rpc failure", nil);
	}
	buf = array[AuthRpcMax] of byte;
	if((n=sys->read(afd, buf, len buf)) < 0){
		if(debug)
			sys->print("<- (readerr) %r\n");
		return ("rpc failure", nil);
	}
	if(n < len buf)
		buf[n] = byte 0;
	buf = buf[0:n];

	#
	# Set error string for good default behavior.
	#
	s: string;
	(t, r) := verbof(buf);
	if(debug)
		sys->print("<- %s %#q\n", t, dump(r));
	case t {
	"ok" or
	"rpc failure" =>
		;	# don't touch
	"error" =>
		if(len r == 0)
			s = "unspecified rpc error";
		else
			s = sys->sprint("%s", string r);
	"needkey" =>
		s = sys->sprint("needkey %s", string r);
	"badkey" =>
		(nf, flds) := sys->tokenize(string r, "\n");
		if(nf < 2)
			s = sys->sprint("badkey %q", string r);
		else
			s = sys->sprint("badkey %q", hd tl flds);
		break;
	"phase" =>
		s = sys->sprint("phase error: %q", string r);
	* =>
		s = sys->sprint("unknown rpc type %q (bug in rpc.c)", t);
	}
	if(s != nil)
		sys->werrstr(s);
	return (t, r);
}

Authinfo.read(fd: ref Sys->FD): ref Authinfo
{
	(o, a) := rpc(fd, "authinfo", nil);	# deprecated in p9p factotum
	e := sys->sprint("%r");
	attrs := rpcattrs(fd);
	cuid := findattrval(attrs, "cuid");
	suid := findattrval(attrs, "suid");
	secret16 := findattrval(attrs, "secret");
	secret: array of byte;
	if(secret16 != nil){
		enc16 := load Encoding Encoding->BASE16PATH;
		if(enc16 != nil)
			secret = enc16->dec(secret16);
	}
	cap := findattrval(attrs, "cap");
	if(o != "ok"){
		if(cuid != nil || suid != nil || secret != nil || cap != nil || attrs != nil)
			return ref Authinfo(cuid, suid, cap, secret, attrs);
		sys->werrstr(e);
		return nil;
	}
	(n, ai) := Authinfo.unpack(a);
	if(n <= 0)
		sys->werrstr("bad auth info from factotum");
	ai.attrs = attrs;
	if(ai.cuid == nil)
		ai.cuid = cuid;
	if(ai.suid == nil)
		ai.suid = suid;
	if(ai.cap == nil)
		ai.cap = cap;
	if(ai.secret == nil)
		ai.secret = secret;
	return ai;
}

proxy(fd: ref Sys->FD, afd: ref Sys->FD, params: string): ref Authinfo
{
	readc := chan of (array of byte, chan of (int, string));
	writec := chan of (array of byte, chan of (int, string));
	donec := chan of (ref Authinfo, string);
	spawn genproxy(readc, writec, donec, afd, params);
	for(;;)alt{
	(buf, reply) := <-readc =>
		n := sys->read(fd, buf, len buf);
		if(n == -1)
			reply <-= (-1, sys->sprint("%r"));
		else
			reply <-= (n, nil);
	(buf, reply) := <-writec =>
		n := sys->write(fd, buf, len buf);
		if(n == -1)
			reply <-= (-1, sys->sprint("%r"));
		else
			reply <-= (n, nil);
	(authinfo, err) := <-donec =>
		if(authinfo == nil)
			sys->werrstr(err);
		return authinfo;
	}
}

#
# do what factotum says
#
genproxy(
	readc: chan of (array of byte, chan of (int, string)),
	writec: chan of (array of byte, chan of (int, string)),
	donec: chan of (ref Authinfo, string),
	afd: ref Sys->FD,
	params: string)
{
	if(afd == nil){
		donec <-= (nil, "no authentication fd");
		return;
	}

	pa := array of byte params;
	(o, a) := dorpc(afd, "start", pa);
	if(o != "ok"){
		donec <-= (nil, sys->sprint("proxy start: %r"));
		return;
	}

	ai: ref Authinfo;
	err: string;
done:
	for(;;){
		(o, a) = dorpc(afd, "read", nil);
		case o {
		"done" =>
			if(len a > 0 && a[0] == byte 'h' && string a == "haveai")
				ai = Authinfo.read(afd);
			else
				ai = ref Authinfo;	# auth succeeded but empty authinfo
			break done;
		"ok" =>
			writec <-= (a[0:len a], reply := chan of (int, string));
			(n, e) := <-reply;
			if(n != len a){
				err = "proxy write fd: "+e;
				break done;
			}
		"phase" =>
			buf := array[AuthRpcMax] of {* => byte 0};
			n := 0;
			for(;;){
				(o, a) = dorpc(afd, "write", buf[0:n]);
				if(o != "toosmall")
					break;
				c := int string a;
				if(c > AuthRpcMax)
					break;
				readc <-= (buf[n:c], reply := chan of (int, string));
				(m, e) := <-reply;
				if(m <= 0){
					err = e;
					if(m == 0)
						err = sys->sprint("proxy short read");
					break done;
				}
				n += m;
			}
			if(o != "ok"){
				err = sys->sprint("proxy rpc write: %r");
				break done;
			}
		* =>
			err = sys->sprint("proxy rpc: %r");
			break done;
		}
	}
	donec <-= (ai, err);
}

#
# insecure passwords, role=client
#

getuserpasswd(keyspec: string): (string, string)
{
	str := load String String->PATH;
	if(str == nil)
		return (nil, nil);
	fd := open();
	if(fd == nil)
		return (nil, nil);
	if(((o, a) := dorpc(fd, "start", array of byte keyspec)).t0 != "ok" ||
	   ((o, a) = dorpc(fd, "read", nil)).t0 != "ok"){
		sys->werrstr("factotum: "+o);
		return (nil, nil);
	}
	flds := str->unquoted(string a);
	if(len flds != 2){
		sys->werrstr("odd response from factotum");
		return (nil, nil);
	}
	return (hd flds, hd tl flds);
}

#
# challenge/response, role=server
#

challenge(keyspec: string): ref Challenge
{
	c := ref Challenge;
	if((c.afd = open()) == nil)
		return nil;
	if(rpc(c.afd, "start", array of byte keyspec).t0 != "ok")
		return nil;
	(w, val) := rpc(c.afd, "read", nil);
	if(w != "ok")
		return nil;
	c.chal = string val;
	return c;
}

response(c: ref Challenge, resp: string): ref Authinfo
{
	if(c.afd == nil){
		sys->werrstr("auth_response: connection not open");
		return nil;
	}
	if(resp == nil){
		sys->werrstr("auth_response: nil response");
		return nil;
	}

	if(c.user != nil){
		if(rpc(c.afd, "write", array of byte c.user).t0 != "ok"){
			# we're out of phase with factotum; give up
			c.afd = nil;
			return nil;
		}
	}

	if(rpc(c.afd, "write", array of byte resp).t0 != "ok"){
		# don't close the connection; we might try again
		return nil;
	}

	(w, val) := rpc(c.afd, "read", nil);
	if(w != "done"){
		sys->werrstr(sys->sprint("unexpected factotum reply: %q %q", w, string val));
		c.afd = nil;
		return nil;
	}
	ai := Authinfo.read(c.afd);
	c.afd = nil;
	return ai;
}

#
# challenge/response, role=client
#

respond(chal: string, keyspec: string): (string, string)
{
	if((afd := open()) == nil)
		return (nil, nil);

	if(dorpc(afd, "start", array of byte keyspec).t0 != "ok" ||
	   dorpc(afd, "write", array of byte chal).t0 != "ok")
		return (nil, nil);
	(o, resp) := dorpc(afd, "read", nil);
	if(o != "ok")
		return (nil, nil);

	return (string resp, findattrval(rpcattrs(afd), "user"));
}

rpcattrs(afd: ref Sys->FD): list of ref Attr
{
	(o, a) := rpc(afd, "attr", nil);
	if(o != "ok")
		return nil;
	return parseattrs(string a);
}

#
# attributes
#

parseattrs(s: string): list of ref Attr
{
	str := load String String->PATH;
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
	# TO DO: eliminate answered queries
	return attrs;
}

Attr.text(a: self ref Attr): string
{
	case a.tag {
	Aattr =>
		return a.name;
	Aval =>
		return sys->sprint("%q=%q", a.name, a.val);
	Aquery =>
		return sys->sprint("%q?", a.name);
	* =>
		return "??";
	}
}

attrtext(attrs: list of ref Attr): string
{
	s := "";
	for(; attrs != nil; attrs = tl attrs){
		if(s != nil)
			s[len s] = ' ';
		s += (hd attrs).text();
	}
	return s;
}

findattr(attrs: list of ref Attr, n: string): ref Attr
{
	for(; attrs != nil; attrs = tl attrs)
		if((a := hd attrs).tag != Aquery && a.name == n)
			return a;
	return nil;
}

findattrval(attrs: list of ref Attr, n: string): string
{
	if((a := findattr(attrs, n)) != nil)
		return a.val;
	return nil;
}

delattr(l: list of ref Attr, n: string): list of ref Attr
{
	rl: list of ref Attr;
	for(; l != nil; l = tl l)
		if((hd l).name != n)
			rl = hd l :: rl;
	return rev(rl);
}

copyattrs(l: list of ref Attr): list of ref Attr
{
	rl: list of ref Attr;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rev(rl);
}

takeattrs(l: list of ref Attr, names: list of string): list of ref Attr
{
	rl: list of ref Attr;
	for(; l != nil; l = tl l){
		n := (hd l).name;
		for(nl := names; nl != nil; nl = tl nl)
			if((hd nl) == n){
				rl = hd l :: rl;
				break;
			}
	}
	return rev(rl);
}

publicattrs(l: list of ref Attr): list of ref Attr
{
	rl: list of ref Attr;
	for(; l != nil; l = tl l){
		a := hd l;
		if(a.tag != Aquery || a.val == nil)
			rl = a :: rl;
	}
	return rev(rl);
}

rev[T](l: list of T): list of T
{
	rl: list of T;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}
