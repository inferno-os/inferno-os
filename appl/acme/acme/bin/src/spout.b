implement Spout;

include "sys.m";
include "draw.m";
include "bufio.m";

Spout : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

sys : Sys;
bufio : Bufio;

OREAD, OWRITE, ORDWR, FORKNS, FORKFD, NEWPGRP, MREPL, FD, UTFmax, pctl, open, read, write, fprint, sprint, fildes, bind, dup, byte2char, utfbytes : import sys;
Iobuf : import bufio;

stdin, stdout, stderr : ref FD;

init(nil : ref Draw->Context, argl : list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	stdin = fildes(0);
	stdout = fildes(1);
	stderr = fildes(2);
	main(argl);	
}

bout : ref Iobuf;

main(argv : list of string)
{
	fd : ref FD;

	bout = bufio->fopen(stdout, OWRITE);
	if(len argv == 1)
		spout(stdin, "");
	else
		for(argv = tl argv; argv != nil; argv = tl argv){
			fd = open(hd argv, OREAD);
			if(fd == nil){
				fprint(stderr, "spell: can't open %s: %r\n", hd argv);
				continue;
			}
			spout(fd, hd argv);
			fd = nil;
		}
	exit;
}

alpha(c : int) : int
{
	return ('a'<=(c) && (c)<='z') || ('A'<=(c) && (c)<='Z');
}

b : ref Iobuf;

spout(fd : ref FD, name : string)
{
	s, buf : string;
	t, w : int;
	inword, wordchar : int;
	n, wn, c, m : int;

	b = bufio->fopen(fd, OREAD);
	n = 0;
	wn = 0;
	while((s = b.gets('\n')) != nil){
		if(s[len s-1] != '\n')
			s[len s] = '\n';
		if(s[0] == '.') {
			for(c=0; c<3 && c < len s && s[c]>' '; c++)
				n++;
			s = s[c:];
		}
		inword = 0;
		w = 0;
		t = 0;
		do{
			c = s[t];
			wordchar = 0;
			if(alpha(c))
				wordchar = 1;
			if(inword && !wordchar){
				if(c=='\'' && alpha(s[t+1])) {
					n++;
					t++;
					continue;
				}
				m = t-w;
				if(m > 1){
					buf = s[w:w+m];
					bout.puts(sprint("%s:#%d,#%d:%s\n", name, wn, n, buf));
				}
				inword = 0;
			}else if(!inword && wordchar){
				wn = n;
				w = t;
				inword = 1;
			}
			if(c=='\\' && (alpha(s[t+1]) || s[t+1]=='(')){
				case(s[t+1]){
				'(' =>
					m = 4;
					break;
				'f' =>
					if(s[t+2] == '(')
						m = 5;
					else
						m = 3;
					break;
				's' =>
					if(s[t+2] == '+' || s[t+2]=='-'){
						if(s[t+3] == '(')
							m = 6;
						else
							m = 4;
					}else{
						if(s[t+2] == '(')
							m = 5;
						else if(s[t+2]=='1' || s[t+2]=='2' || s[t+2]=='3')
							m = 4;
						else
							m = 3;
					}
					break;
				* =>
					m = 2;
				}
				while(m-- > 0){
					if(s[t] == '\n')
						break;
					n++;
					t++;
				}
				continue;
			}
			n++;
			t ++;
		}while(c != '\n');
	}
	bout.flush();
}
