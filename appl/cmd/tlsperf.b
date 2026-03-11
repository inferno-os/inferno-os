# tlsperf - headless TLS/HTTPS performance tester
# Exercises the same TLS code path as Charon's http.b without any GUI.
# Usage: tlsperf [-n count] [-i] url ...
#   -n count   repeat each URL count times (default 3)
#   -i         insecure: skip certificate verification
#
# Output columns: TCP_ms  TLS_ms  TTFB_ms  TOTAL_ms  HTTP_status  URL

implement TLSPerf;

include "sys.m";
	sys: Sys;
	FD, Connection: import sys;

include "draw.m";

include "arg.m";

include "string.m";
	S: String;

include "tls.m";

include "srv.m";

TLSPerf: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

tls: TLS;
Conn: import tls;
srv: Srv;
stderr: ref FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	S = load String String->PATH;
	arg := load Arg Arg->PATH;
	if(S == nil || arg == nil) {
		sys->fprint(stderr, "tlsperf: can't load modules\n");
		raise "fail:modules";
	}

	# Load Srv for direct hostname resolution (bypasses ndb/cs)
	srv = load Srv Srv->PATH;
	if(srv != nil)
		srv->init();

	# Bind IP networking in case the profile hasn't run (e.g. direct emu invocation)
	sys->bind("#I", "/net", sys->MAFTER);

	# Load and init TLS once up front
	tls = load TLS TLS->PATH;
	if(tls == nil) {
		sys->fprint(stderr, "tlsperf: can't load TLS: %r\n");
		raise "fail:tls";
	}
	err := tls->init();
	if(err != nil) {
		sys->fprint(stderr, "tlsperf: tls->init: %s\n", err);
		raise "fail:tls";
	}

	nrep := 3;
	insecure := 0;
	arg->init(args);
	arg->setusage("tlsperf [-n count] [-i] url ...");
	while((o := arg->opt()) != 0)
		case o {
		'n' =>
			nrep = int arg->earg();
			if(nrep < 1) nrep = 1;
		'i' =>
			insecure = 1;
		* =>
			arg->usage();
		}
	urls := arg->argv();
	if(urls == nil)
		arg->usage();
	arg = nil;

	sys->print("%-38s  %5s  %5s  %5s  %5s  %s\n",
		"URL", "TCP", "TLS", "TTFB", "TOT", "STATUS");
	sys->print("%-38s  %5s  %5s  %5s  %5s  %s\n",
		"--------------------------------------", "-----", "-----", "-----", "-----", "------");

	first := 1;
	for(ul := urls; ul != nil; ul = tl ul) {
		if(!first)
			sys->print("\n");
		first = 0;
		url := hd ul;
		for(rep := 0; rep < nrep; rep++)
			fetchurl(url, insecure);
	}
}

# Parse scheme, host, port, path out of a URL string.
parseurl(url: string): (string, string, string, string)
{
	scheme := "https";
	rest := url;

	if(S->prefix("https://", rest)) {
		scheme = "https";
		rest = rest[8:];
	} else if(S->prefix("http://", rest)) {
		scheme = "http";
		rest = rest[7:];
	}

	# Split host[:port] / path at first slash
	hostpart, path: string;
	(hostpart, path) = S->splitl(rest, "/");
	if(path == "")
		path = "/";

	# Split host : port
	host, port: string;
	(host, port) = S->splitl(hostpart, ":");
	if(port != "")
		port = port[1:];	# drop leading ':'
	else if(scheme == "https")
		port = "443";
	else
		port = "80";

	return (scheme, host, port, path);
}

fetchurl(url: string, insecure: int)
{
	(scheme, host, port, path) := parseurl(url);

	# Resolve hostname directly via Srv (no ndb/cs needed)
	dialhost := host;
	if(srv != nil) {
		addrs := srv->iph2a(host);
		if(addrs != nil)
			dialhost = hd addrs;
	}
	addr := "tcp!" + dialhost + "!" + port;

	t0 := sys->millisec();

	# TCP connect
	(rv, conn) := sys->dial(addr, nil);
	tcp_ms := sys->millisec() - t0;
	if(rv < 0) {
		label := shorturl(url);
		sys->print("%-38s  %5s  %5s  %5s  %5s  ERR tcp: %r\n",
			label, "-", "-", "-", "-");
		return;
	}

	tls_ms := 0;
	ttfb_ms := 0;
	tlsconn: ref Conn;
	fd := conn.dfd;
	errmsg := "";

	if(scheme == "https") {
		cfg := tls->defaultconfig();
		cfg.servername = host;
		if(insecure)
			cfg.insecure = 1;

		tls_t0 := sys->millisec();
		(tlsconn, errmsg) = tls->client(fd, cfg);
		tls_ms = sys->millisec() - tls_t0;
		if(errmsg != nil) {
			label := shorturl(url);
			sys->print("%-38s  %5d  %5d  %5s  %5s  ERR tls: %s\n",
				label, tcp_ms, tls_ms, "-", "-", errmsg);
			conn.dfd = nil;
			return;
		}
	}

	# Send HTTP/1.1 request
	req := "GET " + path + " HTTP/1.1\r\n" +
		"Host: " + host + "\r\n" +
		"User-Agent: Inferno/tlsperf\r\n" +
		"Accept: */*\r\n" +
		"Connection: close\r\n" +
		"\r\n";
	reqb := array of byte req;
	if(tlsconn != nil)
		tlsconn.write(reqb, len reqb);
	else
		sys->write(fd, reqb, len reqb);

	# Read until we have the status line (first \r\n)
	buf := array[8192] of byte;
	total := 0;
	status_line := "";
	for(;;) {
		n: int;
		if(tlsconn != nil)
			n = tlsconn.read(buf[total:], len buf - total);
		else
			n = sys->read(fd, buf[total:], len buf - total);
		if(n <= 0)
			break;
		if(ttfb_ms == 0)
			ttfb_ms = sys->millisec() - t0;
		total += n;
		# Scan for end of status line
		for(i := 0; i < total - 1; i++) {
			if(buf[i] == byte '\r' && buf[i+1] == byte '\n') {
				status_line = string buf[0:i];
				break;
			}
		}
		if(status_line != "" || total >= len buf)
			break;
	}

	total_ms := sys->millisec() - t0;

	if(tlsconn != nil)
		tlsconn.close();
	conn.dfd = nil;

	# Parse HTTP status code from "HTTP/1.x NNN Reason"
	http_status := "???";
	if(status_line != "") {
		# drop "HTTP/1.x "
		(nil, rest) := S->splitl(status_line, " ");
		rest = S->drop(rest, " ");
		# take the three-digit code
		(code, nil) := S->splitl(rest, " ");
		if(code != "")
			http_status = code;
	}

	label := shorturl(url);
	sys->print("%-38s  %5d  %5d  %5d  %5d  HTTP %s\n",
		label, tcp_ms, tls_ms, ttfb_ms, total_ms, http_status);
}

shorturl(url: string): string
{
	s := url;
	if(S->prefix("https://", s))
		s = s[8:];
	else if(S->prefix("http://", s))
		s = s[7:];
	if(len s > 38)
		s = s[0:35] + "...";
	return s;
}
