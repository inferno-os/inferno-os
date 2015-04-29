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

include "webget.m";

include "dial.m";
	DI: Dial;

include "wgutils.m";
	W: WebgetUtils;
	Fid, Req: import WebgetUtils;

include "transport.m";

FTPPORT: con "21";
DEBUG: con 1;

# Return codes
Extra, Success, Incomplete, TempFail, PermFail : con (1+iota);

init(w: WebgetUtils)
{
	sys = load Sys Sys->PATH;
	W = w;
	M = W->M;
	S = W->S;
	B = W->B;
	U = W->U;
	DI = W->DI;
}

connect(c: ref Fid, r: ref Req, donec: chan of ref Fid)
{
	mrep: ref Msg = nil;
	io, dio: ref Iobuf = nil;
	err := "";
	u := r.url;
	port := u.port;
	if(port == "")
		port = FTPPORT;
	addr := DI->netmkaddr(u.host, "tcp", port);

dummyloop:	# just for breaking out of on error
	for(;;) {
		W->log(c, sys->sprint("ftp: dialing %s", addr));
		net := DI->dial(addr, nil);
		if(net == nil) {
			err = sys->sprint("dial error: %r");
			break dummyloop;
		}
		io = B->fopen(net.dfd, sys->ORDWR);
		if(io == nil) {
			err = "cannot open network via bufio";
			break dummyloop;
		}

		# look for Hello
		(code, msg) := getreply(c, io);
		if(code != Success) {
			err = "instead of hello: " + msg;
			break dummyloop;
		}
		# logon
		err = sendrequest(c, io, "USER anonymous");
		if(err != "") 
			break dummyloop;
		(code, msg) = getreply(c, io);
		if(code != Success) {
			if(code == Incomplete) {
				# need password
				err = sendrequest(c, io, "PASS webget@webget.com");
				(code, msg) = getreply(c, io);
				if(code != Success) {
					err = "login failed: " + msg;
					break dummyloop;
				}
			}
			else {
				err = "login failed: " + msg;
				break dummyloop;
			}
		}
		# image type
		err = sendrequest(c, io, "TYPE I");
		(code, msg) = getreply(c, io);
		if(code != Success) {
			err = "can't set type I: " + msg;
			break dummyloop;
		}
		# passive mode
		err = sendrequest(c, io, "PASV");
		(code, msg) = getreply(c, io);
		if(code != Success) {
			err = "can't use passive mode: " + msg;
			break dummyloop;
		}
		(paddr, pport) := passvap(msg);
		if(paddr == "") {
			err = "passive mode protocol botch: " + msg;
			break dummyloop;
		}
		# dial data port
		daddr := "tcp!" + paddr + "!" + pport;
		W->log(c, sys->sprint("ftp: dialing data %s", daddr));
		(ok2, dnet) := sys->dial(daddr, nil);
		if(ok2 < 0) {
			err = sys->sprint("data dial error: %r");
			break dummyloop;
		}
		dio = B->fopen(dnet.dfd, sys->ORDWR);
		if(dio == nil) {
			err = "cannot open network via bufio";
			break dummyloop;
		}
		# tell remote to send file
		err = sendrequest(c, io, "RETR " + u.path);
		(code, msg) = getreply(c, io);
		if(code != Extra) {
			err = "passive mode retrieve failed: " + msg;
			break dummyloop;
		}

		mrep = Msg.newmsg();
W->log(c, "reading from dio now");
		err = W->getdata(dio, mrep, W->fixaccept(r.types), u);
W->log(c, "done reading from dio now, err=" + err);
		B->dio.close();
		if(err == "")
			W->okprefix(r, mrep);
		break dummyloop;
	}
	if(io != nil)
		B->io.close();
	if(dio != nil)
		B->dio.close();
	if(err != "")
		mrep = W->usererr(r, err);
	if(mrep != nil) {
		W->log(c, "ftp: reply ready for " + r.reqid + ": " + mrep.prefixline);
		r.reply = mrep;
		donec <-= c;
	}
}

getreply(c: ref Fid, io: ref Iobuf) : (int, string)
{
	for(;;) {
		line := B->io.gets('\n');
		n := len line;
		if(n == 0)
			break;
		if(DEBUG)
			W->log(c, "ftp: got reply: " + line);
		if(line[n-1] == '\n') {
			if(n > 2 && line[n-2] == '\r')
				line = line[0:n-2];
			else
				line = line[0:n-1];
		}
		rv := int line;
		if(rv >= 100 && rv < 600) {
			# if line is like '123-stuff'
			# then there will be more lines until
			# '123 stuff'
			if(len line<4 || line[3]==' ')
				return (rv/100, line);
		}
	}
	return (-1, "");
}

sendrequest(c: ref Fid, io: ref Iobuf, cmd: string) : string
{
	if(DEBUG)
		W->log(c, "ftp: send request: " + cmd);
	cmd = cmd + "\r\n";
	buf := array of byte cmd;
	n := len buf;
	if(B->io.write(buf, n) != n)
		return sys->sprint("write error: %r");
	return "";
}

passvap(s: string) : (string, string)
{
	# Parse reply to PASSV to find address and port numbers.
	# This is AI
	addr := "";
	port := "";
	(nil, v) := S->splitl(s, "(");
	if(v != "")
		s = v[1:];
	else
		(nil, s) = S->splitl(s, "0123456789");
	if(s != "") {
		(n, l) := sys->tokenize(s, ",");
		if(n >= 6) {
			addr = hd l + ".";
			l = tl l;
			addr += hd l + ".";
			l = tl l;
			addr += hd l + ".";
			l = tl l;
			addr += hd l;
			l = tl l;
			p1 := int hd l;
			p2 := int hd tl l;
			port = string (((p1&255)<<8)|(p2&255));
		}
	}
	return (addr, port);
}
