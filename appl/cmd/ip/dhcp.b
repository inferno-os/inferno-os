implement Dhcp;

#
# configure an interface using DHCP
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "ip.m";
	ip: IP;
	IPv4off, IPaddrlen: import IP;
	IPaddr: import ip;
	get2, get4, put2, put4: import ip;

include "dhcp.m";
	dhcpclient: Dhcpclient;
	Bootconf, Lease: import dhcpclient;

include "arg.m";

Dhcp: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

RetryTime: con 10*1000;	# msec

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	ip = load IP IP->PATH;
	dhcpclient = load Dhcpclient Dhcpclient->PATH;

	sys->pctl(Sys->NEWFD|Sys->NEWPGRP, 0 :: 1 :: 2 :: nil);

	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("dhcp [-bdmnpr] [-g ipgw] [-h hostname] [-x /net] ifcdir [ip [ipmask]]");
	trace := 0;
	pcfg := 0;
	bootp := 0;
	monitor := 0;
	retry := 0;
	noctl := 0;
	netdir := "/net";
	cfg := Bootconf.new();
	while((o := arg->opt()) != 0)
		case o {
		'b' =>	bootp = 1;
		'd' =>	trace++;
		'g' =>	cfg.ipgw = arg->earg();
		'h' =>	cfg.puts(Dhcpclient->Ohostname, arg->earg());
		'm' =>	monitor = 1;
		'n' =>	noctl = 1;
		'p' =>	pcfg = 1;
		'r' =>		retry = 1;
		'x' =>	netdir = arg->earg();
		* =>		arg->usage();
		}
	args = arg->argv();
	if(len args == 0)
		arg->usage();

	ifcdir := hd args;
	args = tl args;
	if(args != nil){
		cfg.ip = hd args;
		args = tl args;
		if(args != nil){
			cfg.ipmask = hd args;
			args = tl args;
			if(args != nil)
				arg->usage();
		}
	}
	arg = nil;

	ifcctl: ref Sys->FD;
	if(noctl == 0){
		ifcctl = sys->open(ifcdir+"/ctl", Sys->OWRITE);
		if(ifcctl == nil)
			err(sys->sprint("cannot open %s/ctl: %r", ifcdir));
	}
	etherdir := finddev(ifcdir);
	if(etherdir == nil)
		err(sys->sprint("cannot find network device in %s/status: %r", ifcdir));
	if(etherdir[0] != '/' && etherdir[0] != '#')
		etherdir = netdir+"/"+etherdir;

	ip->init();
	dhcpclient->init();
	dhcpclient->tracing(trace);
	e: string;
	lease: ref Lease;
	for(;;){
		if(bootp){
			(cfg, e) = dhcpclient->bootp(netdir, ifcctl, etherdir+"/addr", cfg);
			if(e == nil){
				if(cfg != nil)
					dhcpclient->applycfg(netdir, ifcctl, cfg);
				if(pcfg)
					printcfg(cfg);
				break;
			}
		}else{
			(cfg, lease, e) = dhcpclient->dhcp(netdir, ifcctl, etherdir+"/addr", cfg, nil);	# last is array of int options
			if(e == nil){
				if(pcfg)
					printcfg(cfg);
				if(cfg.lease > 0 && monitor)
					leasemon(lease.configs, pcfg);
				break;
			}
		}
		if(!retry)
			err("failed to configure network: "+e);
		sys->fprint(sys->fildes(2), "dhcp: failed to configure network: %s; retrying", e);
		sys->sleep(RetryTime);
	}
}

leasemon(configs: chan of (ref Bootconf, string), pcfg: int)
{
	for(;;){
		(cfg, e) := <-configs;
		if(e != nil)
			sys->fprint(sys->fildes(2), "dhcp: %s", e);
		if(pcfg)
			printcfg(cfg);
	}
}

printcfg(cfg: ref Bootconf)
{
	sys->print("ip=%s ipmask=%s ipgw=%s iplease=%d\n", cfg.ip, cfg.ipmask, cfg.ipgw, cfg.lease);
}

finddev(ifcdir: string): string
{
	fd := sys->open(ifcdir+"/status", Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[1024] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;
	(nf, l) := sys->tokenize(string buf[0:n], " \n");
	if(nf < 2){
		sys->werrstr("unexpected format for status file");
		return nil;
	}
	return hd tl l;
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "dhcp: %s\n", s);
	raise "fail:error";
}
