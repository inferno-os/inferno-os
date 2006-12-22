implement mail;

include "sys.m";
include "draw.m";
include "bufio.m";
include "daytime.m";
include "sh.m";

mail : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

sys : Sys;
bufio : Bufio;
daytime : Daytime;

OREAD, OWRITE, ORDWR, NEWFD, FORKFD, FORKENV, NEWPGRP, UTFmax : import Sys;
FD, Dir : import sys;
fprint, sprint, sleep, create, open, read, write, remove, stat, fstat, fwstat, fildes, pctl, pipe, dup, byte2char : import sys;
Context : import Draw;
EOF : import Bufio;
Iobuf : import bufio;
time : import daytime;

DIRLEN : con 116;
PNPROC, PNGROUP : con iota;
False : con 0;
True : con 1;
EVENTSIZE : con 256;
Runeself : con 16r80;
OCEXEC : con 0;
CHEXCL : con 0; # 16r20000000;	# for the moment
CHAPPEND : con 0; # 16r40000000;

MAILDIR : con "/mail";

Win : adt {
	winid : int;
	addr : ref FD;
	body : ref Iobuf;
	ctl : ref FD;
	data : ref FD;
	event : ref FD;
	buf : array of byte;
	bufp : int;
	nbuf : int;

	wnew : fn() : ref Win;
	wwritebody : fn(w : self ref Win, s : string);
	wread : fn(w : self ref Win, m : int, n : int) : string;
	wclean : fn(w : self ref Win);
	wname : fn(w : self ref Win, s : string);
	wdormant : fn(w : self ref Win);
	wevent : fn(w : self ref Win, e : ref Event);
	wshow : fn(w : self ref Win);
	wtagwrite : fn(w : self ref Win, s : string);
	wwriteevent : fn(w : self ref Win, e : ref Event);
	wslave : fn(w : self ref Win, c : chan of Event);
	wreplace : fn(w : self ref Win, s : string, t : string);
	wselect : fn(w : self ref Win, s : string);
	wsetdump : fn(w : self ref Win, s : string, t : string);
	wdel : fn(w : self ref Win, n : int) : int;
	wreadall : fn(w : self ref Win) : string;

 	ctlwrite : fn(w : self ref Win, s : string);
 	getec : fn(w : self ref Win) : int;
 	geten : fn(w : self ref Win) : int;
 	geter : fn(w : self ref Win, s : array of byte) : (int, int);
 	openfile : fn(w : self ref Win, s : string) : ref FD;
 	openbody : fn(w : self ref Win, n : int);
};

Mesg : adt {
	w : ref Win;
	id : int;
	hdr : string;
	realhdr : string;
	replyto : string;
	text : string;
	subj : string;
	next : cyclic ref Mesg;
 	lline1 : int;
	box : cyclic ref Box;
	isopen : int;
	posted : int;

	read : fn(b : ref Box) : ref Mesg;
	open : fn(m : self ref Mesg);
	slave : fn(m : self ref Mesg);
	free : fn(m : self ref Mesg);
	save : fn(m : self ref Mesg, s : string);
	mkreply : fn(m : self ref Mesg);
	mkmail : fn(b : ref Box, s : string);
	putpost : fn(m : self ref Mesg, e : ref Event);

 	command : fn(m : self ref Mesg, s : string) : int;
 	send : fn(m : self ref Mesg);
};

Box : adt {
	w : ref Win;
	nm : int;
	readonly : int;
	m : cyclic ref Mesg;
	file : string;
	io : ref Iobuf;
	clean : int;
 	leng : big;
 	cdel : chan of ref Mesg;
	cevent : chan of Event;
	cmore : chan of int;
	
	line : string;
	peekline : string;

	read : fn(s : string, n : int) : ref Box;
	readmore : fn(b : self ref Box);
	readline : fn(b : self ref Box) : string;
	unreadline : fn(b : self ref Box);
	slave : fn(b : self ref Box);
	mopen : fn(b : self ref Box, n : int);
	rewrite : fn(b : self ref Box);
	mdel : fn(b : self ref Box, m : ref Mesg);
	event : fn(b : self ref Box, e : ref Event);

	command : fn(b : self ref Box, s : string) : int;
};

Event : adt {
	c1 : int;
	c2 : int;
	q0 : int;
	q1 : int;
	flag : int;
	nb : int;
	nr : int;
	b : array of byte;
	r : array of int;
};

Lock : adt {
	cnt : int;
	chann : chan of int;

	init : fn() : ref Lock;
	lock : fn(l : self ref Lock);
	unlock : fn(l : self ref Lock);
};

Ref : adt {
	l : ref Lock;
	cnt : int;

	init : fn() : ref Ref;
	inc : fn(r : self ref Ref) : int;
};

mbox : ref Box;
mboxfile : string;
usermboxfile : string;
usermboxdir : string;
lockfile : string;
user : string;
date : string;
mailctxt : ref Context;
stdout, stderr : ref FD;

killing : int = 0;

init(ctxt : ref Context, argl : list of string)
{
	mailctxt = ctxt;
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	daytime = load Daytime Daytime->PATH;
	stdout = fildes(1);
	stderr = fildes(2);
	main(argl);
}

dlock : ref Lock;
dfd : ref Sys->FD;

debug(s : string)
{
	if (dfd == nil) {
		dfd = sys->create("/usr/jrf/acme/debugmail", Sys->OWRITE, 8r600);
		dlock = Lock.init();
	}
	if (dfd == nil)
		return;
	dlock.lock();
	sys->fprint(dfd, "%s", s);	
	dlock.unlock();
}

postnote(t : int, pid : int, note : string) : int
{
	fd := open("#p/" + string pid + "/ctl", OWRITE);
	if (fd == nil)
		return -1;
	if (t == PNGROUP)
		note += "grp";
	fprint(fd, "%s", note);
	fd = nil;
	return 0;
}

exec(cmd : string, argl : list of string)
{
	file := cmd;
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";

	c := load Command file;
	if(c == nil) {
		err := sprint("%r");
		if(file[0]!='/' && file[0:2]!="./"){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sprint("%r");
		}
		if(c == nil){
			fprint(stderr, "%s: %s\n", cmd, err);
			return;
		}
	}
	c->init(mailctxt, argl);
}

swrite(fd : ref FD, s : string) : int
{
	ab := array of byte s;
	m := len ab;
	p := write(fd, ab, m);
	if (p == m)
		return len s;
	if (p <= 0)
		return p;
	return 0;
}

strchr(s : string, c : int) : int
{
	for (i := 0; i < len s; i++)
		if (s[i] == c)
			return i;
	return -1;
} 

strrchr(s : string, c : int) : int
{
	for (i := len s - 1; i >= 0; i--)
		if (s[i] == c)
			return i;
	return -1;
}

strtoi(s : string) : (int, int)
{
	m := 0;
	neg := 0;
	t := 0;
	ls := len s;
	while (t < ls && (s[t] == ' ' || s[t] == '\t'))
		t++;
	if (t < ls && s[t] == '+')
		t++;
	else if (t < ls && s[t] == '-') {
		neg = 1;
		t++;
	}
	while (t < ls && (s[t] >= '0' && s[t] <= '9')) {
		m = 10*m + s[t]-'0';
		t++;
	}
	if (neg)
		m = -m;
	return (m, t);	
}

access(s : string) : int
{
	fd := open(s, 0);
	if (fd == nil)
		return -1;
	fd = nil;
	return 0;
}

newevent() : ref Event
{
	e := ref Event;
	e.b = array[EVENTSIZE*UTFmax+1] of byte;
	e.r = array[EVENTSIZE+1] of int;
	return e;
}	

newmesg() : ref Mesg
{
	m := ref Mesg;
	m.id = m.lline1 = m.isopen = m.posted = 0;
	return m;
}

lc, uc : chan of ref Lock;

initlock()
{
	lc = chan of ref Lock;
	uc = chan of ref Lock;
	spawn lockmgr();
}

lockmgr()
{
	l : ref Lock;

	for (;;) {
		alt {
			l = <- lc =>
				if (l.cnt++ == 0)
					l.chann <-= 1;
			l = <- uc =>
				if (--l.cnt > 0)
					l.chann <-= 1;
		}
	}
}

Lock.init() : ref Lock
{
	return ref Lock(0, chan of int);
}

Lock.lock(l : self ref Lock)
{
	lc <-= l;
	<- l.chann;
}

Lock.unlock(l : self ref Lock)
{
	uc <-= l;
}

Ref.init() : ref Ref
{
	r := ref Ref;
	r.l = Lock.init();
	r.cnt = 0;
	return r;
}

Ref.inc(r : self ref Ref) : int
{
	r.l.lock();
	i := r.cnt;
	r.cnt++;
	r.l.unlock();
	return i;
}

error(s : string)
{
	if(s != nil)
		fprint(stderr, "mail: %s\n", s);
	rmlockfile();
# debug(sprint("error %s\n", s));
	postnote(PNGROUP, pctl(0, nil), "kill");
	killing = 1;
	exit;
}

rmlockfile()
{
	if (lockfile != nil) {
		remove(lockfile);
		lockfile = nil;
	}
}

#
#  try opening a lock file.  If it doesn't exist try creating it.
#
openlockfile(path : string) : ref FD
{
	try : int;
	fd : ref FD;

	try = 0;
	for(;;){
		# fd = open(path, OWRITE);
		# if(fd!=nil || ++try>3)
		# 	return fd;
		if(++try > 3)
			return fd;
		(ok, d) := stat(path);
		if(ok >= 0)
			sleep(1000);
		else{
			fd = create(path, OWRITE, CHEXCL|8r666);
			if(fd != nil){
				(ok, d) = fstat(fd);
				if(ok >= 0){
					d.mode |= CHEXCL|8r666;
					fwstat(fd, d);
				}
				return fd;
			}
			break;
		}
	}
	return nil;
}

tryopen(s : string, mode : int) : ref FD
{
	fd : ref FD;
	try : int;

	for(try=0; try<3; try++){
		fd = open(s, mode);
		if(fd != nil)
			return fd;
		sleep(1000);
	}
	return nil;
}

run(argv : list of string, c : chan of int, p0 : ref FD)
{
	# pctl(FORKFD|NEWPGRP, nil);	# had RFMEM
	pctl(FORKENV|NEWFD|NEWPGRP, 0::1::2::p0.fd::nil);
	c <-= pctl(0, nil);
	dup(p0.fd, 0);
	p0 = nil;
	exec(hd argv, argv);
	exit;
}

getuser() : string
{
  	fd := open("/dev/user", OREAD);
  	if(fd == nil)
    		return "";
  	buf := array[128] of byte;
  	n := read(fd, buf, len buf);
  	if(n < 0)
    		return "";
  	return string buf[0:n];	
}

main(argv : list of string)
{
	fd : ref FD;
	readonly : int;
	buf : string;

	initlock();
	initreply();
	date = time();
	if(date==nil)
		error("can't get current time");
	user = getuser();
	if(user == nil)
		user = "Wile.E.Coyote";
	usermboxdir = MAILDIR + "/box/" + user + "/";
	usermboxfile = MAILDIR + "/box/" + user + "/mbox";
	if(len argv > 1)
		mboxfile = hd tl argv;
	else
		mboxfile = usermboxfile;

	fd = nil;
	readonly = False;
	if(mboxfile == usermboxfile){
		buf = MAILDIR + "/box/" + user + "/L.reading";
		fd = openlockfile(buf);
		if(fd == nil){
			fprint(stderr, "Mail: %s in use; opened read-only\n", mboxfile);
			readonly = True;
		}
		else
			lockfile = buf;
	}
	mbox = mbox.read(mboxfile, readonly);
	spawn timeslave(fd, mbox, mbox.cmore);
	mbox.slave();
	error(nil);
}

timeslave(rlock : ref FD, b : ref Box, c : chan of int)
{
	buf := array[DIRLEN] of byte;
	for(;;){
		sleep(30*1000);
		if(rlock != nil && write(rlock, buf, 0)<0)
			error("can't maintain L.reading: %r");
		(ok, d) := stat(mboxfile);
		if (ok >= 0 && d.length > b.leng)
			c <-= 0;
	}
}

Win.wnew() : ref Win
{
	w := ref Win;
	buf := array[12] of byte;
	w.ctl = open("/chan/new/ctl", ORDWR);
	if(w.ctl==nil || read(w.ctl, buf, 12)!=12)
		error("can't open window ctl file: %r");
	w.ctlwrite("noscroll\n");
	w.winid = int string buf;
	w.event = w.openfile("event");
	w.addr = nil;	# will be opened when needed
	w.body = nil;
	w.data = nil;
	w.bufp = w.nbuf = 0;
	w.buf = array[512] of byte;
	return w;
}

Win.openfile(w : self ref Win, f : string) : ref FD
{
	buf := sprint("/chan/%d/%s", w.winid, f);
	fd := open(buf, ORDWR|OCEXEC);
	if(fd == nil)
		error(sprint("can't open window %s file: %r", f));
	return fd;
}

Win.openbody(w : self ref Win, mode : int)
{
	buf := sprint("/chan/%d/body", w.winid);
	w.body = bufio->open(buf, mode|OCEXEC);
	if(w.body == nil)
		error("can't open window body file: %r");
}

Win.wwritebody(w : self ref Win, s : string)
{
	n := len s;
	if(w.body == nil)
		w.openbody(OWRITE);
	if(w.body.puts(s) != n)
		error("write error to window: %r");
}

Win.wreplace(w : self ref Win, addr : string, repl : string)
{
	if(w.addr == nil)
		w.addr = w.openfile("addr");
	if(w.data == nil)
		w.data = w.openfile("data");
	if(swrite(w.addr, addr) < 0){
		fprint(stderr, "mail: warning: bad address %s:%r\n", addr);
		return;
	}
	if(swrite(w.data, repl) != len repl)
		error("writing data: %r");
}

nrunes(s : array of byte, nb : int) : int
{
	i, n : int;

	n = 0;
	for(i=0; i<nb; n++) {
		(r, b, ok) := byte2char(s, i);
		if (!ok)
			error("help needed in nrunes()");
		i += b;
	}
	return n;
}

Win.wread(w : self ref Win, q0 : int, q1 : int) : string
{
	m, n, nr : int;
	s, buf : string;
	b : array of byte;

	b = array[256] of byte;
	if(w.addr == nil)
		w.addr = w.openfile("addr");
	if(w.data == nil)
		w.data = w.openfile("data");
	s = nil;
	m = q0;
	while(m < q1){
		buf = sprint("#%d", m);
		if(swrite(w.addr, buf) != len buf)
			error("writing addr: %r");
		n = read(w.data, b, len b);
		if(n <= 0)
			error("reading data: %r");
		nr = nrunes(b, n);
		while(m+nr >q1){
			do; while(n>0 && (int b[--n]&16rC0)==16r80);
			--nr;
		}
		if(n == 0)
			break;
		s += string b[0:n];
		m += nr;
	}
	return s;
}

Win.wshow(w : self ref Win)
{
	w.ctlwrite("show\n");
}

Win.wsetdump(w : self ref Win, dir : string, cmd : string)
{
	t : string;

	if(dir != nil){
		t = "dumpdir " + dir + "\n";
		w.ctlwrite(t);
		t = nil;
	}
	if(cmd != nil){
		t = "dump " + cmd + "\n";
		w.ctlwrite(t);
		t = nil;
	}
}

Win.wselect(w : self ref Win, addr : string)
{
	if(w.addr == nil)
		w.addr = w.openfile("addr");
	if(swrite(w.addr, addr) < 0)
		error("writing addr");
	w.ctlwrite("dot=addr\n");
}

Win.wtagwrite(w : self ref Win, s : string)
{
	fd : ref FD;

	fd = w.openfile("tag");
	if(swrite(fd, s) != len s)
		error("tag write: %r");
	fd = nil;
}

Win.ctlwrite(w : self ref Win, s : string)
{
	if(swrite(w.ctl, s) != len s)
		error("write error to ctl file: %r");
}

Win.wdel(w : self ref Win, sure : int) : int
{
	if (w == nil)
		return False;
	if(sure)
		swrite(w.ctl, "delete\n");
	else if(swrite(w.ctl, "del\n") != 4)
		return False;
	w.wdormant();
	w.ctl = nil;
	w.event = nil;
	return True;
}

Win.wname(w : self ref Win, s : string)
{
	w.ctlwrite("name " + s + "\n");
}

Win.wclean(w : self ref Win)
{
	if(w.body != nil)
		w.body.flush();
	w.ctlwrite("clean\n");
}

Win.wdormant(w : self ref Win)
{
	w.addr = nil;
	if(w.body != nil){
		w.body.close();
		w.body = nil;
	}
	w.data = nil;
}

Win.getec(w : self ref Win) : int
{
	if(w.nbuf == 0){
		w.nbuf = read(w.event, w.buf, len w.buf);
		if(w.nbuf <= 0 && !killing) {
			error("event read error: %r");
		}
		w.bufp = 0;
	}
	w.nbuf--;
	return int w.buf[w.bufp++];
}

Win.geten(w : self ref Win) : int
{
	n, c : int;

	n = 0;
	while('0'<=(c=w.getec()) && c<='9')
		n = n*10+(c-'0');
	if(c != ' ')
		error("event number syntax");
	return n;
}

Win.geter(w : self ref Win, buf : array of byte) : (int, int)
{
	r, m, n, ok : int;

	r = w.getec();
	buf[0] = byte r;
	n = 1;
	if(r >= Runeself) {
		for (;;) {
			(r, m, ok) = byte2char(buf[0:n], 0);
			if (m > 0)
				return (r, n);
			buf[n++] = byte w.getec();
		}
	}
	return (r, n);
}

Win.wevent(w : self ref Win, e : ref Event)
{
	i, nb : int;

	e.c1 = w.getec();
	e.c2 = w.getec();
	e.q0 = w.geten();
	e.q1 = w.geten();
	e.flag = w.geten();
	e.nr = w.geten();
	if(e.nr > EVENTSIZE)
		error("event string too long");
	e.nb = 0;
	for(i=0; i<e.nr; i++){
		(e.r[i], nb) = w.geter(e.b[e.nb:]);
		e.nb += nb;
	}
	e.r[e.nr] = 0;
	e.b[e.nb] = byte 0;
	c := w.getec();
	if(c != '\n')
		error("event syntax 2");
}

Win.wslave(w : self ref Win, ce : chan of Event)
{
	e : ref Event;

	e = newevent();
	for(;;){
		w.wevent(e);
		ce <-= *e;
	}
}

Win.wwriteevent(w : self ref Win, e : ref Event)
{
	fprint(w.event, "%c%c%d %d\n", e.c1, e.c2, e.q0, e.q1);
}

Win.wreadall(w : self ref Win) : string
{
	s, t : string;

	if(w.body != nil)
		w.body.close();
	w.openbody(OREAD);
	s = nil;
	while ((t = w.body.gets('\n')) != nil)
		s += t;
	w.body.close();
	w.body = nil;
	return s;
}

ignored : int;

None,Unknown,Ignore,CC,From,ReplyTo,Sender,Subject,Re,To, Date : con iota;
NHeaders : con 200;

Hdrs : adt {
	name : string;
	typex : int;
};


hdrs := array[NHeaders+1] of {
	Hdrs ( "CC:",				CC ),
	Hdrs ( "From:",				From ),
	Hdrs ( "Reply-To:",			ReplyTo ),
	Hdrs ( "Sender:",			Sender ),
	Hdrs ( "Subject:",			Subject ),
	Hdrs ( "Re:",				Re ),
	Hdrs ( "To:",				To ),
	Hdrs ( "Date:",				Date),
 * => Hdrs ( "",					0 ),
};

StRnCmP(s : string, t : string, n : int) : int
{
	c, d, i, j : int;

	i = j = 0;
	if (len s < n || len t < n)
		return -1;
	while(n > 0){
		c = s[i++];
		d = t[j++];
		--n;
		if(c != d){
			if('a'<=c && c<='z')
				c -= 'a'-'A';
			if('a'<=d && d<='z')
				d -= 'a'-'A';
			if(c != d)
				return c-d;
		}
	}
	return 0;
}

ignore()
{
	b : ref Iobuf;
	s : string;
	i : int;

	ignored = True;
	b = bufio->open(MAILDIR + "/lib/ignore", OREAD);
	if(b == nil)
		return;
	for(i=0; hdrs[i].name != nil; i++)
		;
	while((s = b.gets('\n')) != nil){
		s = s[0:len s - 1];
		hdrs[i].name = s;
		hdrs[i].typex = Ignore;
		if(++i >= NHeaders){
			fprint(stderr, "%s/lib/ignore has more than %d headers\n", MAILDIR, NHeaders);
			break;
		}
	}
	b.close();
}

readhdr(b : ref Box) : (string, int)
{
	i, j, n, m, typex : int;
	s, t : string;

	{
		if(!ignored)
			ignore();
		s = b.readline();
		n = len s;
		if(n <= 0)
			raise("e");
		for(i=0; i<n; i++){
			j = s[i];
			if(i>0 && j == ':')
				break;
			if(j<'!' || '~'<j){
				b.unreadline();
				raise("e");
			}
		}
		typex = Unknown;
		for(i=0; hdrs[i].name != nil; i++){
			j = len hdrs[i].name;
			if(StRnCmP(hdrs[i].name, s, j) == 0){
				typex = hdrs[i].typex;
				break;
			}
		}
		# scan for multiple sublines 
		for(;;){
			t = b.readline();
			m = len t;
			if(m<=0 || (t[0]!=' ' && t[0]!='\t')){
				b.unreadline();
				break;
			}
			# absorb 
			s += t;
		}
		return(s, typex);
	}
	exception{
		"*" =>
			return (nil, None);
	}
}

Mesg.read(b : ref Box) : ref Mesg
{
	m : ref Mesg;
	s : string;
	n, typex : int;

	s = b.readline();
	n = len s;
	if(n <= 0)
		return nil;

{
	if(n < 5 || s[0:5] !="From ")
		raise("e");
	m = newmesg();
	m.realhdr = s;
	# toss 'From ' 
	s = s[5:];
	n -= 5;
	# toss spaces/tabs
	while (n > 0 && (s[0] == ' ' || s[0] == '\t')) {
		s = s[1:];
		n--;
	}
	m.hdr = s;
	# convert first blank to tab 
	s0 := strchr(m.hdr, ' ');
	if(s0 >= 0){
		m.hdr[s0] = '\t';
		# drop trailing seconds, time zone, and year if match local year 
		t := n-6;
		if(t <= 0)
			raise("e");
		if(m.hdr[t:n-1] == date[23:]){
			m.hdr = m.hdr[0:t] + "\n";	# drop year for sure
			t = -1;
			s1 := strchr(m.hdr[s0:], ':');
			if(s1 >= 0)
				t = strchr(m.hdr[s0+s1+1:], ':');
			if(t >= 0)	# drop seconds and time zone 
				m.hdr = m.hdr[0:s0+s1+t+1] + "\n";
			else{	# drop time zone 
				t = strchr(m.hdr[s0+s1+1:], ' ');
				if(t >= 0)
					m.hdr = m.hdr[0:s0+s1+t+1] + "\n";
			}
			n = len m.hdr;
		}
	}
	m.lline1 = n;
	m.text = nil;
	# read header 
loop:
	for(;;){
		(s, typex) = readhdr(b);
		case(typex){
		None =>
			break loop;
		ReplyTo =>
			m.replyto = s[9:];
			break;
		From =>
			if(m.replyto == nil)
				m.replyto = s[5:];
			break;
		Subject =>
			m.subj = s[8:];
			break;
		Re =>
			m.subj = s[3:];
			break;
		Date =>
			break;
		}
		m.realhdr += s;
		if(typex != Ignore)
			m.hdr += s;
	}
	# read body 
	for(;;){
		s = b.readline();
		n = len s;
		if(n <= 0)
			break;
		if(len s >= 5 && s[0:5] == "From "){
			b.unreadline();
			break;
		}
		m.text += s;
	}
	# remove trailing "morF\n" 
	l := len m.text;
	if(l>6 && m.text[l-6:] == "\nmorF\n")
		m.text = m.text[0:l-5];
	m.box = b;
	return m;
}
exception{
	"*" =>
		error("malformed header " + s);
		return nil;
}
}

Mesg.mkmail(b : ref Box, hdr : string)
{
	r : ref Mesg;

	r = newmesg();
	r.hdr = hdr + "\n";
	r.lline1 = len r.hdr;
	r.text = nil;
	r.box = b;
	r.open();
	r.w.wdormant();
}

replyaddr(r : string) : string
{
	p, q, rr : int;

	rr = 0;
	while(r[rr]==' ' || r[rr]=='\t')
		rr++;
	r = r[rr:];
	p = strchr(r, '<');
	if(p >= 0){
		q = strchr(r[p+1:], '>');
		if(q < 0)
			r = r[p+1:];
		else
			r = r[p+1:p+q] + "\n";
		return r;
	}
	p = strchr(r, '(');
	if(p >= 0){
		q = strchr(r[p:], ')');
		if(q < 0)
			r = r[0:p];
		else
			r = r[0:p] + r[p+q+1:];
	}
	return r;
}

Mesg.mkreply(m : self ref Mesg)
{
	r : ref Mesg;

	r = newmesg();
	if(m.replyto != nil){
		r.hdr = replyaddr(m.replyto);
		r.lline1 = len r.hdr;
	}else{
		r.hdr = m.hdr[0:m.lline1];
		r.lline1 = m.lline1;	# was len m.hdr;
	}
	if(m.subj != nil){
		if(StRnCmP(m.subj, "re:", 3)==0 || StRnCmP(m.subj, " re:", 4)==0)
			r.text = "Subject:" + m.subj + "\n";
		else
			r.text = "Subject: Re:" + m.subj + "\n";
	}
	else
		r.text = nil;
	r.box = m.box;
	r.open();
	r.w.wselect("$");
	r.w.wdormant();
}

Mesg.free(m : self ref Mesg)
{
	m.text = nil;
	m.hdr = nil;
	m.subj = nil;
	m.realhdr = nil;
	m.replyto = nil;
	m = nil;
}

replyid : ref Ref;

initreply()
{
	replyid = Ref.init();
}

Mesg.open(m : self ref Mesg)
{
	buf: string;

	if(m.isopen)
		return;
	m.w = Win.wnew();
	if(m.id != 0)
		m.w.wwritebody("From ");
	m.w.wwritebody(m.hdr);
	m.w.wwritebody(m.text);
	if(m.id){
		buf = sprint("%s/%d", m.box.file , m.id);
		m.w.wtagwrite("Reply Delmesg Save");
	}else{
		buf = sprint("%s/Reply%d", m.box.file, replyid.inc());
		m.w.wtagwrite("Post");
	}
	m.w.wname(buf);
	m.w.wclean();
	m.w.wselect("0");
	m.isopen = True;
	m.posted = False;
	spawn m.slave();
}

Mesg.putpost(m : self ref Mesg, e : ref Event)
{
	if(m.posted || m.id==0)
		return;
	if(e.q0 >= len m.hdr+5)	# include "From " 
		return;
	m.w.wtagwrite(" Post");
	m.posted = True;
	return;
}

Mesg.slave(m : self ref Mesg)
{
	e, e2, ea, etoss, eq : ref Event;
	s : string;
	na : int;

	e = newevent();
	e2 = newevent();
	ea = newevent();
	etoss = newevent();
	for(;;){
		m.w.wevent(e);
		case(e.c1){
		'E' =>	# write to body; can't affect us 
			break;
		'F' =>	# generated by our actions; ignore 
			break;
		'K' or 'M' =>	# type away; we don't care 
			case(e.c2){
			'x' or 'X' =>	# mouse only 
				eq = e;
				if(e.flag & 2){
					m.w.wevent(e2);
					eq = e2;
				}
				if(e.flag & 8){
					m.w.wevent(ea);
					m.w.wevent(etoss);
					na = ea.nb;
				}else
					na = 0;
				if(eq.q1>eq.q0 && eq.nb==0)
					s = m.w.wread(eq.q0, eq.q1);
				else
					s = string eq.b[0:eq.nb];
				if(na)
					s = s + " " + string ea.b[0:ea.nb];
				if(!m.command(s))	# send it back 
					m.w.wwriteevent(e);
				s = nil;
				break;
			'l' or 'L' =>	# mouse only 
				if(e.flag & 2)
					m.w.wevent(e2);
				# just send it back 
				m.w.wwriteevent(e);
				break;
			'I' or 'D' =>	# modify away; we don't care 
				m.putpost(e);
				break;
			'd' or 'i' =>
				break;
			* =>
				fprint(stdout, "unknown message %c%c\n", e.c1, e.c2);
				break;
			}
		* =>
			fprint(stdout, "unknown message %c%c\n", e.c1, e.c2);
			break;
		}
	}
}

Mesg.command(m : self ref Mesg, s : string) : int
{
	while(s[0]==' ' || s[0]=='\t' || s[0]=='\n')
		s = s[1:];
	if(s == "Post"){
		m.send();
		return True;
	}
	if(len s >= 4 && s[0:4] == "Save"){
		s = s[4:];
		while(s[0]==' ' || s[0]=='\t' || s[0]=='\n')
			s = s[1:];
		if(s == nil)
			m.save("stored");
		else{
			ss := 0;
			while(ss < len s && s[ss]!=' ' && s[ss]!='\t' && s[ss]!='\n')
				ss++;
			m.save(s[0:ss]);
		}
		return True;
	}
	if(s == "Reply"){
		m.mkreply();
		return True;
	}
	if(s == "Del"){
		if(m.w.wdel(False)){
			m.isopen = False;
			exit;
		}
		return True;
	}
	if(s == "Delmesg"){
		if(m.w.wdel(False)){
			m.isopen = False;
			m.box.cdel <-= m;
			exit;
		}
		return True;
	}
	return False;
}

Mesg.save(m : self ref Mesg, base : string)
{
	s, buf : string;
	n : int;
	fd : ref FD;
	b : ref Iobuf;

	if(m.id <= 0){
		fprint(stderr, "can't save reply message; mail it to yourself\n");
		return;
	}
	buf = nil;
	if(strchr(base, '/') >= 0)
		s = base;
	else
		s = usermboxdir + base;
	{
		if(access(s) < 0)
			raise("e");
		fd = tryopen(s, OWRITE);
		if(fd == nil)
			raise("e");
		buf = nil;
		b = bufio->fopen(fd, OWRITE);
		# seek to end in case file isn't append-only 
		b.seek(big 0, 2);
		# use edited headers: first line of real header followed by remainder of selected ones 
		for(n=0; n<len m.realhdr && m.realhdr[n++]!='\n'; )
			;
		b.puts(m.realhdr[0:n]);
		b.puts(m.hdr[m.lline1:]);
		b.puts(m.text);
		b.close();
		b = nil;
		fd = nil;
	}
	exception{
		"*" =>
			buf = nil;
			fprint(stderr, "mail: can't open %s: %r\n", base);
			return;
	}
}

Mesg.send(m : self ref Mesg)
{
	s, buf : string;
	t, u : int;
	a, b : list of string;
	n : int;
	p : array of ref FD;
	c : chan of int;

	p = array[2] of ref FD;
	s = m.w.wreadall();
	a = "sendmail" :: nil;
	if(len s >= 5 && s[0:5] == "From ")
		s = s[5:];
	for(t=0; t < len s && s[t]!='\n' && s[t]!='\t';){
		while(t < len s && (s[t]==' ' || s[t]==','))
			t++;
		u = t;
		while(t < len s && s[t]!=' ' && s[t]!=',' && s[t]!='\t' && s[t]!='\n')
			t++;
		if(t == u)
			break;
		a = s[u:t] :: a;
	}
	b = nil;
	for ( ; a != nil; a = tl a)
		b = hd a :: b;
	a = b;
	while(t < len s && s[t]!='\n')
		t++;
	if(s[t] == '\n')
		t++;
	if(pipe(p) < 0)
		error("can't pipe: %r");
	c = chan of int;
	spawn run(a, c, p[0]);
	<-c;
	c = nil;
	p[0] = nil;
	n = len s - t;
	if(swrite(p[1], s[t:]) != n)
		fprint(stderr, "write to pipe failed: %r\n");
	p[1] = nil;
	# run() frees the arg list 
	buf = sprint("%s/%d-R", m.box.file, m.id);
	m.w.wname(buf);
	m.w.wclean();
}

Box.read(f : string, readonly : int) : ref Box
{
	b : ref Box;
	m : ref Mesg;
	s, buf : string;

	b = ref Box;
	b.nm = 0;
	b.readonly = readonly;
	b.file = f;
	b.io = bufio->open(f, OREAD|OCEXEC);
	if(b.io == nil)
		error(sprint("can't open %s: %r", f));
	b.w = Win.wnew();
	if (!readonly)
		spawn lockfilemon(b.w.winid);
	while((m = m.read(b)) != nil){
		m.next = b.m;
		b.m = m;
		b.nm++;
		m.id = b.nm;
	}
	b.leng = b.io.offset();
	b.io.close();
	b.io = nil;
	# b.w = Win.wnew();
	for(m=b.m; m != nil; m=m.next){
		if(m.subj != nil)
			buf = sprint("%d\t%s\t %s", m.id, m.hdr[0:m.lline1], m.subj);
		else
			buf = sprint("%d\t%s", m.id, m.hdr[0:m.lline1]);
		b.w.wwritebody(buf);
	}
	buf = sprint("Mail/%s/", s);
	b.w.wname(f);
	if(b.readonly)
		b.w.wtagwrite("Mail");
	else
		b.w.wtagwrite("Put Mail");
	buf = "Mail " + f; 
	b.w.wsetdump("/acme/mail", buf);
	b.w.wclean();
	b.w.wselect("0");
	b.w.wdormant();
	b.cdel= chan of ref Mesg;
	b.cevent = chan of Event;
	b.cmore = chan of int;
	spawn b.w.wslave(b.cevent);
	b.clean = True;
	return b;
}

Box.readmore(b : self ref Box)
{
	m : ref Mesg;
	new : int;
	buf : string;
	doclose : int;

	doclose = False;
	if(b.io == nil){
		b.io = bufio->open(b.file, OREAD|OCEXEC);
		if(b.io == nil)
			error(sprint("can't open %s: %r", b.file));
		b.io.seek(b.leng, 0);
		doclose = True;
	}
	new = False;
	while((m = m.read(b)) != nil){
		m.next = b.m;
		b.m = m;
		b.nm++;
		m.id = b.nm;
		if(m.subj != nil)
			buf  = sprint("%d\t%s\t  %s", m.id, m.hdr[0:m.lline1], m.subj);
		else
			buf = sprint("%d\t%s", m.id, m.hdr[0:m.lline1]);
		b.w.wreplace("0", buf);
		new = True;
	}
	b.leng = b.io.offset();
	if(doclose){
		b.io.close();
		b.io = nil;
	}
	if(new){
		if(b.clean)
			b.w.wclean();
		b.w.wselect("0;/.*(\\n[ \t].*)*");
		b.w.wshow();
	}
	b.w.wdormant();
}

Box.readline(b : self ref Box) : string
{
    	for (;;) {
		if(b.peekline != nil){
			b.line = b.peekline;
			b.peekline = nil;
		}else
			b.line = b.io.gets('\n');
		# nulls appear in mailboxes! 
		if(b.line != nil && strchr(b.line, 0) >= 0)
			;
		else
			break;
	}
	return b.line;
}

Box.unreadline(b : self ref Box)
{
	b.peekline = b.line;
}

Box.slave(b : self ref Box)
{
	e : ref Event;
	m : ref Mesg;

	e = newevent();
	for(;;){
		alt{
		*e = <-b.cevent =>
			b.event(e);
			break;
		<-b.cmore =>
			b.readmore();
			break;
		m = <-b.cdel =>
			b.mdel(m);
			break;
		}
	}
}

Box.event(b : self ref Box, e : ref Event)
{
	e2, ea, eq : ref Event;
	s : string;
	t : int;
	n, na, nopen : int;

	e2 = newevent();
	ea = newevent();
	case(e.c1){
	'E' =>	# write to body; can't affect us 
		break;
	'F' =>	# generated by our actions; ignore 
		break;
	'K' =>	# type away; we don't care 
		break;
	'M' =>
		case(e.c2){
		'x' or 'X' =>
			if(e.flag & 2)
				*e2 = <-b.cevent;
			if(e.flag & 8){
				*ea = <-b.cevent;
				na = ea.nb;
				<- b.cevent;
			}else
				na = 0;
			s = string e.b[0:e.nb];
			# if it's a known command, do it 
			if((e.flag&2) && e.nb==0)
				s = string e2.b[0:e2.nb];
			if(na)
				s = sprint("%s %s", s, string ea.b[0:ea.nb]);
			# if it's a long message, it can't be for us anyway 
			if(!b.command(s))	# send it back 
				b.w.wwriteevent(e);
			if(na)
				s = nil;
			break;
		'l' or 'L' =>
			eq = e;
			if(e.flag & 2){
				*e2 = <-b.cevent;
				eq = e2;
			}
			s = string eq.b[0:eq.nb];
			if(eq.q1>eq.q0 && eq.nb==0)
				s = b.w.wread(eq.q0, eq.q1);
			nopen = 0;
			do{
				t = 0;
				(n, t) = strtoi(s);
				if(n>0 && (t == len s || s[t]==' ' || s[t]=='\t' || s[t]=='\n')){
					b.mopen(n);
					nopen++;
					s = s[t:];
				}
				while(s != nil && s[0]!='\n')
					s = s[1:];
			}while(s != nil);
			if(nopen == 0)	# send it back 
				b.w.wwriteevent(e);
			break;
		'I' or 'D' or 'd' or 'i' =>	# modify away; we don't care 
			break;
		* =>
			fprint(stdout, "unknown message %c%c\n", e.c1, e.c2);
			break;
		}
	* =>
		fprint(stdout, "unknown message %c%c\n", e.c1, e.c2);
		break;
	}
}

Box.mopen(b : self ref Box, id : int)
{
	m : ref Mesg;

	for(m=b.m; m != nil; m=m.next)
		if(m.id == id){
			m.open();
			break;
		}
}

Box.mdel(b : self ref Box, dm : ref Mesg)
{
	prev, m : ref Mesg;
	buf : string;

	if(dm.id){
		prev = nil;
		for(m=b.m; m!=nil && m!=dm; m=m.next)
			prev = m;
		if(m == nil)
			error(sprint("message %d not found", dm.id));
		if(prev == nil)
			b.m = m.next;
		else
			prev.next = m.next;
		# remove from screen: use acme to help 
		buf = sprint("/^%d	.*\\n(^[ \t].*\\n)*/", m.id);
		b.w.wreplace(buf, "");
	}
	dm.free();
	b.clean = False;
}

Box.command(b : self ref Box, s : string) : int
{
	t : int;
	m : ref Mesg;

	while(s[0]==' ' || s[0]=='\t' || s[0]=='\n')
		s = s[1:];
	if(len s >= 4 && s[0:4] == "Mail"){
		s = s[4:];
		while(s != nil && (s[0]==' ' || s[0]=='\t' || s[0]=='\n'))
			s = s[1:];
		t = 0;
		while(t < len s && s[t] && s[t]!=' ' && s[t]!='\t' && s[t]!='\n')
			t++;
		m = b.m;		# avoid warning message on b.m.mkmail(...)
		m.mkmail(b, s[0:t]);
		return True;
	}
	if(s == "Del"){

		if(!b.clean){
			b.clean = True;
			fprint(stderr, "mail: mailbox not written\n");
			return True;
		}
		rmlockfile();
		postnote(PNGROUP, pctl(0, nil), "kill");
		killing = 1;
		pctl(NEWPGRP, nil);
		b.w.wdel(True);
		for(m=b.m; m != nil; m=m.next)
			m.w.wdel(False);
		exit;
		return True;
	}
	if(s == "Put"){
		if(b.readonly)
			fprint(stderr, "Mail: %s is read-only\n", b.file);
		else
			b.rewrite();
		return True;
	}
	return False;
}

Box.rewrite(b : self ref Box)
{
	mbox, Lmbox, mboxtmp : ref FD;
	i, t, ok : int;
	buf : string;
	s : string;
	m : ref Mesg;
	d : Dir;
	Lmboxs : string = nil;

	if(b.clean){
		b.w.wclean();
		return;
	}
	t = strrchr(b.file, '/');
	if(t >= 0)
		s = b.file[t+1:];
	else
		s = b.file;
	if(mboxfile == usermboxfile){
		buf = sprint("%sL.%s", b.file[0:t+1], s);
		Lmbox = openlockfile(buf);
		if(Lmbox == nil)
			error(sprint("can't open lock file %s: %r", buf));
		else
			Lmboxs = buf;
	}else
		Lmbox = nil;
	buf = sprint("%s.tmp", b.file);
	mbox = tryopen(mboxfile, OREAD);
	if(mbox != nil){
		b.io = bufio->fopen(mbox, OREAD);
		b.io.seek(b.leng, 0);
		b.readmore();
	}else if(access(buf)){
		fprint(stderr, "mail: mailbox missing; using %s\n", buf);
		mboxtmp = tryopen(buf, ORDWR);
		b.io = bufio->fopen(mboxtmp, OREAD);
		b.readmore();
		b.io.close();
	}else
		error(sprint("can't open %s to rewrite: %r", s));
	remove(buf);
	mboxtmp = create(buf, OWRITE, 0622|CHAPPEND|CHEXCL);
	if(mboxtmp == nil)
			error(sprint("can't create %s: %r", buf));
	(ok, d) = fstat(mboxtmp);
	if(ok < 0)
		error(sprint("can't fstat %s: %r", buf));
	d.mode |= 0622;
	if(fwstat(mboxtmp, d) < 0)
		error(sprint("can't change mode of %s: %r", buf));
	b.io = bufio->fopen(mboxtmp, OWRITE);
	# write it backwards: stupid code 
	for(i=1; i<=b.nm; i++){
		for(m=b.m; m!=nil && m.id!=i; m=m.next)
			;
		if(m != nil){
			b.io.puts(m.realhdr);
			b.io.puts(m.text);
		}
	}
	if(remove(mboxfile) < 0)
		error(sprint("can't unlink %s: %r", mboxfile));
	d.name = s;
	if(fwstat(mboxtmp, d) < 0)
		error(sprint("can't change name of %s: %r", buf));
	b.leng = b.io.offset();
	b.io.close();
	mboxtmp = nil;
	b.io = nil;
	Lmbox = nil;
	if (Lmboxs != nil)
		remove(Lmboxs);
	b.w.wclean();
	b.clean = True;
}

lockfilemon(id : int)
{
	pctl(NEWPGRP, nil);
	p := "/chan/" + string id;
	for (;;) {
		if (lockfile == nil)
			error(nil);
		sleep(60*1000);
		(ok, d) := stat(p);
		if (ok < 0)
			error(nil);
	}
}
