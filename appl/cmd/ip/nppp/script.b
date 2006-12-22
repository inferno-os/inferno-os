implement Script;

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "lock.m";
include "modem.m";
	modem: Modem;
	Device: import modem;

include "script.m";

Scriptlim: con 32*1024;		# should be enough for all

init(mm: Modem): string
{
	sys = load Sys Sys->PATH;
	modem = mm;
	str = load String String->PATH;
	if(str == nil)
		return sys->sprint("can't load %s: %r", String->PATH);
	return nil;
}

execute(m: ref Modem->Device, scriptinfo: ref ScriptInfo): string
{
	if(scriptinfo.path != nil) {
		if(m.trace)
			sys->print("script: using %s\n",scriptinfo.path);
		# load the script
		err: string;
		(scriptinfo.content, err) = scriptload(scriptinfo.path);
		if(err != nil)
			return err;
	}else{
		if(m.trace)
			sys->print("script: using inline script\n");
	}
	
	if(scriptinfo.timeout == 0)
		scriptinfo.timeout = 20;

	tend := sys->millisec() + 1000*scriptinfo.timeout;

	for(conv := scriptinfo.content; conv != nil; conv = tl conv){
		e, s:	string = nil;
		p := hd conv;
		if(len p == 0)
			continue;
		if(m.trace)
			sys->print("script: %s\n",p);
		if(p[0] == '-') {	# just send
			if(len p == 1)
				continue;
			s = p[1:];
		} else {
			(n, esl) := sys->tokenize(p, "-");
			if(n > 0) {
				e = hd esl;
				esl = tl esl;
				if(n > 1)
					s = hd esl;
			}
		}
		if(e  != nil) {
			if(match(m, special(e,scriptinfo), tend-sys->millisec()) == 0) {
				if(m.trace)
					sys->print("script: match failed\n");
				return "script failed";
			}
		}
		if(s != nil)
			m.send(special(s, scriptinfo));
	}
	if(m.trace)
		sys->print("script: done\n");
	return nil;
}

match(m: ref Modem->Device, s: string, msec: int): int
{
	for(;;) {
		c := m.getc(msec);
		if(c ==  '\r')
			c = '\n';
		if(m.trace)
			sys->print("%c",c);
		if(c == 0)
			return 0;
	head:
		while(c == s[0]) {
			i := 1;
			while(i < len s) {
				c = m.getc(msec);
				if(c == '\r')
					c = '\n';
				if(m.trace)
					sys->print("%c",c);
				if(c == 0)
					return 0;
				if(c != s[i])
					continue head;
				i++;
			}
			return 1;
		}
		if(c == '~')
			return 1;	# assume PPP for now
	}
}

#
# Expand special script sequences
#
special(s: string, scriptinfo: ref ScriptInfo): string
{
	if(s == "$username") 					# special variable
		s = scriptinfo.username;
	else if(s == "$password") 
		s = scriptinfo.password;
	return deparse(s);
}

deparse(s: string): string
{
	r: string = "";
	for(i:=0; i < len s; i++) {
		c := s[i];
		if(c == '\\'  && i+1 < len s) {
			c = s[++i];
			case c {
			't'	=> c = '\t';
			'n'	=> c = '\n';
			'r'	=> c = '\r';
			'b'	=> c = '\b';
			'a'	=> c = '\a';
			'v'	=> c = '\v';
			'0'	=> c = '\0';
			'$'	=> c = '$';
			'u'	=> 
				if(i+4 < len s) {
					i++;
					(c, nil) = str->toint(s[i:i+4], 16);
					i+=3;
				}
			}
		}
		r[len r] = c;
	}
	return r;
}

scriptload(path: string): (list of string, string)
{
	dfd := sys->open(path, Sys->OREAD);
	if(dfd == nil)
		return (nil, sys->sprint("can't open script %s: %r", path));

	b := array[Scriptlim] of byte;
	n := sys->read(dfd, b, len b);
	if(n < 0)
		return (nil, sys->sprint("can't read script %s: %r", path));
    
	(nil, script) := sys->tokenize(string b[0:n], "\n");
	return (script, nil);
}
