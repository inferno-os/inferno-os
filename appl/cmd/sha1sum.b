implement SHA1sum;

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

SHA1sum: module
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
				sys->fprint(stderr, "sha1sum: cannot open %s: %r\n", s);
				err = 1;
			} else
				err |= sha1sum(fd, s);
		}
	} else
		err |= sha1sum(sys->fildes(0), "");
	if(err)
		raise "fail:error";
}

sha1sum(fd: ref Sys->FD, file: string): int
{
	err := 0;
	buf := array[Sys->ATOMICIO] of byte;
	state: ref Keyring->DigestState = nil;
	nbytes := big 0;
	while((nr := sys->read(fd, buf, len buf)) > 0){
		state = kr->sha1(buf, nr, nil, state);
		nbytes += big nr;
	}
	if(nr < 0) {
		sys->fprint(stderr, "sha1sum: error reading %s: %r\n", file);
		err = 1;
	}
	digest := array[Keyring->SHA1dlen] of byte;
	kr->sha1(buf, 0, digest, state);
	sum := "";
	for(i:=0; i<len digest; i++)
		sum += sys->sprint("%2.2ux", int digest[i]);
	if(file != nil)
		sys->print("%s\t%s\n", sum, file);
	else
		sys->print("%s\n", sum);
	return err;
}
