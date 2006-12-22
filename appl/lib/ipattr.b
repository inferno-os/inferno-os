implement IPattr;

include "sys.m";

include "bufio.m";
include "attrdb.m";
	attrdb: Attrdb;
	Db, Dbentry, Tuples: import attrdb;

include "ip.m";
	ip: IP;
	IPaddr: import ip;

include "ipattr.m";

init(m: Attrdb, ipa: IP)
{
#	sys = load Sys Sys->PATH;
	attrdb = m;
	ip = ipa;
}

dbattr(s: string): string
{
	digit := 0;
	dot := 0;
	alpha := 0;
	hex := 0;
	colon := 0;
	for(i := 0; i < len s; i++){
		case c := s[i] {
		'0' to '9' =>
			digit = 1;
		'a' to 'f' or 'A' to 'F' =>
			hex = 1;
		'.' =>
			dot = 1;
		':' =>
			colon = 1;
		* =>
			if(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '-' || c == '&')
				alpha = 1;
		}
	}
	if(alpha){
		if(dot)
			return "dom";
		return "sys";
	}
	if(colon)
		return "ip";
	if(dot){
		if(!hex)
			return "ip";
		return "dom";
	}
	return "sys";
}

findnetattr(ndb: ref Db, attr: string, val: string, rattr: string): (string, string)
{
	(matches, err) := findnetattrs(ndb, attr, val, rattr::nil);
	if(matches == nil)
		return (nil, err);
	(nil, nattr) := hd matches;
	na := hd nattr;
#{sys := load Sys Sys->PATH; sys->print("%q=%q->%q ::", attr, val, rattr);for(al:=na.pairs; al != nil; al = tl al)sys->print(" %q=%q", (hd al).attr, (hd al).val); sys->print("\n");}
	if(na.name == rattr && na.pairs != nil)
		return ((hd na.pairs).val, nil);
	return (nil, nil);
}

reverse(l: list of string): list of string
{
	rl: list of string;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

valueof(l: list of ref Netattr, attr: string): list of string
{
	rl: list of string;
	for(; l != nil; l = tl l){
		na := hd l;
		if(na.name == attr){
			for(p := na.pairs; p != nil; p = tl p)
				rl = (hd p).val :: rl;
		}
	}
	return reverse(rl);
}

netvalueof(l: list of ref Netattr, attr: string, a: IP->IPaddr): list of string
{
	rl: list of string;
	for(; l != nil; l = tl l){
		na := hd l;
		if(na.name == attr && a.mask(na.mask).eq(na.net)){
			for(p := na.pairs; p != nil; p = tl p)
				rl = (hd p).val :: rl;
		}
	}
	return reverse(rl);
}

findnetattrs(ndb: ref Db, attr: string, val: string, rattrs: list of string): (list of (IPaddr, list of ref Netattr), string)
{
	rl: list of (IPaddr, list of ref Netattr);
	if(ndb == nil)
		return (nil, "no database");
	(e, ptr) := ndb.findbyattr(nil, attr, val, "ip");
	if(e == nil){
		if(attr != "ip")
			return (nil, "ip attribute not found");
		# look for attributes associated with networks that include `a'
		(ok, a) := IPaddr.parse(val);
		if(ok < 0)
			return (nil, "invalid ip address in db");
		netattrs := mkattrlist(rattrs);
		netattributes(ndb, a, netattrs);
		rl = (a, netattrs) :: nil;
	}else{
		netattrs: list of ref Netattr;
		for(matches := e.findbyattr(attr, val, "ip"); matches != nil; matches = tl matches){
			for((nil, allip) := hd matches; allip != nil; allip = tl allip){
				ipa := (hd allip).val;
				(ok, a) := IPaddr.parse(ipa);
				if(ok < 0)
					return (nil, "invalid ip address in db");
				netattrs = mkattrlist(rattrs);
				pptr := ptr;
				pe := e;
				for(;;){
					attribute(pe, a, ip->allbits, netattrs, 1);
					(pe, pptr) = ndb.findpair(pptr, attr, val);
					if(pe == nil)
						break;
				}
				netattributes(ndb, a, netattrs);
				rl = (a, netattrs) :: rl;
			}
		}
	}
	results: list of (IPaddr, list of ref Netattr);
	for(; rl != nil; rl = tl rl)
		results = hd rl :: results;
	return (results, nil);
}

netattributes(ndb: ref Db, a: IPaddr, nas: list of ref Netattr): string
{
	e: ref Dbentry;
	ptr: ref Attrdb->Dbptr;
	for(;;){
		(e, ptr) = ndb.find(ptr, "ipnet");
		if(e == nil)
			break;
		ipaddr := e.findfirst("ip");
		if(ipaddr == nil)
			continue;
		(ok, netip) := IPaddr.parse(ipaddr);
		if(ok < 0)
			return "bad ip address in db";
		netmask: IPaddr;
		mask := e.findfirst("ipmask");
		if(mask == nil){
			if(!netip.isv4())
				continue;
			netmask = netip.classmask();
		}else{
			(ok, netmask) = IPaddr.parsemask(mask);
			if(ok < 0)
				return "bad ipmask in db";
		}
		if(a.mask(netmask).eq(netip))
			attribute(e, netip, netmask, nas, 0);
	}
	return nil;
}

attribute(e: ref Dbentry, netip: IPaddr, netmask: IPaddr, nas: list of ref Netattr, ishost: int)
{
	for(; nas != nil; nas = tl nas){
		na := hd nas;
		if(na.pairs != nil){
			if(!na.mask.mask(netmask).eq(na.mask))
				continue;
			# new one is at least as specific
		}
		matches := e.find(na.name);
		if(matches == nil){
			if(na.name != "ipmask" || ishost)
				continue;
			matches = (nil, ref Attrdb->Attr("ipmask", netmask.masktext(), 0)::nil) :: nil;
		}
		na.net = netip;
		na.mask = netmask;
		rl: list of ref Attrdb->Attr;
		for(; matches != nil; matches = tl matches){
			(nil, al) := hd matches;
			for(; al != nil; al = tl al)
				rl = hd al :: rl;
		}
		na.pairs = nil;
		for(; rl != nil; rl = tl rl)
			na.pairs = hd rl :: na.pairs;
	}
}

mkattrlist(rattrs: list of string): list of ref Netattr
{
	netattrs: list of ref Netattr;
	for(; rattrs != nil; rattrs = tl rattrs)
		netattrs = ref Netattr(hd rattrs, nil, ip->noaddr, ip->noaddr) :: netattrs;
	return netattrs;
}
