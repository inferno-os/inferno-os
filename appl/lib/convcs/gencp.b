NCHARS : con 256;
ERRCHAR : con 16rFFFD;

sys : Sys;

GenCP : module {
	init : fn (ctxt : ref Draw->Context, args : list of string);
};

init(nil : ref Draw->Context, nil : list of string)
{
	sys = load Sys Sys->PATH;
	path := sys->sprint("/lib/convcs/%s.cp", CHARSET);
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if (fd == nil) {
		sys->print("cannot create %s: %r\n", path);
		return;
	}
	s := "";
	for (i := 0; i < NCHARS; i++) {
		if (cstab[i] == -1)
			cstab[i] = ERRCHAR;
		s[i] = cstab[i];
	}
	buf := array of byte s;
	sys->write(fd, buf, len buf);
}

