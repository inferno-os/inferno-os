implement Matrix;

#
# matrix - Matrix compositional module runtime
#
# Loads Limbo modules against mounted 9P namespaces, managing
# their lifecycle and layout.  Supports GUI mode (display modules
# render in Lucifer's presentation zone) and headless mode (service
# modules only, no window).
#
# Usage:
#   matrix [-h] [composition-file]
#   matrix -h /lib/matrix/compositions/tbl4-monitor
#
# Flags:
#   -h    Force headless mode (skip GUI even if display modules present)
#
# See doc/matrix-architecture.md for the full specification.
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect, Pointer: import draw;

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

include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "lucitheme.m";

include "widget.m";
	widgetmod: Widget;
	Scrollbar, Label, Statusbar, Kbdfilter: import widgetmod;

include "matrix.m";

Matrix: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# ── Layout constants ────────────────────────────────────────

HSPLIT: con 0;
VSPLIT: con 1;
MAX_DEPTH: con 4;
UPDATE_MS: con 2000;

# ── Layout tree ─────────────────────────────────────────────

LayoutNode: adt
{
	pick {
	Split =>
		orient: int;
		ratio1: int;
		ratio2: int;
		child1: cyclic ref LayoutNode;
		child2: cyclic ref LayoutNode;
		r: Rect;
	Leaf =>
		name: string;
		modname: string;
		mount: string;
		mod: MatrixDisplay;
		r: Rect;
	}
};

# ── Module entries ──────────────────────────────────────────

ModuleAssign: adt
{
	region: string;
	modname: string;
	mount: string;
};

ServiceEntry: adt
{
	name: string;
	mount: string;
	outdir: string;
	mod: MatrixService;
	pid: int;
};

# ── Composition ─────────────────────────────────────────────

Composition: adt
{
	name: string;
	layout: ref LayoutNode;
	assigns: list of ref ModuleAssign;
	services: list of ref ServiceEntry;
	text: string;
};

# ── 9P qid space ───────────────────────────────────────────

Qroot, Qctl, Qcomposition, Qmoddir: con iota;
Qmodbase:  con 100;
MOD_STRIDE: con 8;
Qmod_dir:  con 0;
Qmod_ctl:  con 1;
Qmod_type: con 2;
Qmod_mount: con 3;

# ── Globals ─────────────────────────────────────────────────

stderr: ref Sys->FD;
user: string;
vers: int;
comp: ref Composition;
complock: chan of int;	# mutex for comp access

# GUI state
w: ref Window;
display_g: ref Display;
font_g: ref Font;
kf: ref Kbdfilter;
bgcolor: ref Image;
divcolor: ref Image;
textcolor: ref Image;
dimcolor: ref Image;
redcolor: ref Image;
greencolor: ref Image;
yellowcolor: ref Image;
guimode: int;
dirty: int;
focusmod: MatrixDisplay;	# module with keyboard focus

# Channels
updatech: chan of int;
reloadch: chan of string;
themech: chan of int;

# Module tracking
allmodules: list of (string, string, string);	# (name, type, mount) for 9P

# ── Init ────────────────────────────────────────────────────

init(ctxt: ref Draw->Context, args: list of string)
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

	forceheadless := 0;
	while((o := arg->opt()) != 0)
		case o {
		'h' =>	forceheadless = 1;
		* =>	usage();
		}
	args = arg->argv();
	arg = nil;

	user = readfile("/dev/user");
	if(user == nil)
		user = "inferno";

	complock = chan[1] of int;
	complock <-= 1;
	reloadch = chan[1] of string;

	# Parse initial composition
	comptext := "";
	if(args != nil)
		comptext = readfile(hd args);
	if(comptext == nil || comptext == "")
		comptext = "# empty\n";

	(c, err) := parsecomposition(comptext);
	if(err != nil) {
		sys->fprint(stderr, "matrix: parse error: %s\n", err);
		raise "fail:parse";
	}
	comp = c;

	# Start 9P server (always, both modes)
	start9p();

	# Determine mode
	guimode = !forceheadless && comp.layout != nil && comp.assigns != nil;

	if(guimode) {
		if(ctxt == nil) {
			sys->fprint(stderr, "matrix: no display context, falling back to headless\n");
			guimode = 0;
		}
	}

	if(guimode) {
		initgui(ctxt);
		loaddisplaymodules();
		loadservicemodules();
		guiloop();
	} else {
		loadservicemodules();
		headlessloop();
	}
}

usage()
{
	sys->fprint(stderr, "Usage: matrix [-h] [composition-file]\n");
	raise "fail:usage";
}

nomod(path: string)
{
	sys->fprint(stderr, "matrix: can't load %s: %r\n", path);
	raise "fail:load";
}

# ── Composition Parser ──────────────────────────────────────

parsecomposition(text: string): (ref Composition, string)
{
	c := ref Composition;
	c.text = text;
	c.name = "";
	c.layout = nil;
	c.assigns = nil;
	c.services = nil;

	# Leaf name → LayoutNode map (for resolving nested splits)
	leafnames: list of (string, ref LayoutNode);

	lines := splitlines(text);

	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		line = trim(line);
		if(len line == 0)
			continue;

		# Comment
		if(line[0] == '#') {
			if(c.name == "" && len line > 2)
				c.name = trim(line[2:]);
			continue;
		}

		(nil, toks) := sys->tokenize(line, " \t");
		if(toks == nil)
			continue;
		first := hd toks;
		rest := tl toks;

		# "layout hsplit|vsplit N M" — root split
		if(first == "layout") {
			if(c.layout != nil)
				return (nil, "duplicate layout declaration");
			if(len rest < 3)
				return (nil, "layout needs: hsplit|vsplit ratio1 ratio2");
			orient := parseorient(hd rest);
			if(orient < 0)
				return (nil, "layout: expected hsplit or vsplit");
			rest = tl rest;
			(r1, r1err) := parseint(hd rest);
			if(r1err != nil)
				return (nil, "layout: bad ratio1");
			rest = tl rest;
			(r2, r2err) := parseint(hd rest);
			if(r2err != nil)
				return (nil, "layout: bad ratio2");

			(n1, n2) := childnames("", orient);
			leaf1 := ref LayoutNode.Leaf(n1, "", "", nil, Rect((0,0),(0,0)));
			leaf2 := ref LayoutNode.Leaf(n2, "", "", nil, Rect((0,0),(0,0)));
			c.layout = ref LayoutNode.Split(
				orient, r1, r2, leaf1, leaf2,
				Rect((0,0),(0,0)));
			leafnames = (n1, leaf1) :: (n2, leaf2) :: nil;
			continue;
		}

		# "service name mount"
		if(first == "service") {
			if(len rest < 2)
				return (nil, "service needs: name mount");
			sname := hd rest;
			smount := hd tl rest;
			se := ref ServiceEntry(sname, smount, "", nil, 0);
			c.services = se :: c.services;
			continue;
		}

		# Region split: "left vsplit N M" or "right hsplit N M"
		# Region assign: "left/top module-name /mount/path"
		if(len rest >= 3) {
			# Is the second token an orientation?
			orient := parseorient(hd rest);
			if(orient >= 0) {
				# Region split
				rest = tl rest;
				(r1, r1e) := parseint(hd rest);
				if(r1e != nil)
					return (nil, first + ": bad ratio1");
				rest = tl rest;
				(r2, r2e) := parseint(hd rest);
				if(r2e != nil)
					return (nil, first + ": bad ratio2");

				# Find the leaf with this name
				found := 0;
				for(ln := leafnames; ln != nil; ln = tl ln) {
					(lname, nil) := hd ln;
					if(lname == first) {
						# Check depth
						if(depth(first) >= MAX_DEPTH - 1)
							return (nil, first + ": max layout depth exceeded");

						(n1, n2) := childnames(first, orient);
						leaf1 := ref LayoutNode.Leaf(n1, "", "", nil, Rect((0,0),(0,0)));
						leaf2 := ref LayoutNode.Leaf(n2, "", "", nil, Rect((0,0),(0,0)));
						split := ref LayoutNode.Split(
							orient, r1, r2, leaf1, leaf2,
							Rect((0,0),(0,0)));

						# Replace the leaf in its parent
						replaceleaf(c.layout, lname, split);

						# Update leaf names: remove old, add new
						newnames: list of (string, ref LayoutNode);
						for(ln2 := leafnames; ln2 != nil; ln2 = tl ln2)
							if((hd ln2).t0 != first)
								newnames = hd ln2 :: newnames;
						leafnames = (n1, leaf1) :: (n2, leaf2) :: newnames;
						found = 1;
						break;
					}
				}
				if(!found)
					return (nil, first + ": unknown region for split");
				continue;
			}
		}

		# Module assignment: "region modname mount"
		if(len rest >= 2) {
			modname := hd rest;
			mount := hd tl rest;
			ma := ref ModuleAssign(first, modname, mount);
			c.assigns = ma :: c.assigns;
			continue;
		}

		return (nil, "unrecognized line: " + line);
	}

	# Apply module assignments to layout leaves
	for(al := c.assigns; al != nil; al = tl al) {
		a := hd al;
		if(c.layout != nil) {
			if(!assignleaf(c.layout, a.region, a.modname, a.mount))
				return (nil, a.region + ": region not found in layout");
		}
	}

	return (c, nil);
}

# Parse "hsplit" or "vsplit"
parseorient(s: string): int
{
	if(s == "hsplit")
		return HSPLIT;
	if(s == "vsplit")
		return VSPLIT;
	return -1;
}

# Parse integer
parseint(s: string): (int, string)
{
	(v, rest) := str->toint(s, 10);
	if(rest != nil && rest != "")
		return (0, "not an integer");
	return (v, nil);
}

# Compute child names for a split
childnames(parent: string, orient: int): (string, string)
{
	prefix := "";
	if(parent != "")
		prefix = parent + "/";
	if(orient == HSPLIT)
		return (prefix + "left", prefix + "right");
	return (prefix + "top", prefix + "bottom");
}

# Count slashes to determine depth
depth(name: string): int
{
	d := 0;
	for(i := 0; i < len name; i++)
		if(name[i] == '/')
			d++;
	return d;
}

# Replace a named leaf in the layout tree with a new node
replaceleaf(node: ref LayoutNode, name: string, replacement: ref LayoutNode): int
{
	pick n := node {
	Split =>
		pick c1 := n.child1 {
		Leaf =>
			if(c1.name == name) {
				n.child1 = replacement;
				return 1;
			}
		Split =>
			if(replaceleaf(n.child1, name, replacement))
				return 1;
		}
		pick c2 := n.child2 {
		Leaf =>
			if(c2.name == name) {
				n.child2 = replacement;
				return 1;
			}
		Split =>
			if(replaceleaf(n.child2, name, replacement))
				return 1;
		}
	Leaf =>
		;  # can't recurse into a leaf
	}
	return 0;
}

# Assign a module to a named leaf
assignleaf(node: ref LayoutNode, name, modname, mount: string): int
{
	pick n := node {
	Split =>
		if(assignleaf(n.child1, name, modname, mount))
			return 1;
		return assignleaf(n.child2, name, modname, mount);
	Leaf =>
		if(n.name == name) {
			n.modname = modname;
			n.mount = mount;
			return 1;
		}
	}
	return 0;
}

# ── String utilities ────────────────────────────────────────

splitlines(s: string): list of string
{
	lines: list of string;
	start := 0;
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n') {
			lines = s[start:i] :: lines;
			start = i + 1;
		}
	}
	if(start < len s)
		lines = s[start:] :: lines;

	# Reverse
	rev: list of string;
	for(; lines != nil; lines = tl lines)
		rev = hd lines :: rev;
	return rev;
}

trim(s: string): string
{
	start := 0;
	end := len s;
	while(start < end && (s[start] == ' ' || s[start] == '\t'))
		start++;
	while(end > start && (s[end-1] == ' ' || s[end-1] == '\t'))
		end--;
	if(start == 0 && end == len s)
		return s;
	return s[start:end];
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	content := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		content += string buf[0:n];
	}
	if(content == "")
		return nil;
	return content;
}

writefile(path, data: string): string
{
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return sys->sprint("cannot create %s: %r", path);
	buf := array of byte data;
	n := sys->write(fd, buf, len buf);
	if(n != len buf)
		return sys->sprint("short write to %s", path);
	return nil;
}

ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil)
		return;
	for(i := len path - 1; i > 0; i--)
		if(path[i] == '/') {
			ensuredir(path[0:i]);
			break;
		}
	sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
}

# ── 9P Server ──────────────────────────────────────────────

start9p()
{
	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0) {
		sys->fprint(stderr, "matrix: can't create pipe: %r\n");
		raise "fail:pipe";
	}

	navops := chan of ref Navop;
	spawn matrixnavigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	fds[0] = nil;

	pidc := chan of int;
	spawn matrixserve(tchan, srv, pidc);
	<-pidc;

	ensuredir("/n/matrix");
	if(sys->mount(fds[1], nil, "/n/matrix", Sys->MREPL|Sys->MCREATE, nil) < 0) {
		sys->fprint(stderr, "matrix: mount failed: %r\n");
		raise "fail:mount";
	}
}

matrixserve(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int)
{
	pidc <-= sys->pctl(Sys->NEWFD, 1::2::srv.fd.fd::nil);

Serve:
	while((gm := <-tchan) != nil) {
		pick m := gm {
		Readerror =>
			break Serve;

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
			c.data = nil;
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

			qtype := TYPE(c.path);
			case qtype {
			Qctl =>
				status := "idle";
				<-complock;
				if(comp != nil && (comp.layout != nil || comp.services != nil))
					status = "running";
				complock <-= 1;
				srv.reply(styxservers->readbytes(m, array of byte (status + "\n")));

			Qcomposition =>
				<-complock;
				text := "";
				if(comp != nil)
					text = comp.text;
				complock <-= 1;
				srv.reply(styxservers->readbytes(m, array of byte text));

			* =>
				if(qtype >= Qmodbase) {
					off := modqoffset(qtype);
					mi := findmodbyqid(qtype);
					if(mi == nil) {
						srv.reply(ref Rmsg.Error(m.tag, Enotfound));
						break;
					}
					case off {
					Qmod_ctl =>
						srv.reply(styxservers->readbytes(m, array of byte (mi.status + "\n")));
					Qmod_type =>
						srv.reply(styxservers->readbytes(m, array of byte (mi.mtype + "\n")));
					Qmod_mount =>
						srv.reply(styxservers->readbytes(m, array of byte (mi.mount + "\n")));
					* =>
						srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					}
				} else {
					srv.reply(ref Rmsg.Error(m.tag, Eperm));
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
				ctlerr := handlectl(data);
				if(ctlerr != nil)
					srv.reply(ref Rmsg.Error(m.tag, ctlerr));
				else
					srv.reply(ref Rmsg.Write(m.tag, len m.data));

			Qcomposition =>
				# Write new composition → trigger reload
				alt {
				reloadch <-= string m.data =>
					;
				* =>
					;  # drop if reload already pending
				}
				srv.reply(ref Rmsg.Write(m.tag, len m.data));

			* =>
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
			}

		Clunk =>
			srv.clunk(m);

		Remove =>
			srv.remove(m);

		* =>
			srv.default(gm);
		}
	}
}

handlectl(data: string): string
{
	if(len data > 5 && data[0:5] == "load ") {
		name := data[5:];
		text: string;
		if(name == "-") {
			<-complock;
			if(comp != nil)
				text = comp.text;
			complock <-= 1;
		} else {
			text = readfile("/lib/matrix/compositions/" + name);
			if(text == nil)
				return "composition not found: " + name;
		}
		alt {
		reloadch <-= text =>
			;
		* =>
			;
		}
		return nil;
	}

	if(data == "unload") {
		alt {
		reloadch <-= "# empty\n" =>
			;
		* =>
			;
		}
		return nil;
	}

	if(len data > 4 && data[0:4] == "pin ") {
		name := data[4:];
		<-complock;
		text := "";
		if(comp != nil)
			text = comp.text;
		complock <-= 1;
		if(text == "")
			return "no composition to pin";
		ensuredir("/lib/matrix/compositions");
		werr := writefile("/lib/matrix/compositions/" + name, text);
		if(werr != nil)
			return werr;
		return nil;
	}

	if(len data > 6 && data[0:6] == "unpin ") {
		name := data[6:];
		if(sys->remove("/lib/matrix/compositions/" + name) < 0)
			return sys->sprint("cannot remove: %r");
		return nil;
	}

	return "usage: load <name>|load -|unload|pin <name>|unpin <name>";
}

# Module info for 9P
ModInfo: adt
{
	name: string;
	mtype: string;
	mount: string;
	status: string;
};

buildmodlist(): list of ref ModInfo
{
	mods: list of ref ModInfo;
	<-complock;
	if(comp != nil) {
		# Display modules
		if(comp.layout != nil)
			mods = leafmodlist(comp.layout, mods);
		# Service modules
		for(sl := comp.services; sl != nil; sl = tl sl) {
			se := hd sl;
			status := "stopped";
			if(se.mod != nil)
				status = "running";
			mods = ref ModInfo(se.name, "service", se.mount, status) :: mods;
		}
	}
	complock <-= 1;
	return mods;
}

leafmodlist(node: ref LayoutNode, acc: list of ref ModInfo): list of ref ModInfo
{
	pick n := node {
	Split =>
		acc = leafmodlist(n.child1, acc);
		acc = leafmodlist(n.child2, acc);
	Leaf =>
		if(n.modname != "") {
			status := "stopped";
			if(n.mod != nil)
				status = "running";
			acc = ref ModInfo(n.modname, "display", n.mount, status) :: acc;
		}
	}
	return acc;
}

findmodbyqid(qtype: int): ref ModInfo
{
	if(qtype < Qmodbase)
		return nil;
	base := Qmodbase + ((qtype - Qmodbase) / MOD_STRIDE) * MOD_STRIDE;
	idx := (base - Qmodbase) / MOD_STRIDE;
	mods := buildmodlist();
	i := 0;
	for(ml := mods; ml != nil; ml = tl ml) {
		if(i == idx)
			return hd ml;
		i++;
	}
	return nil;
}

modqoffset(qtype: int): int
{
	return (qtype - Qmodbase) % MOD_STRIDE;
}

TYPE(path: big): int
{
	return int path & 16rFFFF;
}

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
		return (dir(Qid(p, vers, Sys->QTDIR), ".", big 0, 8r755), nil);
	Qctl =>
		return (dir(Qid(p, vers, Sys->QTFILE), "ctl", big 0, 8r644), nil);
	Qcomposition =>
		return (dir(Qid(p, vers, Sys->QTFILE), "composition", big 0, 8r644), nil);
	Qmoddir =>
		return (dir(Qid(p, vers, Sys->QTDIR), "modules", big 0, 8r755), nil);
	}

	if(qtype >= Qmodbase) {
		off := modqoffset(qtype);
		mi := findmodbyqid(qtype);
		if(mi != nil) {
			case off {
			Qmod_dir =>
				return (dir(Qid(p, vers, Sys->QTDIR), mi.name, big 0, 8r755), nil);
			Qmod_ctl =>
				return (dir(Qid(p, vers, Sys->QTFILE), "ctl", big 0, 8r444), nil);
			Qmod_type =>
				return (dir(Qid(p, vers, Sys->QTFILE), "type", big 0, 8r444), nil);
			Qmod_mount =>
				return (dir(Qid(p, vers, Sys->QTFILE), "mount", big 0, 8r444), nil);
			}
		}
	}

	return (nil, Enotfound);
}

matrixnavigator(navops: chan of ref Navop)
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
				"composition" =>
					n.path = big Qcomposition;
				"modules" =>
					n.path = big Qmoddir;
				* =>
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.reply <-= dirgen(n.path);
			} else if(qtype == Qmoddir) {
				# Walk to a module by name
				mods := buildmodlist();
				idx := 0;
				found := 0;
				for(ml := mods; ml != nil; ml = tl ml) {
					mi := hd ml;
					if(mi.name == n.name) {
						n.path = big(Qmodbase + idx * MOD_STRIDE + Qmod_dir);
						n.reply <-= dirgen(n.path);
						found = 1;
						break;
					}
					idx++;
				}
				if(!found) {
					case n.name {
					".." =>
						n.path = big Qroot;
						n.reply <-= dirgen(n.path);
					* =>
						n.reply <-= (nil, Enotfound);
					}
				}
			} else if(qtype >= Qmodbase && modqoffset(qtype) == Qmod_dir) {
				# Walk within a module directory
				case n.name {
				".." =>
					n.path = big Qmoddir;
				"ctl" =>
					n.path = big(qtype + Qmod_ctl);
				"type" =>
					n.path = big(qtype + Qmod_type);
				"mount" =>
					n.path = big(qtype + Qmod_mount);
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
				# Entry 1: composition
				if(i <= 1 && count > 0) {
					n.reply <-= dirgen(big Qcomposition);
					count--;
					i++;
				}
				# Entry 2: modules
				if(i <= 2 && count > 0) {
					n.reply <-= dirgen(big Qmoddir);
					count--;
					i++;
				}
				n.reply <-= (nil, nil);

			Qmoddir =>
				i := n.offset;
				count := n.count;
				mods := buildmodlist();
				idx := 0;
				for(ml := mods; ml != nil && count > 0; ml = tl ml) {
					if(i <= idx) {
						qid := Qmodbase + idx * MOD_STRIDE + Qmod_dir;
						n.reply <-= dirgen(big qid);
						count--;
					}
					idx++;
				}
				n.reply <-= (nil, nil);

			* =>
				if(qtype >= Qmodbase && modqoffset(qtype) == Qmod_dir) {
					# Module directory: ctl, type, mount
					i := n.offset;
					count := n.count;
					base := qtype;
					if(i == 0 && count > 0) {
						n.reply <-= dirgen(big(base + Qmod_ctl));
						count--;
						i++;
					}
					if(i <= 1 && count > 0) {
						n.reply <-= dirgen(big(base + Qmod_type));
						count--;
						i++;
					}
					if(i <= 2 && count > 0) {
						n.reply <-= dirgen(big(base + Qmod_mount));
						count--;
					}
					n.reply <-= (nil, nil);
				} else {
					n.reply <-= (nil, "not a directory");
				}
			}
		}
	}
}

# ── GUI Mode ────────────────────────────────────────────────

initgui(ctxt: ref Draw->Context)
{
	draw = load Draw Draw->PATH;
	if(draw == nil)
		nomod(Draw->PATH);

	wmclient = load Wmclient Wmclient->PATH;
	if(wmclient == nil)
		nomod(Wmclient->PATH);
	wmclient->init();

	w = wmclient->window(ctxt, "Matrix", Wmclient->Appl);
	display_g = w.display;

	font_g = Font.open(display_g, "/fonts/combined/unicode.sans.14.font");
	if(font_g == nil)
		font_g = Font.open(display_g, "*default*");

	widgetmod = load Widget Widget->PATH;
	if(widgetmod != nil)
		widgetmod->init(display_g, font_g);

	kf = Kbdfilter.new();

	loadcolors();

	w.reshape(Rect((0, 0), (800, 600)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	updatech = chan of int;
	themech = chan[1] of int;

	# Compute initial layout
	if(comp.layout != nil)
		computelayout(comp.layout, w.image.r);

	dirty = 1;
	spawn updatetimer();
	spawn themelistener();
}

loadcolors()
{
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor   = display_g.color(th.bg);
		divcolor  = display_g.color(th.border);
		textcolor = display_g.color(th.text);
		dimcolor  = display_g.color(th.dim);
		redcolor  = display_g.color(th.red);
		greencolor= display_g.color(th.green);
		yellowcolor= display_g.color(th.yellow);
	} else {
		bgcolor   = display_g.color(int 16r1A1A2EFF);
		divcolor  = display_g.color(int 16r333355FF);
		textcolor = display_g.color(int 16rDDDDDDFF);
		dimcolor  = display_g.color(int 16r888888FF);
		redcolor  = display_g.color(int 16rFF4444FF);
		greencolor= display_g.color(int 16r44FF44FF);
		yellowcolor= display_g.color(int 16rFFFF44FF);
	}
}

updatetimer()
{
	for(;;) {
		sys->sleep(UPDATE_MS);
		alt {
		updatech <-= 1 =>
			;
		* =>
			;  # skip if main loop is busy
		}
	}
}

themelistener()
{
	fd := sys->open("/lib/lucifer/theme/event", Sys->OREAD);
	if(fd == nil)
		return;
	buf := array[64] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		alt {
		themech <-= 1 =>
			;
		* =>
			;
		}
	}
}

guiloop()
{
	for(;;) {
		if(dirty) {
			redraw();
			dirty = 0;
		}
		alt {
		ctl := <-w.ctl or
		ctl = <-w.ctxt.ctl =>
			if(ctl == nil)
				;
			else if(ctl[0] == '!') {
				w.wmctl(ctl);
				if(comp.layout != nil)
					computelayout(comp.layout, w.image.r);
				resizedisplaymodules(comp.layout);
				dirty = 1;
			} else
				w.wmctl(ctl);

		k := <-w.ctxt.kbd =>
			handlekey(k);

		ptr := <-w.ctxt.ptr =>
			if(ptr == nil)
				;
			else if(w.pointer(*ptr))
				;
			else
				handleptr(ptr);

		<-updatech =>
			if(updatedisplaymodules(comp.layout))
				dirty = 1;

		newcomp := <-reloadch =>
			reloadcomposition(newcomp);
			dirty = 1;

		<-themech =>
			loadcolors();
			if(widgetmod != nil)
				widgetmod->retheme(display_g);
			if(wmclient != nil)
				wmclient->retheme(w);
			rethemedisplaymodules(comp.layout);
			dirty = 1;
		}
	}
}

# ── Layout computation ──────────────────────────────────────

computelayout(node: ref LayoutNode, r: Rect)
{
	if(node == nil)
		return;
	pick n := node {
	Split =>
		n.r = r;
		total := n.ratio1 + n.ratio2;
		if(total <= 0)
			total = 2;
		case n.orient {
		HSPLIT =>
			splitx := r.min.x + r.dx() * n.ratio1 / total;
			computelayout(n.child1, Rect(r.min, (splitx - 1, r.max.y)));
			computelayout(n.child2, Rect((splitx + 1, r.min.y), r.max));
		VSPLIT =>
			splity := r.min.y + r.dy() * n.ratio1 / total;
			computelayout(n.child1, Rect(r.min, (r.max.x, splity - 1)));
			computelayout(n.child2, Rect((r.min.x, splity + 1), r.max));
		}
	Leaf =>
		n.r = r;
	}
}

# ── Drawing ─────────────────────────────────────────────────

redraw()
{
	if(w == nil || w.image == nil)
		return;

	img := w.image;
	img.draw(img.r, bgcolor, nil, (0, 0));

	if(comp != nil && comp.layout != nil)
		drawlayout(img, comp.layout);

	if(widgetmod != nil)
		widgetmod->contentborder(img);
	img.flush(Draw->Flushnow);
}

drawlayout(dst: ref Image, node: ref LayoutNode)
{
	if(node == nil)
		return;
	pick n := node {
	Split =>
		drawlayout(dst, n.child1);
		drawlayout(dst, n.child2);
		# Draw divider
		c1r := noderect(n.child1);
		case n.orient {
		HSPLIT =>
			splitx := c1r.max.x + 1;
			divr := Rect((splitx - 1, n.r.min.y), (splitx, n.r.max.y));
			dst.draw(divr, divcolor, nil, (0, 0));
		VSPLIT =>
			splity := c1r.max.y + 1;
			divr := Rect((n.r.min.x, splity - 1), (n.r.max.x, splity));
			dst.draw(divr, divcolor, nil, (0, 0));
		}
	Leaf =>
		if(n.mod != nil) {
			n.mod->draw(dst);
		} else if(n.modname != "") {
			# Module not loaded — show placeholder
			label := n.modname + " @ " + n.mount;
			pt := Point(n.r.min.x + 8, n.r.min.y + 8 + font_g.height);
			dst.text(pt, dimcolor, (0, 0), font_g, label);
		}
	}
}

# Access rect of any layout node
noderect(node: ref LayoutNode): Rect
{
	pick n := node {
	Split => return n.r;
	Leaf => return n.r;
	}
	return Rect((0,0),(0,0));
}

# ── Module lifecycle ────────────────────────────────────────

loaddisplaymodules()
{
	if(comp == nil || comp.layout == nil)
		return;
	loadleafmodules(comp.layout);
}

loadleafmodules(node: ref LayoutNode)
{
	if(node == nil)
		return;
	pick n := node {
	Split =>
		loadleafmodules(n.child1);
		loadleafmodules(n.child2);
	Leaf =>
		if(n.modname == "" || n.mod != nil)
			return;
		path := "/dis/matrix/" + n.modname + ".dis";
		mod := load MatrixDisplay path;
		if(mod == nil) {
			sys->fprint(stderr, "matrix: cannot load display module %s: %r\n", path);
			return;
		}
		err := mod->init(display_g, font_g, n.mount);
		if(err != nil) {
			sys->fprint(stderr, "matrix: init %s: %s\n", n.modname, err);
			return;
		}
		mod->resize(n.r);
		n.mod = mod;
	}
}

loadservicemodules()
{
	if(comp == nil)
		return;
	for(sl := comp.services; sl != nil; sl = tl sl) {
		se := hd sl;
		if(se.mod != nil)
			continue;
		path := "/dis/matrix/" + se.name + ".dis";
		mod := load MatrixService path;
		if(mod == nil) {
			sys->fprint(stderr, "matrix: cannot load service module %s: %r\n", path);
			continue;
		}
		se.outdir = "/tmp/matrix/" + se.name;
		ensuredir(se.outdir);
		err := mod->init(se.mount, se.outdir);
		if(err != nil) {
			sys->fprint(stderr, "matrix: init %s: %s\n", se.name, err);
			continue;
		}
		se.mod = mod;
		spawn runservice(se);
	}
}

runservice(se: ref ServiceEntry)
{
	se.pid = sys->pctl(0, nil);
	se.mod->run();
	se.pid = 0;
}

# Update all display modules, return 1 if any changed
updatedisplaymodules(node: ref LayoutNode): int
{
	if(node == nil)
		return 0;
	pick n := node {
	Split =>
		c1 := updatedisplaymodules(n.child1);
		c2 := updatedisplaymodules(n.child2);
		return c1 | c2;
	Leaf =>
		if(n.mod != nil)
			return n.mod->update();
	}
	return 0;
}

resizedisplaymodules(node: ref LayoutNode)
{
	if(node == nil)
		return;
	pick n := node {
	Split =>
		resizedisplaymodules(n.child1);
		resizedisplaymodules(n.child2);
	Leaf =>
		if(n.mod != nil)
			n.mod->resize(n.r);
	}
}

rethemedisplaymodules(node: ref LayoutNode)
{
	if(node == nil)
		return;
	pick n := node {
	Split =>
		rethemedisplaymodules(n.child1);
		rethemedisplaymodules(n.child2);
	Leaf =>
		if(n.mod != nil)
			n.mod->retheme(display_g);
	}
}

shutdowndisplaymodules(node: ref LayoutNode)
{
	if(node == nil)
		return;
	pick n := node {
	Split =>
		shutdowndisplaymodules(n.child1);
		shutdowndisplaymodules(n.child2);
	Leaf =>
		if(n.mod != nil) {
			n.mod->shutdown();
			n.mod = nil;
		}
	}
}

shutdownservicemodules()
{
	if(comp == nil)
		return;
	for(sl := comp.services; sl != nil; sl = tl sl) {
		se := hd sl;
		if(se.mod != nil)
			se.mod->shutdown();
		se.mod = nil;
	}
}

# ── Event routing ───────────────────────────────────────────

handleptr(p: ref Pointer)
{
	if(comp == nil || comp.layout == nil)
		return;
	routeptr(comp.layout, p);
	dirty = 1;
}

routeptr(node: ref LayoutNode, p: ref Pointer): int
{
	if(node == nil)
		return 0;
	pick n := node {
	Split =>
		if(routeptr(n.child1, p))
			return 1;
		return routeptr(n.child2, p);
	Leaf =>
		if(n.mod != nil && n.r.contains(p.xy)) {
			focusmod = n.mod;
			return n.mod->pointer(p);
		}
	}
	return 0;
}

handlekey(k: int)
{
	if(kf != nil)
		k = kf.filter(k);
	if(k < 0)
		return;
	if(focusmod != nil)
		focusmod->key(k);
}

# ── Composition reload ──────────────────────────────────────

reloadcomposition(text: string)
{
	(newcomp, err) := parsecomposition(text);
	if(err != nil) {
		sys->fprint(stderr, "matrix: reload parse error: %s\n", err);
		return;
	}

	# Shutdown old modules
	<-complock;
	if(comp != nil) {
		shutdowndisplaymodules(comp.layout);
		shutdownservicemodules();
	}
	comp = newcomp;
	complock <-= 1;

	# Reload
	if(guimode && comp.layout != nil) {
		computelayout(comp.layout, w.image.r);
		loaddisplaymodules();
	}
	loadservicemodules();
	vers++;
}

# ── Headless mode ───────────────────────────────────────────

headlessloop()
{
	for(;;) {
		alt {
		newcomp := <-reloadch =>
			reloadcomposition(newcomp);
		}
	}
}
