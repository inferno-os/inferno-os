implement Transport;

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	S: String;

include "bufio.m";
	B : Bufio;
	Iobuf: import Bufio;

include "message.m";
	M: Message;
	Msg, Nameval: import M;

include "url.m";
	U: Url;
	ParsedUrl: import U;

include "dial.m";

include "webget.m";

include "wgutils.m";
	W: WebgetUtils;
	Fid, Req: import WebgetUtils;

include "transport.m";

init(w: WebgetUtils)
{
	sys = load Sys Sys->PATH;
	W = w;
	M = W->M;
	S = W->S;
	B = W->B;
	U = W->U;
}

connect(c: ref Fid, r: ref Req, donec: chan of ref Fid)
{
	u := r.url;
	mrep: ref Msg = nil;
	if(!(u.host == "" || u.host == "localhost"))
		mrep = W->usererr(r, "no remote file system to " + u.host);
	else {
		f := u.pstart + u.path;
		io := B->open(f, sys->OREAD);
		if(io == nil)
			mrep = W->usererr(r, sys->sprint("can't open %s: %r\n", f));
		else {
			mrep = Msg.newmsg();
			e := W->getdata(io, mrep, W->fixaccept(r.types), u);
			B->io.close();
			if(e != "")
				mrep = W->usererr(r, e);
			else
				W->okprefix(r, mrep);
		}
	}
	if(mrep != nil) {
		W->log(c, "file: reply ready for " + r.reqid + ": " + mrep.prefixline);
		r.reply = mrep;
		donec <-= c;
	}
}
