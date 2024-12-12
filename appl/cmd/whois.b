implement Whois;

include "sys.m"; sys: Sys;
include "draw.m";
include "dial.m"; dial: Dial;
include "arg.m";

Whois: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args: list of string) {
	sys = load Sys Sys->PATH;
	dial = load Dial Dial->PATH;
	arg := load Arg Arg->PATH;

	addr := "tcp!whois.iana.org!43";
	expect_refer := 5;

	arg->init(args);
	arg->setusage("whois [-a addr] [-n] host");
	while((opt := arg->opt()) != 0) {
		case opt {
		'a' =>
			addr = dial->netmkaddr(arg->earg(), "tcp", "43");
		'n' =>
			expect_refer = 0;
		* =>
			arg->usage();
		}
	}

	args = arg->argv();
	if(len args != 1)
		arg->usage();

	host := hd args;
	fd := whois(addr, host);

	buf := array[512] of byte;
	stdout := sys->fildes(1);
	while((i := sys->read(fd, buf, len buf)) > 0) {
		if(expect_refer) {
			ls := sys->tokenize(string buf[0:i], "\n").t1;
			newaddr: string = nil;
			while(ls != nil) {
				l := hd ls;
				(n, rs) := sys->tokenize(l, " \t");
				if(n == 2 && hd rs == "refer:") {
					newaddr = dial->netmkaddr(hd tl rs, "tcp", "43");
					break;
				} else if(n == 3 && hd rs == "Whois" && hd tl rs == "Server:") {
					newaddr = dial->netmkaddr(hd tl tl rs, "tcp", "43");
					break;
				}
				ls = tl ls;
			}
			if(newaddr != nil) {
				fd = whois(newaddr, host);
				expect_refer--;
				continue;
			}
		}
		sys->write(stdout, buf, i);
	}
	if(i < 0) {
		sys->fprint(sys->fildes(2), "whois: reading info: %r\n");
		raise "fail:errors";
	}
}

whois(addr: string, host: string): ref Sys->FD
{
	sys->print("[using server %s]\n", addr);
	conn := dial->dial(addr, nil);
	if(conn == nil) {
		sys->fprint(sys->fildes(2), "whois: dialing %s: %r\n", addr);
		raise "fail:errors";
	}

	fd := conn.dfd;
	i := sys->fprint(fd, "%s\r\n", host);
	if(i != len host + 2) {
		sys->fprint(sys->fildes(2), "whois: sending name: %r\n");
		raise "fail:errors";
	}

	return fd;
}
