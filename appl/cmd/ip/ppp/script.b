implement Script;

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "lock.m";
include "modem.m";
	modem: Modem;

include "script.m";

delim:	con "-";			# expect-send delimiter
BUFSIZE: con (1024 * 32);

execute( modmod: Modem, m: ref Modem->Device, scriptinfo: ref ScriptInfo )
{
	sys= load Sys Sys->PATH;
	str= load String String->PATH;
	if (str == nil) {
		raise "fail: couldn't load string module";
		return;
	}
	modem = modmod;

	if (scriptinfo.path != nil) {
		sys->print("Executing Script %s\n",scriptinfo.path);
		# load the script
		scriptinfo.content = scriptload(scriptinfo.path);
	} else {
		sys->print("Executing Inline Script\n");
	}
	
	# Check for timeout variable

	if (scriptinfo.timeout == 0)
		scriptinfo.timeout = 20;

	tend := sys->millisec() + 1000*scriptinfo.timeout;

	conv := scriptinfo.content;

	while (conv != nil)  {
		e, s:	string = nil;
		p := hd conv;
		conv = tl conv;
		if (len p == 0)
			continue;
		sys->print("script: %s\n",p);
		if (p[0] == '-') {	# just send
			if (len p == 1)
				continue;
			s = p[1:];
		} else {
			(n, esl) := sys->tokenize(p, delim);
			if (n > 0) {
				e = hd esl;
				esl = tl esl;
				if (n > 1)
					s = hd esl;
			}
		}
		if (e  != nil) {
			if (match(m, special(e,scriptinfo), tend-sys->millisec()) == 0) {
				sys->print("script: match failed\n");
				raise "fail: Script Failed";
				return;
			}
		}
		if (s != nil)
			modem->send(m, special(s, scriptinfo));
	}

	sys->print("script: done!\n");
}

match(m: ref Modem->Device, s: string, timo: int): int
{
	for(;;) {
		c := modem->getc(m, timo);
		if (c ==  '\r')
			c = '\n';
		sys->print("%c",c);
		if (c == 0)
			return 0;
	head:
		while(c == s[0]) {
			i := 1;
			while(i < len s) {
				c = modem->getc(m, timo);
				if (c == '\r')
					c = '\n';
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
special(s: string, scriptinfo: ref ScriptInfo ): string
{
	if (s == "$username") 					# special variable
		s = scriptinfo.username;
	else if (s == "$password") 
		s = scriptinfo.password;
 	
	return deparse(s);
}

deparse(s : string) : string
{
	r: string = "";
	for(i:=0; i < len s; i++) {
		c := s[i];
		if (c == '\\'  && i+1 < len s) {
			c = s[++i];
			case c {
			't' => c = '\t';
			'n'	=> c = '\n';
			'r'	=> c = '\r';
			'b'	=> c = '\b';
			'a'	=> c = '\a';
			'v'	=> c = '\v';
			'0'	=> c = '\0';
			'$' => c = '$';
			'u'	=> 
				if (i+4 < len s) {
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

scriptload( path: string) :list of string
{
	dfd := sys->open(path, Sys->OREAD);
	if (dfd == nil) {
		raise "fail: Script file ("+path+") not found";
		return nil;
	}

	scriptbuf := array[BUFSIZE] of byte;
	scriptlen := sys->read(dfd, scriptbuf, len scriptbuf);
	if(scriptlen < 0)
		raise "fail: can't read script: "+sys->sprint("%r");
    
	(nil, scriptlist) := sys->tokenize(string scriptbuf[0:scriptlen], "\n");
	return scriptlist;
}
