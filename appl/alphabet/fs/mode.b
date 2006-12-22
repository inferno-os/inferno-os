implement Mode, Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	Report: import Reports;
include "alphabet/fs.m";
	fs: Fs;
	Value: import fs;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fs;

Mode: module {};

# XXX implement octal modes.

User:	con 8r700;
Group:	con 8r070;
Other:	con 8r007;
All:	con User | Group | Other;

Read:	con 8r444;
Write:	con 8r222;
Exec:	con 8r111;

types(): string
{
	return "ps";
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
	fs->init();
}

run(nil: ref Draw->Context, nil: ref Report,
			nil: list of Option, args: list of ref Value): ref Value
{
	spec := (hd args).s().i;
	(ok, mask, mode) := parsemode(spec);
	if(ok == 0){
		sys->fprint(sys->fildes(2), "fs: mode: bad mode %#q\n", spec);
		return nil;
	}
	c := chan of Gatequery;
	spawn modegate(c, mask, mode);
	return ref Value.Vp(c);
}

modegate(c: Gatechan, mask, mode: int)
{
	m := mode & mask;
	while((((d, nil, nil), reply) := <-c).t0.t0 != nil)
		reply <-= ((d.mode & mask) ^ m) == 0;
}

# stolen from /appl/cmd/chmod.b
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


