implement Idatest;

#
# Copyright © 2006 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "rand.m";
	rand: Rand;

include "ida.m";
	ida: Ida;
	Frag: import ida;

Idatest: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	rand = load Rand Rand->PATH;
	ida = load Ida Ida->PATH;

	rand->init(sys->pctl(0,nil));
	ida->init();

	stderr := sys->fildes(2);
	args = tl args;
	debug := 0;
	nowrite := 0;
	onlyenc := 0;
	for(; args != nil; args = tl args)
		case hd args {
		"-d" =>	debug = 1;
		"-w" =>	nowrite = 1;
		"-e" =>	onlyenc = 1;
		}
	buf := array[1024] of byte;
	while((n := sys->read(sys->fildes(0), buf, len buf)) > 0){
		frags := array[14] of ref Frag;
		for(x := 0; x < len frags; x++){
			frags[x] = f := ida->fragment(buf[0:n], 7);
			if(debug){
				for(i := 0; i < len f.enc; i++)
					sys->fprint(stderr, " %d", f.enc[i]);
				sys->fprint(stderr, "\n");
			}
		}
		if(onlyenc)
			continue;
		if(1){
			# shuffle
			for(i := 0; i < len frags; i++){
				r := rand->rand(len frags);
				if(r != i){
					t := frags[i]; frags[i] = frags[r]; frags[r] = t;
				}
			}
		}
		# recover
		(zot, err) := ida->reconstruct(frags);
		if(err != nil){
			sys->fprint(stderr, "reconstruction failed: %s\n", err);
			raise "fail:reconstruct";
		}
		if(len zot != n){
			sys->fprint(stderr, "bad length: expected %d got %d\n", n, len zot);
			raise "fail:length";
		}
		if(debug){
			for(i := 0; i < len zot; i++)
				sys->fprint(stderr, " %.2ux", int zot[i]);
			sys->fprint(stderr, "\n");
			sys->fprint(stderr, "%q\n", string zot);
		}else if(!nowrite)
			sys->write(sys->fildes(1), zot, len zot);
	}
}
