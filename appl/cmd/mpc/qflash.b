implement Writeflash;

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

Writeflash: module
{
	init:	fn(nil: ref Draw->Context, args: list of string);
};

Region: adt {
	base:	int;
	limit:	int;
};

# could come from file or #F/flash/flashctl
FLASHSEG: con 256*1024;
kernelregion := Region(FLASHSEG, FLASHSEG+2*FLASHSEG);
bootregion := Region(0, FLASHSEG);

stderr: ref Sys->FD;
prog := "qflash";
damaged := 0;

usage()
{
	sys->fprint(stderr, "Usage: %s [-b] [-o offset] [-f flashdev] file\n", prog);
	exit;
}

err(s: string)
{
	sys->fprint(stderr, "%s: %s", prog, s);
	if(!damaged)
		sys->fprint(stderr, "; flash not modified\n");
	else
		sys->fprint(stderr, "; flash might now be invalid\n");
	exit;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);
	if(args != nil){
		prog = hd args;
		args = tl args;
	}
	str = load String String->PATH;
	if(str == nil)
		err(sys->sprint("can't load %s: %r", String->PATH));
	region := kernelregion;
	flash := "#F/flash/flash";
	offset := 0;
	save := 0;
	
	for(; args != nil && (hd args)[0] == '-'; args = tl args)
		case hd args {
		"-b" =>
			region = bootregion;
			offset = 16r100 - 8*4;	# size of exec header
			save = 1;
		"-h" =>
			region.limit += FLASHSEG;
		"-f" =>
			if(tl args == nil)
				usage();
			flash = hd args;
			args = tl args;
		"-o" =>
			if(tl args == nil)
				usage();
			args = tl args;
			s := hd args;
			v: int;
			rs: string;
			if(str->prefix("16r", s))
				(v, rs) = str->toint(s[3:], 16);
			else if(str->prefix("0x", s))
				(v, rs) = str->toint(s[2:], 16);
			else if(str->prefix("0", s))
				(v, rs) = str->toint(s[1:], 8);
			else
				(v, rs) = str->toint(s, 10);
			if(v < 0 || len rs != 0)
				err(sys->sprint("bad offset: %s", s));
			offset = v;
		"-s" =>
			save = 1;
		* =>
			usage();
		}
	if(args == nil)
		usage();
	fname := hd args;
	fd := sys->open(fname, Sys->OREAD);
	if(fd == nil)
		err(sys->sprint("can't open %s: %r", fname));
	(r, dir) := sys->fstat(fd);
	if(r < 0)
		err(sys->sprint("can't stat %s: %r", fname));
	length := int dir.length;
	avail := region.limit - (region.base+offset);
	if(length > avail)
		err(sys->sprint("%s contents %ud bytes, exceeds flash region %ud bytes", fname, length, avail));
	# check fname's contents...
	where := region.base+offset;
	saved: list of (int, array of byte);
	if(save){
		saved = saveflash(flash, region.base, where) :: saved;
		saved = saveflash(flash, where+length, region.limit) :: saved;
	}
	for(i := (region.base+offset)/FLASHSEG; i < region.limit/FLASHSEG; i++)
		erase(flash, i);
	out := sys->open(flash, Sys->OWRITE);
	if(out == nil)
		err(sys->sprint("can't open %s for writing: %r", flash));
	if(sys->seek(out, big where, 0) != big where)
		err(sys->sprint("can't seek to #%6.6ux on flash: %r", where));
	if(length)
		sys->print("writing %ud bytes to %s at #%6.6ux\n", length, flash, where);
	buf := array[Sys->ATOMICIO] of byte;
	total := 0;
	while((n := sys->read(fd, buf, len buf)) > 0) {
		if(total+n > avail)
			err(sys->sprint("file %s too big for region of %ud bytes", fname, avail));
		r = sys->write(out, buf, n);
		damaged = 1;
		if(r != n){
			if(r < 0)
				err(sys->sprint("error writing %s at byte %ud: %r", flash, total));
			else
				err(sys->sprint("short write on %s at byte %ud", flash, total));
		}
		total += n;
	}
	if(n < 0)
		err(sys->sprint("error reading %s: %r", fname));
	sys->print("wrote %ud bytes from %s to flash %s (#%6.6ux-#%6.6ux)\n", total, fname, flash, region.base, region.base+total);
	for(l := saved; l != nil; l = tl l){
		(addr, data) := hd l;
		n = len data;
		if(n == 0)
			continue;
		sys->print("restoring %ud bytes at #%6.6ux\n", n, addr);
		if(sys->seek(out, big addr, 0) != big addr)
			err(sys->sprint("can't seek to #%6.6ux on %s: %r", addr, flash));
		r = sys->write(out, data, n);
		if(r < 0)
			err(sys->sprint("error writing %s: %r", flash));
		else if(r != n)
			err(sys->sprint("short write on %s at byte %ud/%ud", flash, r, n));
		else
			sys->print("restored %ud bytes at #%6.6ux\n", n, addr);
	}
}

erase(flash: string, seg: int)
{
	ctl := sys->open(flash+"ctl", Sys->OWRITE);
	if(ctl == nil)
		err(sys->sprint("can't open %sctl: %r\n", flash));
	if(sys->fprint(ctl, "erase %ud", seg*FLASHSEG) < 0)
		err(sys->sprint("can't erase flash %s segment %d: %r\n", flash, seg));
}

saveflash(flash: string, base: int, limit: int): (int, array of byte)
{
	fd := sys->open(flash, Sys->OREAD);
	if(fd == nil)
		err(sys->sprint("can't open %s for reading: %r", flash));
	nb := limit - base;
	if(nb <= 0)
		return (base, nil);
	if(sys->seek(fd, big base, 0) != big base)
		err(sys->sprint("can't seek to #%6.6ux to save flash contents: %r", base));
	saved := array[nb] of byte;
	if(sys->read(fd, saved, len saved) != len saved)
		err(sys->sprint("can't read flash #%6.6ux to #%6.6ux: %r", base, limit));
	sys->print("saved %ud bytes at #%6.6ux\n", len saved, base);
	return (base, saved);
}
