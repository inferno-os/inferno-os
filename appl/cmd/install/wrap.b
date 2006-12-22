implement Wrap;

include "sys.m";
	sys : Sys;
include "draw.m";
include "bufio.m";
	bufio : Bufio;
	Iobuf : import bufio;
include "keyring.m";
	keyring : Keyring;
include "sh.m";
include "arch.m";
	arch : Arch;
include "wrap.m";
include "archfs.m";

archpid := -1;
gzfd: ref Sys->FD;
gzfile: string;

init(bio: Bufio)
{
	sys = load Sys Sys->PATH;
	if(bio == nil)
		bufio = load Bufio Bufio->PATH;
	else
		bufio = bio;
	keyring = load Keyring Keyring->PATH;
	arch = load Arch Arch->PATH;
	arch->init(bufio);
}

end()
{
	if(gzfile != nil)
		sys->remove(gzfile);
	if (archpid > 0){
		fd := sys->open("#p/" + string archpid + "/ctl", sys->OWRITE);
		if (fd != nil)
			sys->fprint(fd, "killgrp");
	}
}
 
archfs(f : string, mtpt : string, all : int, c : chan of int)
{
	sys->pctl(Sys->NEWPGRP, nil);
	cmd := "/dis/install/archfs.dis";
	m := load Archfs Archfs->PATH;
	if(m == nil) {
		c <-= -1;
		return;
	}
	ch := chan of int;
	if (all)
		spawn m->initc(cmd :: "-m" :: mtpt :: f :: nil, ch);
	else
		spawn m->initc(cmd :: "-s" :: "-m" :: mtpt :: f :: "/wrap" :: nil, ch);
	pid := <- ch;
	c <-= pid;
}

mountarch(f : string, mtpt : string, all : int) : int
{
	c := chan of int;
	spawn archfs(f, mtpt, all, c);
	pid := <- c;
	if (pid < 0) {
		if(pid == -1)
			sys->fprint(sys->fildes(2), "fatal: cannot run archfs\n");
		# else probably not an archive file
		return -1;
	}
	archpid = pid;
	return 0;
}
	
openmount(f : string, d : string) : ref Wrapped
{
	if (f == nil) {
		p := d+"/wrap";
		f = getfirstdir(p);
		if (f == nil)
			return nil;
	}
	w := ref Wrapped;
	w.name = f;
	w.root = d;
	# p := d + "/wrap/" + f;
	p := pathcat(d, pathcat("wrap", f));
	(w.u, w.nu, w.tfull) = openupdate(p);
	if (w.nu < 0) {
		closewrap(w);
		return nil;
	}
	return w;
}

closewrap(w : ref Wrapped)
{
	w = nil;
}

openwraphdr(f : string, d : string, argl : list of string, all : int) : ref Wrapped
{
	argl = nil;
	(ok, dir) := sys->stat(f);
	if (ok < 0 || dir.mode & Sys->DMDIR)
		return openwrap(f, d, all);
	(nf, fd) := arch->openarchgz(f);
	if (nf != nil) {
		gzfile = nf;
		f = nf;
		gzfd = fd;
	}
	return openwrap(f, "/mnt/wrap", all);
}

openwrap(f : string, d : string, all : int) : ref Wrapped
{
	if (d == nil)
		d = "/";
	if((w := openmount(f, d)) != nil)
		return w;		# don't mess about if /wrap/ structure exists
	(ok, dir) := sys->stat(f);
	if (ok < 0)
		return nil;
	# accept root/ or root/wrap/pkgname
	if (dir.mode & Sys->DMDIR) {
		d = f;
		if ((i := strstr(f, "/wrap/")) >= 0) {
			f = f[i+6:];
			d = d[0:i+6];
		}
		else
			f = nil;
		return openmount(f, d);
	}
	(ok, dir) = sys->stat(f);
	if (ok < 0 || dir.mode & Sys->DMDIR)
		return openmount(f, d);		# ?
	if (mountarch(f, d, all) < 0)
		return nil;
	return openmount(nil, d);
}

getfirstdir(d : string) : string
{
	if ((fd := sys->open(d, Sys->OREAD)) == nil)
		return nil;
	for(;;){
		(n, dir) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i:=0; i<n; i++)
			if(dir[i].mode & Sys->DMDIR)
				return dir[i].name;
	}
	return nil;
}

NONE : con 0;

sniffdir(base : string, elem : string) : (int, int)
{
	# t := int elem;
	t := string2now(elem, 0);
	if (t == 0)
		return (NONE, 0);
	# buf := sys->sprint("%ud", t);
	# if (buf != elem)
	#	return (NONE, 0);
	rv := NONE;
	p := base + "/" + elem + "/package";
	(ok, nil) := sys->stat(p);
	if (ok >= 0)
		rv |= FULL;
	p = base + "/" + elem + "/update";
	(ok, nil) = sys->stat(p);
	if (ok >= 0)
		rv |= UPD;
	return (rv, t);
}

openupdate(d : string) : (array of Update, int, int)
{
	u : array of Update;

	if ((fd := sys->open(d, Sys->OREAD)) == nil)
		return (nil, -1, 0);
	#
	# We are looking to find the most recent full
	# package; anything before that is irrelevant.
	# Also figure out the most recent package update.
	# Non-package updates before that are irrelevant.
	# If there are no packages installed, 
	# grab all the updates we can find.
	#
	tbase := -1;
	tfull := -1;
	nu := 0;
	for(;;){
		(n, dir) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++){
			(k, t) := sniffdir(d, dir[i].name);
			case (k) {
				FULL =>
					nu++;
					if (t > tfull)
						tfull = t;
					if (t > tbase)
						tbase = t;
				FULL|UPD =>
					nu++;
					if (t > tfull)
						tfull = t;
				UPD =>
					nu++;
			}
		}
	}
	if (nu == 0)
		return (nil, -1, 0);
	u = nil;
	nu = 0;
	if ((fd = sys->open(d, Sys->OREAD)) == nil)
		return (nil, -1, 0);
	for(;;){
		(n, dir) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++){
			(k, t) := sniffdir(d, dir[i].name);
			if (k == 0)
				continue;
			if (t < tbase)
				continue;
			if (t < tfull && k == UPD)
				continue;
			if (nu%8 == 0) {
				newu := array[nu+8] of Update;
				newu[0:] = u[0:nu];
				u = newu;
			}
			u[nu].typ = k;
			if (readupdate(u, nu, d, dir[i].name) != nil)
				nu++;
		}
	}
	if (nu == 0)
		return (nil, -1, 0);
	qsort(u, nu);
	return (u, nu, tfull);
}

readupdate(u : array of Update, ui : int, base : string, elem : string) : array of Update
{
	# u[ui].dir = base + "/" + elem;
	u[ui].dir = pathcat(base, elem);
	p := u[ui].dir + "/desc";
	u[ui].desc = readfile(p);
	# u[ui].time = int elem;
	u[ui].time = string2now(elem, 0);
	p = u[ui].dir + "/md5sum";
	u[ui].bmd5 = bufio->open(p, Bufio->OREAD);
	p = u[ui].dir + "/update";
	q := readfile(p);
	if (q != nil)
		u[ui].utime = int q;
	else
		u[ui].utime = 0;
	if (u[ui].bmd5 == nil)
		return nil;
	return u;
}

readfile(s : string) : string
{
	(ok, d) := sys->stat(s);
	if (ok < 0)
		return nil;
	buf := array[int d.length] of byte;
	if ((fd := sys->open(s, Sys->OREAD)) == nil || sys->read(fd, buf, int d.length) != int d.length)
		return nil;
	s = string buf;
	ls := len s;
	if (s[ls-1] == '\n')
		s = s[0:ls-1];
	return s;
}
	
hex(c : int) : int
{
	if (c >= '0' && c <= '9')
		return c-'0';
	if (c >= 'a' && c <= 'f')
		return c-'a'+10;
	if (c >= 'A' && c <= 'F')
		return c-'A'+10;
	return -1;
}

getfileinfo(w : ref Wrapped, f : string, rdigest : array of byte, wdigest : array of byte, ardigest: array of byte) : (int, int)
{
	p : string;

	if (w == nil)
		return (-1, 0);
	digest := array[keyring->MD5dlen] of { * => byte 0 };
	for (i := w.nu-1; i >= 0; i--){
		if ((p = bsearch(w.u[i].bmd5, f)) == nil)
			continue;
		if (p == nil)
			continue;
		k := 0;
		while (k < len p && p[k] != ' ')
			k++;
		if (k == len p)
			continue;
		q := p[k+1:];
		if (q == nil)
			continue;
		if (len q != 2*Keyring->MD5dlen+1)
			continue;
		for (j := 0; j < Keyring->MD5dlen; j++) {
			a := hex(q[2*j]);
			b := hex(q[2*j+1]);
			if (a < 0 || b < 0)
				break;
			digest[j] = byte ((a<<4)|b);
		}
		if(j != Keyring->MD5dlen)
			continue;
		if(rdigest == nil || memcmp(rdigest, digest, keyring->MD5dlen) == 0 || (ardigest != nil && memcmp(ardigest, digest, keyring->MD5dlen) == 0))
			break;
		else
			return (-1, 0);	# NEW
	}
	if(i < 0)
		return (-1, 0);
	if(wdigest != nil)
		wdigest[0:] = rdigest;
	return (0, w.u[i].time);
		
	
}

bsearch(b : ref Bufio->Iobuf, p : string) : string
{
	if (b == nil)
		return nil;
	lo := 0;
	b.seek(big 0, Bufio->SEEKEND);
	hi := int b.offset();
	l := len p;
	while (lo < hi) {
		m := (lo+hi)/2;
		b.seek(big m, Bufio->SEEKSTART);
		b.gets('\n');
		if (int b.offset() == hi) {
			bgetbackc(b);
			m = int b.offset();
			while (m-- > lo) {
				if (bgetbackc(b) == '\n') {
					b.getc();
					break;
				}
			}
		}
		s := b.gets('\n');
		if (len s >= l+1 && s[0:l] == p && (s[l] == ' ' || s[l] == '\n'))
			return s;
		if (s < p)
			lo = int b.offset();
		else
			hi = int b.offset()-len s;
	}
	return nil;
}

bgetbackc(b : ref Bufio->Iobuf) : int
{
	m := int b.offset();
	b.seek(big (m-1), Bufio->SEEKSTART);
	c := b.getc();
	b.ungetc();
	return c;
}

strstr(s : string, p : string) : int
{
	lp := len p;
	ls := len s;
	for (i := 0; i < ls-lp; i++)
		if (s[i:i+lp] == p)
			return i;
	return -1;
}

qsort(a : array of Update, n : int)
{
	i, j : int;
	t : Update;

	while(n > 1) {
		i = n>>1;
		t = a[0]; a[0] = a[i]; a[i] = t;
		i = 0;
		j = n;
		for(;;) {
			do
				i++;
			while(i < n && a[i].time < a[0].time);
			do
				j--;
			while(j > 0 && a[j].time > a[0].time);
			if(j < i)
				break;
			t = a[i]; a[i] = a[j]; a[j] = t;
		}
		t = a[0]; a[0] = a[j]; a[j] = t;
		n = n-j-1;
		if(j >= n) {
			qsort(a, j);
			a = a[j+1:];
		} else {
			qsort(a[j+1:], n);
			n = j;
		}
	}
}

md5file(file : string, digest : array of byte) : int
{
	(ok, d) := sys->stat(file);
	if (ok < 0)
		return -1;
	if (d.mode & Sys->DMDIR)
		return 0;
	bio := bufio->open(file, Bufio->OREAD);
	if (bio == nil)
		return -1;
	# return md5sum(bio, digest, d.length);
	buff := array[Sys->ATOMICIO] of byte;
	ds := keyring->md5(nil, 0, nil, nil);
	while ((n := bio.read(buff, len buff)) > 0)
		keyring->md5(buff, n, nil, ds);
	keyring->md5(nil, 0, digest, ds);
	bio = nil;
	return 0;
}

md5sum(b : ref Iobuf, digest : array of byte, leng : int) : int
{
	ds := keyring->md5(nil, 0, nil, nil);
	buff := array[Sys->ATOMICIO] of byte;
	while (leng > 0) {
		if (leng > len buff)
			n := len buff;
		else
			n = leng;
		if ((n = b.read(buff, n)) <= 0)
			return -1;
		keyring->md5(buff, n, nil, ds);
		leng -= n;
	}
	keyring->md5(nil, 0, digest, ds);
	return 0;
}
		
md5conv(d : array of byte) : string
{
	s : string = nil;

	for (i := 0; i < keyring->MD5dlen; i++)
		s += sys->sprint("%.2ux", int d[i]);
	return s;
}	

zd : Sys->Dir;

newd(time : int, uid : string, gid : string) : ref Sys->Dir
{
	d := ref Sys->Dir;
	*d = zd;
	d.uid = uid;
	d.gid = gid;
	d.mtime = time;
	return d;
}

putwrapfile(b : ref Iobuf, name : string, time : int, elem : string, file : string, uid : string, gid : string)
{
	d := newd(time, uid, gid);
	d.mode = 8r444;
	(ok, dir) := sys->stat(file);
	if (ok < 0)
		sys->fprint(sys->fildes(2), "cannot stat %s: %r", file);
	d.length = dir.length;
	# s := "/wrap/"+name+"/"+sys->sprint("%ud", time)+"/"+elem;
	s := "/wrap/"+name+"/"+now2string(time, 0)+"/"+elem;
	arch->puthdr(b, s, d);
	arch->putfile(b, file, int d.length);
}

putwrap(b : ref Iobuf, name : string, time : int, desc : string, utime : int, pkg : int, uid : string, gid : string)
{
	if (!(utime || pkg))
		sys->fprint(sys->fildes(2), "bad precondition in putwrap()");
	d := newd(time, uid, gid);
	d.mode = Sys->DMDIR|8r775;
	s := "/wrap";
	arch->puthdr(b, s, d);
	s += "/"+name;
	arch->puthdr(b, s, d);
	# s += "/"+sys->sprint("%ud", time);
	s += "/"+now2string(time, 0);
	arch->puthdr(b, s, d);
	d.mode = 8r444;
	s += "/";
	dir := s;
	if (utime) {
		s = dir+"update";
		d.length = big 23;
		arch->puthdr(b, s, d);
		arch->putstring(b, sys->sprint("%22ud\n", utime));
	}
	if (pkg) {
		s = dir+"package";
		d.length = big 0;
		arch->puthdr(b, s, d);
	}
	if (desc != nil) {
		s = dir+"desc";
		d.length = big (len desc+1);
		d.mode = 8r444;
		arch->puthdr(b, s, d);
		arch->putstring(b, desc+"\n");
	}
}

memcmp(b1, b2 : array of byte, n : int) : int
{
	for (i := 0; i < n; i++)
		if (b1[i] < b2[i])
			return -1;
		else if (b1[i] > b2[i])
			return 1;
	return 0;
}

strprefix(s: string, pre: string): int
{
	return len s >= (l := len pre) && s[0:l] == pre;
}

match(s: string, pre: list of string): int
{
	if(pre == nil || s == "/wrap" || strprefix(s, "/wrap/"))
		return 1;
	for( ; pre != nil; pre = tl pre)
		if(strprefix(s, hd pre))
			return 1;
	return 0;
}

notmatch(s: string, pre: list of string): int
{
	if(pre == nil || s == "/wrap" || strprefix(s, "/wrap/"))
		return 1;
	for( ; pre != nil; pre = tl pre)
		if(strprefix(s, hd pre))
			return 0;
	return 1;
}

pathcat(s : string, t : string) : string
{
	if (s == nil) return t;
	if (t == nil) return s;
	slashs := s[len s - 1] == '/';
	slasht := t[0] == '/';
	if (slashs && slasht)
		return s + t[1:];
	if (!slashs && !slasht)
		return s + "/" + t;
	return s + t;
}

md5filea(file : string, digest : array of byte) : int
{
	n, n0: int;

	(ok, d) := sys->stat(file);
	if (ok < 0)
		return -1;
	if (d.mode & Sys->DMDIR)
		return 0;
	bio := bufio->open(file, Bufio->OREAD);
	if (bio == nil)
		return -1;
	buff := array[Sys->ATOMICIO] of byte;
	m := len buff;
	ds := keyring->md5(nil, 0, nil, nil);
	r := 0;
	while(1){
		if(r){
			if((n = bio.read(buff[1:], m-1)) <= 0)
				break;
			n++;
		}
		else{
			if ((n = bio.read(buff, m)) <= 0)
				break;
		}
		(n0, r) = remcr(buff, n);
		if(r){
			keyring->md5(buff, n0-1, nil, ds);
			buff[0] = byte '\r';
		}
		else
			keyring->md5(buff, n0, nil, ds);
	}
	if(r)
		keyring->md5(buff, 1, nil, ds);
	keyring->md5(nil, 0, digest, ds);
	bio = nil;
	return 0;
}

remcr(b: array of byte, n: int): (int, int)
{
	if(n == 0)
		return (0, 0);
	for(i := 0; i < n; ){
		if(b[i] == byte '\r' && i+1 < n && b[i+1] == byte '\n')
			b[i:] = b[i+1:n--];
		else
			i++;
	}
	return (n, b[n-1] == byte '\r');
}

TEN2EIGHT: con 100000000;

now2string(n: int, flag: int): string
{
	if(flag == 0)
		return sys->sprint("%ud", n);
	if(n < 0)
		return nil;
	q := n/TEN2EIGHT;
	s := "0" +  string (n-TEN2EIGHT*q);
	while(len s < 9)
		s = "0" + s;
	if(q <= 9)
		s[0] = '0' + q - 0;
	else if(q <= 21)
		s[0] = 'A' + q - 10;
	else
		return nil;
	return s;
}

string2now(s: string, flag: int): int
{
	if(flag == 0 && s[0] != 'A')
		return int s;
	if(len s != 9)
		return 0;
	r := int s[1: ];
	c := s[0];
	if(c >= '0' && c <= '9')
		q := c - '0' + 0;
	else if(c >= 'A' && c <= 'L')
		q = c - 'A' + 10;
	else
		return 0;
	n := TEN2EIGHT*q + r;
	if(n < 0)
		return 0;
	return n;
}
