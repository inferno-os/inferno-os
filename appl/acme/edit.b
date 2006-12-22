implement Edit;

include "common.m";

sys: Sys;
dat: Dat;
utils: Utils;
textm: Textm;
windowm: Windowm;
rowm: Rowm;
scroll: Scroll;
editlog: Editlog;
editcomd: Editcmd;

sprint, print: import sys;
FALSE, TRUE, BUFSIZE, Null, Empty, Inactive: import Dat;
warning, error, strchr: import utils;
Text: import textm;
File: import Filem;
Window: import windowm;
allwindows: import rowm;
scrdraw: import scroll;
elogterm, elogapply: import editlog;
cmdexec, resetxec: import editcomd;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	dat = mods.dat;
	utils = mods.utils;
	textm = mods.textm;
	windowm = mods.windowm;
	rowm = mods.rowm;
	scroll = mods.scroll;
	editlog = mods.editlog;
	editcomd = mods.editcmd;
	editing = Inactive;
}

linex: con "\n";
wordx: con "\t\n";

cmdtab = array[28] of {
#		cmdc	text	regexp	addr	defcmd	defaddr	count	token	 fn
	Cmdt ( '\n',	0,	0,	0,	0,	aDot,	0,	nil,		C_nl ),
	Cmdt ( 'a',		1,	0,	0,	0,	aDot,	0,	nil,		C_a ),
	Cmdt ( 'b',		0,	0,	0,	0,	aNo,		0,	linex,	C_b ),
	Cmdt ( 'c',		1,	0,	0,	0,	aDot,	0,	nil,		C_c ),
	Cmdt ( 'd',		0,	0,	0,	0,	aDot,	0,	nil,		C_d ),
	Cmdt ( 'e',		0,	0,	0,	0,	aNo,		0,	wordx,	C_e ),
	Cmdt ( 'f',		0,	0,	0,	0,	aNo,		0,	wordx,	C_f ),
	Cmdt ( 'g',		0,	1,	0,	'p',	aDot,	0,	nil,		C_g ),
	Cmdt ( 'i',		1,	0,	0,	0,	aDot,	0,	nil,		C_i ),
	Cmdt ( 'm',	0,	0,	1,	0,	aDot,	0,	nil,		C_m ),
	Cmdt ( 'p',		0,	0,	0,	0,	aDot,	0,	nil,		C_p ),
	Cmdt ( 'r',		0,	0,	0,	0,	aDot,	0,	wordx,	C_e ),
	Cmdt ( 's',		0,	1,	0,	0,	aDot,	1,	nil,		C_s ),
	Cmdt ( 't',		0,	0,	1,	0,	aDot,	0,	nil,		C_m ),
	Cmdt ( 'u',		0,	0,	0,	0,	aNo,		2,	nil,		C_u ),
	Cmdt ( 'v',		0,	1,	0,	'p',	aDot,	0,	nil,		C_g ),
	Cmdt ( 'w',	0,	0,	0,	0,	aAll,		0,	wordx,	C_w ),
	Cmdt ( 'x',		0,	1,	0,	'p',	aDot,	0,	nil,		C_x ),
	Cmdt ( 'y',		0,	1,	0,	'p',	aDot,	0,	nil,		C_x ),
	Cmdt ( '=',		0,	0,	0,	0,	aDot,	0,	linex,	C_eq ),
	Cmdt ( 'B',		0,	0,	0,	0,	aNo,		0,	linex,	C_B ),
	Cmdt ( 'D',	0,	0,	0,	0,	aNo,		0,	linex,	C_D ),
	Cmdt ( 'X',		0,	1,	0,	'f',	aNo,		0,	nil,		C_X ),
	Cmdt ( 'Y',		0,	1,	0,	'f',	aNo,		0,	nil,		C_X ),
	Cmdt ( '<',		0,	0,	0,	0,	aDot,	0,	linex,	C_pipe ),
	Cmdt ( '|',		0,	0,	0,	0,	aDot,	0,	linex,	C_pipe ),
	Cmdt ( '>',		0,	0,	0,	0,	aDot,	0,	linex,	C_pipe ),
	# deliberately unimplemented
	# Cmdt ( 'k',	0,	0,	0,	0,	aDot,	0,	nil,		C_k ),
	# Cmdt ( 'n',	0,	0,	0,	0,	aNo,		0,	nil,		C_n ),
	# Cmdt ( 'q',	0,	0,	0,	0,	aNo,		0,	nil,		C_q ),
	# Cmdt ( '!',	0,	0,	0,	0,	aNo,		0,	linex,	C_plan9 ),
	Cmdt (0,		0,	0,	0,	0,	0,		0,	nil,		-1 )
};

cmdstartp: string;
cmdendp: int;
cmdp: int;
editerrc: chan of string;

lastpat : ref String;
patset: int;

# cmdlist: ref List;
# addrlist: ref List;
# stringlist: ref List;

editwaitproc(pid : int, sync: chan of int)
{
	fd : ref Sys->FD;
	n : int;

	sys->pctl(Sys->FORKFD, nil);
	w := sprint("#p/%d/wait", pid);
	fd = sys->open(w, Sys->OREAD);
	if (fd == nil)
		error("fd == nil in editwaitproc");
	sync <-= sys->pctl(0, nil);
	buf := array[Sys->WAITLEN] of byte;
	status := "";
	for(;;){
		if ((n = sys->read(fd, buf, len buf))<0)
			error("bad read in editwaitproc");
		status = string buf[0:n];
		dat->cwait <-= status;
	}
}

editthread()
{
	cmdp: ref Cmd;

	mypid := sys->pctl(0, nil);
	sync := chan of int;
	spawn editwaitproc(mypid, sync);
	yourpid := <- sync;
	while((cmdp=parsecmd(0)) != nil){
#		ocurfile = curfile;
#		loaded = curfile && !curfile->unread;
		if(cmdexec(curtext, cmdp) == 0)
			break;
		freecmd();
	}
	editerrc <-= nil;
	utils->postnote(Utils->PNPROC, mypid, yourpid, "kill");
}

allelogterm(w: ref Window)
{
	elogterm(w.body.file);
}

alleditinit(w: ref Window)
{
	w.tag.commit(TRUE);
	w.body.commit(TRUE);
	w.body.file.editclean = FALSE;
}

allupdate(w: ref Window)
{
	t: ref Text;
	i: int;
	f: ref File;

	t = w.body;
	f = t.file;
	if(f.curtext != t)		# do curtext only
		return;
	if(f.elog.typex == Null)
		elogterm(f);
	else if(f.elog.typex != Empty){
		elogapply(f);
		if(f.editclean){
			f.mod = FALSE;
			for(i=0; i<f.ntext; i++)
				f.text[i].w.dirty = FALSE;
		}
		t.setselect(t.q0, t.q1);
		scrdraw(t);
		w.settag();
	}
}

editerror(s: string)
{
	# print("%s", s);
	freecmd();
	allwindows(ALLELOGTERM, nil);	# truncate the edit logs
	editerrc <-= s;
	exit;
}

editcmd(ct: ref Text, r: string, n: int)
{
	err: string;

	if(n == 0)
		return;
	if(2*n > BUFSIZE){
		warning(nil, "string too long\n");
		return;
	}

	allwindows(ALLEDITINIT, nil);
	cmdstartp = r[0:n];
	if(r[n-1] != '\n')
		cmdstartp[n++] = '\n';
	cmdendp = n;
	cmdp = 0;
	if(ct.w == nil)
		curtext = nil;
	else
		curtext = ct.w.body;
	resetxec();
	if(editerrc == nil){
		editerrc = chan of string;
		lastpat = allocstring(0);
	}
	spawn editthread();
	err = <- editerrc;
	editing = Inactive;
	if(err != nil)
		warning(nil, sprint("Edit: %s\n", err));

	# update everyone whose edit log has data
	allwindows(ALLUPDATE, nil);
}

getch(): int
{
	if(cmdp == cmdendp)
		return -1;
	return cmdstartp[cmdp++];
}

nextc(): int
{
	if(cmdp == cmdendp)
		return -1;
	return cmdstartp[cmdp];
}

ungetch()
{
	if(--cmdp < 0)
		error("ungetch");
}

getnum(signok: int): int
{
	n: int;
	c, sign: int;

	n = 0;
	sign = 1;
	if(signok>1 && nextc()=='-'){
		sign = -1;
		getch();
	}
	if((c=nextc())<'0' || '9'<c)	# no number defaults to 1
		return sign;
	while('0'<=(c=getch()) && c<='9')
		n = n*10 + (c-'0');
	ungetch();
	return sign*n;
}

cmdskipbl(): int
{
	c: int;
	do
		c = getch();
	while(c==' ' || c=='\t');
	if(c >= 0)
		ungetch();
	return c;
}

# Check that list has room for one more element.
# growlist(l: ref List)
# {
#	if(l.elems == nil || l.nalloc==0){
#		l.nalloc = INCR;
#		l.elems = array[INCR] of Listelement;
#		l.nused = 0;
#	}else if(l.nused == l.nalloc){
#		old := l.elems;
#		l.elems = array[l.nalloc+INCR] of Listelement;
#		l.elems[0:] = old[0:l.nalloc];
#		l.nalloc += INCR;
#	}
# }

# Remove the ith element from the list
# dellist(l: ref List, i: int)
# {
#	l.elems[i:] = l.elems[i+1:l.nused];
#	l.nused--;
# }

# Add a new element, whose position is i, to the list
# inslist(l: ref List, i: int, val: int)
# {
#	growlist(l);
#	l.elems[i+1:] = l.elems[i:l.nused];
#	l.elems[i] = val;
#	l.nused++;
# }

# listfree(l: ref List)
# {
#	l.elems = nil;
# }

allocstring(n: int): ref String
{
	s: ref String;

	s = ref String;
	s.n = n;
	s.r = string array[s.n] of { * => byte '\0' };
	return s;
}

freestring(s: ref String)
{
	s.r = nil;
}

newcmd(): ref Cmd
{
	p: ref Cmd;

	p = ref Cmd;
	# inslist(cmdlist, cmdlist.nused, p);
	return p;
}

newstring(n: int): ref String
{
	p: ref String;

	p = allocstring(n);
	# inslist(stringlist, stringlist.nused, p);
	return p;
}

newaddr(): ref Addr
{
	p: ref Addr;

	p = ref Addr;
	# inslist(addrlist, addrlist.nused, p);
	return p;
}

freecmd()
{
	# i: int;

	# cmdlist.elems = nil;
	# addrlist.elems = nil;
	# stringlist.elems = nil;
	# cmdlist.nused = addrlist.nused = stringlist.nused = 0;
}

okdelim(c: int)
{
	if(c=='\\' || ('a'<=c && c<='z')
	|| ('A'<=c && c<='Z') || ('0'<=c && c<='9'))
		editerror(sprint("bad delimiter %c\n", c));
}

atnl()
{
	c: int;

	cmdskipbl();
	c = getch();
	if(c != '\n')
		editerror(sprint("newline expected (saw %c)", c));
}

Straddc(s: ref String, c: int)
{
	s.r[s.n++] = c;
}

getrhs(s: ref String, delim: int, cmd: int)
{
	c: int;

	while((c = getch())>0 && c!=delim && c!='\n'){
		if(c == '\\'){
			if((c=getch()) <= 0)
				error("bad right hand side");
			if(c == '\n'){
				ungetch();
				c='\\';
			}else if(c == 'n')
				c='\n';
			else if(c!=delim && (cmd=='s' || c!='\\'))	# s does its own
				Straddc(s, '\\');
		}
		Straddc(s, c);
	}
	ungetch();	# let client read whether delimiter, '\n' or whatever
}

collecttoken(end: string): ref String
{
	c: int;

	s := newstring(0);

	while((c=nextc())==' ' || c=='\t')
		Straddc(s, getch()); # blanks significant for getname()
	while((c=getch())>0 && strchr(end, c)<0)
		Straddc(s, c);
	if(c != '\n')
		atnl();
	return s;
}

collecttext(): ref String
{
	s: ref String;
	begline, i, c, delim: int;

	s = newstring(0);
	if(cmdskipbl()=='\n'){
		getch();
		i = 0;
		do{
			begline = i;
			while((c = getch())>0 && c!='\n'){
				i++;
				Straddc(s, c);
			}
			i++;
			Straddc(s, '\n');
			if(c < 0)
				return s;
		}while(s.r[begline]!='.' || s.r[begline+1]!='\n');
		s.r[s.n-2] = '\0';
	}else{
		okdelim(delim = getch());
		getrhs(s, delim, 'a');
		if(nextc()==delim)
			getch();
		atnl();
	}
	return s;
}

cmdlookup(c: int): int
{
	i: int;

	for(i=0; cmdtab[i].cmdc; i++)
		if(cmdtab[i].cmdc == c)
			return i;
	return -1;
}

parsecmd(nest: int): ref Cmd
{
	i, c: int;
	cp, ncp: ref Cmd;
	cmd: ref Cmd;

	cmd = ref Cmd;
	cmd.next = cmd.cmd = nil;
	cmd.re = nil;
	cmd.flag = cmd.num = 0;
	cmd.addr = compoundaddr();
	if(cmdskipbl() == -1)
		return nil;
	if((c=getch())==-1)
		return nil;
	cmd.cmdc = c;
	if(cmd.cmdc=='c' && nextc()=='d'){	# sleazy two-character case
		getch();		# the 'd'
		cmd.cmdc='c'|16r100;
	}
	i = cmdlookup(cmd.cmdc);
	if(i >= 0){
		if(cmd.cmdc == '\n'){
			cp = newcmd();
			*cp = *cmd;
			return cp;
			# let nl_cmd work it all out
		}
		ct := cmdtab[i];
		if(ct.defaddr==aNo && cmd.addr != nil)
			editerror("command takes no address");
		if(ct.count)
			cmd.num = getnum(ct.count);
		if(ct.regexp){
			# x without pattern -> .*\n, indicated by cmd.re==0
			# X without pattern is all files
			if((ct.cmdc!='x' && ct.cmdc!='X') ||
			   ((c = nextc())!=' ' && c!='\t' && c!='\n')){
				cmdskipbl();
				if((c = getch())=='\n' || c<0)
					editerror("no address");
				okdelim(c);
				cmd.re = getregexp(c);
				if(ct.cmdc == 's'){
					cmd.text = newstring(0);
					getrhs(cmd.text, c, 's');
					if(nextc() == c){
						getch();
						if(nextc() == 'g')
							cmd.flag = getch();
					}
			
				}
			}
		}
		if(ct.addr && (cmd.mtaddr=simpleaddr())==nil)
			editerror("bad address");
		if(ct.defcmd){
			if(cmdskipbl() == '\n'){
				getch();
				cmd.cmd = newcmd();
				cmd.cmd.cmdc = ct.defcmd;
			}else if((cmd.cmd = parsecmd(nest))==nil)
				error("defcmd");
		}else if(ct.text)
			cmd.text = collecttext();
		else if(ct.token != nil)
			cmd.text = collecttoken(ct.token);
		else
			atnl();
	}else
		case(cmd.cmdc){
		'{' =>
			cp = nil;
			do{
				if(cmdskipbl()=='\n')
					getch();
				ncp = parsecmd(nest+1);
				if(cp != nil)
					cp.next = ncp;
				else
					cmd.cmd = ncp;
			}while((cp = ncp) != nil);
			break;
		'}' =>
			atnl();
			if(nest==0)
				editerror("right brace with no left brace");
			return nil;
		'c'|16r100 =>
			editerror("unimplemented command cd");
		* =>
			editerror(sprint("unknown command %c", cmd.cmdc));
		}
	cp = newcmd();
	*cp = *cmd;
	return cp;
}

getregexp(delim: int): ref String
{
	buf, r: ref String;
	i, c: int;

	buf = allocstring(0);
	for(i=0; ; i++){
		if((c = getch())=='\\'){
			if(nextc()==delim)
				c = getch();
			else if(nextc()=='\\'){
				Straddc(buf, c);
				c = getch();
			}
		}else if(c==delim || c=='\n')
			break;
		if(i >= BUFSIZE)
			editerror("regular expression too long");
		Straddc(buf, c);
	}
	if(c!=delim && c)
		ungetch();
	if(buf.n > 0){
		patset = TRUE;
		freestring(lastpat);
		lastpat = buf;
	}else
		freestring(buf);
	if(lastpat.n == 0)
		editerror("no regular expression defined");
	r = newstring(lastpat.n);
	k := lastpat.n;
	for(j := 0; j < k; j++)
		r.r[j] = lastpat.r[j];	# newstring put \0 at end
	return r;
}

simpleaddr(): ref Addr
{
	addr: Addr;
	ap, nap: ref Addr;

	addr.next = nil;
	addr.left = nil;
	case(cmdskipbl()){
	'#' =>
		addr.typex = getch();
		addr.num = getnum(1);
		break;
	'0' to '9' =>
		addr.num = getnum(1);
		addr.typex='l';
		break;
	'/' or '?' or '"' =>
		addr.re = getregexp(addr.typex = getch());
		break;
	'.' or
	'$' or
	'+' or
	'-' or
	'\'' =>
		addr.typex = getch();
		break;
	* =>
		return nil;
	}
	if((addr.next = simpleaddr()) != nil)
		case(addr.next.typex){
		'.' or
		'$' or
		'\'' =>
			if(addr.typex!='"')
				editerror("bad address syntax");
			break;
		'"' =>
			editerror("bad address syntax");
			break;
		'l' or
		'#' =>
			if(addr.typex=='"')
				break;
			if(addr.typex!='+' && addr.typex!='-'){
				# insert the missing '+'
				nap = newaddr();
				nap.typex='+';
				nap.next = addr.next;
				addr.next = nap;
			}
			break;
		'/' or
		'?' =>
			if(addr.typex!='+' && addr.typex!='-'){
				# insert the missing '+'
				nap = newaddr();
				nap.typex='+';
				nap.next = addr.next;
				addr.next = nap;
			}
			break;
		'+' or
		'-' =>
			break;
		* =>
			error("simpleaddr");
		}
	ap = newaddr();
	*ap = addr;
	return ap;
}

compoundaddr(): ref Addr
{
	addr: Addr;
	ap, next: ref Addr;

	addr.left = simpleaddr();
	if((addr.typex = cmdskipbl())!=',' && addr.typex!=';')
		return addr.left;
	getch();
	next = addr.next = compoundaddr();
	if(next != nil && (next.typex==',' || next.typex==';') && next.left==nil)
		editerror("bad address syntax");
	ap = newaddr();
	*ap = addr;
	return ap;
}

