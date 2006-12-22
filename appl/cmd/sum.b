implement Sum;

include "sys.m";
include "draw.m";
include "crc.m";

Sum : module
{
	init : fn(nil : ref Draw->Context, argv : list of string);
};

init(nil : ref Draw->Context, argv : list of string)
{
	sys := load Sys Sys->PATH;
	stderr := sys->fildes(2);
	crcm := load Crc Crc->PATH;
	crcs := crcm->init(0, 0);
	a := tl argv;
	buf := array[Sys->ATOMICIO] of byte;
	err := 0;
	for ( ; a != nil; a = tl a) {
		s := hd a;
		(ok, d) := sys->stat(s);
		if (ok < 0) {
			sys->fprint(stderr, "sum: cannot get status of %s: %r\n", s);
			err = 1;
			continue;
		}
		if (d.mode & Sys->DMDIR)
			continue;
		fd := sys->open(s, Sys->OREAD);
		if (fd == nil) {
			sys->fprint(stderr, "sum: cannot open %s: %r\n", s);
			err = 1;
			continue;
		}
		crc := 0;
		nbytes := big 0;
		while((nr := sys->read(fd, buf, len buf)) > 0){
			crc = crcm->crc(crcs, buf, nr);
			nbytes += big nr;
		}
		if(nr < 0) {
			sys->fprint(stderr, "sum: error reading %s: %r\n", s);
			err = 1;
		}
		# encode the length but make n==0 not 0
		l := int (nbytes & big 16rFFFFFFFF);
		buf[0] = byte((l>>24)^16rCC);
		buf[1] = byte((l>>16)^16r55);
		buf[2] = byte((l>>8)^16rCC);
		buf[3] = byte(l^16r55);
		crc = crcm->crc(crcs, buf, 4);
		sys->print("%.8ux %6bd %s\n", crc, nbytes, s);
		crcm->reset(crcs);
	}
	if(err)
		raise "fail:error";
}
