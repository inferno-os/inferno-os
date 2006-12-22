implement MD5sum;

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

MD5sum: module
{
	init: fn(nil : ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	kr = load Keyring Keyring->PATH;
	a := tl argv;
	err := 0;
	if(a != nil){
		for( ; a != nil; a = tl a) {
			s := hd a;
			fd := sys->open(s, Sys->OREAD);
			if (fd == nil) {
				sys->fprint(stderr, "md5sum: cannot open %s: %r\n", s);
				err = 1;
			} else
				err |= md5sum(fd, s);
		}
	} else
		err |= md5sum(sys->fildes(0), "");
	if(err)
		raise "fail:error";
}

md5sum(fd: ref Sys->FD, file: string): int
{
	err := 0;
	buf := array[Sys->ATOMICIO] of byte;
	state: ref Keyring->DigestState = nil;
	nbytes := big 0;
	while((nr := sys->read(fd, buf, len buf)) > 0){
		state = kr->md5(buf, nr, nil, state);
		nbytes += big nr;
	}
	if(nr < 0) {
		sys->fprint(stderr, "md5sum: error reading %s: %r\n", file);
		err = 1;
	}
	digest := array[Keyring->MD5dlen] of byte;
	kr->md5(buf, 0, digest, state);
	sum := "";
	for(i:=0; i<len digest; i++)
		sum += sys->sprint("%2.2ux", int digest[i]);
	if(file != nil)
		sys->print("%s\t%s\n", sum, file);
	else
		sys->print("%s\n", sum);
	return err;
}
