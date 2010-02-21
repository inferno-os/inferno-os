implement Keyfs;

#
# Copyright © 2002,2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;
	AESbsize, AESstate: import kr;

include "rand.m";
	rand: Rand;

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Fid, Styxserver, Navigator, Navop: import styxservers;
	Enotfound, Eperm, Ebadarg, Edot: import styxservers;

include "arg.m";

Keyfs: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

User: adt
{
	x:	int;		# table index
	name:	string;
	secret:	array of byte;	# eg, password hashed by SHA1
	expire:	int;	# expiration time (epoch seconds)
	status:	int;
	failed:	int;	# count of failed attempts
	path:		big;
};

Qroot, Quser, Qsecret, Qlog, Qstatus, Qexpire: con iota;
files := array[] of {
	(Qsecret, "secret"),
	(Qlog, "log"),
	(Qstatus, "status"),
	(Qexpire, "expire")
};

Maxsecret: con 255;
Maxname: con 255;
Maxfail: con 50;
users: array of ref User;
Sok, Sdisabled: con iota;
status := array[] of {Sok => "ok", Sdisabled => "disabled" };
Never: con 0;	# expiry time

Eremoved: con "user has been removed";

pathgen := 0;
keyversion := 0;
user: string;
now: int;

usage()
{
	sys->fprint(sys->fildes(2), "Usage: keyfs [-D] [-m mountpoint] [keyfile]\n");
	raise "fail:usage";
}

nomod(s: string)
{
	sys->fprint(sys->fildes(2), "keyfs: can't load %s: %r\n", s);
	raise "fail:load";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);
	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		nomod(Keyring->PATH);
	styx = load Styx Styx->PATH;
	if(styx == nil)
		nomod(Styx->PATH);
	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		nomod(Styxservers->PATH);
	rand = load Rand Rand->PATH;
	if(rand == nil)
		nomod(Rand->PATH);

	styx->init();
	styxservers->init(styx);
	rand->init(sys->millisec());

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);
	arg->setusage("keyfs [-m mntpt] [-D] [-n nvramfile] [keyfile]");
	mountpt := "/mnt/keys";
	keyfile := "/keydb/keys";
	nvram: string;
	while((o := arg->opt()) != 0)
		case o {
		'm' =>
			mountpt = arg->earg();
		'D' =>
			styxservers->traceset(1);
		'n' =>
			nvram = arg->earg();
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;

	if(args != nil)
		keyfile = hd args;

	pwd, err: string;
	if(nvram != nil){
		pwd = rf(nvram);
		if(pwd == nil)
			error(sys->sprint("can't read %s: %r", nvram));
	}
	if(pwd == nil){
		(pwd, err) = readconsline("Key: ", 1);
		if(pwd == nil || err == "exit")
			exit;
		if(err != nil)
			error(sys->sprint("couldn't get key: %s", err));
		(rc, d) := sys->stat(keyfile);
		if(rc == -1 || d.length == big 0){
			pwd0 := pwd;
			(pwd, err) = readconsline("Confirm key: ", 1);
			if(pwd == nil || err == "exit")
				exit;
			if(pwd != pwd0)
				error("key mismatch");
			for(i := 0; i < len pwd0; i++)
				pwd0[i] = ' ';	# clear it out
		}
	}

	thekey = hashkey(pwd);
	for(i:=0; i<len pwd; i++)
		pwd[i] = ' ';	# clear it out

	sys->pctl(Sys->NEWPGRP|Sys->FORKFD, nil);	# immediately avoid sharing keyfd

	readkeys(keyfile);

	user = rf("/dev/user");
	if(user == nil)
		user = "keyfs";

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0)
		error(sys->sprint("can't create pipe: %r"));

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	fds[0] = nil;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops, keyfile);
	<-pidc;

	if(sys->mount(fds[1], nil, mountpt, Sys->MREPL|Sys->MCREATE, nil) < 0)
		error(sys->sprint("mount on %s failed: %r", mountpt));
}

rf(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[256] of byte;
	n := sys->read(fd, b, len b);
	if(n < 0)
		return nil;
	return string b[0:n];
}

quit(err: string)
{
	fd := sys->open("/prog/"+string sys->pctl(0, nil)+"/ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
	if(err != nil)
		raise "fail:"+err;
	exit;
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "keyfs: %s\n", s);
	quit("error");
}

thekey: array of byte;

hashkey(s: string): array of byte
{
	key := array of byte s;
	skey := array[Keyring->SHA1dlen] of byte;
	sha := kr->sha1(array of byte "aescbc file", 11, nil, nil);
	kr->sha1(key, len key, skey, sha);
	for(i:=0; i<len key; i++)
		key[i] = byte 0;	# clear it out
#{sys->print("HEX="); for(i:=0;i<len skey&&i<AESbsize; i++)sys->print("%.2ux", int skey[i]);sys->print("\n");}
	return skey[0:AESbsize];
}

readconsline(prompt: string, raw: int): (string, string)
{
	fd := sys->open("/dev/cons", Sys->ORDWR);
	if(fd == nil)
		return (nil, sys->sprint("can't open cons: %r"));
	sys->fprint(fd, "%s", prompt);
	fdctl: ref Sys->FD;
	if(raw){
		fdctl = sys->open("/dev/consctl", sys->OWRITE);
		if(fdctl == nil || sys->fprint(fdctl, "rawon") < 0)
			return (nil, sys->sprint("can't open consctl: %r"));
	}
	line := array[256] of byte;
	o := 0;
	err: string;
	buf := array[1] of byte;
  Read:
	while((r := sys->read(fd, buf, len buf)) > 0){
		c := int buf[0];
		case c {
		16r7F =>
			err = "interrupt";
			break Read;
		'\b' =>
			if(o > 0)
				o--;
		'\n' or '\r' or 16r4 =>
			break Read;
		* =>
			if(o > len line){
				err = "line too long";
				break Read;
			}
			line[o++] = byte c;
		}
	}
	sys->fprint(fd, "\n");
	if(r < 0)
		err = sys->sprint("can't read cons: %r");
	if(raw)
		sys->fprint(fdctl, "rawoff");
	if(err != nil)
		return (nil, err);
	return (string line[0:o], err);
}

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int, navops: chan of ref Navop, keyfile: string)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWFD, 1::2::srv.fd.fd::nil);
	while((gm := <-tchan) != nil){
		now = time();
		pick m := gm {
		Readerror =>
			error(sys->sprint("mount read error: %s", m.error));
		Create =>
			(c, mode, nil, err) := srv.cancreate(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			case TYPE(c.path) {	# parent
			Qroot =>
				if((m.perm & Sys->DMDIR) == 0){
					srv.reply(ref Rmsg.Error(m.tag, Eperm));
					break;
				}
				u := findusername(m.name);
				if(u != nil){
					srv.reply(ref Rmsg.Error(m.tag, "user already exists"));
					continue;
				}
				if(len m.name > Maxname){
					srv.reply(ref Rmsg.Error(m.tag, "user name too long"));
					continue;
				}
				u = newuser(m.name, nil);
				qid := Qid((u.path | big Quser), 0, Sys->QTDIR);
				c.open(mode, qid);
				writekeys(keyfile);
				srv.reply(ref Rmsg.Create(m.tag, qid, srv.iounit()));
			* =>
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
				break;
			}
		Read =>
			(c, err) := srv.canread(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			if(c.qtype & Sys->QTDIR){
				srv.read(m);	# does readdir
				break;
			}
			u := finduserpath(c.path);
			if(u == nil){
				srv.reply(ref Rmsg.Error(m.tag, Eremoved));
				break;
			}
			case TYPE(c.path) {
			Qsecret =>
				if(u.status != Sok){
					srv.reply(ref Rmsg.Error(m.tag, "user disabled"));
					break;
				}
				if(u.expire < now && u.expire != Never){
					srv.reply(ref Rmsg.Error(m.tag, "user expired"));
					break;
				}
				srv.reply(styxservers->readbytes(m, u.secret));
			Qlog =>
				srv.reply(styxservers->readstr(m, sys->sprint("%d", u.failed)));
			Qstatus =>
				s := status[u.status];
				if(u.status == Sok && u.expire != Never && u.expire < now)
					s = "expired";
				srv.reply(styxservers->readstr(m, s));
			Qexpire =>
				s: string;
				if(u.expire != Never)
					s = sys->sprint("%ud", u.expire);
				else
					s = "never";
				srv.reply(styxservers->readstr(m, s));
			* =>
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
			}
		Write =>
			(c, merr) := srv.canwrite(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, merr));
				break;
			}
			u := finduserpath(c.path);
			if(u == nil){
				srv.reply(ref Rmsg.Error(m.tag, Eremoved));
				break;
			}
		    Case:
			case TYPE(c.path) {
			Qsecret =>
				if(m.offset != big 0 || len m.data > Maxsecret){
					srv.reply(ref Rmsg.Error(m.tag, "illegal write"));
					break;
				}
				u.secret = m.data;
				writekeys(keyfile);
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
			Qexpire =>
				s := trim(string m.data);
				if(s != "never"){
					if(!isnumeric(s)){
						srv.reply(ref Rmsg.Error(m.tag, "illegal expiry time"));
						break;
					}
					u.expire = int s;
				}else
					u.expire = Never;
				u.failed = 0;
				writekeys(keyfile);
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
			Qstatus =>
				s := trim(string m.data);
				for(i := 0; i < len status; i++)
					if(s == status[i]){
						u.status = i;
						if(i == Sok)
							u.failed = 0;
						writekeys(keyfile);
						srv.reply(ref Rmsg.Write(m.tag, len m.data));
						break Case;
					}
				srv.reply(ref Rmsg.Error(m.tag, "unknown status"));
			Qlog =>
				s := trim(string m.data);
				if(s != "good" && s != "ok"){
					if(++u.failed >= Maxfail)
						u.status = Sdisabled;
				}else
					u.failed = 0;
				writekeys(keyfile);
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
			* =>
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
			}
		Remove =>
			c := srv.getfid(m.fid);
			if(c == nil){
				srv.remove(m);	# let it diagnose the errors
				break;
			}
			case TYPE(c.path) {
			Quser =>
				srv.delfid(c);
				u := finduserpath(c.path);
				if(u == nil){
					srv.reply(ref Rmsg.Error(m.tag, Eremoved));
					break;
				}
				removeuser(u);
				writekeys(keyfile);
				srv.reply(ref Rmsg.Remove(m.tag));
			Qsecret =>
				srv.delfid(c);
				u := finduserpath(c.path);
				if(u == nil){
					srv.reply(ref Rmsg.Error(m.tag, Eremoved));
					break;
				}
				u.secret = nil;
				writekeys(keyfile);
				srv.reply(ref Rmsg.Remove(m.tag));
			* =>
				srv.remove(m);	# let it reject it
			}
		Wstat =>
			# rename user
			c := srv.getfid(m.fid);
			if(c == nil || TYPE(c.path) != Quser){
				srv.default(gm);	# let it reject it
				break;
			}
			u := finduserpath(c.path);
			if(u == nil){
				srv.reply(ref Rmsg.Error(m.tag, Eremoved));
				break;
			}
			if((new := m.stat.name) == nil){
				srv.default(gm);
				break;
			}
			if(new == "." || new == ".."){
				srv.reply(ref Rmsg.Error(m.tag, Edot));
				break;
			}
			if(findusername(new) != nil){
				srv.reply(ref Rmsg.Error(m.tag, "user already exists"));
				break;
			}
			# unhashuser(u);
			u.name = new;
			# hashuser(u);
			writekeys(keyfile);
			srv.reply(ref Rmsg.Wstat(m.tag));
		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;		# shut down navigator
}

trim(s: string): string
{
	(nf, flds) := sys->tokenize(s, " \t\n");
	if(nf == 0)
		return nil;
	return hd flds;
}

isnumeric(s: string): int
{
	for(i:=0; i<len s; i++)
		if(!(s[i]>='0' && s[i]<='9'))
			return 0;
	return i>0;
}

TYPE(path: big): int
{
	return int path & 16rF;
}

INDEX(path: big): int
{
	return (int path & 16rFFFF) >> 4;
}

finduserpath(path: big): ref User
{
	i := INDEX(path);
	if(i >= len users || (u := users[i]) == nil || u.path != (path & ~big 16rF))
		return nil;
	return u;
}

findusername(name: string): ref User
{
	for(i := 0; i < len users; i++)
		if((u := users[i]) != nil && u.name == name)
			return u;
	return nil;
}

newuser(name: string, u: ref User): ref User
{
	for(i := 0; i < len users; i++)
		if(users[i] == nil)
			break;
	if(i >= len users)
		users = (array[i+16] of ref User)[0:] = users;
	path := big ((pathgen++ << 16) | (i<<4));
	if(u == nil)
		u = ref User(i, name, nil, Never, Sok, 0, path);
	else{
		u.x = i;
		u.path = path;
	}
	users[i] = u;
	return u;
}

removeuser(u: ref User)
{
	if(u != nil)
		users[u.x] = nil;
}

dirslot(n: int): int
{
	for(i := 0; i < len users; i++){
		u := users[i];
		if(u != nil){
			if(n == 0)
				break;
			n--;
		}
	}
	return i;
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
	d.atime = now;
	d.mtime = now;
	return d;
}

dirgen(p: big, name: string, u: ref User): (ref Sys->Dir, string)
{
	case t := TYPE(p) {
	Qroot =>
		return (dir(Qid(big Qroot, keyversion,Sys->QTDIR), "/", big 0, 8r755), nil);
	Quser =>
		if(name == nil){
			if(u == nil){
				u = finduserpath(p);
				if(u == nil)
					return (nil, Enotfound);
			}
			name = u.name;
		}
		return (dir(Qid(p,0,Sys->QTDIR), name, big 0, 8r500), nil);	# note: unwritable
	* =>
		l := 0;
		if(t == Qsecret){
			if(u == nil)
				u = finduserpath(p);
			if(u != nil)
				l = len u.secret;
		}
		return (dir(Qid(p,0,Sys->QTFILE), name, big l, 8r600), nil);
	}
}

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil){
	   Pick:
		pick n := m {
		Stat =>
			n.reply <-= dirgen(n.path, nil, nil);
		Walk =>
			case TYPE(n.path) {
			Qroot =>
				if(n.name == ".."){
					n.reply <-= dirgen(n.path, nil, nil);
					break;
				}
				u := findusername(n.name);
				if(u == nil){
					n.reply <-= (nil, Enotfound);
					break;
				}
				n.reply <-= dirgen(u.path | big Quser, u.name, u);
			Quser =>
				if(n.name == ".."){
					n.reply <-= dirgen(big Qroot, nil, nil);
					break;
				}
				for(j := 0; j < len files; j++){
					(ftype, name) := files[j];
					if(n.name == name){
						n.reply <-= dirgen((n.path & ~big 16rF) | big ftype, name, nil);
						break Pick;
					}
				}
				n.reply <-= (nil, Enotfound);
			* =>
				if(n.name != ".."){
					n.reply <-= (nil, Enotfound);
					break;
				}
				n.reply <-= dirgen((n.path & ~big 16rF) | big Quser, nil, nil);	# parent directory
			}
		Readdir =>
			case TYPE(n.path) {
			Qroot =>
				for(j := dirslot(n.offset); --n.count >= 0 && j < len users; j++)
					if((u := users[j]) != nil)
						n.reply <-= dirgen(u.path | big Quser, u.name, u);
				n.reply <-= (nil, nil);
			Quser =>
				u := finduserpath(n.path);
				if(u == nil){
					n.reply <-= (nil, Eremoved);
					break;
				}
				for(j := n.offset; --n.count >= 0 && j < len files; j++){
					(ftype, name) := files[j];
					n.reply <-= dirgen((n.path & ~big 16rF)|big ftype, name, u);
				}
				n.reply <-= (nil, nil);
			}
		}
	}
}

timefd: ref Sys->FD;

time(): int
{
	if(timefd == nil){
		timefd = sys->open("/dev/time", Sys->OREAD);
		if(timefd == nil)
			return 0;
	}
	buf := array[128] of byte;
	sys->seek(timefd, big 0, 0);
	n := sys->read(timefd, buf, len buf);
	if(n < 0)
		return 0;
	t := (big string buf[0:n]) / big 1000000;
	return int t;
}

Checkpat: con "XXXXXXXXXXXXXXXX";	# it's what Plan 9's aescbc uses
Checklen: con len Checkpat;

Hdrlen: con 1+1+4;

packedsize(u: ref User): int
{
	return Hdrlen+(1+len array of byte u.name)+(1+len u.secret);
}

pack(u: ref User): array of byte
{
	a := array[packedsize(u)] of byte;
	a[0] = byte u.status;
	a[1] = byte u.failed;
	a[2] = byte u.expire;
	a[3] = byte (u.expire>>8);
	a[4] = byte (u.expire>>16);
	a[5] = byte (u.expire>>24);
	bn := array of byte u.name;
	n := len bn;
	if(n > 255)
		error(sys->sprint("overlong user name: %s", u.name));	# shouldn't happen
	a[6] = byte n;
	a[7:] = bn;
	n += 7;
	a[n] = byte len u.secret;
	a[n+1:] = u.secret;
	return a;
}

unpack(a: array of byte): (ref User, int)
{
	if(len a < Hdrlen+2)
		return (nil, 0);
	u := ref User;
	u.status = int a[0];
	u.failed = int a[1];
	u.expire = (int a[5] << 24) | (int a[4] << 16) | (int a[3] << 8) | int a[2];
	n := int a[6];
	j := 7+n;
	if(j > len a)
		return (nil, 0);
	u.name = string a[7:j];
	if(j >= len a)
		return (nil, 0);
	n = int a[j++];
	if(j+n > len a)
		return (nil, 0);
	if(n > 0){
		u.secret = array[n] of byte;
		u.secret[0:] = a[j:j+n];
	}
	return (u, j+n);
}

corrupt(keyfile: string)
{
	error(sys->sprint("%s: incorrect key or corrupt/damaged keyfile", keyfile));
}

readkeys(keyfile: string)
{
	fd := sys->open(keyfile, Sys->OREAD);
	if(fd == nil)
		error(sys->sprint("can't open %s: %r", keyfile));
	(rc, d) := sys->fstat(fd);
	if(rc < 0)
		error(sys->sprint("can't get status of %s: %r", keyfile));
	length := int d.length;
	if(length == 0)
		return;
	if(length < AESbsize+Checklen)
		corrupt(keyfile);
	buf := array[length] of byte;
	if(sys->read(fd, buf, len buf) != len buf)
		error(sys->sprint("can't read %s: %r", keyfile));
	state := kr->aessetup(thekey, buf[0:AESbsize]);
	if(state == nil)
		error("can't initialise AES");
	kr->aescbc(state, buf[AESbsize:], length-AESbsize, Keyring->Decrypt);
	if(string buf[length-Checklen:] != Checkpat)
		corrupt(keyfile);
	length -= Checklen;
	for(i := AESbsize; i < length;){
		(u, n) := unpack(buf[i:]);
		if(u == nil)
			corrupt(keyfile);
		newuser(u.name, u);
		i += n;
	}
}

writekeys(keyfile: string)
{
	length := 0;
	for(i := 0; i < len users; i++)
		if((u := users[i]) != nil)
			length += packedsize(u);
	if(length == 0){
		# leave it empty for clarity
		fd := sys->create(keyfile, Sys->OWRITE, 8r600);
		if(fd == nil)
			error(sys->sprint("can't create %s: %r", keyfile));
		return;
	}
	length += AESbsize+Checklen;
	buf := array[length] of byte;
	for(i=0; i<AESbsize; i++)
		buf[i] = byte rand->rand(256);
	j := AESbsize;
	for(i = 0; i < len users; i++)
		if((u = users[i]) != nil){
			a := pack(u);
			buf[j:] = a;
			j += len a;
		}
	buf[length-Checklen:] = array of byte Checkpat;
	state := kr->aessetup(thekey, buf[0:AESbsize]);
	if(state == nil)
		error("can't initialise AES");
	kr->aescbc(state, buf[AESbsize:], length-AESbsize, Keyring->Encrypt);
	fd := sys->create(keyfile, Sys->OWRITE, 8r600);
	if(fd == nil)
		error(sys->sprint("can't create %s: %r", keyfile));
	if(sys->write(fd, buf, len buf) != len buf)
		error(sys->sprint("error writing to %s: %r", keyfile));
}
