implement Taskboard9p;

#
# taskboard9p - Dashboard 9P Server for task metadata
#
# Mounted at /n/dashboard.  Syncs task state from /n/ui/ and
# exposes structured metadata (synopsis, category, instructions,
# progress, ordering) that the meta-agent can read and write.
#
# Filesystem:
#   /n/dashboard/
#     ctl              rw: "synopsis {id} text" | "categorize {id} cat" |
#                          "progress {id} val" | "order {id} n" |
#                          "instructions {id} text"
#     event            r:  blocking event stream (fan-out to all readers)
#     summary          r:  auto-rendered markdown
#     tasks/           dir
#       {id}/          dir
#         label        r: synced from /n/ui/
#         status       r: synced from /n/ui/
#         urgency      r: synced from /n/ui/
#         synopsis     rw
#         category     rw
#         instructions rw
#         progress     rw
#         order        rw
#
# Usage: taskboard9p [-m mountpoint]
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

Taskboard9p: module {
	init: fn(nil: ref Draw->Context, nil: list of string);
};

# --- Qid scheme ---
Qroot, Qctl, Qevent, Qsummary, Qtaskdir: con iota;
Qtaskbase: con 100;
TASK_STRIDE: con 9;	# dir, label, status, urgency, synopsis, category, instructions, progress, order
Qt_dir:          con 0;
Qt_label:        con 1;
Qt_status:       con 2;
Qt_urgency:      con 3;
Qt_synopsis:     con 4;
Qt_category:     con 5;
Qt_instructions: con 6;
Qt_progress:     con 7;
Qt_order:        con 8;

SUBFILE_NAMES := array[] of {
	"",              # 0 = dir (not a file name)
	"label",         # 1
	"status",        # 2
	"urgency",       # 3
	"synopsis",      # 4
	"category",      # 5
	"instructions",  # 6
	"progress",      # 7
	"order",         # 8
};

# --- Task entry ---
TaskEntry: adt {
	id:           int;
	label:        string;
	status:       string;
	urgency:      int;
	synopsis:     string;
	category:     string;
	instructions: string;
	progress:     string;
	order:        int;
	hidden:       int;
	qbase:        int;		# qid base for this task
};

# --- Pending read for blocking event files ---
PendingRead: adt {
	fid:    int;
	tag:    int;
	m:      ref Tmsg.Read;
	ft:     int;		# Qevent
	next:   ref PendingRead;
};

# --- Module state ---
stderr: ref Sys->FD;
user: string;
tasks: list of ref TaskEntry;
nextqid := Qtaskbase;
vers := 0;
pending: ref PendingRead;
eventbuf: list of string;	# buffered events when no reader
summarytext: string;		# cached rendered summary
mountpt_g := "/n/dashboard";
uimount := "/n/ui";
srv_g: ref Styxserver;

nomod(s: string)
{
	sys->fprint(stderr, "taskboard9p: can't load %s: %r\n", s);
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
		'm' =>	mountpt_g = arg->earg();
		'D' =>	styxservers->traceset(1);
		* =>
			sys->fprint(stderr, "usage: taskboard9p [-m mountpoint]\n");
			raise "fail:usage";
		}

	user = readfile("/dev/user");
	if(user == nil || user == "")
		user = "inferno";
	user = strip(user);

	tasks = nil;
	summarytext = "# Tasks\n\n(no tasks)\n";

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0) {
		sys->fprint(stderr, "taskboard9p: pipe: %r\n");
		raise "fail:pipe";
	}

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	fds[0] = nil;
	srv_g = srv;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops);
	<-pidc;

	# Ensure mount point exists
	ensuredir(mountpt_g);

	if(sys->mount(fds[1], nil, mountpt_g, Sys->MREPL|Sys->MCREATE, nil) < 0) {
		sys->fprint(stderr, "taskboard9p: mount failed: %r\n");
		raise "fail:mount";
	}

	# Initial sync: discover existing activities
	initialsync();

	# Start watching /n/ui/event for activity changes
	spawn eventwatcher();
}

# Scan existing activities from /n/ui/ctl and populate task entries
initialsync()
{
	info := readfile(uimount + "/ctl");
	if(info == nil)
		return;
	info = strip(info);
	(nil, lines) := sys->tokenize(info, "\n");
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		if(hasprefix(line, "activities:")) {
			rest := strip(line[len "activities:":]);
			(nil, toks) := sys->tokenize(rest, " ");
			for(; toks != nil; toks = tl toks) {
				(id, nil) := str->toint(hd toks, 10);
				if(id <= 0)
					continue;	# skip activity 0 (meta-agent) and invalid
				te := addtask(id);
				synctask(te);
				if(te.synopsis == "")
					te.synopsis = "New task: " + te.label;
			}
		}
	}
	rendersummary();
}

ensuredir(path: string)
{
	(ok, nil) := sys->stat(path);
	if(ok < 0)
		sys->create(path, Sys->OREAD, 8r755 | Sys->DMDIR);
}

# --- Task management ---

findtask(id: int): ref TaskEntry
{
	for(t := tasks; t != nil; t = tl t)
		if((hd t).id == id)
			return hd t;
	return nil;
}

addtask(id: int): ref TaskEntry
{
	te := ref TaskEntry(id, "", "idle", 0, "", "", "", "", 0, 0, nextqid);
	nextqid += TASK_STRIDE;
	tasks = te :: tasks;
	vers++;
	return te;
}

# Sync label/status/urgency from /n/ui/ for a task
synctask(te: ref TaskEntry)
{
	s := readfile(sys->sprint("%s/activity/%d/label", uimount, te.id));
	if(s != nil)
		te.label = strip(s);
	s = readfile(sys->sprint("%s/activity/%d/status", uimount, te.id));
	if(s != nil)
		te.status = strip(s);
	s = readfile(sys->sprint("%s/activity/%d/urgency", uimount, te.id));
	if(s != nil) {
		(v, nil) := str->toint(strip(s), 10);
		te.urgency = v;
	}
	# Read instructions from brief file if not yet set
	if(te.instructions == "") {
		s = readfile(sys->sprint("/tmp/veltro/instructions.%d", te.id));
		if(s != nil)
			te.instructions = strip(s);
	}
}

# --- Event handling ---

pushevent(msg: string)
{
	# Fan-out: deliver to ALL pending Qevent readers
	prev: ref PendingRead;
	p := pending;
	delivered := 0;
	while(p != nil) {
		next := p.next;
		if(p.ft == Qevent) {
			data := array of byte (msg + "\n");
			srv_g.reply(styxservers->readbytes(p.m, data));
			if(prev == nil)
				pending = next;
			else
				prev.next = next;
			delivered = 1;
			p = next;
			continue;
		}
		prev = p;
		p = next;
	}
	if(!delivered)
		eventbuf = msg :: eventbuf;
}

addpending(fid, tag, ft: int, m: ref Tmsg.Read)
{
	p := ref PendingRead(fid, tag, m, ft, pending);
	pending = p;
}

# --- Summary rendering ---

rendersummary()
{
	# Group tasks by category
	categories: list of string;
	for(t := tasks; t != nil; t = tl t) {
		te := hd t;
		if(te.hidden)
			continue;
		cat := te.category;
		if(cat == "")
			cat = "Uncategorized";
		if(!listcontains(categories, cat))
			categories = cat :: categories;
	}

	# Reverse to preserve insertion order
	rev: list of string;
	for(; categories != nil; categories = tl categories)
		rev = hd categories :: rev;
	categories = rev;

	result := "# Tasks\n";

	for(; categories != nil; categories = tl categories) {
		cat := hd categories;
		result += "\n## " + cat + "\n";
		for(t = tasks; t != nil; t = tl t) {
			te := hd t;
			if(te.hidden)
				continue;
			tcat := te.category;
			if(tcat == "")
				tcat = "Uncategorized";
			if(tcat != cat)
				continue;
			line := sys->sprint("- **[%d] %s**", te.id, te.label);
			line += " — " + te.status;
			if(te.progress != "")
				line += " (" + te.progress + ")";
			if(te.synopsis != "")
				line += " — " + te.synopsis;
			result += line + "\n";
		}
	}

	# Check if we had any visible tasks
	hastasks := 0;
	for(t = tasks; t != nil; t = tl t)
		if(!(hd t).hidden)
			hastasks = 1;
	if(!hastasks)
		result += "\n(no tasks)\n";

	summarytext = result;
}

listcontains(l: list of string, s: string): int
{
	for(; l != nil; l = tl l)
		if(hd l == s)
			return 1;
	return 0;
}

# --- Event watcher ---
# Blocks on /n/ui/event and syncs task state

eventwatcher()
{
	evpath := uimount + "/event";
	backoff := 500;
	for(;;) {
		fd := sys->open(evpath, Sys->OREAD);
		if(fd == nil) {
			sys->sleep(backoff);
			if(backoff < 8000)
				backoff *= 2;
			continue;
		}
		buf := array[4096] of byte;
		n := sys->read(fd, buf, len buf);
		if(n <= 0) {
			sys->sleep(backoff);
			if(backoff < 8000)
				backoff *= 2;
			continue;
		}
		backoff = 500;
		ev := strip(string buf[0:n]);
		handleuievent(ev);
	}
}

handleuievent(ev: string)
{
	if(hasprefix(ev, "activity new ")) {
		rest := strip(ev[len "activity new ":]);
		(id, nil) := str->toint(rest, 10);
		if(id > 0) {
			te := findtask(id);
			if(te == nil)
				te = addtask(id);
			synctask(te);
			# Default synopsis from label
			if(te.synopsis == "")
				te.synopsis = "New task: " + te.label;
			rendersummary();
			pushevent(sys->sprint("task %d new", id));
		}
	} else if(hasprefix(ev, "activity delete ")) {
		rest := strip(ev[len "activity delete ":]);
		(id, nil) := str->toint(rest, 10);
		if(id > 0) {
			te := findtask(id);
			if(te != nil)
				te.hidden = 1;
			rendersummary();
			pushevent(sys->sprint("task %d delete", id));
		}
	} else if(hasprefix(ev, "activity ")) {
		# Other activity events: "activity urgency {id} {val}" or
		# activity switch "activity {id}"
		rest := strip(ev[len "activity ":]);
		if(hasprefix(rest, "urgency ")) {
			rest2 := strip(rest[len "urgency ":]);
			(id, nil) := str->toint(rest2, 10);
			if(id > 0) {
				te := findtask(id);
				if(te != nil) {
					synctask(te);
					rendersummary();
					pushevent(sys->sprint("task %d urgency %d", id, te.urgency));
				}
			}
		} else {
			# Might be a switch or status change; re-sync all
			for(t := tasks; t != nil; t = tl t) {
				te := hd t;
				if(!te.hidden)
					synctask(te);
			}
			rendersummary();
		}
	}
}

# --- Ctl command handling ---

handlectl(data: string): string
{
	if(hasprefix(data, "synopsis ")) {
		rest := data[len "synopsis ":];
		(id, tail) := parseidtext(rest);
		if(id < 0)
			return "bad id";
		te := findtask(id);
		if(te == nil)
			return "unknown task";
		te.synopsis = tail;
		rendersummary();
		pushevent(sys->sprint("task %d synopsis", id));
		return nil;
	}
	if(hasprefix(data, "categorize ")) {
		rest := data[len "categorize ":];
		(id, tail) := parseidtext(rest);
		if(id < 0)
			return "bad id";
		te := findtask(id);
		if(te == nil)
			return "unknown task";
		te.category = tail;
		rendersummary();
		pushevent(sys->sprint("task %d category %s", id, tail));
		return nil;
	}
	if(hasprefix(data, "progress ")) {
		rest := data[len "progress ":];
		(id, tail) := parseidtext(rest);
		if(id < 0)
			return "bad id";
		te := findtask(id);
		if(te == nil)
			return "unknown task";
		te.progress = tail;
		rendersummary();
		pushevent(sys->sprint("task %d progress %s", id, tail));
		return nil;
	}
	if(hasprefix(data, "order ")) {
		rest := data[len "order ":];
		(id, tail) := parseidtext(rest);
		if(id < 0)
			return "bad id";
		te := findtask(id);
		if(te == nil)
			return "unknown task";
		(v, nil) := str->toint(tail, 10);
		te.order = v;
		rendersummary();
		pushevent(sys->sprint("task %d order %d", id, v));
		return nil;
	}
	if(hasprefix(data, "instructions ")) {
		rest := data[len "instructions ":];
		(id, tail) := parseidtext(rest);
		if(id < 0)
			return "bad id";
		te := findtask(id);
		if(te == nil)
			return "unknown task";
		te.instructions = tail;
		rendersummary();
		pushevent(sys->sprint("task %d instructions", id));
		return nil;
	}
	return "usage: synopsis|categorize|progress|order|instructions {id} {text}";
}

# Parse "<id> <rest>" from a string
parseidtext(s: string): (int, string)
{
	# Skip leading whitespace
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;
	# Read digits
	start := i;
	while(i < len s && s[i] >= '0' && s[i] <= '9')
		i++;
	if(i == start)
		return (-1, "");
	(id, nil) := str->toint(s[start:i], 10);
	# Skip whitespace after id
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;
	tail := "";
	if(i < len s)
		tail = s[i:];
	return (id, tail);
}

# --- Serveloop ---

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver,
	pidc: chan of int, navops: chan of ref Navop)
{
	pidc <-= sys->pctl(0, nil);

	while((gm := <-tchan) != nil) {
		pick m := gm {
		Read =>
			(c, merr) := srv.canread(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, merr));
				break;
			}

			qtype := TYPE(c.path);

			case qtype {
			Qctl =>
				srv.reply(styxservers->readstr(m, ""));

			Qevent =>
				# Blocking read — check buffered events first
				if(eventbuf != nil) {
					# Reverse and take first
					rev: list of string;
					for(eb := eventbuf; eb != nil; eb = tl eb)
						rev = hd eb :: rev;
					msg := hd rev;
					# Remove from buffer
					newbuf: list of string;
					for(eb = eventbuf; eb != nil; eb = tl eb)
						if(hd eb != msg || newbuf != nil)
							newbuf = hd eb :: newbuf;
					eventbuf = newbuf;
					data := array of byte (msg + "\n");
					srv.reply(styxservers->readbytes(m, data));
				} else {
					addpending(c.fid, m.tag, Qevent, m);
				}

			Qsummary =>
				srv.reply(styxservers->readstr(m, summarytext));

			* =>
				if(qtype >= Qtaskbase) {
					(te, suboff) := taskfromqid(qtype);
					if(te == nil) {
						srv.reply(ref Rmsg.Error(m.tag, Enotfound));
						break;
					}
					val := "";
					case suboff {
					Qt_label =>        val = te.label;
					Qt_status =>       val = te.status;
					Qt_urgency =>      val = string te.urgency;
					Qt_synopsis =>     val = te.synopsis;
					Qt_category =>     val = te.category;
					Qt_instructions => val = te.instructions;
					Qt_progress =>     val = te.progress;
					Qt_order =>        val = string te.order;
					* =>
						srv.reply(ref Rmsg.Error(m.tag, Enotfound));
						break;
					}
					srv.reply(styxservers->readstr(m, val));
				} else {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
				}
			}

		Write =>
			(c, merr) := srv.canwrite(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, merr));
				break;
			}

			qtype := TYPE(c.path);
			data := string m.data;
			if(len data > 0 && data[len data - 1] == '\n')
				data = data[0:len data - 1];

			case qtype {
			Qctl =>
				err := handlectl(data);
				if(err != nil)
					srv.reply(ref Rmsg.Error(m.tag, err));
				else
					srv.reply(ref Rmsg.Write(m.tag, len m.data));

			* =>
				if(qtype >= Qtaskbase) {
					(te, suboff) := taskfromqid(qtype);
					if(te == nil) {
						srv.reply(ref Rmsg.Error(m.tag, Enotfound));
						break;
					}
					case suboff {
					Qt_synopsis =>
						te.synopsis = data;
						rendersummary();
						pushevent(sys->sprint("task %d synopsis", te.id));
						srv.reply(ref Rmsg.Write(m.tag, len m.data));
					Qt_category =>
						te.category = data;
						rendersummary();
						pushevent(sys->sprint("task %d category %s", te.id, data));
						srv.reply(ref Rmsg.Write(m.tag, len m.data));
					Qt_instructions =>
						te.instructions = data;
						rendersummary();
						pushevent(sys->sprint("task %d instructions", te.id));
						srv.reply(ref Rmsg.Write(m.tag, len m.data));
					Qt_progress =>
						te.progress = data;
						rendersummary();
						pushevent(sys->sprint("task %d progress %s", te.id, data));
						srv.reply(ref Rmsg.Write(m.tag, len m.data));
					Qt_order =>
						(v, nil) := str->toint(data, 10);
						te.order = v;
						rendersummary();
						pushevent(sys->sprint("task %d order %d", te.id, v));
						srv.reply(ref Rmsg.Write(m.tag, len m.data));
					* =>
						srv.reply(ref Rmsg.Error(m.tag, Eperm));
					}
				} else {
					srv.reply(ref Rmsg.Error(m.tag, Eperm));
				}
			}

		Clunk =>
			srv.clunk(m);

		Remove =>
			srv.remove(m);

		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;
}

# --- Qid helpers ---

TYPE(path: big): int
{
	return int path & 16rFFFF;
}

taskfromqid(qtype: int): (ref TaskEntry, int)
{
	if(qtype < Qtaskbase)
		return (nil, -1);
	off := qtype - Qtaskbase;
	base := Qtaskbase + (off / TASK_STRIDE) * TASK_STRIDE;
	suboff := off % TASK_STRIDE;
	for(t := tasks; t != nil; t = tl t) {
		te := hd t;
		if(te.qbase == base)
			return (te, suboff);
	}
	return (nil, -1);
}

findtaskbyqbase(qbase: int): ref TaskEntry
{
	for(t := tasks; t != nil; t = tl t)
		if((hd t).qbase == qbase)
			return hd t;
	return nil;
}

# --- Navigator ---

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
	qtype := TYPE(p);

	case qtype {
	Qroot =>
		return (dir(Qid(p, vers, Sys->QTDIR), "/", big 0, 8r755), nil);
	Qctl =>
		return (dir(Qid(p, vers, Sys->QTFILE), "ctl", big 0, 8r644), nil);
	Qevent =>
		return (dir(Qid(p, vers, Sys->QTFILE), "event", big 0, 8r444), nil);
	Qsummary =>
		return (dir(Qid(p, vers, Sys->QTFILE), "summary", big 0, 8r444), nil);
	Qtaskdir =>
		return (dir(Qid(p, vers, Sys->QTDIR), "tasks", big 0, 8r755), nil);
	}

	if(qtype >= Qtaskbase) {
		off := qtype - Qtaskbase;
		base := Qtaskbase + (off / TASK_STRIDE) * TASK_STRIDE;
		suboff := off % TASK_STRIDE;
		te := findtaskbyqbase(base);
		if(te != nil) {
			case suboff {
			Qt_dir =>
				return (dir(Qid(p, vers, Sys->QTDIR), string te.id, big 0, 8r755), nil);
			Qt_label or Qt_status or Qt_urgency =>
				return (dir(Qid(p, vers, Sys->QTFILE), SUBFILE_NAMES[suboff], big 0, 8r444), nil);
			Qt_synopsis or Qt_category or Qt_instructions or Qt_progress or Qt_order =>
				return (dir(Qid(p, vers, Sys->QTFILE), SUBFILE_NAMES[suboff], big 0, 8r644), nil);
			}
		}
	}

	return (nil, Enotfound);
}

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil) {
		pick n := m {
		Stat =>
			n.reply <-= dirgen(n.path);

		Walk =>
			qtype := TYPE(n.path);

			if(qtype == Qroot) {
				case n.name {
				".." =>
					;
				"ctl" =>
					n.path = big Qctl;
				"event" =>
					n.path = big Qevent;
				"summary" =>
					n.path = big Qsummary;
				"tasks" =>
					n.path = big Qtaskdir;
				* =>
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.reply <-= dirgen(n.path);
			} else if(qtype == Qtaskdir) {
				if(n.name == "..") {
					n.path = big Qroot;
					n.reply <-= dirgen(n.path);
					continue;
				}
				# Walk to task dir by id
				(id, nil) := str->toint(n.name, 10);
				te := findtask(id);
				if(te == nil || te.hidden) {
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.path = big te.qbase;
				n.reply <-= dirgen(n.path);
			} else if(qtype >= Qtaskbase) {
				off := qtype - Qtaskbase;
				suboff := off % TASK_STRIDE;
				base := Qtaskbase + (off / TASK_STRIDE) * TASK_STRIDE;
				if(suboff != Qt_dir) {
					n.reply <-= (nil, "not a directory");
					continue;
				}
				case n.name {
				".." =>
					n.path = big Qtaskdir;
				"label" =>
					n.path = big(base + Qt_label);
				"status" =>
					n.path = big(base + Qt_status);
				"urgency" =>
					n.path = big(base + Qt_urgency);
				"synopsis" =>
					n.path = big(base + Qt_synopsis);
				"category" =>
					n.path = big(base + Qt_category);
				"instructions" =>
					n.path = big(base + Qt_instructions);
				"progress" =>
					n.path = big(base + Qt_progress);
				"order" =>
					n.path = big(base + Qt_order);
				* =>
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.reply <-= dirgen(n.path);
			} else {
				n.reply <-= (nil, "not a directory");
			}

		Readdir =>
			qtype := TYPE(m.path);

			case qtype {
			Qroot =>
				i := n.offset;
				count := n.count;
				# Entry 0: ctl
				if(i == 0 && count > 0) {
					n.reply <-= dirgen(big Qctl);
					count--;
					i++;
				}
				# Entry 1: event
				if(i <= 1 && count > 0) {
					n.reply <-= dirgen(big Qevent);
					count--;
					i++;
				}
				# Entry 2: summary
				if(i <= 2 && count > 0) {
					n.reply <-= dirgen(big Qsummary);
					count--;
					i++;
				}
				# Entry 3: tasks/
				if(i <= 3 && count > 0) {
					n.reply <-= dirgen(big Qtaskdir);
					count--;
					i++;
				}
				n.reply <-= (nil, nil);

			Qtaskdir =>
				i := n.offset;
				count := n.count;
				idx := 0;
				for(t := tasks; t != nil && count > 0; t = tl t) {
					te := hd t;
					if(te.hidden)
						continue;
					if(idx >= i) {
						n.reply <-= dirgen(big te.qbase);
						count--;
					}
					idx++;
				}
				n.reply <-= (nil, nil);

			* =>
				if(qtype >= Qtaskbase) {
					off := qtype - Qtaskbase;
					suboff := off % TASK_STRIDE;
					base := Qtaskbase + (off / TASK_STRIDE) * TASK_STRIDE;
					if(suboff != Qt_dir) {
						n.reply <-= (nil, "not a directory");
					} else {
						i := n.offset;
						count := n.count;
						for(si := 1; si < TASK_STRIDE && count > 0; si++) {
							if(si - 1 >= i) {
								n.reply <-= dirgen(big(base + si));
								count--;
							}
						}
						n.reply <-= (nil, nil);
					}
				} else {
					n.reply <-= (nil, "not a directory");
				}
			}
		}
	}
}

# --- Utility ---

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

strip(s: string): string
{
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' ' || s[len s - 1] == '\t'))
		s = s[0:len s - 1];
	return s;
}

hasprefix(s, pfx: string): int
{
	return len s >= len pfx && s[0:len pfx] == pfx;
}
