implement Diff;

#	diff - differential file comparison
#
#	Uses an algorithm due to Harold Stone, which finds
#	a pair of longest identical subsequences in the two
#	files.
#
#	The major goal is to generate the match vector J.
#	J[i] is the index of the line in file1 corresponding
#	to line i file0. J[i] = 0 if there is no
#	such line in file1.
#
#	Lines are hashed so as to work in core. All potential
#	matches are located by sorting the lines of each file
#	on the hash (called value). In particular, this
#	collects the equivalence classes in file1 together.
#	Subroutine equiv replaces the value of each line in
#	file0 by the index of the first element of its 
#	matching equivalence in (the reordered) file1.
#	To save space equiv squeezes file1 into a single
#	array member in which the equivalence classes
#	are simply concatenated, except that their first
#	members are flagged by changing sign.
#
#	Next the indices that point into member are unsorted into
#	array class according to the original order of file0.
#
#	The cleverness lies in routine stone. This marches
#	through the lines of file0, developing a vector klist
#	of "k-candidates". At step i a k-candidate is a matched
#	pair of lines x,y (x in file0 y in file1) such that
#	there is a common subsequence of lenght k
#	between the first i lines of file0 and the first y 
#	lines of file1, but there is no such subsequence for
#	any smaller y. x is the earliest possible mate to y
#	that occurs in such a subsequence.
#
#	Whenever any of the members of the equivalence class of
#	lines in file1 matable to a line in file0 has serial number 
#	less than the y of some k-candidate, that k-candidate 
#	with the smallest such y is replaced. The new 
#	k-candidate is chained (via pred) to the current
#	k-1 candidate so that the actual subsequence can
#	be recovered. When a member has serial number greater
#	that the y of all k-candidates, the klist is extended.
#	At the end, the longest subsequence is pulled out
#	and placed in the array J by unravel.
#
#	With J in hand, the matches there recorded are
#	check'ed against reality to assure that no spurious
#	matches have crept in due to hashing. If they have,
#	they are broken, and "jackpot " is recorded--a harmless
#	matter except that a true match for a spuriously
#	mated line may now be unnecessarily reported as a change.
#
#	Much of the complexity of the program comes simply
#	from trying to minimize core utilization and
#	maximize the range of doable problems by dynamically
#	allocating what is needed and reusing what is not.
#	The core requirements for problems larger than somewhat
#	are (in words) 2*length(file0) + length(file1) +
#	3*(number of k-candidates installed),  typically about
#	6n words for files of length n. 
#
# 

include "sys.m";
	sys: Sys;

include "bufio.m";
	bufio : Bufio;
Iobuf : import bufio;

include "draw.m";
	draw: Draw;
include "readdir.m";
	readdir : Readdir;
include "string.m";
	str : String;
include "arg.m";

Diff : module  
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;

mode : int;			# '\0', 'e', 'f', 'h' 
bflag : int;			# ignore multiple and trailing blanks 
rflag : int;			# recurse down directory trees 
mflag : int;			# pseudo flag: doing multiple files, one dir

REG,
BIN: con iota;

HALFINT : con 16;
Usage : con  "usage: diff [ -efbwr ] file1 ... file2";

cand : adt {
	x : int;
	y : int;
	pred : int;
};

line : adt {
	serial : int;
	value : int;
};

out : ref Iobuf;
file := array[2] of array of line;
sfile := array[2] of array of line;	# shortened by pruning common prefix and suffix
slen := array[2] of int;
ilen := array[2] of int;
pref, suff, clen : int;			# length of prefix and suffix
firstchange : int;
clist : array of cand;			# merely a free storage pot for candidates
J : array of int;			# will be overlaid on class
ixold, ixnew : array of int;
input := array[2] of ref Iobuf ;
file1, file2 : string;
tmpname := array[] of {"/tmp/diff1", "/tmp/diff2"};
whichtmp : int;
anychange := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	bufio = load Bufio Bufio->PATH;
	readdir = load Readdir Readdir->PATH;	
	str = load String String->PATH;
	if (bufio==nil)
		fatal(sys->sprint("cannot load %s: %r", Bufio->PATH));
	if (readdir==nil)
		fatal(sys->sprint("cannot load %s: %r", Readdir->PATH));
	if (str==nil)
		fatal(sys->sprint("cannot load %s: %r", String->PATH));
	arg := load Arg Arg->PATH;
	if (arg==nil)
		fatal(sys->sprint("cannot load %s: %r", Arg->PATH));
	fsb, tsb : Sys->Dir;
	arg->init(args);
	while((o := arg->opt()) != 0)
		case o {
		'e' or 'f' =>
			mode = o;
		'w' =>
			bflag = 2;
		'b' =>
			bflag = 1;
		'r' =>
			rflag = 1;
		'm' =>
			mflag = 1;
		* =>
			fatal(Usage);
		}
	tmp := arg->argv();
	arg = nil;
	j := len tmp;
	if (j < 2)
		fatal(Usage);
	arr := array[j] of string;
	for(i:=0;i<j;i++){
		arr[i]= hd tmp;
		tmp = tl tmp;
	}

	(i,tsb)=sys->stat(arr[j-1]);
	if (i == -1)
		fatal(sys->sprint("can't stat %s: %r", arr[j-1]));
	if (j > 2) {
		if (!(tsb.qid.qtype&Sys->QTDIR))
			fatal(Usage);
		mflag = 1;
	}
	else {
		(i,fsb)=sys->stat(arr[0]);
		if (i == -1)
			fatal(sys->sprint("can't stat %s: %r", arr[0]));
		if ((fsb.qid.qtype&Sys->QTDIR) && (tsb.qid.qtype&Sys->QTDIR))
			mflag = 1;
	}
	out=bufio->fopen(sys->fildes(1),Bufio->OWRITE);
	for (i = 0; i < j-1; i++) {
		diff(arr[i], arr[j-1], 0);
		rmtmpfiles();
	}
	rmtmpfiles();
	out.flush();
	if (anychange)
		raise "fail:some";
}

############################# diffreg from here ....

# shellsort CACM #201

sort(a : array of line, n : int)
{
	w : line;
	m := 0;
	for (i := 1; i <= n; i *= 2)
		m = 2*i - 1;
	for (m /= 2; m != 0; m /= 2) {
		for (j := 1; j <= n-m ; j++) {
			ai:=j;
			aim:=j+m;
			do {
				if (a[aim].value > a[ai].value ||
				   a[aim].value == a[ai].value &&
				   a[aim].serial > a[ai].serial)
					break;
				w = a[ai];
				a[ai] = a[aim];
				a[aim] = w;
				aim=ai;
				ai-=m;
			} while (ai > 0 && aim >= ai);
		}
	}
}

unsort(f : array of line, l : int) : array of int 
{
	i : int;
	a := array[l+1] of int;
	for(i=1;i<=l;i++)
		a[f[i].serial] = f[i].value;
	return a;
}

prune() 
{
	for(pref=0;pref< ilen[0]&&pref< ilen[1]&&
		file[0][pref+1].value==file[1][pref+1].value;
		pref++ ) ;
	for(suff=0;suff< ilen[0]-pref&&suff< ilen[1]-pref&&
		file[0][ilen[0]-suff].value==file[1][ilen[1]-suff].value;
		suff++) ;
	for(j:=0;j<2;j++) {
		sfile[j] = file[j][pref:];
		slen[j]= ilen[j]-pref-suff;
		for(i:=0;i<=slen[j];i++)
			sfile[j][i].serial = i;
	}
}

equiv(a: array of line, n:int , b: array of line, m: int, c : array of int) 
{
	i := 1;
	j := 1;
	while(i<=n && j<=m) {
		if(a[i].value < b[j].value)
			a[i++].value = 0;
		else if(a[i].value == b[j].value)
			a[i++].value = j;
		else
			j++;
	}
	while(i <= n)
		a[i++].value = 0;
	b[m+1].value = 0; # huh ?
	j = 1;
	while(j <= m) {
		c[j] = -b[j].serial;
		while(b[j+1].value == b[j].value) {
			j++;
			c[j] = b[j].serial;
		}
		j++;
	}
	c[j] = -1;
}

newcand(x, y, pred : int) : int 
{
	if (clen==len clist){
		q := array[clen*2] of cand;
		q[0:]=clist;
		clist= array[clen*2] of cand;
		clist[0:]=q;
		q=nil;
	}
	clist[clen].x=x;
	clist[clen].y=y;
	clist[clen].pred=pred;
	return clen++;
}

search(c : array of int, k,y : int) : int 
{
	if(clist[c[k]].y < y)	# quick look for typical case
		return k+1;
	i := 0;
	j := k+1;
	while((l:=(i+j)/2) > i) {
		t := clist[c[l]].y;
		if(t > y)
			j = l;
		else if(t < y)
			i = l;
		else
			return l;
	}
	return l+1;
}

stone(a : array of int ,n : int, b: array of int , c : array of int) : int 
{
	oldc, oldl, tc, l ,y : int;
	k := 0;
	c[0] = newcand(0,0,0);
	for(i:=1; i<=n; i++) {
		j := a[i];
		if(j==0)
			continue;
		y = -b[j];
		oldl = 0;
		oldc = c[0];
		do {
			if(y <= clist[oldc].y)
				continue;
			l = search(c, k, y);
			if(l!=oldl+1)
				oldc = c[l-1];
			if(l<=k) {
				if(clist[c[l]].y <= y)
					continue;
				tc = c[l];
				c[l] = newcand(i,y,oldc);
				oldc = tc;
				oldl = l;
			} else {
				c[l] = newcand(i,y,oldc);
				k++;
				break;
			}
		} while((y=b[j+=1]) > 0);
	}
	return k;
}

unravel(p : int) 
{
	for(i:=0; i<=ilen[0]; i++) {
		if (i <= pref)
			J[i] = i;
		else if (i > ilen[0]-suff)
			J[i] = i+ ilen[1]-ilen[0];
		else
			J[i] = 0;
	}
	for(q:=clist[p];q.y!=0;q=clist[q.pred])
		J[q.x+pref] = q.y+pref;
}

output() 
{
	i1: int;
	m := ilen[0];
	J[0] = 0;
	J[m+1] = ilen[1]+1;
	if (mode != 'e') {
		for (i0 := 1; i0 <= m; i0 = i1+1) {
			while (i0 <= m && J[i0] == J[i0-1]+1)
				i0++;
			j0 := J[i0-1]+1;
			i1 = i0-1;
			while (i1 < m && J[i1+1] == 0)
				i1++;
			j1 := J[i1+1]-1;
			J[i1] = j1;
			change(i0, i1, j0, j1);
		}
	}
	else {
		for (i0 := m; i0 >= 1; i0 = i1-1) {
			while (i0 >= 1 && J[i0] == J[i0+1]-1 && J[i0])
				i0--;
			j0 := J[i0+1]-1;
			i1 = i0+1;
			while (i1 > 1 && J[i1-1] == 0)
				i1--;
			j1 := J[i1-1]+1;
			J[i1] = j1;
			change(i1 , i0, j1, j0);
		}
	}
	if (m == 0)
		change(1, 0, 1, ilen[1]);
	out.flush();
}

diffreg(f,t : string) 
{
	k : int;

	(b0, b0type) := prepare(0, f);
	if (b0==nil)
		return;
	(b1, b1type) := prepare(1, t);
	if (b1==nil) {
		b0=nil;
		return;
	}
	if (b0type == BIN || b1type == BIN) {
		if (cmp(b0, b1)) {
			out.puts(sys->sprint("Binary files %s %s differ\n", f, t));
			anychange = 1;
		}
		b0 = nil;
		b1 = nil;
		return;
	}
	clen=0;
	prune();
	file[0]=nil;
	file[1]=nil;
	sort(sfile[0],slen[0]);
	sort(sfile[1],slen[1]);
	member := array[slen[1]+2] of int;
	equiv(sfile[0], slen[0],sfile[1],slen[1], member);
	class:=unsort(sfile[0],slen[0]);
	sfile[0]=nil;
	sfile[1]=nil;
	klist := array[slen[0]+2] of int;
	clist = array[1] of cand;
	k = stone(class, slen[0], member, klist);
	J = array[ilen[0]+2] of int;
	unravel(klist[k]);
	clist=nil;
	klist=nil;
	class=nil;
	member=nil;
	ixold = array[ilen[0]+2] of int;
	ixnew = array[ilen[1]+2] of int;

	b0.seek(big 0, 0); 
	b1.seek(big 0, 0);
	check(b0, b1);
	output();
	ixold=nil;
	ixnew=nil;
	b0=nil; 
	b1=nil;			
}

######################## diffio starts here...


# hashing has the effect of
# arranging line in 7-bit bytes and then
# summing 1-s complement in 16-bit hunks 

readhash(bp : ref Iobuf) : int 
{
	sum := 1;
	shift := 0;
	buf := bp.gets('\n');
	if (buf == nil)
		return 0;
	buf = buf[0:len buf -1];
	p := 0;
	case bflag {
		# various types of white space handling 
		0 =>
			while (p< len buf) {
				sum += (buf[p] << (shift &= (HALFINT-1)));
				p++;
				shift += 7;
			}
		1 =>
			
			 # coalesce multiple white-space
			 
			for (space := 0; p< len buf; p++) {
				if (buf[p]==' ' || buf[p]=='\t') {
					space++;
					continue;
				}
				if (space) {
					shift += 7;
					space = 0;
				}
				sum +=  (buf[p] << (shift &= (HALFINT-1)));
				p++;
				shift += 7;
			}
		* =>
			
			 # strip all white-space
			 
			while (p< len buf) {
				if (buf[p]==' ' || buf[p]=='\t') {
					p++;
					continue;
				}
				sum +=  (buf[p] << (shift &= (HALFINT-1)));
				p++;
				shift += 7;
			}
	}
	return sum;
}

prepare(i : int, arg : string) : (ref Iobuf, int)
{
	h : int;
	bp := bufio->open(arg,Bufio->OREAD);
	if (bp==nil) {
		error(sys->sprint("cannot open %s: %r", arg));
		return (nil, 0);
	}
	buf := array[1024] of byte;
	n :=bp.read(buf, len buf);
	str1 := string buf[0:n];
	for (j:=0;j<len str1 -2;j++)
		if (str1[j] == Sys->UTFerror)
			return (bp, BIN);
	bp.seek(big 0, Sys->SEEKSTART);
	p := array[4] of line;
	for (j = 0; h = readhash(bp); p[j].value = h){
		j++;
		if (j+3>=len p){
			newp:=array[len p*2] of line;
			newp[0:]=p[0:];
			p=array[len p*2] of line;
			p=newp;
			newp=nil;
		}
	}
	ilen[i]=j;
	file[i] = p;
	input[i] = bp;			
	if (i == 0) {			
		file1 = arg;
		firstchange = 0;
	}
	else
		file2 = arg;
	return (bp, REG);
}

squishspace(buf : string) : string 
{
	q:=0;
	p:=0;
	for (space := 0; q<len buf; q++) {
		if (buf[q]==' ' || buf[q]=='\t') {
			space++;
			continue;
		}
		if (space && bflag == 1) {
			buf[p] = ' ';
			p++;
			space = 0;
		}
		buf[p]=buf[q];
		p++;
	}
	buf=buf[0:p];
	return buf;
}


# need to fix up for unexpected EOF's

ftell(b: ref Iobuf): int
{
	return int b.offset();
}

check(bf, bt : ref Iobuf) 
{
	fbuf, tbuf : string;
	f:=1;
	t:=1;
	ixold[0] = ixnew[0] = 0;
	for (; f < ilen[0]; f++) {
		fbuf = bf.gets('\n');
		if (fbuf!=nil)
			fbuf=fbuf[0:len fbuf -1];
		ixold[f] = ftell(bf);
		if (J[f] == 0)
			continue;
		tbuflen: int;
		do {
			tbuf = bt.gets('\n');
			if (tbuf!=nil)
				tbuf=tbuf[0:len tbuf -1];
			tbuflen = len array of byte tbuf;
			ixnew[t] = ftell(bt);
		} while (t++ < J[f]);
		if (bflag) {
			fbuf = squishspace(fbuf);
			tbuf = squishspace(tbuf);
		}
		if (len fbuf != len tbuf || fbuf!=tbuf)
			J[f] = 0;
	}
	while (t < ilen[1]) {
		tbuf = bt.gets('\n');
		if (tbuf!=nil)
			tbuf=tbuf[0:len tbuf -1];
		ixnew[t] = ftell(bt);
		t++;
	}
}

range(a, b : int, separator : string) 
{
	if (a>b)
		out.puts(sys->sprint("%d", b));
	else
		out.puts(sys->sprint("%d", a));
	if (a < b)
		out.puts(sys->sprint("%s%d", separator, b));
}

fetch(f : array of int, a,b : int , bp : ref Iobuf, s : string) 
{
	buf : string;
	bp.seek(big f[a-1], 0);
	while (a++ <= b) {
		buf=bp.gets('\n');
		out.puts(s);
		out.puts(buf);
	}
}

change(a, b, c, d : int) 
{
	if (a > b && c > d)
		return;
	anychange = 1;
	if (mflag && firstchange == 0) {
		out.puts(sys->sprint( "diff %s %s\n", file1, file2));
		firstchange = 1;
	}
	if (mode != 'f') {
		range(a, b, ",");
		if (a>b)
			out.putc('a');
		else if (c>d)
			out.putc('d');
		else
			out.putc('c');
		if (mode != 'e')
			range(c, d, ",");
	}
	else {
		if (a>b)
			out.putc('a');
		else if (c>d)
			out.putc('d');
		else
			out.putc('c');
		range(a, b, " ");
	}
	out.putc('\n');
	if (mode == 0) {
		fetch(ixold, a, b, input[0], "< ");
		if (a <= b && c <= d)
			out.puts("---\n");
	}
	if (mode==0)
		fetch(ixnew, c, d, input[1], "> ");
	else
		fetch(ixnew, c, d, input[1], "");

	if (mode != 0 && c <= d)
		out.puts(".\n");
}


######################### diffdir starts here ......

scandir(name : string) : array of string 
{
	(db,nitems):= readdir->init(name,Readdir->NAME);
	cp := array[nitems] of string;
	for(i:=0;i<nitems;i++)
		cp[i]=db[i].name;
	return cp;
}


diffdir(f, t : string, level : int) 
{
	df, dt : array of string;
	fb, tb : string;
	i:=0;
	j:=0;
	df = scandir(f);
	dt = scandir(t);
	while ((i<len df) || (j<len dt)) {
		if ((j==len dt) || (i<len df && df[i] < dt[j])) {
			if (mode == 0)
				out.puts(sys->sprint("Only in %s: %s\n", f, df[i]));
			i++;
			continue;
		}
		if ((i==len df) || (j<len dt && df[i] > dt[j])) {
			if (mode == 0)
				out.puts(sys->sprint("Only in %s: %s\n", t, dt[j]));
			j++;
			continue;
		}
		fb=sys->sprint("%s/%s", f, df[i]);
		tb=sys->sprint("%s/%s", t, dt[j]);		
		diff(fb, tb, level+1);
		i++; j++;
	}
}

cmp(b0, b1: ref Iobuf): int
{
	b0.seek(big 0, Sys->SEEKSTART);
	b1.seek(big 0, Sys->SEEKSTART);
	buf0 := array[1024] of byte;
	buf1 := array[1024] of byte;
	for (;;) {
		n0 := b0.read(buf0, len buf0);
		n1 := b1.read(buf1, len buf1);

		if (n0 != n1)
			return 1;

		if (n0 == 0)
			return 0;

		for (i := 0; i < n0; i++) 
			if (buf0[i] != buf1[i])
				return 1;
	}
}

################## main from here.....

REGULAR_FILE(s : Sys->Dir) : int 
{
	# both pipes and networks contain non-zero-length files
	# which are not seekable.
	return (s.qid.qtype&Sys->QTDIR) == 0 &&
		s.dtype != '|' &&
		s.dtype != 'I';
#		&& s.length > 0;	device files have zero length. 
}

rmtmpfiles() 
{
	while (whichtmp > 0) {
		whichtmp--;
		sys->remove(tmpname[whichtmp]);
	}
}

mktmpfile(inputf : ref Sys->FD) : (string, Sys->Dir) 
{
	i, j : int;
	sb : Sys->Dir;
	p : string;
	buf := array[8192] of byte;

	p = tmpname[whichtmp++];
	fd := sys->create(p, Sys->OWRITE, 8r600);
	if (fd == nil) {
		error(sys->sprint("cannot create %s: %r", p));
		return (nil, sb);
	}
	while ((i = sys->read(inputf, buf, len buf)) > 0) {
		if ((i = sys->write(fd, buf, i)) < 0)
			break;
	}
	(j,sb)=sys->fstat(fd);
	if (i < 0 || j < 0) {
		error(sys->sprint("cannot read/write %s: %r", p));
		return (nil, sb);
	}
	return (p, sb);
}


statfile(file : string) : (string,Sys->Dir) 
{
	(ret,sb):=sys->stat(file);
	if (ret==-1) {
		if (file != "-" || sys->fstat(sys->fildes(0)).t0 == -1){
			error(sys->sprint("cannot stat %s: %r", file));
			return (nil,sb);
		}
		(file, sb) = mktmpfile(sys->fildes(0));
	}
	else if (!REGULAR_FILE(sb) && !(sb.qid.qtype&Sys->QTDIR)) {
		if ((i := sys->open(file, Sys->OREAD)) == nil) {
			error(sys->sprint("cannot open %s: %r", file));
			return (nil, sb);
		}
		(file, sb) = mktmpfile(i);
	}
	return (file,sb);
}

diff(f, t : string, level : int) 
{
	fp,tp,p,rest,fb,tb : string;
	fsb, tsb : Sys->Dir;
	(fp,fsb) = statfile(f);
	if (fp == nil)
		return;
	(tp,tsb) = statfile(t);
	if (tp == nil)
		return;
	if ((fsb.qid.qtype&Sys->QTDIR) && (tsb.qid.qtype&Sys->QTDIR)) {
		if (rflag || level == 0)
			diffdir(fp, tp, level);
		else
			out.puts(sys->sprint("Common subdirectories: %s and %s\n", fp, tp));
	}
	else if (REGULAR_FILE(fsb) && REGULAR_FILE(tsb)){
		diffreg(fp, tp);
	} else {
		if (!(fsb.qid.qtype&Sys->QTDIR)) {
			(p,rest)=str->splitr(f,"/");
			if (rest!=nil)
				p = rest;
			tb=sys->sprint("%s/%s", tp, p);			
			diffreg(fp, tb);
		}
		else {
			(p,rest)=str->splitr(t,"/");
			if (rest!=nil)
				p = rest;
			fb=sys->sprint("%s/%s", fp, p);			
			diffreg(fb, tp);
		}
	}
}

fatal(s: string)
{
	sys->fprint(stderr, "diff: %s\n", s);
	raise "fail:error";
}

error(s: string)
{
	sys->fprint(stderr, "diff: %s\n", s);
}
