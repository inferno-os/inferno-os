implement Authproto;
include "sys.m";
	sys: Sys;
	Rread, Rwrite: import Sys;
include "draw.m";
include "keyring.m";
include "bufio.m";
include "sexprs.m";
	sexprs: Sexprs;
	Sexp: import sexprs;
include "spki.m";
	spki: SPKI;
include "../authio.m";
	authio: Authio;
	Aattr, Aval, Aquery: import Authio;
	Attr, IO, Key, Authinfo: import authio;

# queries to handle:
# are you a member of group X?
# are you group leader of group X?

Debug: con 0;

# init, addkey, closekey, write, read, close, keyprompt

Query: adt {
	e: ref Sexp;
	certs: list of ref Sexp;
	gotcerts: list of ref Sexp;

	parse: fn(se: ref Sexp): (ref Query, string);
	neededcert: fn(q: self ref Query): ref Sexp;
	addcert: fn(q: self ref Query, cert: ref Sexp): string;
	result: fn(q: self ref Query): ref Sexp;
};

Read: adt {
	buf: array of byte;
	ptr: int;
	off: int;
	io: ref IO;

	new: fn(io: ref IO): ref Read;
	getb: fn(r: self ref Read): int;
	ungetb: fn(r: self ref Read): int;
	offset: fn(r: self ref Read): big;
};


Maxmsg: con 4000;

init(f: Authio): string
{
	authio = f;
	sys = load Sys Sys->PATH;
	spki = load SPKI SPKI->PATH;
	spki->init();
	sexprs = load Sexprs Sexprs->PATH;
	sexprs->init();
	return nil;
}

interaction(attrs: list of ref Attr, io: ref IO): string
{
	case authio->lookattrval(attrs, "role") {
	"client" =>
		return client(attrs, io);
	"server" =>
		return server(attrs, io);
	* =>
		return "unknown role";
	}
}

client(attrs: list of ref Attr, io: ref IO): string
{
	(sexp, nil, err) := Sexp.parse(authio->lookattrval(attrs, "query"));
	if(sexp == nil || err != nil)
		raise sys->sprint("bad or empty query %q: %s", authio->lookattrval(attrs, "query"), err);
	for(;;){
		write(io, sexp.pack());
		(sexp, err) = Sexp.read(Read.new(io));
		if(err != nil)
			return "authquery: bad query: "+err;
		if(sexp == nil)
			return "authquery: no result";
		if(sexp.op() != "needcert"){
			io.done(ref Authinfo(nil, nil, nil, sexp.pack()));	# XXX use something other than secret
			return nil;
		}
		(sexp, err) = needcert(io, sexp);
		if(sexp == nil)
			return "authquery: no cert: "+err;
	}
}

server(nil: list of ref Attr, io: ref IO): string
{
	(sexp, err) := Sexp.read(Read.new(io));
	if(err != nil)
		return "authquery: bad query sexp: "+err;
	q: ref Query;
	(q, err) = Query.parse(sexp);
	if(q == nil)
		return "authquery: bad query: "+err;
	while((sexp = q.neededcert()) != nil){
		write(io, sexp.pack());
		(sexp, err) = Sexp.read(Read.new(io));
		if(err != nil)
			return "authquery: bad cert sexp: "+err;
		if((err = q.addcert(sexp)) != nil)
			return "authquery: bad certificate received: "+err;
	}
	write(io,  q.result().pack());
	io.done(ref Authinfo);
	return nil;
}

mkop(op: string, els: list of ref Sexp): ref Sexp
{
	return ref Sexp.List(ref Sexp.String(op, nil) :: els);
}

needcert(nil: ref IO, se: ref Sexp): (ref Sexp, string)
{
	return (mkop("cert", se :: nil), nil);
#	(key, err) := io.findkey(
}

write(io: ref IO, buf: array of byte)
{
	while(len buf > Maxmsg){
		io.write(buf[0:Maxmsg], Maxmsg);
		buf = buf[Maxmsg:];
	}
	io.write(buf, len buf);
}

Query.parse(sexp: ref Sexp): (ref Query, string)
{
	if(!sexp.islist())
		return (nil, "query must be a list");
	return (ref Query(sexp, sexp.els(), nil), nil);
}

Query.neededcert(q: self ref Query): ref Sexp
{
	if(q.certs == nil)
		return nil;
	c := hd q.certs;
	q.certs = tl q.certs;
	if(c.op() != "cert")
		return nil;
	for(a := c.args(); a != nil; a = tl a)
		if((hd a).op() == "delay" && (hd a).args() != nil)
			sys->sleep(int (hd (hd a).args()).astext());
	return mkop("needcert", c :: nil);
}

Query.addcert(q: self ref Query, cert: ref Sexp): string
{
	q.gotcerts = cert :: q.gotcerts;
	return nil;
}

Query.result(q: self ref Query): ref Sexp
{
	return mkop("result", q.gotcerts);
}

Read.new(io: ref IO): ref Read
{
	return ref Read(nil, 0, 0, io);
}

Read.getb(r: self ref Read): int
{
	if(r.ptr >= len r.buf){
		while((buf := r.io.read()) == nil || len buf == 0)
			r.io.toosmall(Maxmsg);
		r.buf = buf;
		r.ptr = 0;
	}
	r.off++;
	return int r.buf[r.ptr++];
}

Read.ungetb(r: self ref Read): int
{
	if(r.buf == nil || r.ptr == 0)
		return -1;
	r.off--;
	return int r.buf[--r.ptr];
}

Read.offset(r: self ref Read): big
{
	return big r.off;
}

keycheck(nil: ref Authio->Key): string
{
	return nil;
}
