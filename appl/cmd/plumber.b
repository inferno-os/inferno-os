implement Plumber;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

include "sh.m";

include "regex.m";
	regex: Regex;

include "string.m";
	str: String;

include "../lib/plumbing.m";
	plumbing: Plumbing;
	Pattern, Rule: import plumbing;

include "plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg, Attr: import plumbmsg;

include "arg.m";

Plumber: module
{
	init:	fn(ctxt: ref Draw->Context, argl: list of string);
};

Input: adt
{
	inc:		chan of ref Inmesg;
	resc:		chan of int;
	io:		ref Sys->FileIO;
};

Output: adt
{
	name:	string;
	outc:		chan of string;
	io:		ref Sys->FileIO;
	queue:	list of array of byte;
	started:	int;
	startup:	string;
	waiting:	int;
};

Port: adt
{
	name:		string;
	startup:	string;
	alwaysstart:	int;
};

Match: adt
{
	p0, p1:	int;
};

Inmesg: adt
{
	msg:		ref Msg;
	text:		string;	# if kind is text
	p0,p1:	int;
	match:	array of Match;
	port:		int;
	startup:	string;
	args:		list of string;
	attrs:		list of ref Attr;
	clearclick:	int;
	set:		int;
	# $ arguments
	_n:		array of string;
	_dir:		string;
	_file:		string;
};

# Message status after processing
HANDLED: con -1;
UNKNOWN: con -2;
NOTSTARTED: con -3;

output: array of ref Output;

input: ref Input;

stderr: ref Sys->FD;
pgrp: int;
rules: list of ref Rule;
titlectl: chan of string;
ports: list of ref Port;
wmstartup := 0;
wmchan := "/chan/wm";
verbose := 0;

context: ref Draw->Context;

usage()
{
	sys->fprint(stderr, "Usage: plumb [-vw] [-c wmchan] [initfile ...]\n");
	raise "fail:usage";
}

init(ctxt: ref Draw->Context, args: list of string)
{
	context = ctxt;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	stderr = sys->fildes(2);

	regex = load Regex Regex->PATH;
	plumbing = load Plumbing Plumbing->PATH;
	str = load String String->PATH;

	err: string;
	nogrp := 0;

	arg := load Arg Arg->PATH;
	arg->init(args);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'w' =>
			wmstartup = 1;
		'c' =>
			if ((wmchan = arg->arg()) == nil)
				usage();
		'v' =>
			verbose = 1;
		'n' =>
			nogrp = 1;
		* =>
			usage();
		}
	}
	args = arg->argv();
	arg = nil;

	(rules, err) = plumbing->init(regex, args);
	if(err != nil){
		sys->fprint(stderr, "plumb: %s\n", err);
		raise "fail:init";
	}

	plumbmsg = load Plumbmsg Plumbmsg->PATH;
	plumbmsg->init(0, nil, 0);

	if(nogrp)
		pgrp = sys->pctl(0, nil);
	else
		pgrp = sys->pctl(sys->NEWPGRP, nil);

	r := rules;
	for(i:=0; i<len rules; i++){
		rule := hd r;
		r = tl r;
		for(j:=0; j<len rule.action; j++)
			if(rule.action[j].pred == "to" || rule.action[j].pred == "alwaysstart"){
				p := findport(rule.action[j].arg);
				if(p == nil){
					p = ref Port(rule.action[j].arg, nil, rule.action[j].pred == "alwaysstart");
					ports = p :: ports;
				}
				for(k:=0; k<len rule.action; k++)
					if(rule.action[k].pred == "start")
						p.startup = rule.action[k].arg;
				break;
			}
	}

	input = ref Input;
	input.io = makefile("plumb.input");
	if(input.io == nil)
		shutdown();
	input.inc = chan of ref Inmesg;
	input.resc = chan of int;
	spawn receiver(input);

	output = array[len ports] of ref Output;

	pp := ports;
	for(i=0; i<len output; i++){
		p := hd pp;
		pp = tl pp;
		output[i] = ref Output;
		output[i].name = p.name;
		output[i].io = makefile("plumb."+p.name);
		if(output[i].io == nil)
			shutdown();
		output[i].outc = chan of string;
		output[i].started = 0;
		output[i].startup = p.startup;
		output[i].waiting = 0;
	}

	# spawn so we return without needing to run plumb in background
	spawn sender(input, output);
}

findport(name: string): ref Port
{
	for(p:=ports; p!=nil; p=tl p)
		if((hd p).name == name)
			return hd p;
	return nil;
}

makefile(file: string): ref Sys->FileIO
{
	io := sys->file2chan("/chan", file);
	if(io == nil){
		sys->fprint(stderr, "plumb: can't establish /chan/%s: %r\n", file);
		return nil;
	}
	return io;
}

receiver(input: ref Input)
{

	for(;;){
		(nil, msg, nil, wc) := <-input.io.write;
		if(wc == nil)
			;	# not interested in EOF; leave channel open
		else{
			input.inc <-= parse(msg);
			res := <- input.resc;
			err := "";
			if(res == UNKNOWN)
				err = "no matching plumb rule";
			wc <-= (len msg, err);
		}
	}
}

sender(input: ref Input, output: array of ref Output)
{
	outputc := array[len output] of chan of (int, int, int, Sys->Rread);

	for(;;){
		alt{
		in := <-input.inc =>
			if(in == nil){
				input.resc <-= HANDLED;
				break;
			}
			(j, msg) := process(in);
			case j {
			HANDLED =>
				break;
			UNKNOWN =>
				if(in.msg.src != "acme")
					sys->fprint(stderr, "plumb: don't know who message goes to\n");
			NOTSTARTED =>
				sys->fprint(stderr, "plumb: can't start application\n");
			* =>
				output[j].queue = append(output[j].queue, msg);
				outputc[j] = output[j].io.read;
			}
			input.resc <-= j;
		
		(j, tmp) := <-outputc =>
			(nil, nbytes, nil, rc) := tmp;
			if(rc == nil)	# no interest in EOF
				break;
			msg := hd output[j].queue;
			if(nbytes < len msg){
				rc <-= (nil, "buffer too short for message");
				break;
			}
			output[j].queue = tl output[j].queue;
			if(output[j].queue == nil)
				outputc[j] = nil;
			rc <-= (msg, nil);
		}
	}
}

parse(a: array of byte): ref Inmesg
{
	msg := Msg.unpack(a);
	if(msg == nil)
		return nil;
	i := ref Inmesg;
	i.msg = msg;
	if(msg.dst != nil){
		if(control(i))
			return nil;
		toport(i, msg.dst);
	}else
		i.port = -1;
	i.match = array[10] of { * => Match(-1, -1)};
	i._n = array[10] of string;
	i.attrs = plumbmsg->string2attrs(i.msg.attr);
	return i;
}

append(l: list of array of byte, a: array of byte): list of array of byte
{
	if(l == nil)
		return a :: nil;
	return hd l :: append(tl l, a);
}

shutdown()
{
	fname := sys->sprint("#p/%d/ctl", pgrp);
	if((fdesc := sys->open(fname, sys->OWRITE)) != nil)
		sys->write(fdesc, array of byte "killgrp\n", 8);
	raise "fail:error";
}

# Handle control messages
control(in: ref Inmesg): int
{
	msg := in.msg;
	if(msg.kind!="text" || msg.dst!="plumb")
		return 0;
	text := string msg.data;
	case text {
	"start" =>
		start(msg.src, 1);
	"stop" =>
		start(msg.src, -1);
	* =>
		sys->fprint(stderr, "plumb: unrecognized control message from %s: %s\n", msg.src, text);
	}
	return 1;
}

start(port: string, startstop: int)
{
	for(i:=0; i<len output; i++)
		if(port == output[i].name){
			output[i].waiting = 0;
			output[i].started += startstop;
			return;
		}
	sys->fprint(stderr, "plumb: \"start\" message from unrecognized port %s\n", port);
}

startup(dir, prog: string, args: list of string, wait: chan of int)
{
	if(wmstartup){
		fd := sys->open(wmchan, Sys->OWRITE);
		if(fd != nil){
			sys->fprint(fd, "s %s", str->quoted(dir :: prog :: args));
			wait <-= 1;
			return;
		}
	}

	sys->pctl(Sys->NEWFD|Sys->NEWPGRP|Sys->FORKNS, list of {0, 1, 2});
	wait <-= 1;
	wait = nil;
	mod := load Command prog;
	if(mod == nil){
		sys->fprint(stderr, "plumb: can't load %s: %r\n", prog);
		return;
	}
	sys->chdir(dir);
	mod->init(context, prog :: args);
}

# See if messages should be queued while waiting for program to connect
shouldqueue(out: ref Output): int
{
	p := findport(out.name);
	if(p == nil){
		sys->fprint(stderr, "plumb: can't happen in shouldqueue\n");
		return 0;
	}
	if(p.alwaysstart)
		return 0;
	return out.waiting;	
}

# Determine destination of input message, reformat for output
process(in: ref Inmesg): (int, array of byte)
{
	if(!clarify(in))
		return (UNKNOWN, nil);
	if(in.port < 0)
		return (UNKNOWN, nil);
	a := in.msg.pack();
	j := in.port;
	if(a == nil)
		j = UNKNOWN;
	else if(output[j].started==0 && !shouldqueue(output[j])){
		path: string;
		args: list of string;
		if(in.startup!=nil){
			path = macro(in, in.startup);
			args = expand(in, in.args);
		}else if(output[j].startup != nil){
			path = output[j].startup;
			args = in.text :: nil;
		}else
			return (NOTSTARTED, nil);
		log(sys->sprint("start %s port %s\n", path, output[j].name));
		wait := chan of int;
		output[j].waiting = 1;
		spawn startup(in.msg.dir, path, args, wait);
		<-wait;
		return (HANDLED, nil);
	}else{
		if(in.msg.kind != "text")
			text := sys->sprint("message of type %s", in.msg.kind);
		else{
			text = in.text;
			for(i:=0; i<len text; i++){
				if(text[i]=='\n'){
					text = text[0:i];
					break;
				}
				if(i > 50) {
					text = text[0:i]+"...";
					break;
				}
			}
		}
		log(sys->sprint("send \"%s\" to %s", text, output[j].name));
	}
	return (j, a);
}

# expand $arguments
expand(in: ref Inmesg, args: list of string): list of string
{
	a: list of string;
	while(args != nil){
		a = macro(in, hd args) :: a;
		args = tl args;
	}
	while(a != nil){
		args = hd a :: args;
		a = tl a;
	}
	return args;
}

# resolve all ambiguities, fill in any missing fields
clarify(in: ref Inmesg): int
{
	in.clearclick = 0;
	in.set = 0;
	msg := in.msg;
	if(msg.kind != "text")
		return 0;
	in.text = string msg.data;
	if(msg.dst != "")
		return 1;
	return dorules(in, rules);
}

dorules(in: ref Inmesg, rules: list of ref Rule): int
{
	if (verbose)
		log("msg: " + inmesg2s(in));
	for(r:=rules; r!=nil; r=tl r) {
		if(matchrule(in, hd r)){
			applyrule(in, hd r);
			if (verbose)
				log("yes");
			return 1;
		} else if (verbose)
			log("no");
	}
	return 0;
}

inmesg2s(in: ref Inmesg): string
{
	m := in.msg;
	s := sys->sprint("src=%s; dst=%s; dir=%s; kind=%s; attr='%s'",
			m.src, m.dst, m.dir, m.kind, m.attr);
	if (m.kind == "text")
		s += "; data='" + string m.data + "'";
	return s;
}

matchrule(in: ref Inmesg, r: ref Rule): int
{
	pats := r.pattern;
	for(i:=0; i<len in.match; i++)
		in.match[i] = (-1,-1);
	# no rules at all implies success, so return if any fail
	for(i=0; i<len pats; i++)
		if(matchpattern(in, pats[i]) == 0)
			return 0;
	return 1;
}

applyrule(in: ref Inmesg, r: ref Rule)
{
	acts := r.action;
	for(i:=0; i<len acts; i++)
		applypattern(in, acts[i]);
	if(in.clearclick){
		al: list of ref Attr;
		for(l:=in.attrs; l!=nil; l=tl l)
			if((hd l).name != "click")
				al = hd l :: al;
		in.attrs = al;
		in.msg.attr = plumbmsg->attrs2string(al);
		if(in.set){
			in.text = macro(in, "$0");
			in.msg.data = array of byte in.text;
		}
	}
}

matchpattern(in: ref Inmesg, p: ref Pattern): int
{
	msg := in.msg;
	text: string;
	case p.field {
	"src" =>	text = msg.src;
	"dst" =>	text = msg.dst;
	"dir" =>	text = msg.dir;
	"kind" =>	text = msg.kind;
	"attr" =>	text = msg.attr;
	"data" =>	text = in.text;
	* =>
		sys->fprint(stderr, "plumb: don't recognize pattern field %s\n", p.field);
		return 0;
	}
	if (verbose)
		log(sys->sprint("'%s' %s '%s'\n", text, p.pred, p.arg));
	case p.pred {
	"is" =>
		return text == p.arg;
	"isfile" or "isdir" =>
		text = p.arg;
		if(p.expand)
			text = macro(in, text);
		if(len text == 0)
			return 0;
		if(len in.msg.dir!=0 && text[0] != '/' && text[0]!='#')
			text = in.msg.dir+"/"+text;
		text = cleanname(text);
		(ok, dir) := sys->stat(text);
		if(ok < 0)
			return 0;
		if(p.pred=="isfile" && (dir.mode&Sys->DMDIR)==0){
			in._file = text;
			return 1;
		}
		if(p.pred=="isdir" && (dir.mode&Sys->DMDIR)!=0){
			in._dir = text;
			return 1;
		}
		return 0;
	"matches" =>
		(clickspecified, val) := plumbmsg->lookup(in.attrs, "click");
		if(p.field != "data")
			clickspecified = 0;
		if(!clickspecified){
			# easy case. must match whole string
			matches := regex->execute(p.regex, text);
			if(matches == nil)
				return 0;
			(p0, p1) := matches[0];
			if(p0!=0 || p1!=len text)
				return 0;
			in.match = matches;
			setvars(in, text);
			return 1;
		}
		matches := clickmatch(p.regex, text, int val);
		if(matches == nil)
			return 0;
		(p0, p1) := matches[0];
		# assumes all matches are in same sequence
		if(in.match[0].p0 != -1)
			return p0==in.match[0].p0 && p1==in.match[0].p1;
		in.match = matches;
		setvars(in, text);
		in.clearclick = 1;
		in.set = 1;
		return 1;
	"set" =>
		text = p.arg;
		if(p.expand)
			text = macro(in, text);
		case p.field {
		"src" =>	msg.src = text;
		"dst" =>	msg.dst = text;
		"dir" =>	msg.dir = text;
		"kind" =>	msg.kind = text;
		"attr" =>	msg.attr = text;
		"data" =>	in.text = text;
				msg.data = array of byte text;
				msg.kind = "text";
				in.set = 0;
		}
		return 1;
	* =>
		sys->fprint(stderr, "plumb: don't recognize pattern predicate %s\n", p.pred);
	}
	return 0;
}

applypattern(in: ref Inmesg, p: ref Pattern): int
{
	if(p.field != "plumb"){
		sys->fprint(stderr, "plumb: don't recognize action field %s\n", p.field);
		return 0;
	}
	case p.pred {
	"to" or "alwaysstart" =>
		if(in.port >= 0)	# already specified
			return 1;
		toport(in, p.arg);
	"start" =>
		in.startup = p.arg;
		in.args = p.extra;
	* =>
		sys->fprint(stderr, "plumb: don't recognize action %s\n", p.pred);
	}
	return 1;
}

toport(in: ref Inmesg, name: string): int
{
	for(i:=0; i<len output; i++)
		if(name == output[i].name){
			in.msg.dst = name;
			in.port = i;
			return i;
		}
	in.port = -1;
	sys->fprint(stderr, "plumb: unrecognized port %s\n", name);
	return -1;
}

# simple heuristic: look for leftmost match that reaches click position
clickmatch(re: ref Regex->Arena, text: string, click: int): array of Match
{
	for(i:=0; i<=click && i < len text; i++){
		matches := regex->executese(re, text, (i, -1), i == 0, 1);
		if(matches == nil)
			continue;
		(p0, p1) := matches[0];
		
		if(p0>=i && p1>=click)
			return matches;
	}
	return nil;
}

setvars(in: ref Inmesg, text: string)
{
	for(i:=0; i<len in.match && in.match[i].p0>=0; i++)
		in._n[i] = text[in.match[i].p0:in.match[i].p1];
	for(; i<len in._n; i++)
		in._n[i] = "";
}

macro(in: ref Inmesg, text: string): string
{
	word := "";
	i := 0;
	j := 0;
	for(;;){
		if(i == len text)
			break;
		if(text[i++] != '$')
			continue;
		if(i == len text)
			break;
		word += text[j:i-1];
		(res, skip) := dollar(in, text[i:]);
		word += res;
		i += skip;
		j = i;
	}
	if(j < len text)
		word += text[j:];
	return word;
}

dollar(in: ref Inmesg, text: string): (string, int)
{
	if(text[0] == '$')
		return ("$", 1);
	if('0'<=text[0] && text[0]<='9')
		return (in._n[text[0]-'0'], 1);
	if(len text < 3)
		return ("$", 0);
	case text[0:3] {
	"src" =>	return (in.msg.src, 3);
	"dst" =>	return (in.msg.dst, 3);
	"dir" =>	return (in._dir, 3);
	}
	if(len text< 4)
		return ("$", 0);
	case text[0:4] {
	"attr" =>	return (in.msg.attr, 4);
	"data" =>	return (in.text, 4);
	"file" =>	return (in._file, 4);
	"kind" =>	return (in.msg.kind, 4);
	}
	return ("$", 0);
}

# compress ../ references and do other cleanups
cleanname(name: string): string
{
	# compress multiple slashes
	n := len name;
	for(i:=0; i<n-1; i++)
		if(name[i]=='/' && name[i+1]=='/'){
			name = name[0:i]+name[i+1:];
			--i;
			n--;
		}
	#  eliminate ./
	for(i=0; i<n-1; i++)
		if(name[i]=='.' && name[i+1]=='/' && (i==0 || name[i-1]=='/')){
			name = name[0:i]+name[i+2:];
			--i;
			n -= 2;
		}
	found: int;
	do{
		# compress xx/..
		found = 0;
		for(i=1; i<=n-3; i++)
			if(name[i:i+3] == "/.."){
				if(i==n-3 || name[i+3]=='/'){
					found = 1;
					break;
				}
			}
		if(found)
			for(j:=i-1; j>=0; --j)
				if(j==0 || name[j-1]=='/'){
					i += 3;		# character beyond ..
					if(i<n && name[i]=='/')
						++i;
					name = name[0:j]+name[i:];
					n -= (i-j);
					break;
				}
	}while(found);
	# eliminate trailing .
	if(n>=2 && name[n-2]=='/' && name[n-1]=='.')
		--n;
	if(n == 0)
		return ".";
	if(n != len name)
		name = name[0:n];
	return name;
}

log(s: string)
{
	if(len s == 0)
		return;
	if(s[len s-1] != '\n')
		s[len s] = '\n';
	sys->print("plumb: %s", s);
}
