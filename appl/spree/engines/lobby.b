implement Engine;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sets.m";
	sets: Sets;
	Set, set, A, B, All, None: import sets;
include "../spree.m";
	spree: Spree;
	archives: Archives;
	Archive: import Archives;
	Attributes, Range, Object, Clique, Member, rand: import spree;
include "readdir.m";
	readdir: Readdir;

# what the lobby provides:
#	a list of cliques it's started
#		name of clique
#		current members
#	list of members inside the lobby.
#		name
#		invites
#			how does a gather engine know who's been invited?
#			as the lobby's the only place with the knowledge of who's around to invite.
#			could allow lobby to communicate with the cliques it's started...
#			but clique also needs to communicate with the lobby
#			(e.g. to say clique has started, no more invites necessary or allowed)
#
#	list of available engines
#		title
#		clienttype(s?)
#
#	understands commands:
#		chat message
#		invite
#		new 	name params
#
#	question: how do we know about archives?
#	answer: maybe we don't... could have another module
#		that does, or maybe an option to gather ("gather unarchive"?)
#
#	the one that's started the clique is always invited.
#	start clique.
#		clique says to parent "invite x, y and z" (perhaps they were in the archive)
#		how should we deal with recursive invocation?
#		could queue up requests to other clique engines,
#			and deliver them after the current request has been processed.
#			no return available (one way channel) but maybe that's good,
#			as if sometime in the future engines do run in parallel, we will
#			need to avoid deadlock.
#		Clique.notify(clique: self ref Clique, cliqueid: int, note: string);
#			when a request has been completed, we run notify requests
#			for all the cliques that have been notified, and repeat
#			until no more. (could keep a count to check for infinite loop).
#			don't allow communication between unrelated cliques.

clique: ref Clique;

members: ref Object;
sessions: ref Object;
available: ref Object;
archiveobj: ref Object;

ARCHIVEDIR: con "./archive";

init(srvmod: Spree, g: ref Clique, nil: list of string): string
{
	sys = load Sys Sys->PATH;
	clique = g;
	spree = srvmod;
	sets = load Sets Sets->PATH;
	if (sets == nil) {
		sys->print("lobby: cannot load %s: %r\n", Sets->PATH);
		return "bad module";
	}
	readdir = load Readdir Readdir->PATH;
	if (readdir == nil) {
		sys->print("lobby: cannot load %s: %r\n", Readdir->PATH);
		return "bad module";
	}
	archives = load Archives Archives->PATH;
	if (archives == nil) {
		sys->print("lobby: cannot load %s: %r\n", Archives->PATH);
		return "bad module";
	}
	archives->init(srvmod);
	members = clique.newobject(nil, All, "members");
	sessions = clique.newobject(nil, All, "sessions");
	available = clique.newobject(nil, All, "available");
	o := clique.newobject(available, All, "sessiontype");
	o.setattr("name", "freecell", All);
	o.setattr("title", "Freecell", All);
	o.setattr("clienttype", "cards", All);
	o.setattr("start", "gather 1 freecell", All);

	o = clique.newobject(available, All, "sessiontype");
	o.setattr("title", "Lobby", All);
	o.setattr("name", "lobby", All);
	o.setattr("clienttype", "lobby", All);
	o.setattr("start", "lobby", All);

	o = clique.newobject(available, All, "sessiontype");
	o.setattr("title", "Spit", All);
	o.setattr("name", "spit", All);
	o.setattr("clienttype", "cards", All);
	o.setattr("start", "gather 2 spit", All);

	o = clique.newobject(available, All, "sessiontype");
	o.setattr("title", "Canfield", All);
	o.setattr("name", "canfield", All);
	o.setattr("clienttype", "cards", All);
	o.setattr("start", "gather 1 canfield", All);

	o = clique.newobject(available, All, "sessiontype");
	o.setattr("title", "Afghan", All);
	o.setattr("name", "afghan", All);
	o.setattr("clienttype", "cards", All);
	o.setattr("start", "gather 1 afghan", All);

	o = clique.newobject(available, All, "sessiontype");
	o.setattr("title", "Spider", All);
	o.setattr("name", "spider", All);
	o.setattr("clienttype", "cards", All);
	o.setattr("start", "gather 1 spider", All);

	o = clique.newobject(available, All, "sessiontype");
	o.setattr("title", "Racing Demon", All);
	o.setattr("name", "racingdemon", All);
	o.setattr("clienttype", "cards", All);
	o.setattr("start", "gather 3 racingdemon", All);

	o = clique.newobject(available, All, "sessiontype");
	o.setattr("title", "Othello", All);
	o.setattr("name", "othello", All);
	o.setattr("clienttype", "othello", All);
	o.setattr("start", "gather 2 othello", All);

	o = clique.newobject(available, All, "sessiontype");
	o.setattr("title", "Whist", All);
	o.setattr("name", "whist", All);
	o.setattr("clienttype", "whist", All);
	o.setattr("start", "gather 4 whist", All);

	getarchives();

	clique.start();

	return nil;
}

join(p: ref Member, cmd: string, nil: int): string
{
	sys->print("%s joins '%s'\n", p.name, cmd);
	clique.notify(clique.parentid, "join " + p.name);
	s := None.add(p.id);
	clique.action("clienttype lobby", nil, nil, s);
	clique.breakmsg(s);
	clique.action("name " + p.name, nil, nil, s);
	o := clique.newobject(members, All, "member");
	o.setattr("name", p.name, All);
	return nil;
}

leave(p: ref Member): int
{
	clique.notify(clique.parentid, "leave " + p.name);
	deletename(members, p.name, "member");
	sys->print("%s leaves\n", p.name);
	return 1;
}

readfile(nil: int, nil: big, nil: int): array of byte
{
	return nil;
}

command(p: ref Member, cmd: string): string
{
	sys->print("%s: '%s'\n", p.name, cmd);
	(n, toks) := sys->tokenize(cmd, " \n");
	if (n == 0)
		return "bad command";
	case hd toks {
	"kick" =>
		getarchives();
		return nil;
	"chat" =>
		clique.action("chat " + p.name + " " + concat(tl toks), nil, nil, All);
		return nil;
	"start" =>
		# start engine [params]
		if (n >= 2) {
			(gid, fname, err) := clique.new(
				ref Archive(tl toks, nil, nil, nil),
				p.name);
			if (gid == -1)
				return err;
			s := addname(sessions, string gid, "session");
			s.setattr("title", concat(tl toks), All);
			s.setattr("filename", fname, All);
			s.setattr("cliqueid", string gid, None);
			s.setattr("owner", p.name, All);
			return nil;
		}
		return "bad start params";
	"invite" or
	"uninvite"=>
		# invite sessionid name
		if (n == 3) {
			(what, sessionid, name) := (hd toks, int hd tl toks, hd tl tl toks);
			if ((s := p.obj(sessionid)) == nil)
				return "bad object id";
			if (s.objtype != "session")
				return "bad session type " + s.objtype;
			if (s.getattr("owner") != p.name)
				return "permission denied";
			clique.notify(int s.getattr("cliqueid"), what + " " + name);
			if (hd toks == "invite")
				addname(s, name, "invite");
			else
				deletename(s, name, "invite");
			return nil;
		}
		return "bad invite params";
	"unarchive" =>
		# unarchive object
		if (n == 2) {
			o := p.obj(int hd tl toks);
			if (o == nil || o.objtype != "archive")
				return "bad archive object";
			# archive object contains:
			# name		name of clique
			# members		members of the clique
			# file			filename of archive

			aname := o.getattr("file");
			(archive, err) := archives->read(aname);
			if (archive == nil)
				return sys->sprint("cannot load archive: %s", err);
			for (i := 0; i < len archive.members; i++)
				if (p.name == archive.members[i])
					break;
			if (i == len archive.members)
				return "you did not participate in that session";
			(gid, fname, err2) := clique.new(archive, p.name);
			if (gid == -1)
				return err2;
			s := addname(sessions, string gid, "session");
			s.setattr("title", concat(archive.argv), All);
			s.setattr("filename", fname, All);
			s.setattr("cliqueid", string gid, None);
			s.setattr("owner", p.name, All);

			o.delete();
			(ok, d) := sys->stat(aname);
			if (ok != -1) {
				d.name += ".old";
				sys->wstat(aname, d);
			}
			# XXX delete old archive file?
			return nil;
		}
		return "bad unarchive params";
	* =>
		return "bad command";
	}
}

notify(srcid: int, note: string)
{
	sys->print("lobby: note from %d: %s\n", srcid, note);
	s := findname(sessions, string srcid);
	if (s == nil) {
		sys->print("cannot find srcid %d\n", srcid);
		return;
	}
	if (note == nil) {
		s.delete();
		return;
	}
	if (srcid == clique.parentid)
		return;
	(n, toks) := sys->tokenize(note, " ");
	case hd toks {
	"join" =>
		p := addname(s, hd tl toks, "member");
	"leave" =>
		deletename(s, hd tl toks, "member");
	"invite" =>
		addname(s, hd tl toks, "invite");
	"uninvite" =>
		deletename(s, hd tl toks, "invite");
	"title" =>
		s.setattr("title", concat(tl toks), All);
	"archived" =>
		# archived filename
		arch := clique.newobject(archiveobj, All, "archive");
		arch.setattr("name", s.getattr("title"), All);
		pnames := "";
		for (i := 0; i < len s.children; i++)
			if (s.children[i].objtype == "member")
				pnames += " " + s.children[i].getattr("name");
		if (pnames != nil)
			pnames = pnames[1:];
		arch.setattr("members", pnames, All);
		arch.setattr("file", hd tl toks, None);
	* =>
		sys->print("unknown note from %d: %s\n", srcid, note);
	}
}

addname(o: ref Object, name: string, otype: string): ref Object
{
	x := clique.newobject(o, All, otype);
	x.setattr("name", name, All);
	return x;
}

findname(o: ref Object, name: string): ref Object
{
	c := o.children;
	for (i := 0; i < len c; i++)
		if (c[i].getattr("name") == name)
			return c[i];
	return nil;
}

deletename(o: ref Object, name: string, objtype: string)
{
	c := o.children;
	for (i := 0; i < len c; i++)
		if (c[i].objtype == objtype && c[i].getattr("name") == name) {
			o.deletechildren((i, i+1));
			break;
		}
}

getarchives()
{
	if (archiveobj == nil)
		archiveobj = clique.newobject(nil, All, "archives");
	else
		archiveobj.deletechildren((0, len archiveobj.children));
	for (names := spree->archivenames(); names != nil; names = tl names) {
		fname := hd names;
		(a, err) := archives->readheader(fname);
		if (a == nil) {
			sys->print("lobby: cannot read archive header on %s: %s\n", fname, err);
			continue;
		}
		title := "";
		for (inf := a.info; inf != nil; inf = tl inf) {
			if ((hd inf).t0 == "title") {
				title = (hd inf).t1;
				break;
			}
		}
		if (title == nil)
			title = concat(a.argv);
		arch := clique.newobject(archiveobj, All, "archive");
		arch.setattr("name", title, All);
		arch.setattr("members", concatarray(a.members), All);
		arch.setattr("file", fname, None);
		j := 0;
		for (info := a.info; info != nil; info = tl info)
			arch.setattr("info" + string j++, (hd info).t0 + " " + (hd info).t1, All);
	}
}

concat(l: list of string): string
{
	if (l == nil)
		return nil;
	s := hd l;
	for (l = tl l; l != nil; l = tl l)
		s += " " + hd l;
	return s;
}

concatarray(a: array of string): string
{
	if (len a == 0)
		return nil;
	s := a[0];
	for (i := 1; i < len a; i++)
		s += " " + a[i];
	return s;
}
