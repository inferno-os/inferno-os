implement RegPoll;

include "sys.m";
	sys : Sys;
include "draw.m";
include "registries.m";
	registries: Registries;
	Attributes, Service: import registries;

RegPoll: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (sys == nil)
		badmod(Sys->PATH);
	registries = load Registries Registries->PATH;
	if (registries == nil)
		badmod(Registries->PATH);
	registries->init();
	
	if (len argv != 3)
		usage();

	regaddr := hd tl argv;
	action := hd tl tl argv;
	if (action != "up" && action != "down")
		usage();

	sys->pctl(sys->FORKNS, nil);
	sys->unmount(nil, "/mnt/registry");
	svc := ref Service(hd tl argv, Attributes.new(("auth", "none") :: nil));
	for (;;) {
		a := svc.attach(nil, nil);
		if (a != nil && sys->mount(a.fd, nil, "/mnt/registry", Sys->MREPL, nil) != -1) {
			if (action == "up")
				return;
			else
				break;
		}
		sys->sleep(30000);
	}
	for (;;) {
		fd := sys->open("/mnt/registry/new", sys->OREAD);
		sys->sleep(30000);
		if (fd == nil)
			return;
	}
}

badmod(path: string)
{
	sys->print("RegPoll: failed to load: %s\n",path);
	exit;
}

usage()
{
	sys->print("usage: regpoll regaddr up | down\n");
	raise "fail:usage";
}