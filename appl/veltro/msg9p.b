implement Msg9p;

#
# msg9p - 9P file server for the Veltro message layer
#
# Presents message sources (email, telegram, etc.) as a unified filesystem
# at /n/msg/. Each source implements the MsgSrc interface and is loaded
# dynamically via the ctl file.
#
# Filesystem:
#   /n/msg/
#   ├── ctl         (rw)  "register <name> <dispath> <config...>"
#   ├── notify      (r)   Blocking read: returns next notification
#   ├── status      (r)   Summary of all sources
#   └── sources/    (dir) Per-source directories (future expansion)
#
# The notify file is the key mechanism: reading it BLOCKS until a
# notification arrives from any registered source. This is the standard
# Inferno event-file pattern.
#
# Usage:
#   msg9p                        Start, mount at /n/msg
#   msg9p -m /n/msg              Custom mount point
#   msg9p -D                     9P debug tracing
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";

include "arg.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Fid, Styxserver, Navigator, Navop: import styxservers;
	Enotfound, Eperm, Ebadarg: import styxservers;

include "string.m";
	str: String;

include "msgsrc.m";

Msg9p: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

# Qid layout
Qroot, Qctl, Qnotify, Qstatus, Qsrcdir: con iota;

# Registered source info
SrcInfo: adt {
	name:    string;      # "email", "telegram", etc.
	path:    string;      # dis path
	mod:     MsgSrc;      # loaded module
	stopc:   chan of int;  # stop channel for watch goroutine
};

# Pending reader waiting on notify
PendingRead: adt {
	tag:  int;
	fid:  int;
};

stderr: ref Sys->FD;
user: string;
mountpt := "/n/msg";

# Registered sources
sources: list of ref SrcInfo;

# Notification aggregation channel (all sources feed into this)
notifychan: chan of string;

# Pending readers blocked on /n/msg/notify
pendingReaders: list of ref PendingRead;

# Queued notifications when no reader is waiting
notifyq: list of string;
MAXQ: con 64;

# Global reference to the styx server for deferred replies
gsrv: ref Styxserver;

nomod(s: string)
{
	sys->fprint(stderr, "msg9p: can't load %s: %r\n", s);
	raise "fail:load";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	styx = load Styx Styx->PATH;
	if(styx == nil)
		nomod(Styx->PATH);
	styx->init();

	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		nomod(Styxservers->PATH);
	styxservers->init(styx);

	str = load String String->PATH;
	if(str == nil)
		nomod(String->PATH);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);

	while((o := arg->opt()) != 0)
		case o {
		'D' =>	styxservers->traceset(1);
		'm' =>	mountpt = arg->earg();
		* =>
			sys->fprint(stderr, "usage: msg9p [-D] [-m mountpt]\n");
			raise "fail:usage";
		}
	arg = nil;

	notifychan = chan of string;

	sys->pctl(Sys->FORKFD, nil);

	user = readfile("/dev/user");
	if(user == nil)
		user = "inferno";

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0) {
		sys->fprint(stderr, "msg9p: can't create pipe: %r\n");
		raise "fail:pipe";
	}

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	fds[0] = nil;
	gsrv = srv;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops);
	<-pidc;

	# Ensure mount point exists
	ensuredir(mountpt);

	if(sys->mount(fds[1], nil, mountpt, Sys->MREPL|Sys->MCREATE, nil) < 0) {
		sys->fprint(stderr, "msg9p: mount failed: %r\n");
		raise "fail:mount";
	}
}

# === Navigator (directory traversal) ===

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil) {
		pick n := m {
		Stat =>
			n.reply <-= dirgen(int n.path);
		Walk =>
			walkto(n);
		Readdir =>
			doreaddir(n, int n.path);
		}
	}
}

walkto(n: ref Navop.Walk)
{
	parent := int n.path;

	case parent {
	Qroot =>
		case n.name {
		"ctl" =>
			n.path = big Qctl;
			n.reply <-= dirgen(int n.path);
		"notify" =>
			n.path = big Qnotify;
			n.reply <-= dirgen(int n.path);
		"status" =>
			n.path = big Qstatus;
			n.reply <-= dirgen(int n.path);
		"sources" =>
			n.path = big Qsrcdir;
			n.reply <-= dirgen(int n.path);
		* =>
			n.reply <-= (nil, Enotfound);
		}
	* =>
		n.reply <-= (nil, Enotfound);
	}
}

dirgen(path: int): (ref Sys->Dir, string)
{
	d := ref sys->zerodir;
	d.uid = user;
	d.gid = user;
	d.muid = user;
	d.atime = 0;
	d.mtime = 0;

	case path {
	Qroot =>
		d.name = ".";
		d.mode = Sys->DMDIR | 8r555;
		d.qid.qtype = Sys->QTDIR;
	Qctl =>
		d.name = "ctl";
		d.mode = 8r666;
	Qnotify =>
		d.name = "notify";
		d.mode = 8r444;
	Qstatus =>
		d.name = "status";
		d.mode = 8r444;
	Qsrcdir =>
		d.name = "sources";
		d.mode = Sys->DMDIR | 8r555;
		d.qid.qtype = Sys->QTDIR;
	* =>
		return (nil, Enotfound);
	}

	d.qid.path = big path;
	return (d, nil);
}

doreaddir(n: ref Navop.Readdir, path: int)
{
	case path {
	Qroot =>
		entries := array[] of {Qctl, Qnotify, Qstatus, Qsrcdir};
		for(i := 0; i < len entries; i++) {
			if(i >= n.offset) {
				(d, err) := dirgen(entries[i]);
				if(d != nil)
					n.reply <-= (d, err);
			}
		}
	Qsrcdir =>
		# Currently flat — no per-source subdirectories in navigator
		;
	}
	n.reply <-= (nil, nil);
}

# === Main serve loop ===

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int,
	navops: chan of ref Navop)
{
	pidc <-= sys->pctl(0, nil);

Serve:
	for(;;) alt {
	gm := <-tchan =>
		if(gm == nil)
			break Serve;

		pick m := gm {
		Readerror =>
			sys->fprint(stderr, "msg9p: read error: %s\n", m.error);
			break Serve;

		Read =>
			(c, err) := srv.canread(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				continue;
			}

			if(c.qtype & Sys->QTDIR) {
				srv.read(m);
				continue;
			}

			path := int c.path;

			case path {
			Qctl =>
				data := array of byte gensrclist();
				srv.reply(styxservers->readbytes(m, data));

			Qstatus =>
				data := array of byte genstatus();
				srv.reply(styxservers->readbytes(m, data));

			Qnotify =>
				# Blocking read: if we have queued notifications,
				# reply immediately. Otherwise, park the reader.
				if(notifyq != nil) {
					# Dequeue oldest (last in reversed list)
					text := dequeue();
					srv.reply(styxservers->readbytes(m, array of byte text));
				} else {
					# Park — do NOT reply. Reply happens when
					# notification arrives (see notifychan handler).
					pendingReaders = ref PendingRead(m.tag, c.fid) :: pendingReaders;
				}

			* =>
				srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			}

		Write =>
			(c, merr) := srv.canwrite(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, merr));
				continue;
			}

			path := int c.path;
			data := string m.data;
			# Strip trailing newline
			if(len data > 0 && data[len data - 1] == '\n')
				data = data[:len data - 1];

			case path {
			Qctl =>
				cerr := handlectl(data);
				if(cerr != nil)
					srv.reply(ref Rmsg.Error(m.tag, cerr));
				else
					srv.reply(ref Rmsg.Write(m.tag, len m.data));
			* =>
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
			}

		Clunk =>
			# Cancel any pending reads for this fid
			c := srv.getfid(m.fid);
			if(c != nil && int c.path == Qnotify)
				cancelpending(m.fid);
			srv.clunk(m);

		* =>
			srv.default(gm);
		}

	notification := <-notifychan =>
		# Notification from a source. Wake a pending reader or queue.
		if(pendingReaders != nil) {
			# Wake oldest reader (last in list since we prepend)
			pr := lastpending();
			pendingReaders = droplast(pendingReaders);
			srv.reply(ref Rmsg.Read(pr.tag, array of byte notification));
		} else {
			# Queue (bounded)
			enqueue(notification);
		}
	}

	navops <-= nil;
}

# === Ctl command handling ===

# register <name> <dispath> [config key=value ...]
# unregister <name>
handlectl(data: string): string
{
	(n, toks) := sys->tokenize(data, " \t");
	if(n < 1)
		return Ebadarg;

	cmd := str->tolower(hd toks);
	toks = tl toks;

	case cmd {
	"register" =>
		return doregister(toks);
	"unregister" =>
		if(toks == nil)
			return "usage: unregister <name>";
		return dounregister(hd toks);
	* =>
		return "unknown command: " + cmd;
	}
}

doregister(args: list of string): string
{
	if(args == nil || tl args == nil)
		return "usage: register <name> <dispath> [config...]";

	srcname := hd args;
	dispath := hd tl args;

	# Check for duplicate
	for(sl := sources; sl != nil; sl = tl sl)
		if((hd sl).name == srcname)
			return "source already registered: " + srcname;

	# Build config string from remaining tokens
	config := "";
	for(a := tl tl args; a != nil; a = tl a) {
		if(config != "")
			config += " ";
		config += hd a;
	}

	# Load the source module
	mod := load MsgSrc dispath;
	if(mod == nil)
		return sys->sprint("cannot load %s: %r", dispath);

	# Initialize
	err := mod->init(config);
	if(err != nil)
		return "init " + srcname + ": " + err;

	# Start watch goroutine
	stopc := chan of int;
	src := ref SrcInfo(srcname, dispath, mod, stopc);
	sources = src :: sources;

	spawn watchwrapper(src, notifychan, stopc);

	sys->fprint(stderr, "msg9p: registered source '%s' from %s\n", srcname, dispath);
	return nil;
}

dounregister(srcname: string): string
{
	newsources: list of ref SrcInfo;
	found := 0;
	for(sl := sources; sl != nil; sl = tl sl) {
		src := hd sl;
		if(src.name == srcname) {
			src.stopc <-= 1;	# signal watch to stop
			src.mod->close();
			found = 1;
		} else
			newsources = src :: newsources;
	}
	if(!found)
		return "source not found: " + srcname;
	sources = newsources;
	sys->fprint(stderr, "msg9p: unregistered source '%s'\n", srcname);
	return nil;
}

# Watch goroutine: bridges MsgSrc.watch() notifications to the aggregated
# notifychan as formatted text strings.
watchwrapper(src: ref SrcInfo, nchan: chan of string, stopc: chan of int)
{
	updates := chan of ref MsgSrc->Notification;
	relaystop := chan of int;

	# Start the source's watch in a sub-goroutine
	spawn sourcewatcher(src, updates, relaystop);

	for(;;) alt {
	n := <-updates =>
		if(n == nil)
			return;
		text := formatnotification(src.name, n);
		nchan <-= text;

	<-stopc =>
		relaystop <-= 1;
		return;
	}
}

sourcewatcher(src: ref SrcInfo, updates: chan of ref MsgSrc->Notification,
	stop: chan of int)
{
	src.mod->watch(updates, stop);
}

# Format a notification as a structured text message suitable for
# injection into the Meta Agent's conversation.
formatnotification(srcname: string, n: ref MsgSrc->Notification): string
{
	if(n.kind == "error")
		return "[Message error — " + srcname + "]\n" + n.detail;

	if(n.msg == nil)
		return "[Message " + n.kind + " — " + srcname + "]";

	m := n.msg;

	text := "[Message notification — " + srcname + "]\n";

	if(m.sender != nil)
		text += "From: " + m.sender + "\n";
	if(m.recipient != nil)
		text += "To: " + m.recipient + "\n";
	if(m.subject != nil)
		text += "Subject: " + m.subject + "\n";
	if(m.timestamp != nil)
		text += "Date: " + m.timestamp + "\n";

	# Include preview of body (first 200 chars)
	if(m.body != nil && m.body != "") {
		preview := m.body;
		if(len preview > 200)
			preview = preview[:200] + "...";
		text += "Preview: " + preview + "\n";
	}

	text += "Message ID: " + m.id + "\n";
	text += "---\n";
	text += "Handle this per your message policy. Use \"mail read " + m.id + "\" for the full message.";

	return text;
}

# === Notify queue management ===

enqueue(s: string)
{
	# Count queue length
	count := 0;
	for(q := notifyq; q != nil; q = tl q)
		count++;
	if(count >= MAXQ)
		return;	# drop if full

	# Append to end (build reversed, then reverse)
	notifyq = appendstr(notifyq, s);
}

dequeue(): string
{
	if(notifyq == nil)
		return "";
	# Return first element
	s := hd notifyq;
	notifyq = tl notifyq;
	return s;
}

appendstr(l: list of string, s: string): list of string
{
	if(l == nil)
		return s :: nil;
	return hd l :: appendstr(tl l, s);
}

# === Pending reader management ===

lastpending(): ref PendingRead
{
	pr := hd pendingReaders;
	for(l := tl pendingReaders; l != nil; l = tl l)
		pr = hd l;
	return pr;
}

droplast(l: list of ref PendingRead): list of ref PendingRead
{
	if(l == nil)
		return nil;
	if(tl l == nil)
		return nil;
	return hd l :: droplast(tl l);
}

cancelpending(fid: int)
{
	newlist: list of ref PendingRead;
	for(l := pendingReaders; l != nil; l = tl l) {
		pr := hd l;
		if(pr.fid != fid)
			newlist = pr :: newlist;
		# else: silently drop — the clunk response handles the fid
	}
	pendingReaders = newlist;
}

# === Status generation ===

gensrclist(): string
{
	if(sources == nil)
		return "no sources registered\n";
	result := "";
	for(sl := sources; sl != nil; sl = tl sl) {
		src := hd sl;
		if(result != "")
			result += "\n";
		result += src.name + " " + src.path;
	}
	return result;
}

genstatus(): string
{
	if(sources == nil)
		return "no sources registered\n";
	result := "";
	for(sl := sources; sl != nil; sl = tl sl) {
		src := hd sl;
		if(result != "")
			result += "\n";
		st := src.mod->status();
		result += src.name + ": " + st;
	}
	return result;
}

# === Helpers ===

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	s := string buf[:n];
	# Strip trailing whitespace
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' '))
		s = s[:len s - 1];
	return s;
}

ensuredir(path: string)
{
	fd := sys->create(path, Sys->OREAD, Sys->DMDIR | 8r777);
	if(fd != nil)
		fd = nil;
}
