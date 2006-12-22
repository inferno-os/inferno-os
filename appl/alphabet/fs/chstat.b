implement Chstat, Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
include "alphabet/fs.m";
	fsfilter: Fsfilter;
	fs: Fs;
	Value: import fs;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fs;

Chstat: module {};

Query: adt {
	gate: Gatechan;
	stat: Sys->Dir;
	mask: int;
	cflag: int;
	reply: chan of int;

	query: fn(q: self ref Query, d: ref Sys->Dir, name: string, depth: int): int;
};

types(): string
{
	return "xx-pp-ms-us-gs-ts-as-c";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: size: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fs = load Fs Fs->PATH;
	if(fs == nil)
		badmod(Fs->PATH);
	
	fsfilter = load Fsfilter Fsfilter->PATH;
	if(fsfilter == nil)
		badmod(Fsfilter->PATH);
}

run(nil: ref Draw->Context, nil: ref Reports->Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	ws := Sys->nulldir;
	mask := 0;
	gate: ref Value;
	cflag := 0;
	for(; opts != nil; opts = tl opts){
		o := (hd opts).args;
		case (hd opts).opt {
		'p' =>
			gate.free(0);
			gate = hd o;
		'm' =>
			ok: int;
			m := (hd o).s().i;
			(ok, mask, ws.mode) = parsemode(m);
			mask &= ~Sys->DMDIR;
			if(ok == 0){
				sys->fprint(sys->fildes(2), "fs: chstat: bad mode %#q\n", m);
				gate.free(0);
				return nil;
			}
		'u' =>
			ws.uid = (hd o).s().i;
		'g' =>
			ws.gid = (hd o).s().i;
		't' =>
			ws.mtime = int (hd o).s().i;
		'a' =>
			ws.atime = int (hd o).s().i;
		'c' =>
			cflag++;
		}
	}

	dst := chan of (Fsdata, chan of int);
	p: Gatechan;
	if(gate != nil)
		p = gate.p().i;
	spawn chstatproc((hd args).x().i, dst, p, ws, mask, cflag);
	return ref Value.Vx(dst);
}

chstatproc(src, dst: Fschan, gate: Gatechan, stat: Sys->Dir, mask: int, cflag: int)
{
	fsfilter->filter(ref Query(gate, stat, mask, cflag, chan of int), src, dst);
	if(gate != nil)
		gate <-= ((nil, nil, 0), nil);
}

Query.query(q: self ref Query, d: ref Sys->Dir, name: string, depth: int): int
{
	c := 1;
	if(q.gate != nil){
		q.gate <-= ((d, name, depth), q.reply);
		c = <-q.reply;
	}
	if(c){
		if(q.cflag){
			m := d.mode & 8r700;
			d.mode = (d.mode & ~8r77)|(m>>3)|(m>>6);
		}
		stat := q.stat;
		d.mode = (d.mode & ~q.mask) | (stat.mode & q.mask);
		if(stat.uid != nil)
			d.uid = stat.uid;
		if(stat.gid != nil)
			d.gid = stat.gid;
		if(stat.mtime != ~0)
			d.mtime = stat.mtime;
		if(stat.atime != ~0)
			d.atime = stat.atime;
	}
	return 1;
}

# stolen from /appl/cmd/chmod.b
User:	con 8r700;
Group:	con 8r070;
Other:	con 8r007;
All:	con User | Group | Other;

Read:	con 8r444;
Write:	con 8r222;
Exec:	con 8r111;
parsemode(spec: string): (int, int, int)
{
	mask := Sys->DMAPPEND | Sys->DMEXCL | Sys->DMDIR | Sys->DMAUTH;
loop:
	for(i := 0; i < len spec; i++){
		case spec[i] {
		'u' =>
			mask |= User;
		'g' =>
			mask |= Group;
		'o' =>
			mask |= Other;
		'a' =>
			mask |= All;
		* =>
			break loop;
		}
	}
	if(i == len spec)
		return (0, 0, 0);
	if(i == 0)
		mask |= All;

	op := spec[i++];
	if(op != '+' && op != '-' && op != '=')
		return (0, 0, 0);

	mode := 0;
	for(; i < len spec; i++){
		case spec[i]{
		'r' =>
			mode |= Read;
		'w' =>
			mode |= Write;
		'x' =>
			mode |= Exec;
		'a' =>
			mode |= Sys->DMAPPEND;
		'l' =>
			mode |= Sys->DMEXCL;
		'd' =>
			mode |= Sys->DMDIR;
		'A' =>
			mode |= Sys->DMAUTH;
		* =>
			return (0, 0, 0);
		}
	}
	if(op == '+' || op == '-')
		mask &= mode;
	if(op == '-')
		mode = ~mode;
	return (1, mask, mode);
}
