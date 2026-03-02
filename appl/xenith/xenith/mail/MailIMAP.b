implement mailimap;

include "sys.m";
include "draw.m";
include "bufio.m";
include "daytime.m";
include "sh.m";
include "xenithwin.m";
include "arg.m";
include "imap.m";
include "factotum.m";

mailimap : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

sys : Sys;
bufio : Bufio;
daytime : Daytime;
imap : Imap;
xenithwin: Xenithwin;
Win, Event: import xenithwin;

OREAD, OWRITE, ORDWR, FORKENV, NEWFD, FORKFD, NEWPGRP, UTFmax : import Sys;
FD, Dir : import sys;
fprint, sprint, sleep, create, open, read, write, fildes, pctl, pipe, dup : import sys;
Context : import Draw;
Envelope, Msg, Mailbox : import imap;
time : import daytime;

PNPROC, PNGROUP : con iota;
False : con 0;
True : con 1;
EVENTSIZE : con 256;

Mesg : adt {
	w : ref Win;
	id : int;		# display id (1-based)
	seq : int;		# IMAP sequence number
	uid : int;		# IMAP UID
	flags : int;		# IMAP flags bitmask
	fromaddr : string;	# From address
	subject : string;	# Subject
	datestr : string;	# Date string
	replyto : string;	# Reply-To address
	toaddr : string;	# To address
	cc : string;		# CC
	messageid : string;	# Message-ID
	text : string;		# Body (fetched on demand)
	hdr : string;		# formatted header for display
	next : cyclic ref Mesg;
	box : cyclic ref Box;
	isopen : int;
	posted : int;

	open : fn(m : self ref Mesg);
	slave : fn(m : self ref Mesg);
	free : fn(m : self ref Mesg);
	command : fn(m : self ref Mesg, s : string) : int;
	mkreply : fn(m : self ref Mesg);
	mkforward : fn(m : self ref Mesg);
	send : fn(m : self ref Mesg);
};

Box : adt {
	w : ref Win;
	nm : int;
	m : cyclic ref Mesg;
	server : string;
	folder : string;
	exists : int;		# message count from SELECT
	cdel : chan of ref Mesg;
	cevent : chan of Event;
	cmore : chan of int;

	slave : fn(b : self ref Box);
	mopen : fn(b : self ref Box, id : int);
	mdel : fn(b : self ref Box, dm : ref Mesg);
	event : fn(b : self ref Box, e : ref Event);
	command : fn(b : self ref Box, s : string) : int;
	refresh : fn(b : self ref Box);
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
mailctxt : ref Context;
stdout, stderr : ref FD;
killing : int = 0;
serveraddr : string;

init(ctxt : ref Context, argl : list of string)
{
	mailctxt = ctxt;
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	daytime = load Daytime Daytime->PATH;
	imap = load Imap Imap->PATH;
	xenithwin = load Xenithwin Xenithwin->PATH;
	if(imap == nil){
		sys->fprint(sys->fildes(2), "MailIMAP: can't load imap: %r\n");
		raise "fail:load imap";
	}
	xenithwin->init();
	stdout = fildes(1);
	stderr = fildes(2);
	main(argl);
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

newevent() : ref Event
{
	e := ref Event;
	e.b = array[EVENTSIZE*UTFmax+1] of byte;
	e.r = array[EVENTSIZE+1] of int;
	return e;
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
		fprint(stderr, "MailIMAP: %s\n", s);
	imap->logout();
	postnote(PNGROUP, pctl(0, nil), "kill");
	killing = 1;
	exit;
}

replyid : ref Ref;

initreply()
{
	replyid = Ref.init();
}

run(argv : list of string, c : chan of int, p0 : ref FD)
{
	pctl(FORKENV|NEWFD|NEWPGRP, 0::1::2::p0.fd::nil);
	c <-= pctl(0, nil);
	dup(p0.fd, 0);
	p0 = nil;
	exec(hd argv, argv);
	exit;
}

# extract bare email address from "Name <addr>" or "(comment) addr" form
replyaddr(r : string) : string
{
	if(r == nil)
		return "";
	rr := 0;
	while(rr < len r && (r[rr]==' ' || r[rr]=='\t'))
		rr++;
	r = r[rr:];
	p := strchr(r, '<');
	if(p >= 0){
		q := strchr(r[p+1:], '>');
		if(q < 0)
			r = r[p+1:];
		else
			r = r[p+1:p+1+q];
		return r;
	}
	p = strchr(r, '(');
	if(p >= 0){
		q := strchr(r[p:], ')');
		if(q < 0)
			r = r[0:p];
		else
			r = r[0:p] + r[p+q+1:];
	}
	# trim trailing whitespace/newline
	while(len r > 0 && (r[len r - 1] == '\n' || r[len r - 1] == ' ' || r[len r - 1] == '\t'))
		r = r[:len r - 1];
	return r;
}

# format flag characters: N=new, R=read, A=answered, *=flagged
flagchar(flags : int) : string
{
	s := "";
	if(flags & Imap->FFLAGGED)
		s += "*";
	if(flags & Imap->FANSWERED)
		s += "A";
	if(flags & Imap->FSEEN)
		s += "R";
	else
		s += "N";
	return s;
}

# build a one-line summary for the message list
msgsummary(m : ref Mesg) : string
{
	from := m.fromaddr;
	if(from == nil)
		from = "?";
	# trim long from addresses
	if(len from > 30)
		from = from[:30];
	subj := m.subject;
	if(subj == nil)
		subj = "(no subject)";
	# trim trailing newline from subject
	while(len subj > 0 && (subj[len subj-1] == '\n' || subj[len subj-1] == '\r'))
		subj = subj[:len subj-1];
	return sprint("%d\t%s %s\t %s\n", m.id, flagchar(m.flags), from, subj);
}

main(argv : list of string)
{
	arg : Arg;
	user, pass, folder : string;

	initlock();
	initreply();
	arg = load Arg Arg->PATH;
	arg->init(argv);
	while((c := arg->opt()) != 0)
	case c {
	'u' => user = arg->earg();
	'p' => pass = arg->earg();
	}
	argv = arg->argv();
	if(argv == nil){
		fprint(stderr, "usage: MailIMAP [-u user] [-p pass] server [folder]\n");
		raise "fail:usage";
	}
	serveraddr = hd argv;
	argv = tl argv;
	if(argv != nil)
		folder = hd argv;
	else
		folder = "INBOX";

	# get credentials from factotum if not provided
	if(user == nil || pass == nil){
		factotum := load Factotum Factotum->PATH;
		if(factotum != nil){
			factotum->init();
			(fu, fp) := factotum->getuserpasswd(
				sprint("proto=pass service=imap dom=%s", serveraddr));
			if(user == nil)
				user = fu;
			if(pass == nil)
				pass = fp;
		}
	}

	# connect to IMAP server
	err := imap->open(user, pass, serveraddr, Imap->IMPLICIT_TLS);
	if(err != nil){
		fprint(stderr, "MailIMAP: connect %s: %s\n", serveraddr, err);
		raise "fail:connect";
	}

	mbox = boxconnect(serveraddr, folder);
	spawn timeslave(mbox.cmore);
	mbox.slave();
	error(nil);
}

boxconnect(server, folder : string) : ref Box
{
	b := ref Box;
	b.nm = 0;
	b.server = server;
	b.folder = folder;
	b.exists = 0;

	# select the mailbox
	(mbx, err) := imap->select(folder);
	if(err != nil)
		error(sprint("select %s: %s", folder, err));
	b.exists = mbx.exists;

	b.w = Win.wnew();

	# fetch last N messages (up to 100)
	first := b.exists - 99;
	if(first < 1)
		first = 1;
	if(b.exists > 0){
		(msgs, merr) := imap->msglist(first, b.exists);
		if(merr != nil)
			fprint(stderr, "MailIMAP: msglist: %s\n", merr);
		else {
			# build Mesg linked list
			id := 0;
			for(ml := msgs; ml != nil; ml = tl ml){
				msg := hd ml;
				id++;
				m := ref Mesg;
				m.id = id;
				m.seq = msg.seq;
				m.uid = msg.uid;
				m.flags = msg.flags;
				m.isopen = False;
				m.posted = False;
				if(msg.envelope != nil){
					m.fromaddr = msg.envelope.sender;
					m.subject = msg.envelope.subject;
					m.datestr = msg.envelope.date;
					m.replyto = msg.envelope.replyto;
					m.toaddr = msg.envelope.recipient;
					m.cc = msg.envelope.cc;
					m.messageid = msg.envelope.messageid;
				}
				m.box = b;
				m.next = b.m;
				b.m = m;
				b.nm++;
			}
		}
	}

	# write summary lines (messages are in reverse order from cons)
	for(m := b.m; m != nil; m = m.next)
		b.w.wwritebody(msgsummary(m));

	b.w.wname(sprint("IMAP/%s/%s/", server, folder));
	b.w.wtagwrite("Strut Folders Search Mail Del");
	b.w.wsetdump("/xenith/mail", sprint("MailIMAP %s", server));
	b.w.wclean();
	b.w.wselect("0");
	b.w.wdormant();
	b.cdel = chan of ref Mesg;
	b.cevent = chan of Event;
	b.cmore = chan of int;
	spawn b.w.wslave(b.cevent);
	return b;
}

timeslave(c : chan of int)
{
	for(;;){
		sleep(60*1000);
		c <-= 0;
	}
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
			b.refresh();
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
			if((e.flag&2) && e.nb==0)
				s = string e2.b[0:e2.nb];
			if(na)
				s = sprint("%s %s", s, string ea.b[0:ea.nb]);
			if(!b.command(s))
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
			if(nopen == 0)
				b.w.wwriteevent(e);
			break;
		'I' or 'D' or 'd' or 'i' =>
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
	for(m := b.m; m != nil; m = m.next)
		if(m.id == id){
			m.open();
			break;
		}
}

Box.mdel(b : self ref Box, dm : ref Mesg)
{
	buf : string;

	if(dm.id != 0){
		# flag as deleted on server
		err := imap->store(dm.seq, Imap->FDELETED, 1);
		if(err != nil)
			fprint(stderr, "MailIMAP: delete %d: %s\n", dm.seq, err);

		# remove from linked list
		prev : ref Mesg = nil;
		for(m := b.m; m != nil && m != dm; m = m.next)
			prev = m;
		if(m != nil){
			if(prev == nil)
				b.m = m.next;
			else
				prev.next = m.next;
		}

		# remove from screen
		buf = sprint("/^%d	.*\\n(^[ \t].*\\n)*/", dm.id);
		b.w.wreplace(buf, "");
	}
	dm.free();
}

Box.command(b : self ref Box, s : string) : int
{
	while(len s > 0 && (s[0]==' ' || s[0]=='\t' || s[0]=='\n'))
		s = s[1:];
	if(len s >= 4 && s[0:4] == "Mail"){
		s = s[4:];
		while(s != nil && (s[0]==' ' || s[0]=='\t' || s[0]=='\n'))
			s = s[1:];
		t := 0;
		while(t < len s && s[t]!=' ' && s[t]!='\t' && s[t]!='\n')
			t++;
		mkcompose(b, s[0:t]);
		return True;
	}
	if(len s >= 7 && s[0:7] == "Folders"){
		showfolders(b);
		return True;
	}
	if(len s >= 6 && s[0:6] == "Search"){
		s = s[6:];
		while(len s > 0 && (s[0]==' ' || s[0]=='\t'))
			s = s[1:];
		if(len s > 0)
			dosearch(b, s);
		return True;
	}
	if(s == "Del"){
		imap->logout();
		postnote(PNGROUP, pctl(0, nil), "kill");
		killing = 1;
		pctl(NEWPGRP, nil);
		b.w.wdel(True);
		for(m := b.m; m != nil; m = m.next)
			if(m.isopen && m.w != nil)
				m.w.wdel(False);
		exit;
		return True;
	}
	return False;
}

Box.refresh(b : self ref Box)
{
	# re-select to get updated message count
	(mbx, err) := imap->select(b.folder);
	if(err != nil){
		fprint(stderr, "MailIMAP: refresh: %s\n", err);
		b.w.wdormant();
		return;
	}
	if(mbx.exists <= b.exists){
		b.w.wdormant();
		return;
	}

	# fetch new messages
	first := b.exists + 1;
	last := mbx.exists;
	b.exists = mbx.exists;

	(msgs, merr) := imap->msglist(first, last);
	if(merr != nil){
		fprint(stderr, "MailIMAP: refresh msglist: %s\n", merr);
		b.w.wdormant();
		return;
	}

	new := False;
	for(ml := msgs; ml != nil; ml = tl ml){
		msg := hd ml;
		b.nm++;
		m := ref Mesg;
		m.id = b.nm;
		m.seq = msg.seq;
		m.uid = msg.uid;
		m.flags = msg.flags;
		m.isopen = False;
		m.posted = False;
		if(msg.envelope != nil){
			m.fromaddr = msg.envelope.sender;
			m.subject = msg.envelope.subject;
			m.datestr = msg.envelope.date;
			m.replyto = msg.envelope.replyto;
			m.toaddr = msg.envelope.recipient;
			m.cc = msg.envelope.cc;
			m.messageid = msg.envelope.messageid;
		}
		m.box = b;
		m.next = b.m;
		b.m = m;
		b.w.wreplace("0", msgsummary(m));
		new = True;
	}

	if(new){
		b.w.wclean();
		b.w.wselect("0;/.*(\\n[ \t].*)*");
		b.w.wshow();
	}
	b.w.wdormant();
}

showfolders(b : ref Box)
{
	(folders, err) := imap->folders();
	if(err != nil){
		fprint(stderr, "MailIMAP: folders: %s\n", err);
		return;
	}
	w := Win.wnew();
	w.wname(sprint("IMAP/%s/Folders", b.server));
	for(fl := folders; fl != nil; fl = tl fl)
		w.wwritebody(hd fl + "\n");
	w.wclean();
	w.wselect("0");
	w.wdormant();
}

dosearch(b : ref Box, criteria : string)
{
	# trim trailing newline
	while(len criteria > 0 && (criteria[len criteria-1] == '\n' || criteria[len criteria-1] == '\r'))
		criteria = criteria[:len criteria-1];
	(seqs, err) := imap->search(criteria);
	if(err != nil){
		fprint(stderr, "MailIMAP: search: %s\n", err);
		return;
	}
	w := Win.wnew();
	w.wname(sprint("IMAP/%s/%s/Search", b.server, b.folder));
	for(sl := seqs; sl != nil; sl = tl sl){
		seq := hd sl;
		# find message by seq number and display summary
		found := False;
		for(m := b.m; m != nil; m = m.next){
			if(m.seq == seq){
				w.wwritebody(msgsummary(m));
				found = True;
				break;
			}
		}
		if(!found)
			w.wwritebody(sprint("%d\t(not loaded)\n", seq));
	}
	w.wclean();
	w.wselect("0");
	w.wdormant();
}

mkcompose(b : ref Box, toaddr : string)
{
	m := ref Mesg;
	m.id = 0;
	m.seq = 0;
	m.isopen = False;
	m.posted = False;
	m.box = b;
	m.toaddr = toaddr;
	m.hdr = toaddr + "\n";
	m.text = nil;
	m.open();
	m.w.wdormant();
}

Mesg.open(m : self ref Mesg)
{
	if(m.isopen)
		return;
	m.w = Win.wnew();

	if(m.id != 0){
		# existing message — fetch body from server
		(body, ferr) := imap->fetch(m.seq);
		if(ferr != nil){
			fprint(stderr, "MailIMAP: fetch %d: %s\n", m.seq, ferr);
			body = sprint("(fetch error: %s)\n", ferr);
		}
		m.text = body;

		# mark as seen
		imap->store(m.seq, Imap->FSEEN, 1);
		m.flags |= Imap->FSEEN;

		# write headers
		if(m.fromaddr != nil)
			m.w.wwritebody("From: " + m.fromaddr + "\n");
		if(m.toaddr != nil)
			m.w.wwritebody("To: " + m.toaddr + "\n");
		if(m.cc != nil)
			m.w.wwritebody("CC: " + m.cc + "\n");
		if(m.datestr != nil)
			m.w.wwritebody("Date: " + m.datestr + "\n");
		if(m.subject != nil)
			m.w.wwritebody("Subject: " + m.subject + "\n");
		m.w.wwritebody("\n");
		m.w.wwritebody(m.text);

		m.w.wname(sprint("IMAP/%s/%s/%d", m.box.server, m.box.folder, m.seq));
		m.w.wtagwrite("Reply Forward Flag Delmesg");
	} else {
		# compose new message
		if(m.hdr != nil)
			m.w.wwritebody(m.hdr);
		if(m.text != nil)
			m.w.wwritebody(m.text);
		m.w.wname(sprint("IMAP/%s/%s/Reply%d", m.box.server, m.box.folder, replyid.inc()));
		m.w.wtagwrite("Post");
	}
	m.w.wclean();
	m.w.wselect("0");
	m.isopen = True;
	m.posted = False;
	spawn m.slave();
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
		'E' =>
			break;
		'F' =>
			break;
		'K' or 'M' =>
			case(e.c2){
			'x' or 'X' =>
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
				if(!m.command(s))
					m.w.wwriteevent(e);
				s = nil;
				break;
			'l' or 'L' =>
				if(e.flag & 2)
					m.w.wevent(e2);
				m.w.wwriteevent(e);
				break;
			'I' or 'D' =>
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
	while(len s > 0 && (s[0]==' ' || s[0]=='\t' || s[0]=='\n'))
		s = s[1:];
	if(s == "Post"){
		m.send();
		return True;
	}
	if(s == "Reply"){
		m.mkreply();
		return True;
	}
	if(s == "Forward"){
		m.mkforward();
		return True;
	}
	if(s == "Flag"){
		if(m.id != 0 && m.seq != 0){
			if(m.flags & Imap->FFLAGGED){
				imap->store(m.seq, Imap->FFLAGGED, 0);
				m.flags &= ~Imap->FFLAGGED;
			} else {
				imap->store(m.seq, Imap->FFLAGGED, 1);
				m.flags |= Imap->FFLAGGED;
			}
		}
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

Mesg.mkreply(m : self ref Mesg)
{
	r := ref Mesg;
	r.id = 0;
	r.seq = 0;
	r.isopen = False;
	r.posted = False;
	r.box = m.box;

	addr := m.replyto;
	if(addr == nil)
		addr = m.fromaddr;
	r.hdr = replyaddr(addr) + "\n";

	if(m.subject != nil){
		subj := m.subject;
		# trim trailing whitespace
		while(len subj > 0 && (subj[len subj-1]=='\n' || subj[len subj-1]==' '))
			subj = subj[:len subj-1];
		if(len subj >= 3 && (subj[0:3] == "Re:" || subj[0:3] == "re:" || subj[0:3] == "RE:"))
			r.text = "Subject: " + subj + "\n\n";
		else
			r.text = "Subject: Re: " + subj + "\n\n";
	}

	r.open();
	r.w.wselect("$");
	r.w.wdormant();
}

Mesg.mkforward(m : self ref Mesg)
{
	r := ref Mesg;
	r.id = 0;
	r.seq = 0;
	r.isopen = False;
	r.posted = False;
	r.box = m.box;

	r.hdr = "\n";

	subj := m.subject;
	if(subj == nil)
		subj = "";
	while(len subj > 0 && (subj[len subj-1]=='\n' || subj[len subj-1]==' '))
		subj = subj[:len subj-1];
	r.text = "Subject: Fwd: " + subj + "\n\n";
	r.text += "---------- Forwarded message ----------\n";
	if(m.fromaddr != nil)
		r.text += "From: " + m.fromaddr + "\n";
	if(m.datestr != nil)
		r.text += "Date: " + m.datestr + "\n";
	if(m.subject != nil)
		r.text += "Subject: " + m.subject + "\n";
	r.text += "\n";
	if(m.text != nil)
		r.text += m.text;

	r.open();
	r.w.wselect("0");
	r.w.wdormant();
}

Mesg.send(m : self ref Mesg)
{
	s : string;
	t, u : int;
	a, b : list of string;
	n : int;
	p : array of ref FD;
	c : chan of int;

	p = array[2] of ref FD;
	s = m.w.wreadall();
	a = "sendmail" :: nil;
	# first line is the To address
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
	# reverse to get correct order
	b = nil;
	for ( ; a != nil; a = tl a)
		b = hd a :: b;
	a = b;
	while(t < len s && s[t]!='\n')
		t++;
	if(t < len s && s[t] == '\n')
		t++;
	if(pipe(p) < 0){
		fprint(stderr, "MailIMAP: can't pipe: %r\n");
		return;
	}
	c = chan of int;
	spawn run(a, c, p[0]);
	<-c;
	c = nil;
	p[0] = nil;
	n = len s - t;
	if(swrite(p[1], s[t:]) != n)
		fprint(stderr, "write to pipe failed: %r\n");
	p[1] = nil;
	m.w.wname(sprint("IMAP/%s/%s/Sent", m.box.server, m.box.folder));
	m.w.wclean();
}

Mesg.free(m : self ref Mesg)
{
	m.text = nil;
	m.hdr = nil;
	m.subject = nil;
	m.fromaddr = nil;
	m.replyto = nil;
	m.toaddr = nil;
	m.cc = nil;
	m.datestr = nil;
	m.messageid = nil;
	m = nil;
}
