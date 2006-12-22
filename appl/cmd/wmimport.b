implement Wmimport;

#
# Copyright © 2003 Vita Nuova Holdings Limited.
#

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
include "arg.m";
include "wmlib.m";
include "sh.m";

# turn wmexport namespace into a Draw->Context.
# usage: wmimport [-d /dev/draw] [-w /mnt/wm] cmd [arg...]

Wmimport: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmlib := load Wmlib Wmlib->PATH;
	wmlib->init();
	sh := load Sh Sh->PATH;
	arg := load Arg Arg->PATH;

	devdraw := "/dev";
	mntwm := "/mnt/wm";
	arg->init(argv);
	arg->setusage("wmimport [-d /dev] [-w /mnt/wm] cmd [arg...]");
	while((opt := arg->opt()) != 0){
		case opt{
		'd' =>
			devdraw = arg->earg();
		'w' =>
			mntwm = arg->earg();
		* =>
			arg->usage();
		}
	}
	argv = arg->argv();
	if(argv == nil)
		arg->usage();
	arg = nil;
	(ok, nil) := sys->stat(mntwm + "/clone");
	if(ok == -1){
		sys->fprint(sys->fildes(2), "wmimport: no wm at %s\n", mntwm);
		raise "fail:no wm";
	}
	(ctxt, err) := wmlib->importdrawcontext(devdraw, mntwm);
	if(ctxt == nil){
		sys->fprint(sys->fildes(2), "wmimport: remote connect failed; %s\n", err);
		raise "fail:error";
	}

	e := sh->run(ctxt, argv);
	if(e != nil)
		raise "fail:" + e;
}

