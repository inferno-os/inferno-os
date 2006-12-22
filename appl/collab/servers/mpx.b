implement Service;

#
# 1 to many and many to 1 multiplexor
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Navigator: import styxservers;
	nametree: Nametree;
	Tree: import nametree;

include "service.m";

include "messages.m";
	messages: Messages;
	Msg, Msglist, Readreq, User: import messages;

Qdir, Qroot, Qusers, Qleaf: con iota;

srv: ref Styxserver;
clientidgen := 0;

Einactive: con "not currently active";

toleaf: ref Msglist;
toroot: ref Msglist;
userlist: list of ref User;

user := "inferno";

dir(name: string, perm: int, path: int): Sys->Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = user;
	d.gid = user;
	d.qid.path = big path;
	if(perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else
		d.qid.qtype = Sys->QTFILE;
	d.mode = perm;
	return d;
}

init(nil: list of string): (string, string, ref Sys->FD)
{
	sys = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	if(styx == nil)
		return (sys->sprint("can't load %s: %r", Styx->PATH), nil, nil);
	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		return (sys->sprint("can't load %s: %r", Styxservers->PATH), nil, nil);
	nametree = load Nametree Nametree->PATH;
	if(nametree == nil)
		return (sys->sprint("can't load %s: %r", Nametree->PATH), nil, nil);
	styx->init();
	styxservers->init(styx);
styxservers->traceset(1);
	nametree->init();
	messages = load Messages Messages->PATH;
	if(messages == nil)
		return (sys->sprint("can't load %s: %r", Messages->PATH), nil, nil);

	(tree, treeop) := nametree->start();
	tree.create(big Qdir, dir(".", Sys->DMDIR|8r555, Qdir));
	tree.create(big Qdir, dir("leaf", 8r666, Qleaf));
	tree.create(big Qdir, dir("root", 8r666, Qroot));
	tree.create(big Qdir, dir("users", 8r444, Qusers));
	
	p := array [2] of ref Sys->FD;
	if (sys->pipe(p) < 0){
		tree.quit();
		return (sys->sprint("can't create pipe: %r"), nil, nil);
	}

	toleaf = Msglist.new();
	toroot = Msglist.new();

	tc: chan of ref Tmsg;
	(tc, srv) = Styxserver.new(p[1], Navigator.new(treeop), big Qdir);
	spawn mpx(tc, tree);

	return (nil, "/", p[0]);
}

mpx(tc: chan of ref Tmsg, tree: ref Tree)
{
	root: ref User;
	while((tmsg := <-tc) != nil){
		pick tm := tmsg {
		Readerror =>
			break;
		Open =>
			c := srv.getfid(tm.fid);
			if(c == nil || c.isopen){
				srv.reply(ref Rmsg.Error(tm.tag, Styxservers->Ebadfid));
				continue;
			}
			case int c.path {
			Qroot =>
				if(root != nil){
					srv.reply(ref Rmsg.Error(tm.tag, sys->sprint("interaction already directed by %s", root.name)));
					continue;
				}
				c = srv.open(tm);
				if (c == nil)
					continue;
				root = ref User(0, tm.fid, c.uname, nil);
				root.initqueue(toroot);
			Qleaf =>
				if(root == nil){
					srv.reply(ref Rmsg.Error(tm.tag, Einactive));
					continue;
				}
				c = srv.open(tm);
				if (c == nil)
					continue;
				userarrives(tm.fid, c.uname);
				# mpxdir[1].qid.vers++;	# TO DO
			* =>
				srv.open(tm);
			}
		Read =>
			c := srv.getfid(tm.fid);
			if (c == nil || !c.isopen) {
				srv.reply(ref Rmsg.Error(tm.tag, Styxservers->Ebadfid));
				continue;
			}
			case int c.path {
			Qdir =>
				srv.read(tm);
			Qroot =>
				tm.offset = big 0;
				m := qread(toroot, root, tm, 1);
				if(m != nil)
					srv.reply(ref Rmsg.Read(tm.tag, m.data));
			Qleaf =>
				u := fid2user(tm.fid);
				if (u == nil) {
					srv.reply(ref Rmsg.Error(tm.tag, "internal error -- lost user"));
					continue;
				}
				tm.offset = big 0;
				m := qread(toleaf, u, tm, 0);
				if(m == nil){
					if(root == nil)
						srv.reply(ref Rmsg.Read(tm.tag, nil));
					else
						qread(toleaf, u, tm, 1);	# put us on the wait queue
				}else
					srv.reply(ref Rmsg.Read(tm.tag, m.data));
			Qusers =>
				srv.reply(styxservers->readstr(tm, usernames()));
			* =>
				srv.reply(ref Rmsg.Error(tm.tag, "phase error -- bad path"));
			}
		Write =>
			c := srv.getfid(tm.fid);
			if (c == nil || !c.isopen) {
				srv.reply(ref Rmsg.Error(tm.tag, Styxservers->Ebadfid));
				continue;
			}
			case int c.path {
			Qroot =>
				qwrite(toleaf, msg(root, 'M', tm.data));
				srv.reply(ref Rmsg.Write(tm.tag, len tm.data));
			Qleaf =>
				u := fid2user(tm.fid);
				if(u == nil) {
					srv.reply(ref Rmsg.Error(tm.tag, "internal error -- lost user"));
					continue;
				}
				if(root == nil){
					srv.reply(ref Rmsg.Error(tm.tag, Einactive));
					continue;
				}
				qwrite(toroot, msg(u, 'm', tm.data));
				srv.reply(ref Rmsg.Write(tm.tag, len tm.data));
			* =>
				srv.reply(ref Rmsg.Error(tm.tag, Styxservers->Eperm));
			}
		Flush =>
			cancelpending(tm.tag);
			srv.reply(ref Rmsg.Flush(tm.tag));
		Clunk =>
			c := srv.getfid(tm.fid);
			if(c.isopen){
				case int c.path {
				Qroot =>
					# shut down?
					qwrite(toleaf, msg(root, 'L', nil));
					root = nil;
				Qleaf =>
					userleaves(tm.fid);
					# mpxdir[1].qid.vers++;	# TO DO
				}
			}
		* =>
			srv.default(tmsg);
		}
	}
	tree.quit();
	sys->print("mpx exit\n");
}

mpxseqgen := 0;

time(): int
{
	return ++mpxseqgen;	# server time; assumes 2^31-1 is large enough
}

userarrives(fid: int, name: string)
{
	u := User.new(fid, name);
	qwrite(toroot, msg(u, 'a', nil));
	u.initqueue(toleaf);	# sees leaf messages from now on
	userlist = u :: userlist;
}

fid2user(fid: int): ref User
{
	for(ul := userlist; ul != nil; ul = tl ul)
		if((u := hd ul).fid == fid)
			return u;
	return nil;
}

userleaves(fid: int)
{
	ul := userlist;
	userlist = nil;
	u: ref User;
	for(; ul != nil; ul = tl ul)
		if((hd ul).fid != fid)
			userlist = hd ul :: userlist;
		else
			u = hd ul;
	if(u != nil)
		qwrite(toroot, msg(u, 'l', nil));
}

usernames(): string
{
	s := "";
	for(ul := userlist; ul != nil; ul = tl ul){
		u := hd ul;
		s += string u.id+" "+u.name+"\n";
	}
	return s;
}

qwrite(msgs: ref Msglist, m: ref Msg)
{
	pending := msgs.write(m);
	for(; pending != nil; pending = tl pending){
		(u, req) := hd pending;
		m = u.read();	# must succeed, or the code is wrong
		data := m.data;
		if(req.count < len data)
			data = data[0:req.count];
		srv.reply(ref Rmsg.Read(req.tag, data));
	}
}

qread(msgs: ref Msglist, u: ref User, tm: ref Tmsg.Read, wait: int): ref Msg
{
	m := u.read();
	if(m != nil){
		if(tm.count < len m.data)
			m.data = m.data[0:tm.count];
	}else if(wait)
		msgs.wait(u, ref Readreq(tm.tag, tm.fid, tm.count, tm.offset));
	return m;
}

cancelpending(tag: int)
{
	toroot.flushtag(tag);
	toleaf.flushtag(tag);
}

msg(u: ref User, op: int, data: array of byte): ref Msg
{
	a := sys->aprint("%ud %d %c %s ", time(), u.id, op, u.name);
	m := ref Msg(u, array[len a + len data] of byte, nil);
	m.data[0:] = a;
	m.data[len a:] = data;
	return m;
}
