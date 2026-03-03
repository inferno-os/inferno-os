implement Luciuisrv;

#
# luciuisrv - Lucifer UI Styx Server
#
# Synthetic 9P filesystem serving /n/ui/ for the Lucifer GUI.
# Three-zone layout: conversation, presentation, context.
# All UI state lives here; renderers are just views into this namespace.
#
# Filesystem layout:
#   /n/ui/
#       ctl                          global control
#       event                        global events (blocking read)
#       notification                 write-once-read-once
#       toast                        write-once-read-once
#       activity/
#           current                  read: current id, write: switch
#           {id}/
#               label                read/write
#               status               read/write
#               event                per-activity blocking read
#               conversation/
#                   ctl              write new messages
#                   input            user text (blocking read)
#                   0, 1, 2...       numbered message files
#               presentation/
#                   ctl              create/remove artifacts
#                   current          currently centered artifact id
#                   {artifact-id}/
#                       type         artifact type
#                       label        display name
#                       data         structured content
#               context/
#                   ctl              update resources/gaps/bg tasks
#                   resources/
#                       0, 1...      resource entries
#                   gaps/
#                       0, 1...      gap entries
#                   background/
#                       0, 1...      background task entries
#
# Usage:
#   luciuisrv              mount at /n/ui
#   luciuisrv -m /mnt/ui   legacy mount point
#   luciuisrv -D           debug tracing
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

Luciuisrv: module {
	init: fn(nil: ref Draw->Context, nil: list of string);
};

# --- File types (low 8 bits of qid path) ---
Qroot:		con 0;
Qctl:		con 1;
Qevent:		con 2;
Qnotification:	con 3;
Qtoast:		con 4;
Qactdir:	con 5;	# /activity/
Qactcurrent:	con 6;	# /activity/current
Qact:		con 7;	# /activity/{id}/
Qactlabel:	con 8;
Qactstatus:	con 9;
Qactevent:	con 10;
Qconvdir:	con 11;	# conversation/
Qconvctl:	con 12;
Qconvinput:	con 13;
Qconvmsg:	con 14;	# numbered message
Qpresdir:	con 15;	# presentation/
Qpresctl:	con 16;
Qprescurrent:	con 17;
Qartdir:	con 18;	# {artifact-id}/
Qarttype:	con 19;
Qartlabel:	con 20;
Qartdata:	con 21;
Qctxdir:	con 22;	# context/
Qctxctl:	con 23;
Qresdir:	con 24;	# resources/
Qresentry:	con 25;
Qgapdir:	con 26;	# gaps/
Qgapentry:	con 27;
Qbgdir:		con 28;	# background/
Qbgentry:	con 29;

# --- QID encoding ---
# 64-bit path: [activity_id:16][sub_id:16][unused:24][filetype:8]
# activity_id: 0 for global files
# sub_id: message number, artifact index, resource index, etc.

MKPATH(actid, subid, ft: int): big
{
	return big ((actid << 32) | (subid << 16) | ft);
}

ACTID(path: big): int
{
	return int (path >> 32) & 16rFFFF;
}

SUBID(path: big): int
{
	return (int (path >> 16)) & 16rFFFF;
}

FTYPE(path: big): int
{
	return int path & 16rFF;
}

# --- Data types ---

ConvMsg: adt {
	role:	string;		# human | veltro
	text:	string;
	using:	string;		# comma-separated resource paths
};

Artifact: adt {
	id:	string;
	atype:	string;		# table | chart | map | doc | ...
	label:	string;
	data:	string;		# structured content
	idx:	int;		# index in artifacts array
};

Resource: adt {
	path:	string;
	label:	string;
	rtype:	string;		# sensor | db | api | ...
	status:	string;		# streaming | stale | offline
	latency: string;
	via:	string;
	staleFor: string;
};

Gap: adt {
	desc:	string;
	relevance: string;	# high | medium | low
};

BgTask: adt {
	label:	string;
	status:	string;		# live | done | error
	progress: string;	# percentage or empty
};

Activity: adt {
	id:	int;
	label:	string;
	status:	string;		# active | working | idle

	# Conversation
	messages: array of ref ConvMsg;
	nmsg:	int;
	inputq:	list of string;

	# Presentation
	currentArtifact: string;
	artifacts: array of ref Artifact;
	nart:	int;

	# Context
	resources: array of ref Resource;
	nres:	int;
	gaps:	array of ref Gap;
	ngaps:	int;
	bgtasks: array of ref BgTask;
	nbg:	int;
};

# --- Pending read for blocking files ---
PendingRead: adt {
	fid:	int;
	tag:	int;
	m:	ref Tmsg.Read;
	ft:	int;		# file type
	actid:	int;		# activity id
	next:	cyclic ref PendingRead;
};

# --- Globals ---
stderr: ref Sys->FD;
user: string;
vers: int;

activities: array of ref Activity;
nact: int;
nextactid: int;
currentact: int;		# id of current activity

# Blocking read queues
notifyq: list of string;
toastq: list of string;
pending: ref PendingRead;	# linked list of pending reads

# --- Module loading ---

nomod(s: string)
{
	sys->fprint(stderr, "luciuisrv: can't load %s: %r\n", s);
	raise "fail:load";
}

usage()
{
	sys->fprint(stderr, "Usage: luciuisrv [-D] [-m mountpoint]\n");
	raise "fail:usage";
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

	mountpt := "/n/ui";

	while((o := arg->opt()) != 0)
		case o {
		'D' =>	styxservers->traceset(1);
		'm' =>	mountpt = arg->earg();
		* =>	usage();
		}
	arg = nil;

	# Initialize state
	activities = array[16] of ref Activity;
	nact = 0;
	nextactid = 0;
	currentact = -1;
	vers = 0;

	user = rf("/dev/user");
	if(user == nil)
		user = "inferno";

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0) {
		sys->fprint(stderr, "luciuisrv: can't create pipe: %r\n");
		raise "fail:pipe";
	}

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	fds[0] = nil;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops);
	<-pidc;

	ensuredir(mountpt);

	if(sys->mount(fds[1], nil, mountpt, Sys->MREPL|Sys->MCREATE, nil) < 0) {
		sys->fprint(stderr, "luciuisrv: mount failed: %r\n");
		raise "fail:mount";
	}
}

# --- Activity management ---

newactivity(label: string): ref Activity
{
	id := nextactid++;
	a := ref Activity(
		id, label, "active",
		array[32] of ref ConvMsg, 0, nil,	# conversation
		"", array[16] of ref Artifact, 0,	# presentation
		array[16] of ref Resource, 0,		# resources
		array[8] of ref Gap, 0,			# gaps
		array[8] of ref BgTask, 0		# bgtasks
	);

	if(nact >= len activities) {
		na := array[len activities * 2] of ref Activity;
		na[0:] = activities[0:nact];
		activities = na;
	}
	activities[nact++] = a;

	if(currentact < 0)
		currentact = id;

	vers++;
	return a;
}

findactivity(id: int): ref Activity
{
	for(i := 0; i < nact; i++)
		if(activities[i].id == id)
			return activities[i];
	return nil;
}

findactidx(id: int): int
{
	for(i := 0; i < nact; i++)
		if(activities[i].id == id)
			return i;
	return -1;
}

# --- Conversation ---

addmessage(a: ref Activity, role, text, using: string): int
{
	if(a.nmsg >= len a.messages) {
		nm := array[len a.messages * 2] of ref ConvMsg;
		nm[0:] = a.messages[0:a.nmsg];
		a.messages = nm;
	}
	idx := a.nmsg;
	a.messages[a.nmsg++] = ref ConvMsg(role, text, using);
	vers++;
	return idx;
}

# --- Artifact management ---

findartifact(a: ref Activity, id: string): ref Artifact
{
	for(i := 0; i < a.nart; i++)
		if(a.artifacts[i].id == id)
			return a.artifacts[i];
	return nil;
}

findartidx(a: ref Activity, id: string): int
{
	for(i := 0; i < a.nart; i++)
		if(a.artifacts[i].id == id)
			return i;
	return -1;
}

addartifact(a: ref Activity, id, atype, label: string): ref Artifact
{
	if(a.nart >= len a.artifacts) {
		na := array[len a.artifacts * 2] of ref Artifact;
		na[0:] = a.artifacts[0:a.nart];
		a.artifacts = na;
	}
	art := ref Artifact(id, atype, label, "", a.nart);
	a.artifacts[a.nart++] = art;
	vers++;
	return art;
}

# --- Event dispatch ---

pushevent(actid: int, msg: string)
{
	# Wake pending readers on activity event file
	prev: ref PendingRead;
	p := pending;
	while(p != nil) {
		next := p.next;
		if(p.ft == Qactevent && p.actid == actid) {
			data := array of byte (msg + "\n");
			srv_reply_read(p, data);
			# Remove from list
			if(prev == nil)
				pending = next;
			else
				prev.next = next;
			p = next;
			continue;
		}
		prev = p;
		p = next;
	}
}

pushglobalevent(msg: string)
{
	prev: ref PendingRead;
	p := pending;
	while(p != nil) {
		next := p.next;
		if(p.ft == Qevent) {
			data := array of byte (msg + "\n");
			srv_reply_read(p, data);
			if(prev == nil)
				pending = next;
			else
				prev.next = next;
			p = next;
			continue;
		}
		prev = p;
		p = next;
	}
}

srv_g: ref Styxserver;

srv_reply_read(p: ref PendingRead, data: array of byte)
{
	srv_g.reply(styxservers->readbytes(p.m, data));
}

addpending(fid, tag, ft, actid: int, m: ref Tmsg.Read)
{
	p := ref PendingRead(fid, tag, m, ft, actid, pending);
	pending = p;
}

cancelpending(tag: int)
{
	prev: ref PendingRead;
	p := pending;
	while(p != nil) {
		if(p.tag == tag) {
			if(prev == nil)
				pending = p.next;
			else
				prev.next = p.next;
			return;
		}
		prev = p;
		p = p.next;
	}
}

# --- Serve loop ---

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver,
	pidc: chan of int, navops: chan of ref Navop)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWFD, 1::2::srv.fd.fd::nil);
	srv_g = srv;

Serve:
	while((gm := <-tchan) != nil) {
		pick m := gm {
		Readerror =>
			sys->fprint(stderr, "luciuisrv: fatal read error: %s\n", m.error);
			break Serve;

		Flush =>
			cancelpending(m.oldtag);
			srv.reply(ref Rmsg.Flush(m.tag));

		Open =>
			c := srv.getfid(m.fid);
			if(c == nil) {
				srv.open(m);
				break;
			}
			mode := styxservers->openmode(m.mode);
			if(mode < 0) {
				srv.reply(ref Rmsg.Error(m.tag, Ebadarg));
				break;
			}
			qid := Qid(c.path, 0, c.qtype);
			c.open(mode, qid);
			srv.reply(ref Rmsg.Open(m.tag, qid, srv.iounit()));

		Read =>
			(c, err) := srv.canread(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			if(c.qtype & Sys->QTDIR) {
				srv.read(m);
				break;
			}
			doread(srv, m, c);

		Write =>
			(c, merr) := srv.canwrite(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, merr));
				break;
			}
			dowrite(srv, m, c);

		Clunk =>
			# Remove pending reads for this fid
			prev: ref PendingRead;
			p := pending;
			while(p != nil) {
				next := p.next;
				if(p.fid == m.fid) {
					if(prev == nil)
						pending = next;
					else
						prev.next = next;
					p = next;
					continue;
				}
				prev = p;
				p = next;
			}
			srv.clunk(m);

		Remove =>
			srv.remove(m);

		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;
}

# --- Read handling ---

doread(srv: ref Styxserver, m: ref Tmsg.Read, c: ref Fid)
{
	ft := FTYPE(c.path);
	actid := ACTID(c.path);
	subid := SUBID(c.path);

	case ft {
	Qctl =>
		info := "";
		if(nact > 0) {
			info = "activities:";
			for(i := 0; i < nact; i++)
				info += " " + string activities[i].id;
			info += "\n";
		}
		info += "current: " + string currentact + "\n";
		srv.reply(styxservers->readbytes(m, array of byte info));

	Qevent =>
		# Blocking read: queue pending
		addpending(m.fid, m.tag, Qevent, 0, m);

	Qnotification =>
		if(notifyq == nil) {
			srv.reply(styxservers->readbytes(m, array[0] of byte));
		} else {
			data := array of byte (hd notifyq + "\n");
			notifyq = tl notifyq;
			srv.reply(styxservers->readbytes(m, data));
		}

	Qtoast =>
		if(toastq == nil) {
			srv.reply(styxservers->readbytes(m, array[0] of byte));
		} else {
			data := array of byte (hd toastq + "\n");
			toastq = tl toastq;
			srv.reply(styxservers->readbytes(m, data));
		}

	Qactcurrent =>
		srv.reply(styxservers->readbytes(m, array of byte (string currentact + "\n")));

	Qactlabel =>
		a := findactivity(actid);
		if(a == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		srv.reply(styxservers->readbytes(m, array of byte (a.label + "\n")));

	Qactstatus =>
		a := findactivity(actid);
		if(a == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		srv.reply(styxservers->readbytes(m, array of byte (a.status + "\n")));

	Qactevent =>
		# Blocking read: queue pending
		addpending(m.fid, m.tag, Qactevent, actid, m);

	Qconvinput =>
		a := findactivity(actid);
		if(a == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		if(a.inputq == nil) {
			# Blocking read
			addpending(m.fid, m.tag, Qconvinput, actid, m);
		} else {
			data := array of byte (hd a.inputq + "\n");
			a.inputq = tl a.inputq;
			srv.reply(styxservers->readbytes(m, data));
		}

	Qconvmsg =>
		a := findactivity(actid);
		if(a == nil || subid >= a.nmsg) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		msg := a.messages[subid];
		text := "role=" + msg.role;
		if(msg.using != nil && msg.using != "")
			text += " using=" + msg.using;
		text += " text=" + msg.text + "\n";
		srv.reply(styxservers->readbytes(m, array of byte text));

	Qprescurrent =>
		a := findactivity(actid);
		if(a == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		srv.reply(styxservers->readbytes(m, array of byte (a.currentArtifact + "\n")));

	Qarttype =>
		a := findactivity(actid);
		if(a == nil || subid >= a.nart) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		srv.reply(styxservers->readbytes(m, array of byte (a.artifacts[subid].atype + "\n")));

	Qartlabel =>
		a := findactivity(actid);
		if(a == nil || subid >= a.nart) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		srv.reply(styxservers->readbytes(m, array of byte (a.artifacts[subid].label + "\n")));

	Qartdata =>
		a := findactivity(actid);
		if(a == nil || subid >= a.nart) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		srv.reply(styxservers->readbytes(m, array of byte a.artifacts[subid].data));

	Qresentry =>
		a := findactivity(actid);
		if(a == nil || subid >= a.nres) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		r := a.resources[subid];
		text := "path=" + r.path + " label=" + r.label + " type=" + r.rtype + " status=" + r.status;
		if(r.latency != "")
			text += " latency=" + r.latency;
		if(r.via != "")
			text += " via=" + r.via;
		if(r.staleFor != "")
			text += " staleFor=" + r.staleFor;
		text += "\n";
		srv.reply(styxservers->readbytes(m, array of byte text));

	Qgapentry =>
		a := findactivity(actid);
		if(a == nil || subid >= a.ngaps) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		g := a.gaps[subid];
		text := "desc=" + g.desc + " relevance=" + g.relevance + "\n";
		srv.reply(styxservers->readbytes(m, array of byte text));

	Qbgentry =>
		a := findactivity(actid);
		if(a == nil || subid >= a.nbg) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		bg := a.bgtasks[subid];
		text := "label=" + bg.label + " status=" + bg.status;
		if(bg.progress != "")
			text += " progress=" + bg.progress;
		text += "\n";
		srv.reply(styxservers->readbytes(m, array of byte text));

	* =>
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
	}
}

# --- Write handling ---

dowrite(srv: ref Styxserver, m: ref Tmsg.Write, c: ref Fid)
{
	ft := FTYPE(c.path);
	actid := ACTID(c.path);

	data := string m.data;
	# Strip trailing newline
	if(len data > 0 && data[len data - 1] == '\n')
		data = data[0:len data - 1];

	case ft {
	Qctl =>
		err := globalctl(data);
		if(err != nil) {
			srv.reply(ref Rmsg.Error(m.tag, err));
			break;
		}
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qnotification =>
		notifyq = appendstr(notifyq, data);
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qtoast =>
		toastq = appendstr(toastq, data);
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qactcurrent =>
		id := strtoint(data);
		if(id < 0 || findactivity(id) == nil) {
			srv.reply(ref Rmsg.Error(m.tag, "unknown activity"));
			break;
		}
		currentact = id;
		vers++;
		pushglobalevent("activity " + data);
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qactlabel =>
		a := findactivity(actid);
		if(a == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		a.label = data;
		vers++;
		pushevent(actid, "label");
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qactstatus =>
		a := findactivity(actid);
		if(a == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		a.status = data;
		vers++;
		pushevent(actid, "status");
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qconvctl =>
		a := findactivity(actid);
		if(a == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		err := convctl(a, data);
		if(err != nil) {
			srv.reply(ref Rmsg.Error(m.tag, err));
			break;
		}
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qconvinput =>
		a := findactivity(actid);
		if(a == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		# Check for pending input readers
		delivered := 0;
		prev: ref PendingRead;
		p := pending;
		while(p != nil) {
			next := p.next;
			if(p.ft == Qconvinput && p.actid == actid) {
				reply := array of byte (data + "\n");
				srv_g.reply(styxservers->readbytes(p.m, reply));
				if(prev == nil)
					pending = next;
				else
					prev.next = next;
				delivered = 1;
				p = next;
				break;	# deliver to first waiter only
			}
			prev = p;
			p = next;
		}
		if(!delivered)
			a.inputq = appendstr(a.inputq, data);
		pushevent(actid, "input");
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qpresctl =>
		a := findactivity(actid);
		if(a == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		err := presctl(a, data);
		if(err != nil) {
			srv.reply(ref Rmsg.Error(m.tag, err));
			break;
		}
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qprescurrent =>
		a := findactivity(actid);
		if(a == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		a.currentArtifact = data;
		vers++;
		pushevent(actid, "presentation current");
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qartdata =>
		a := findactivity(actid);
		subid := SUBID(c.path);
		if(a == nil || subid >= a.nart) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		a.artifacts[subid].data = data;
		vers++;
		pushevent(actid, "presentation " + a.artifacts[subid].id);
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qctxctl =>
		a := findactivity(actid);
		if(a == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		err := ctxctl(a, data);
		if(err != nil) {
			srv.reply(ref Rmsg.Error(m.tag, err));
			break;
		}
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	* =>
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
	}
}

# --- Ctl command handlers ---

globalctl(data: string): string
{
	if(hasprefix(data, "activity create ")) {
		label := data[len "activity create ":];
		a := newactivity(label);
		pushglobalevent("activity new " + string a.id);
		return nil;
	}
	if(hasprefix(data, "activity delete ")) {
		idstr := data[len "activity delete ":];
		id := strtoint(idstr);
		if(id < 0)
			return "bad activity id";
		idx := findactidx(id);
		if(idx < 0)
			return "unknown activity: " + idstr;
		# Mark as hidden but preserve data ("data is sacred")
		activities[idx].status = "hidden";
		vers++;
		pushglobalevent("activity delete " + idstr);
		return nil;
	}
	return "unknown ctl command: " + data;
}

convctl(a: ref Activity, data: string): string
{
	# In-place update of an existing message (for streaming token updates).
	# Format: "update idx=N text=..."
	if(hasprefix(data, "update ")) {
		attrs := parseattrs(data[len "update ":]);
		idx := strtoint(getattr(attrs, "idx"));
		text := getattr(attrs, "text");
		if(idx < 0 || idx >= a.nmsg)
			return "bad idx";
		if(text == nil)
			text = "";
		a.messages[idx].text = text;
		vers++;
		pushevent(a.id, "conversation update " + string idx);
		return nil;
	}

	# Parse key=value pairs
	attrs := parseattrs(data);
	role := getattr(attrs, "role");
	text := getattr(attrs, "text");
	using := getattr(attrs, "using");

	if(role == nil || role == "")
		return "missing role";
	if(text == nil)
		text = "";

	idx := addmessage(a, role, text, using);
	pushevent(a.id, "conversation " + string idx);
	return nil;
}

presctl(a: ref Activity, data: string): string
{
	if(hasprefix(data, "create ")) {
		rest := data[len "create ":];
		attrs := parseattrs(rest);
		id := getattr(attrs, "id");
		atype := getattr(attrs, "type");
		label := getattr(attrs, "label");
		if(id == nil || id == "")
			return "missing id";
		if(atype == nil || atype == "")
			atype = "text";
		if(label == nil)
			label = id;
		if(findartifact(a, id) != nil)
			return "artifact already exists: " + id;
		addartifact(a, id, atype, label);
		pushevent(a.id, "presentation new " + id);
		return nil;
	}
	if(hasprefix(data, "update ")) {
		rest := data[len "update ":];
		attrs := parseattrs(rest);
		id := getattr(attrs, "id");
		if(id == nil || id == "")
			return "missing id";
		art := findartifact(a, id);
		if(art == nil)
			return "unknown artifact: " + id;
		d := getattr(attrs, "data");
		if(d != nil)
			art.data = d;
		l := getattr(attrs, "label");
		if(l != nil)
			art.label = l;
		t := getattr(attrs, "type");
		if(t != nil)
			art.atype = t;
		vers++;
		pushevent(a.id, "presentation " + id);
		return nil;
	}
	if(hasprefix(data, "append ")) {
		attrs := parseattrs(data[len "append ":]);
		id := getattr(attrs, "id");
		chunk := getattr(attrs, "data");
		if(id == nil || id == "")
			return "missing id";
		art := findartifact(a, id);
		if(art == nil)
			return "unknown artifact: " + id;
		if(chunk != nil)
			art.data += chunk;
		vers++;
		pushevent(a.id, "presentation " + id);
		return nil;
	}
	if(hasprefix(data, "center ")) {
		rest := data[len "center ":];
		attrs := parseattrs(rest);
		id := getattr(attrs, "id");
		if(id == nil || id == "")
			id = rest;	# plain "center foo"
		if(findartifact(a, id) == nil)
			return "unknown artifact: " + id;
		a.currentArtifact = id;
		vers++;
		pushevent(a.id, "presentation current");
		return nil;
	}
	return "unknown presentation command: " + data;
}

ctxctl(a: ref Activity, data: string): string
{
	if(hasprefix(data, "resource add ")) {
		rest := data[len "resource add ":];
		attrs := parseattrs(rest);
		path := getattr(attrs, "path");
		label := getattr(attrs, "label");
		rtype := getattr(attrs, "type");
		status := getattr(attrs, "status");
		latency := getattr(attrs, "latency");
		via := getattr(attrs, "via");
		if(path == nil || path == "")
			return "missing path";
		if(label == nil)
			label = path;
		if(rtype == nil)
			rtype = "unknown";
		if(status == nil)
			status = "idle";
		if(a.nres >= len a.resources) {
			nr := array[len a.resources * 2] of ref Resource;
			nr[0:] = a.resources[0:a.nres];
			a.resources = nr;
		}
		a.resources[a.nres++] = ref Resource(path, label, rtype, status, latency, via, "");
		vers++;
		pushevent(a.id, "context resources");
		return nil;
	}
	if(hasprefix(data, "resource update ")) {
		rest := data[len "resource update ":];
		attrs := parseattrs(rest);
		path := getattr(attrs, "path");
		if(path == nil || path == "")
			return "missing path";
		found := 0;
		for(i := 0; i < a.nres; i++) {
			if(a.resources[i].path == path) {
				s := getattr(attrs, "status");
				if(s != nil)
					a.resources[i].status = s;
				sf := getattr(attrs, "staleFor");
				if(sf != nil)
					a.resources[i].staleFor = sf;
				l := getattr(attrs, "latency");
				if(l != nil)
					a.resources[i].latency = l;
				found = 1;
				break;
			}
		}
		if(!found)
			return "unknown resource: " + path;
		vers++;
		pushevent(a.id, "context resources");
		return nil;
	}
	if(hasprefix(data, "resource remove ")) {
		rest := data[len "resource remove ":];
		path := rest;
		found := 0;
		for(i := 0; i < a.nres; i++) {
			if(a.resources[i].path == path) {
				a.resources[i:] = a.resources[i+1:a.nres];
				a.nres--;
				a.resources[a.nres] = nil;
				found = 1;
				break;
			}
		}
		if(!found)
			return "unknown resource: " + path;
		vers++;
		pushevent(a.id, "context resources");
		return nil;
	}
	if(hasprefix(data, "gap add ")) {
		rest := data[len "gap add ":];
		attrs := parseattrs(rest);
		desc := getattr(attrs, "desc");
		relevance := getattr(attrs, "relevance");
		if(desc == nil || desc == "")
			return "missing desc";
		if(relevance == nil)
			relevance = "medium";
		if(a.ngaps >= len a.gaps) {
			ng := array[len a.gaps * 2] of ref Gap;
			ng[0:] = a.gaps[0:a.ngaps];
			a.gaps = ng;
		}
		a.gaps[a.ngaps++] = ref Gap(desc, relevance);
		vers++;
		pushevent(a.id, "context gaps");
		return nil;
	}
	if(hasprefix(data, "gap remove ")) {
		rest := data[len "gap remove ":];
		idx := strtoint(rest);
		if(idx < 0 || idx >= a.ngaps)
			return "bad gap index";
		a.gaps[idx:] = a.gaps[idx+1:a.ngaps];
		a.ngaps--;
		a.gaps[a.ngaps] = nil;
		vers++;
		pushevent(a.id, "context gaps");
		return nil;
	}
	if(hasprefix(data, "bg add ")) {
		rest := data[len "bg add ":];
		attrs := parseattrs(rest);
		label := getattr(attrs, "label");
		status := getattr(attrs, "status");
		if(label == nil || label == "")
			return "missing label";
		if(status == nil)
			status = "idle";
		if(a.nbg >= len a.bgtasks) {
			nb := array[len a.bgtasks * 2] of ref BgTask;
			nb[0:] = a.bgtasks[0:a.nbg];
			a.bgtasks = nb;
		}
		a.bgtasks[a.nbg++] = ref BgTask(label, status, "");
		vers++;
		pushevent(a.id, "context background");
		return nil;
	}
	if(hasprefix(data, "bg update ")) {
		rest := data[len "bg update ":];
		# "bg update 0 progress=67"
		(ntok, toks) := sys->tokenize(rest, " \t");
		if(ntok < 2)
			return "usage: bg update <idx> key=value...";
		idx := strtoint(hd toks);
		if(idx < 0 || idx >= a.nbg)
			return "bad bg task index";
		# Parse remaining as attrs
		rem := "";
		for(t := tl toks; t != nil; t = tl t) {
			if(rem != "")
				rem += " ";
			rem += hd t;
		}
		attrs := parseattrs(rem);
		s := getattr(attrs, "status");
		if(s != nil)
			a.bgtasks[idx].status = s;
		p := getattr(attrs, "progress");
		if(p != nil)
			a.bgtasks[idx].progress = p;
		l := getattr(attrs, "label");
		if(l != nil)
			a.bgtasks[idx].label = l;
		vers++;
		pushevent(a.id, "context background");
		return nil;
	}
	return "unknown context command: " + data;
}

# --- Directory generation ---

dir(qid: Sys->Qid, name: string, length: big, perm: int): ref Sys->Dir
{
	d := ref sys->zerodir;
	d.qid = qid;
	if(qid.qtype & Sys->QTDIR)
		perm |= Sys->DMDIR;
	d.mode = perm;
	d.name = name;
	d.uid = user;
	d.gid = user;
	d.length = length;
	return d;
}

dirgen(p: big): (ref Sys->Dir, string)
{
	ft := FTYPE(p);
	actid := ACTID(p);
	subid := SUBID(p);

	case ft {
	Qroot =>
		return (dir(Qid(p, vers, Sys->QTDIR), "/", big 0, 8r755), nil);
	Qctl =>
		return (dir(Qid(p, vers, Sys->QTFILE), "ctl", big 0, 8r644), nil);
	Qevent =>
		return (dir(Qid(p, vers, Sys->QTFILE), "event", big 0, 8r444), nil);
	Qnotification =>
		return (dir(Qid(p, vers, Sys->QTFILE), "notification", big 0, 8r666), nil);
	Qtoast =>
		return (dir(Qid(p, vers, Sys->QTFILE), "toast", big 0, 8r666), nil);
	Qactdir =>
		return (dir(Qid(p, vers, Sys->QTDIR), "activity", big 0, 8r755), nil);
	Qactcurrent =>
		return (dir(Qid(p, vers, Sys->QTFILE), "current", big 0, 8r644), nil);
	Qact =>
		return (dir(Qid(p, vers, Sys->QTDIR), string actid, big 0, 8r755), nil);
	Qactlabel =>
		return (dir(Qid(p, vers, Sys->QTFILE), "label", big 0, 8r644), nil);
	Qactstatus =>
		return (dir(Qid(p, vers, Sys->QTFILE), "status", big 0, 8r644), nil);
	Qactevent =>
		return (dir(Qid(p, vers, Sys->QTFILE), "event", big 0, 8r444), nil);
	Qconvdir =>
		return (dir(Qid(p, vers, Sys->QTDIR), "conversation", big 0, 8r755), nil);
	Qconvctl =>
		return (dir(Qid(p, vers, Sys->QTFILE), "ctl", big 0, 8r644), nil);
	Qconvinput =>
		return (dir(Qid(p, vers, Sys->QTFILE), "input", big 0, 8r666), nil);
	Qconvmsg =>
		return (dir(Qid(p, vers, Sys->QTFILE), string subid, big 0, 8r444), nil);
	Qpresdir =>
		return (dir(Qid(p, vers, Sys->QTDIR), "presentation", big 0, 8r755), nil);
	Qpresctl =>
		return (dir(Qid(p, vers, Sys->QTFILE), "ctl", big 0, 8r644), nil);
	Qprescurrent =>
		return (dir(Qid(p, vers, Sys->QTFILE), "current", big 0, 8r644), nil);
	Qartdir =>
		a := findactivity(actid);
		if(a != nil && subid < a.nart)
			return (dir(Qid(p, vers, Sys->QTDIR), a.artifacts[subid].id, big 0, 8r755), nil);
		return (dir(Qid(p, vers, Sys->QTDIR), string subid, big 0, 8r755), nil);
	Qarttype =>
		return (dir(Qid(p, vers, Sys->QTFILE), "type", big 0, 8r444), nil);
	Qartlabel =>
		return (dir(Qid(p, vers, Sys->QTFILE), "label", big 0, 8r444), nil);
	Qartdata =>
		return (dir(Qid(p, vers, Sys->QTFILE), "data", big 0, 8r666), nil);
	Qctxdir =>
		return (dir(Qid(p, vers, Sys->QTDIR), "context", big 0, 8r755), nil);
	Qctxctl =>
		return (dir(Qid(p, vers, Sys->QTFILE), "ctl", big 0, 8r644), nil);
	Qresdir =>
		return (dir(Qid(p, vers, Sys->QTDIR), "resources", big 0, 8r755), nil);
	Qresentry =>
		return (dir(Qid(p, vers, Sys->QTFILE), string subid, big 0, 8r444), nil);
	Qgapdir =>
		return (dir(Qid(p, vers, Sys->QTDIR), "gaps", big 0, 8r755), nil);
	Qgapentry =>
		return (dir(Qid(p, vers, Sys->QTFILE), string subid, big 0, 8r444), nil);
	Qbgdir =>
		return (dir(Qid(p, vers, Sys->QTDIR), "background", big 0, 8r755), nil);
	Qbgentry =>
		return (dir(Qid(p, vers, Sys->QTFILE), string subid, big 0, 8r444), nil);
	}

	return (nil, Enotfound);
}

# --- Navigator ---

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil) {
		pick n := m {
		Stat =>
			n.reply <-= dirgen(n.path);

		Walk =>
			ft := FTYPE(n.path);
			actid := ACTID(n.path);
			subid := SUBID(n.path);

			case ft {
			Qroot =>
				case n.name {
				".." =>
					;
				"ctl" =>
					n.path = MKPATH(0, 0, Qctl);
				"event" =>
					n.path = MKPATH(0, 0, Qevent);
				"notification" =>
					n.path = MKPATH(0, 0, Qnotification);
				"toast" =>
					n.path = MKPATH(0, 0, Qtoast);
				"activity" =>
					n.path = MKPATH(0, 0, Qactdir);
				* =>
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.reply <-= dirgen(n.path);

			Qactdir =>
				case n.name {
				".." =>
					n.path = big Qroot;
				"current" =>
					n.path = MKPATH(0, 0, Qactcurrent);
				* =>
					id := strtoint(n.name);
					if(id < 0 || findactivity(id) == nil) {
						n.reply <-= (nil, Enotfound);
						continue;
					}
					n.path = MKPATH(id, 0, Qact);
				}
				n.reply <-= dirgen(n.path);

			Qact =>
				case n.name {
				".." =>
					n.path = MKPATH(0, 0, Qactdir);
				"label" =>
					n.path = MKPATH(actid, 0, Qactlabel);
				"status" =>
					n.path = MKPATH(actid, 0, Qactstatus);
				"event" =>
					n.path = MKPATH(actid, 0, Qactevent);
				"conversation" =>
					n.path = MKPATH(actid, 0, Qconvdir);
				"presentation" =>
					n.path = MKPATH(actid, 0, Qpresdir);
				"context" =>
					n.path = MKPATH(actid, 0, Qctxdir);
				* =>
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.reply <-= dirgen(n.path);

			Qconvdir =>
				case n.name {
				".." =>
					n.path = MKPATH(actid, 0, Qact);
				"ctl" =>
					n.path = MKPATH(actid, 0, Qconvctl);
				"input" =>
					n.path = MKPATH(actid, 0, Qconvinput);
				* =>
					# Numbered message file
					idx := strtoint(n.name);
					a := findactivity(actid);
					if(idx < 0 || a == nil || idx >= a.nmsg) {
						n.reply <-= (nil, Enotfound);
						continue;
					}
					n.path = MKPATH(actid, idx, Qconvmsg);
				}
				n.reply <-= dirgen(n.path);

			Qpresdir =>
				case n.name {
				".." =>
					n.path = MKPATH(actid, 0, Qact);
				"ctl" =>
					n.path = MKPATH(actid, 0, Qpresctl);
				"current" =>
					n.path = MKPATH(actid, 0, Qprescurrent);
				* =>
					# Artifact by id
					a := findactivity(actid);
					if(a == nil) {
						n.reply <-= (nil, Enotfound);
						continue;
					}
					aidx := findartidx(a, n.name);
					if(aidx < 0) {
						n.reply <-= (nil, Enotfound);
						continue;
					}
					n.path = MKPATH(actid, aidx, Qartdir);
				}
				n.reply <-= dirgen(n.path);

			Qartdir =>
				case n.name {
				".." =>
					n.path = MKPATH(actid, 0, Qpresdir);
				"type" =>
					n.path = MKPATH(actid, subid, Qarttype);
				"label" =>
					n.path = MKPATH(actid, subid, Qartlabel);
				"data" =>
					n.path = MKPATH(actid, subid, Qartdata);
				* =>
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.reply <-= dirgen(n.path);

			Qctxdir =>
				case n.name {
				".." =>
					n.path = MKPATH(actid, 0, Qact);
				"ctl" =>
					n.path = MKPATH(actid, 0, Qctxctl);
				"resources" =>
					n.path = MKPATH(actid, 0, Qresdir);
				"gaps" =>
					n.path = MKPATH(actid, 0, Qgapdir);
				"background" =>
					n.path = MKPATH(actid, 0, Qbgdir);
				* =>
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.reply <-= dirgen(n.path);

			Qresdir =>
				case n.name {
				".." =>
					n.path = MKPATH(actid, 0, Qctxdir);
				* =>
					idx := strtoint(n.name);
					a := findactivity(actid);
					if(idx < 0 || a == nil || idx >= a.nres) {
						n.reply <-= (nil, Enotfound);
						continue;
					}
					n.path = MKPATH(actid, idx, Qresentry);
				}
				n.reply <-= dirgen(n.path);

			Qgapdir =>
				case n.name {
				".." =>
					n.path = MKPATH(actid, 0, Qctxdir);
				* =>
					idx := strtoint(n.name);
					a := findactivity(actid);
					if(idx < 0 || a == nil || idx >= a.ngaps) {
						n.reply <-= (nil, Enotfound);
						continue;
					}
					n.path = MKPATH(actid, idx, Qgapentry);
				}
				n.reply <-= dirgen(n.path);

			Qbgdir =>
				case n.name {
				".." =>
					n.path = MKPATH(actid, 0, Qctxdir);
				* =>
					idx := strtoint(n.name);
					a := findactivity(actid);
					if(idx < 0 || a == nil || idx >= a.nbg) {
						n.reply <-= (nil, Enotfound);
						continue;
					}
					n.path = MKPATH(actid, idx, Qbgentry);
				}
				n.reply <-= dirgen(n.path);

			* =>
				# Non-directory files
				case n.name {
				".." =>
					# Navigate up based on file type
					case ft {
					Qctl or Qevent or Qnotification or Qtoast =>
						n.path = big Qroot;
					Qactcurrent =>
						n.path = MKPATH(0, 0, Qactdir);
					Qactlabel or Qactstatus or Qactevent =>
						n.path = MKPATH(actid, 0, Qact);
					Qconvctl or Qconvinput or Qconvmsg =>
						n.path = MKPATH(actid, 0, Qconvdir);
					Qpresctl or Qprescurrent =>
						n.path = MKPATH(actid, 0, Qpresdir);
					Qarttype or Qartlabel or Qartdata =>
						n.path = MKPATH(actid, subid, Qartdir);
					Qctxctl =>
						n.path = MKPATH(actid, 0, Qctxdir);
					Qresentry =>
						n.path = MKPATH(actid, 0, Qresdir);
					Qgapentry =>
						n.path = MKPATH(actid, 0, Qgapdir);
					Qbgentry =>
						n.path = MKPATH(actid, 0, Qbgdir);
					* =>
						n.path = big Qroot;
					}
					n.reply <-= dirgen(n.path);
				* =>
					n.reply <-= (nil, "not a directory");
				}
			}

		Readdir =>
			ft := FTYPE(m.path);
			actid := ACTID(m.path);

			case ft {
			Qroot =>
				entries := array[] of {
					MKPATH(0, 0, Qctl),
					MKPATH(0, 0, Qevent),
					MKPATH(0, 0, Qnotification),
					MKPATH(0, 0, Qtoast),
					MKPATH(0, 0, Qactdir),
				};
				i := n.offset;
				for(; i < len entries && n.count > 0; i++) {
					n.reply <-= dirgen(entries[i]);
					n.count--;
				}
				n.reply <-= (nil, nil);

			Qactdir =>
				# current + activity directories
				total := 1 + nact;
				i := n.offset;
				cnt := n.count;
				if(i == 0 && cnt > 0) {
					n.reply <-= dirgen(MKPATH(0, 0, Qactcurrent));
					cnt--;
					i++;
				}
				for(; i < total && cnt > 0; i++) {
					aidx := i - 1;
					n.reply <-= dirgen(MKPATH(activities[aidx].id, 0, Qact));
					cnt--;
				}
				n.reply <-= (nil, nil);

			Qact =>
				entries := array[] of {
					MKPATH(actid, 0, Qactlabel),
					MKPATH(actid, 0, Qactstatus),
					MKPATH(actid, 0, Qactevent),
					MKPATH(actid, 0, Qconvdir),
					MKPATH(actid, 0, Qpresdir),
					MKPATH(actid, 0, Qctxdir),
				};
				i := n.offset;
				for(; i < len entries && n.count > 0; i++) {
					n.reply <-= dirgen(entries[i]);
					n.count--;
				}
				n.reply <-= (nil, nil);

			Qconvdir =>
				a := findactivity(actid);
				# ctl + input + message files
				total := 2;
				if(a != nil)
					total += a.nmsg;
				i := n.offset;
				cnt := n.count;
				if(i == 0 && cnt > 0) {
					n.reply <-= dirgen(MKPATH(actid, 0, Qconvctl));
					cnt--;
					i++;
				}
				if(i == 1 && cnt > 0) {
					n.reply <-= dirgen(MKPATH(actid, 0, Qconvinput));
					cnt--;
					i++;
				}
				if(a != nil) {
					for(; i < total && cnt > 0; i++) {
						midx := i - 2;
						n.reply <-= dirgen(MKPATH(actid, midx, Qconvmsg));
						cnt--;
					}
				}
				n.reply <-= (nil, nil);

			Qpresdir =>
				a := findactivity(actid);
				# ctl + current + artifact dirs
				total := 2;
				if(a != nil)
					total += a.nart;
				i := n.offset;
				cnt := n.count;
				if(i == 0 && cnt > 0) {
					n.reply <-= dirgen(MKPATH(actid, 0, Qpresctl));
					cnt--;
					i++;
				}
				if(i == 1 && cnt > 0) {
					n.reply <-= dirgen(MKPATH(actid, 0, Qprescurrent));
					cnt--;
					i++;
				}
				if(a != nil) {
					for(; i < total && cnt > 0; i++) {
						aidx := i - 2;
						n.reply <-= dirgen(MKPATH(actid, aidx, Qartdir));
						cnt--;
					}
				}
				n.reply <-= (nil, nil);

			Qartdir =>
				entries := array[] of {
					MKPATH(actid, SUBID(m.path), Qarttype),
					MKPATH(actid, SUBID(m.path), Qartlabel),
					MKPATH(actid, SUBID(m.path), Qartdata),
				};
				i := n.offset;
				for(; i < len entries && n.count > 0; i++) {
					n.reply <-= dirgen(entries[i]);
					n.count--;
				}
				n.reply <-= (nil, nil);

			Qctxdir =>
				entries := array[] of {
					MKPATH(actid, 0, Qctxctl),
					MKPATH(actid, 0, Qresdir),
					MKPATH(actid, 0, Qgapdir),
					MKPATH(actid, 0, Qbgdir),
				};
				i := n.offset;
				for(; i < len entries && n.count > 0; i++) {
					n.reply <-= dirgen(entries[i]);
					n.count--;
				}
				n.reply <-= (nil, nil);

			Qresdir =>
				a := findactivity(actid);
				cnt := 0;
				if(a != nil)
					cnt = a.nres;
				i := n.offset;
				ncnt := n.count;
				for(; i < cnt && ncnt > 0; i++) {
					n.reply <-= dirgen(MKPATH(actid, i, Qresentry));
					ncnt--;
				}
				n.reply <-= (nil, nil);

			Qgapdir =>
				a := findactivity(actid);
				cnt := 0;
				if(a != nil)
					cnt = a.ngaps;
				i := n.offset;
				ncnt := n.count;
				for(; i < cnt && ncnt > 0; i++) {
					n.reply <-= dirgen(MKPATH(actid, i, Qgapentry));
					ncnt--;
				}
				n.reply <-= (nil, nil);

			Qbgdir =>
				a := findactivity(actid);
				cnt := 0;
				if(a != nil)
					cnt = a.nbg;
				i := n.offset;
				ncnt := n.count;
				for(; i < cnt && ncnt > 0; i++) {
					n.reply <-= dirgen(MKPATH(actid, i, Qbgentry));
					ncnt--;
				}
				n.reply <-= (nil, nil);

			* =>
				n.reply <-= (nil, "not a directory");
			}
		}
	}
}

# --- Attribute parsing ---
# Parses "key1=value1 key2=value2" into list of (key, value) tuples.
# Values can be quoted or unquoted. Unquoted values end at next space-before-equals.

Attr: adt {
	key:	string;
	val:	string;
};

parseattrs(s: string): list of ref Attr
{
	# Find all key= positions. Each key= starts at the beginning of
	# the string or after whitespace, and a key is a non-whitespace
	# word followed by =.

	# Step 1: collect (keystart, eqpos) pairs as parallel arrays
	kstarts := array[32] of int;
	eqposs := array[32] of int;
	nkp := 0;

	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;

	j := i;
	while(j < len s) {
		if(s[j] == '=') {
			kstart := j - 1;
			while(kstart > i && s[kstart - 1] != ' ' && s[kstart - 1] != '\t')
				kstart--;
			if(kstart >= 0 && kstart < j) {
				# Make sure this key starts at string start or after whitespace
				if(kstart == 0 || kstart == i || s[kstart - 1] == ' ' || s[kstart - 1] == '\t') {
					if(nkp >= len kstarts) {
						nks := array[len kstarts * 2] of int;
						nks[0:] = kstarts[0:nkp];
						kstarts = nks;
						neq := array[len eqposs * 2] of int;
						neq[0:] = eqposs[0:nkp];
						eqposs = neq;
					}
					kstarts[nkp] = kstart;
					eqposs[nkp] = j;
					nkp++;
				}
			}
		}
		j++;
	}

	# Step 2: extract key=value pairs
	attrs: list of ref Attr;
	for(k := 0; k < nkp; k++) {
		key := s[kstarts[k]:eqposs[k]];
		vstart := eqposs[k] + 1;
		vend: int;
		if(k + 1 < nkp) {
			# Value ends before the whitespace preceding next key
			vend = kstarts[k + 1];
			while(vend > vstart && (s[vend - 1] == ' ' || s[vend - 1] == '\t'))
				vend--;
		} else
			vend = len s;
		val := "";
		if(vstart < vend)
			val = s[vstart:vend];
		attrs = ref Attr(key, val) :: attrs;
	}

	# Reverse to preserve original order
	rev: list of ref Attr;
	for(; attrs != nil; attrs = tl attrs)
		rev = hd attrs :: rev;
	return rev;
}

getattr(attrs: list of ref Attr, key: string): string
{
	for(; attrs != nil; attrs = tl attrs)
		if((hd attrs).key == key)
			return (hd attrs).val;
	return nil;
}

# --- Helpers ---

ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil)
		return;
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			ensuredir(path[0:i]);
			break;
		}
	}
	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
	if(fd == nil)
		sys->fprint(stderr, "luciuisrv: cannot create directory %s: %r\n", path);
}

rf(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, b, len b);
	if(n < 0)
		return nil;
	return string b[0:n];
}

strtoint(s: string): int
{
	n := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9')
			return -1;
		n = n * 10 + (c - '0');
	}
	if(len s == 0)
		return -1;
	return n;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

appendstr(l: list of string, s: string): list of string
{
	# Append to end of list (order matters for queues)
	if(l == nil)
		return s :: nil;
	rev: list of string;
	for(; l != nil; l = tl l)
		rev = hd l :: rev;
	rev = s :: rev;
	result: list of string;
	for(; rev != nil; rev = tl rev)
		result = hd rev :: result;
	return result;
}
