implement Match, Fsmodule;
include "sys.m";
	sys: Sys;
include "filepat.m";
	filepat: Filepat;
include "regex.m";
	regex: Regex;
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

Match: module {};

types(): string
{
	return "ps-a-r";
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
	regex = load Regex Regex->PATH;
	if(regex == nil)
		badmod(Regex->PATH);
	filepat = load Filepat Filepat->PATH;
	if(filepat == nil)
		badmod(Filepat->PATH);
}

run(nil: ref Draw->Context, nil: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	pat := (hd args).s().i;
	aflag := rflag := 0;
	for(; opts != nil; opts = tl opts){
		case (hd opts).opt {
		'a' =>
			aflag = 1;
		'r' =>
			rflag = 1;
		}
	}
	v := ref Value.Vp(chan of Gatequery);
	re: Regex->Re;
	if(rflag){
		err: string;
		(re, err) = regex->compile(pat, 0);
		if(re == nil){
			sys->fprint(sys->fildes(2), "fs: match: regex error on %#q: %s\n", pat, err);
			return nil;
		}
	}
	spawn matchproc(v.i, aflag, pat, re);
	return v;
}

matchproc(c: Gatechan, all: int, pat: string, re: Regex->Re)
{
	while((((d, name, nil), reply) := <-c).t0.t0 != nil){
		if(all == 0)
			name = d.name;
		if(re != nil)
			reply <-= regex->execute(re, name) != nil;		# XXX should anchor it?
		else
			reply <-= filepat->match(pat, name);
	}
}
