implement Chatsrv;

#
# simple text-based chat service
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import Styx;

include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Navigator: import styxservers;
	nametree: Nametree;
	Tree: import nametree;

Chatsrv : module {
	init : fn (ctxt : ref Draw->Context, args : list of string);
};

Qdir, Qusers, Qmsgs: con iota;

tc: chan of ref Tmsg;
srv: ref Styxserver;

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

badmod(path: string)
{
	sys->fprint(sys->fildes(1), "chatsrv: cannot load %s: %r\n", path);
	exit;
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	if(styx == nil)
		badmod(Styx->PATH);
	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		badmod(Styxservers->PATH);
	nametree = load Nametree Nametree->PATH;
	if(nametree == nil)
		badmod(Nametree->PATH);
	styx->init();
	styxservers->init(styx);
	nametree->init();

	(tree, treeop) := nametree->start();
	tree.create(big Qdir, dir(".", Sys->DMDIR|8r555, Qdir));
	tree.create(big Qdir, dir("users", 8r444, Qusers));
	tree.create(big Qdir, dir("msgs", 8r666, Qmsgs));
	
	nextmsg = ref Msg (0, nil, nil, nil);
	keptmsg = nextmsg;

	(tc, srv) = Styxserver.new(sys->fildes(0), Navigator.new(treeop), big Qdir);
	chatsrv(tree);
}

chatsrv(tree: ref Tree)
{
	while((tmsg := <-tc) != nil){
		pick tm := tmsg {
		Readerror =>
			break;
		Flush =>
			cancelpending(tm.tag);
			srv.reply(ref Rmsg.Flush(tm.tag));
		Open =>
			c := srv.open(tm);
			if (c == nil)
				break;
			if (int c.path == Qmsgs){
				newmsgclient(tm.fid, c.uname);
				#root[0].qid.vers++;		# TO DO
			}
		Read =>
			c := srv.getfid(tm.fid);
			if (c == nil || !c.isopen) {
				srv.reply(ref Rmsg.Error(tm.tag, Styxservers->Ebadfid));
				break;
			}
			case int c.path {
			Qdir =>
				srv.read(tm);
			Qmsgs =>
				mc := getmsgclient(tm.fid);
				if (mc == nil) {
					srv.reply(ref Rmsg.Error(tm.tag, "internal error -- lost client"));
					continue;
				}
				tm.offset = big 0;
				msg := getnextmsg(mc);
				if (msg == nil) {
					if(mc.pending != nil)
						srv.reply(ref Rmsg.Error(tm.tag, "read already pending"));
					else
						mc.pending = tm;
					continue;
				}
				srv.reply(styxservers->readstr(tm, msg));
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
			if (int c.path != Qmsgs) {
				srv.reply(ref Rmsg.Error(tm.tag, Styxservers->Eperm));
				continue;
			}
			writemsgclients(tm.fid, c.uname, string tm.data);
			srv.reply(ref Rmsg.Write(tm.tag, len tm.data));
		Clunk =>
			c := srv.clunk(tm);
			if (c != nil && int c.path == Qmsgs){
				closemsgclient(tm.fid);
				# root[0].qid.vers++;		# TO DO
			}
		* =>
			srv.default(tmsg);
		}
	}
	tree.quit();
	sys->print("chatsrv exit\n");
}

Msg: adt {
	fromfid: int;
	from: string;
	msg: string;
	next: cyclic ref Msg;
};

Msgclient: adt {
	fid: int;
	name: string;
	nextmsg: ref Msg;
	pending: ref Tmsg.Read;
	next: cyclic ref Msgclient;
};

NKEPT: con 6;
keptcount := 0;
nextmsg: ref Msg;
keptmsg: ref Msg;
msgclients: ref Msgclient;

usernames(): string
{
	s := "";
	for (c := msgclients; c != nil; c = c.next)
		s += c.name+"\n";
	return s;
}

newmsgclient(fid: int, name: string)
{
	writemsgclients(fid, nil, "+++ " + name + " has arrived");
	msgclients = ref Msgclient(fid, name, keptmsg, nil, msgclients);
}

getmsgclient(fid: int): ref Msgclient
{
	for (c := msgclients; c != nil; c = c.next)
		if (c.fid == fid)
			return c;
	return nil;
}

cancelpending(tag: int)
{
	for (c := msgclients; c != nil; c = c.next)
		if((tm := c.pending) != nil && tm.tag == tag){
			c.pending = nil;
			break;
		}
}

closemsgclient(fid: int)
{
	prev: ref Msgclient;
	s := "";
	for (c := msgclients; c != nil; c = c.next) {
		if (c.fid == fid) {
			if (prev == nil)
				msgclients = c.next;
			else 
				prev.next = c.next;
			s = "--- " + c.name + " has left";
			break;
		}
		prev = c;
	}
	if (s != nil)
		writemsgclients(fid, nil, s);
}

writemsgclients(fromfid: int, from: string, msg: string)
{
	nm := ref Msg(0, nil, nil, nil);
	nextmsg.fromfid = fromfid;
	nextmsg.from = from;
	nextmsg.msg = msg;
	nextmsg.next = nm;

	for (c := msgclients; c != nil; c = c.next) {
		if (c.pending != nil) {
			s := msgtext(nextmsg);
			srv.reply(styxservers->readstr(c.pending, s));
			c.pending = nil;
			c.nextmsg = nm;
		}
	}
	nextmsg = nm;
	if (keptcount < NKEPT)
		keptcount++;
	else
		keptmsg = keptmsg.next;
}

getnextmsg(mc: ref Msgclient): string
{
# uncomment next two lines to eliminate queued messages to self
#	while(mc.nextmsg.next != nil && mc.nextmsg.fromfid == mc.fid)
#		mc.nextmsg = mc.nextmsg.next;
	if ((m := mc.nextmsg).next != nil){
		mc.nextmsg = m.next;
		return msgtext(m);
	}
	return nil;
}

msgtext(m: ref Msg): string
{
	prefix := "";
	if (m.from != nil)
		prefix = m.from + ": ";
	return prefix + m.msg;
}
