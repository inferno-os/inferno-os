implement Mc9p;

#
# mc9p - 9P-based MCP alternative where filesystem IS schema
#
# Design: Each domain is a directory, each endpoint is a file.
# Write request to file, read response from file.
#
# Example:
#   echo "https://example.com" > /n/mcp/http/get
#   cat /n/mcp/http/get  -> HTTP response body
#
# Filesystem structure:
#   /n/mcp/
#   ├── _meta/
#   │   ├── name        -> provider name
#   │   ├── version     -> version string
#   │   └── caps        -> enabled domains
#   ├── http/           <- HTTP domain
#   │   ├── get         -> write URL, read response
#   │   ├── post        -> write "URL\nbody", read response
#   │   └── headers     -> current headers
#   └── fs/             <- Filesystem domain
#       ├── read        -> write path, read content
#       └── list        -> write path, read entries
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";

include "arg.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Fid, Styxserver, Navigator, Navop: import styxservers;
	Enotfound, Eperm, Ebadarg: import styxservers;

include "string.m";
	str: String;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "tls.m";
	tlsmod: TLS;
	Conn: import tlsmod;

Mc9p: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

# Qid types for synthetic files
Qroot: con 0;
Qmeta: con 1;
Qmetaname: con 2;
Qmetaversion: con 3;
Qmetacaps: con 4;

# Domain directories start at 100
Qdomainbase: con 100;
# Endpoints start at 1000
Qendpointbase: con 1000;

# Endpoint state (per-fid)
EndpointState: adt {
	request:  array of byte;
	response: array of byte;
};

# Endpoint info
EndpointInfo: adt {
	name:   string;
	domain: string;
	qid:    int;
	state:  ref EndpointState;
};

# Domain info
DomainInfo: adt {
	name:      string;
	qid:       int;
	endpoints: list of ref EndpointInfo;
};

stderr: ref Sys->FD;
user: string;
domains: list of ref DomainInfo;
providername := "mc9p";
providerversion := "1.0";
mountpt := "/n/mcp";
hasnet := 0;

nomod(s: string)
{
	sys->fprint(stderr, "mc9p: can't load %s: %r\n", s);
	raise "fail:load";
}

usage()
{
	sys->fprint(stderr, "Usage: mc9p [-D] [-m mountpoint] [-n] domain [domain ...]\n");
	sys->fprint(stderr, "  -D            Enable 9P debug tracing\n");
	sys->fprint(stderr, "  -m mountpoint Mount point (default: /n/mcp)\n");
	sys->fprint(stderr, "  -n            Enable network access (for http domain)\n");
	sys->fprint(stderr, "\n");
	sys->fprint(stderr, "Available domains:\n");
	sys->fprint(stderr, "  http  - HTTP client (get, post, headers)\n");
	sys->fprint(stderr, "  fs    - Filesystem access (read, list)\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	styx = load Styx Styx->PATH;
	if(styx == nil)
		nomod(Styx->PATH);
	styx->init();

	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		nomod(Styxservers->PATH);
	styxservers->init(styx);

	str = load String String->PATH;
	if(str == nil)
		nomod(String->PATH);

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		nomod(Bufio->PATH);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);

	while((o := arg->opt()) != 0)
		case o {
		'D' =>	styxservers->traceset(1);
		'm' =>	mountpt = arg->earg();
		'n' =>	hasnet = 1;
		* =>	usage();
		}
	args = arg->argv();
	arg = nil;

	if(args == nil)
		usage();

	# Build domain registry
	initdomains(args);

	if(domains == nil) {
		sys->fprint(stderr, "mc9p: no valid domains specified\n");
		raise "fail:no domains";
	}

	sys->pctl(Sys->FORKFD, nil);

	user = rf("/dev/user");
	if(user == nil)
		user = "inferno";

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0) {
		sys->fprint(stderr, "mc9p: can't create pipe: %r\n");
		raise "fail:pipe";
	}

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	fds[0] = nil;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops);
	<-pidc;

	# Ensure mount point exists
	ensuredir(mountpt);

	if(sys->mount(fds[1], nil, mountpt, Sys->MREPL|Sys->MCREATE, nil) < 0) {
		sys->fprint(stderr, "mc9p: mount failed: %r\n");
		raise "fail:mount";
	}
}

# Initialize domains from argument list
initdomains(args: list of string)
{
	domains = nil;
	domqid := Qdomainbase;
	epqid := Qendpointbase;

	for(; args != nil; args = tl args) {
		name := str->tolower(hd args);
		eps := domainendpoints(name);
		if(eps == nil) {
			sys->fprint(stderr, "mc9p: unknown domain '%s', skipping\n", name);
			continue;
		}

		# Check for duplicates
		if(finddomain(name) != nil)
			continue;

		# Create endpoint list
		eplist: list of ref EndpointInfo;
		for(; eps != nil; eps = tl eps) {
			epname := hd eps;
			ep := ref EndpointInfo(epname, name, epqid, ref EndpointState(nil, nil));
			eplist = ep :: eplist;
			epqid++;
		}

		# Reverse to maintain order
		reveps: list of ref EndpointInfo;
		for(e := eplist; e != nil; e = tl e)
			reveps = hd e :: reveps;

		di := ref DomainInfo(name, domqid, reveps);
		domains = di :: domains;
		domqid++;
	}

	# Reverse to maintain argument order
	rev: list of ref DomainInfo;
	for(d := domains; d != nil; d = tl d)
		rev = hd d :: rev;
	domains = rev;
}

# Get endpoints for a domain
domainendpoints(name: string): list of string
{
	case name {
	"http" =>
		return "get" :: "post" :: "headers" :: nil;
	"fs" =>
		return "read" :: "list" :: "stat" :: nil;
	}
	return nil;
}

# Find domain by name
finddomain(name: string): ref DomainInfo
{
	for(d := domains; d != nil; d = tl d) {
		if((hd d).name == name)
			return hd d;
	}
	return nil;
}

# Find domain by qid
finddomainbyqid(qid: int): ref DomainInfo
{
	for(d := domains; d != nil; d = tl d) {
		if((hd d).qid == qid)
			return hd d;
	}
	return nil;
}

# Find endpoint by qid
findendpointbyqid(qid: int): ref EndpointInfo
{
	for(d := domains; d != nil; d = tl d) {
		for(e := (hd d).endpoints; e != nil; e = tl e) {
			if((hd e).qid == qid)
				return hd e;
		}
	}
	return nil;
}

# Generate capabilities list
gencapslist(): string
{
	result := "";
	for(d := domains; d != nil; d = tl d) {
		if(result != "")
			result += "\n";
		result += (hd d).name;
	}
	return result;
}

rf(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, b, len b);
	if(n < 0)
		return nil;
	return string b[0:n];
}

ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil) {
		fd = nil;
		return;
	}
	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
	if(fd != nil)
		fd = nil;
}

# Navigator for directory structure
navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil) {
		pick n := m {
		Stat =>
			n.reply <-= dirgen(int n.path);
		Walk =>
			walkto(n);
		Readdir =>
			readdir(n, int n.path);
		}
	}
}

# Walk to a name within a directory
walkto(n: ref Navop.Walk)
{
	parent := int n.path;

	case parent {
	Qroot =>
		if(n.name == "_meta") {
			n.path = big Qmeta;
			n.reply <-= dirgen(int n.path);
			return;
		}
		# Check domains
		di := finddomain(n.name);
		if(di != nil) {
			n.path = big di.qid;
			n.reply <-= dirgen(int n.path);
			return;
		}
		n.reply <-= (nil, Enotfound);

	Qmeta =>
		case n.name {
		"name" =>
			n.path = big Qmetaname;
			n.reply <-= dirgen(int n.path);
		"version" =>
			n.path = big Qmetaversion;
			n.reply <-= dirgen(int n.path);
		"caps" =>
			n.path = big Qmetacaps;
			n.reply <-= dirgen(int n.path);
		* =>
			n.reply <-= (nil, Enotfound);
		}

	* =>
		# Walking within a domain directory
		if(parent >= Qdomainbase && parent < Qendpointbase) {
			di := finddomainbyqid(parent);
			if(di != nil) {
				for(e := di.endpoints; e != nil; e = tl e) {
					if((hd e).name == n.name) {
						n.path = big (hd e).qid;
						n.reply <-= dirgen(int n.path);
						return;
					}
				}
			}
		}
		n.reply <-= (nil, Enotfound);
	}
}

# Generate directory entry for a path
dirgen(path: int): (ref Sys->Dir, string)
{
	d := ref sys->zerodir;
	d.uid = user;
	d.gid = user;
	d.muid = user;
	d.atime = 0;
	d.mtime = 0;

	case path {
	Qroot =>
		d.name = ".";
		d.mode = Sys->DMDIR | 8r555;
		d.qid.qtype = Sys->QTDIR;
	Qmeta =>
		d.name = "_meta";
		d.mode = Sys->DMDIR | 8r555;
		d.qid.qtype = Sys->QTDIR;
	Qmetaname =>
		d.name = "name";
		d.mode = 8r444;
		d.length = big len providername;
	Qmetaversion =>
		d.name = "version";
		d.mode = 8r444;
		d.length = big len providerversion;
	Qmetacaps =>
		d.name = "caps";
		d.mode = 8r444;
		d.length = big len gencapslist();
	* =>
		# Check if it's a domain
		if(path >= Qdomainbase && path < Qendpointbase) {
			di := finddomainbyqid(path);
			if(di != nil) {
				d.name = di.name;
				d.mode = Sys->DMDIR | 8r555;
				d.qid.qtype = Sys->QTDIR;
			} else {
				return (nil, Enotfound);
			}
		} else if(path >= Qendpointbase) {
			# It's an endpoint
			ep := findendpointbyqid(path);
			if(ep != nil) {
				d.name = ep.name;
				d.mode = 8r666;  # Read/write
				if(ep.state.response != nil)
					d.length = big len ep.state.response;
			} else {
				return (nil, Enotfound);
			}
		} else {
			return (nil, Enotfound);
		}
	}

	d.qid.path = big path;
	return (d, nil);
}


# Read directory contents
readdir(n: ref Navop.Readdir, path: int)
{
	entries: list of int;

	case path {
	Qroot =>
		# Root contains _meta and all domains
		entries = Qmeta :: nil;
		for(d := domains; d != nil; d = tl d)
			entries = (hd d).qid :: entries;
	Qmeta =>
		entries = Qmetaname :: Qmetaversion :: Qmetacaps :: nil;
	* =>
		# Domain directory contains endpoints
		if(path >= Qdomainbase && path < Qendpointbase) {
			di := finddomainbyqid(path);
			if(di != nil) {
				for(e := di.endpoints; e != nil; e = tl e)
					entries = (hd e).qid :: entries;
			}
		}
	}

	# Reverse to get original order
	rev: list of int;
	for(; entries != nil; entries = tl entries)
		rev = hd entries :: rev;

	# Generate directory entries
	for(i := 0; rev != nil; rev = tl rev) {
		if(i >= n.offset) {
			(d, err) := dirgen(hd rev);
			if(d != nil)
				n.reply <-= (d, nil);
		}
		i++;
	}
	n.reply <-= (nil, nil);
}

# Main server loop
serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int, navops: chan of ref Navop)
{
	pidc <-= sys->pctl(0, nil);

Serve:
	for(;;) {
		gm := <-tchan;
		if(gm == nil)
			break Serve;

		pick m := gm {
		Readerror =>
			break Serve;

		Read =>
			fid := srv.getfid(m.fid);
			if(fid == nil) {
				srv.reply(ref Rmsg.Error(m.tag, "bad fid"));
				continue;
			}

			path := int fid.path;
			case path {
			Qmetaname =>
				srv.reply(styxservers->readstr(m, providername));
			Qmetaversion =>
				srv.reply(styxservers->readstr(m, providerversion));
			Qmetacaps =>
				srv.reply(styxservers->readstr(m, gencapslist()));
			* =>
				if(path >= Qendpointbase) {
					ep := findendpointbyqid(path);
					if(ep != nil && ep.state.response != nil) {
						srv.reply(styxservers->readbytes(m, ep.state.response));
					} else {
						srv.reply(styxservers->readbytes(m, nil));
					}
				} else {
					srv.default(gm);
				}
			}

		Write =>
			fid := srv.getfid(m.fid);
			if(fid == nil) {
				srv.reply(ref Rmsg.Error(m.tag, "bad fid"));
				continue;
			}

			path := int fid.path;
			if(path >= Qendpointbase) {
				ep := findendpointbyqid(path);
				if(ep != nil) {
					# Store request and execute
					ep.state.request = m.data;
					ep.state.response = executeendpoint(ep);
					srv.reply(ref Rmsg.Write(m.tag, len m.data));
				} else {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
				}
			} else {
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
			}

		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;
}

# Execute an endpoint and return response
executeendpoint(ep: ref EndpointInfo): array of byte
{
	request := string ep.state.request;

	case ep.domain {
	"http" =>
		return array of byte exechttp(ep.name, request);
	"fs" =>
		return array of byte execfs(ep.name, request);
	}
	return array of byte "error: unknown domain";
}

# Execute HTTP endpoint
exechttp(endpoint, request: string): string
{
	if(!hasnet)
		return "error: network access not granted (use -n flag)";

	case endpoint {
	"get" =>
		return httpget(strip(request));
	"post" =>
		# Format: URL\nbody
		(url, body) := splitfirst(request, "\n");
		return httppost(strip(url), body);
	"headers" =>
		return "Content-Type: application/json\n";
	}
	return "error: unknown endpoint";
}

# Execute filesystem endpoint
execfs(endpoint, request: string): string
{
	path := strip(request);

	case endpoint {
	"read" =>
		return readfile(path);
	"list" =>
		return listdir(path);
	"stat" =>
		return statpath(path);
	}
	return "error: unknown endpoint";
}

# HTTP GET request
httpget(url: string): string
{
	# Simple HTTP client - requires /net access
	(scheme, host, port, path, err) := parseurl(url);
	if(err != nil)
		return "error: " + err;

	if(scheme == "https")
		return httpsget(host, port, path);

	(ok, conn) := sys->dial("tcp!" + host + "!" + port, nil);
	if(ok < 0)
		return sys->sprint("error: cannot connect to %s: %r", host);

	# Send request
	req := "GET " + path + " HTTP/1.0\r\n" +
	       "Host: " + host + "\r\n" +
	       "Connection: close\r\n" +
	       "\r\n";
	data := array of byte req;
	if(sys->write(conn.dfd, data, len data) < 0)
		return sys->sprint("error: write failed: %r");

	# Read response
	response := "";
	buf := array[8192] of byte;
	while((n := sys->read(conn.dfd, buf, len buf)) > 0)
		response += string buf[0:n];

	# Parse response
	(nil, nil, rbody) := parseresponse(response);
	return rbody;
}

# HTTP POST request
httppost(url, body: string): string
{
	(scheme, host, port, path, err) := parseurl(url);
	if(err != nil)
		return "error: " + err;

	if(scheme == "https")
		return httpspost(host, port, path, body);

	(ok, conn) := sys->dial("tcp!" + host + "!" + port, nil);
	if(ok < 0)
		return sys->sprint("error: cannot connect: %r");

	req := "POST " + path + " HTTP/1.0\r\n" +
	       "Host: " + host + "\r\n" +
	       "Content-Length: " + string len body + "\r\n" +
	       "Content-Type: application/x-www-form-urlencoded\r\n" +
	       "Connection: close\r\n" +
	       "\r\n" + body;
	data := array of byte req;
	if(sys->write(conn.dfd, data, len data) < 0)
		return sys->sprint("error: write failed: %r");

	response := "";
	buf := array[8192] of byte;
	while((n := sys->read(conn.dfd, buf, len buf)) > 0)
		response += string buf[0:n];

	(nil, nil, rbody) := parseresponse(response);
	return rbody;
}

# Load TLS module on first use
loadtls(): string
{
	if(tlsmod != nil)
		return nil;
	tlsmod = load TLS TLS->PATH;
	if(tlsmod == nil)
		return "cannot load TLS module";
	terr := tlsmod->init();
	if(terr != nil)
		return "TLS init: " + terr;
	return nil;
}

# HTTPS GET via TLS
httpsget(host, port, path: string): string
{
	lerr := loadtls();
	if(lerr != nil)
		return "error: " + lerr;

	(ok, conn) := sys->dial("tcp!" + host + "!" + port, nil);
	if(ok < 0)
		return sys->sprint("error: cannot connect to %s: %r", host);

	config := tlsmod->defaultconfig();
	config.servername = host;

	(tc, cerr) := tlsmod->client(conn.dfd, config);
	if(cerr != nil)
		return "error: TLS: " + cerr;

	req := "GET " + path + " HTTP/1.0\r\n" +
	       "Host: " + host + "\r\n" +
	       "Connection: close\r\n" +
	       "\r\n";
	data := array of byte req;
	if(tc.write(data, len data) < 0) {
		tc.close();
		return "error: TLS write failed";
	}

	response := "";
	buf := array[8192] of byte;
	while((n := tc.read(buf, len buf)) > 0)
		response += string buf[0:n];
	tc.close();

	(nil, nil, rbody) := parseresponse(response);
	return rbody;
}

# HTTPS POST via TLS
httpspost(host, port, path, body: string): string
{
	lerr := loadtls();
	if(lerr != nil)
		return "error: " + lerr;

	(ok, conn) := sys->dial("tcp!" + host + "!" + port, nil);
	if(ok < 0)
		return sys->sprint("error: cannot connect: %r");

	config := tlsmod->defaultconfig();
	config.servername = host;

	(tc, cerr) := tlsmod->client(conn.dfd, config);
	if(cerr != nil)
		return "error: TLS: " + cerr;

	req := "POST " + path + " HTTP/1.0\r\n" +
	       "Host: " + host + "\r\n" +
	       "Content-Length: " + string len body + "\r\n" +
	       "Content-Type: application/x-www-form-urlencoded\r\n" +
	       "Connection: close\r\n" +
	       "\r\n" + body;
	data := array of byte req;
	if(tc.write(data, len data) < 0) {
		tc.close();
		return "error: TLS write failed";
	}

	response := "";
	buf := array[8192] of byte;
	while((n := tc.read(buf, len buf)) > 0)
		response += string buf[0:n];
	tc.close();

	(nil, nil, rbody) := parseresponse(response);
	return rbody;
}

# Read file contents
readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", path);

	content := "";
	buf := array[8192] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0)
		content += string buf[0:n];

	return content;
}

# List directory
listdir(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r", path);

	result := "";
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			if(result != "")
				result += "\n";
			d := dirs[i];
			if(d.mode & Sys->DMDIR)
				result += d.name + "/";
			else
				result += d.name;
		}
	}
	return result;
}

# Stat a path
statpath(path: string): string
{
	(ok, d) := sys->stat(path);
	if(ok < 0)
		return sys->sprint("error: cannot stat %s: %r", path);

	typestr := "file";
	if(d.mode & Sys->DMDIR)
		typestr = "dir";

	return sys->sprint("name: %s\ntype: %s\nsize: %bd\nmode: %uo\n",
		d.name, typestr, d.length, d.mode & 8r777);
}

# Parse URL
parseurl(url: string): (string, string, string, string, string)
{
	scheme := "http";
	port := "80";
	i: int;

	if(len url > 7 && str->tolower(url[0:7]) == "http://") {
		url = url[7:];
	} else if(len url > 8 && str->tolower(url[0:8]) == "https://") {
		scheme = "https";
		port = "443";
		url = url[8:];
	} else {
		return ("", "", "", "", "invalid URL");
	}

	# Find path
	path := "/";
	for(i = 0; i < len url; i++) {
		if(url[i] == '/') {
			path = url[i:];
			url = url[0:i];
			break;
		}
	}

	# Find port
	host := url;
	for(i = 0; i < len url; i++) {
		if(url[i] == ':') {
			host = url[0:i];
			port = url[i+1:];
			break;
		}
	}

	return (scheme, host, port, path, nil);
}

# Parse HTTP response
parseresponse(response: string): (string, string, string)
{
	statusend := 0;
	for(; statusend < len response; statusend++) {
		if(response[statusend] == '\n')
			break;
	}
	if(statusend == 0)
		return ("", "", "");

	status := response[0:statusend];

	# Find headers end
	headersend := statusend + 1;
	for(; headersend < len response - 1; headersend++) {
		if(response[headersend] == '\n' &&
		   (response[headersend+1] == '\n' || response[headersend+1] == '\r'))
			break;
	}

	headers := "";
	if(headersend > statusend + 1)
		headers = response[statusend+1:headersend];

	# Find body
	bodystart := headersend + 1;
	if(bodystart < len response && response[bodystart] == '\r')
		bodystart++;
	if(bodystart < len response && response[bodystart] == '\n')
		bodystart++;

	body := "";
	if(bodystart < len response)
		body = response[bodystart:];

	return (status, headers, body);
}

# Strip whitespace
strip(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n' || s[j-1] == '\r'))
		j--;
	if(i >= j)
		return "";
	return s[i:j];
}

# Split on first occurrence of separator
splitfirst(s, sep: string): (string, string)
{
	for(i := 0; i <= len s - len sep; i++) {
		if(s[i:i+len sep] == sep)
			return (s[0:i], s[i+len sep:]);
	}
	return (s, "");
}
