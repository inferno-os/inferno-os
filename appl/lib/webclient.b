implement Webclient;

include "sys.m";
	sys: Sys;

include "draw.m";

include "dial.m";
	dial: Dial;

include "url.m";
	url: Url;
	ParsedUrl: import url;

include "keyring.m";

include "tls.m";
	tls: TLS;
	Conn: import tls;

include "string.m";
	str: String;

include "webclient.m";

MAXREDIRECTS: con 10;

init(): string
{
	sys = load Sys Sys->PATH;

	str = load String String->PATH;
	if(str == nil)
		return sys->sprint("load String: %r");

	dial = load Dial Dial->PATH;
	if(dial == nil)
		return sys->sprint("load Dial: %r");

	url = load Url Url->PATH;
	if(url == nil)
		return sys->sprint("load Url: %r");
	url->init();

	# TLS loaded lazily on first HTTPS use
	return nil;
}

# [private]
loadtls(): string
{
	if(tls != nil)
		return nil;
	tls = load TLS TLS->PATH;
	if(tls == nil)
		return sys->sprint("load TLS: %r");
	err := tls->init();
	if(err != nil)
		return "tls init: " + err;
	return nil;
}

Response.hdrval(r: self ref Response, name: string): string
{
	lname := str->tolower(name);
	for(h := r.headers; h != nil; h = tl h) {
		hdr := hd h;
		if(str->tolower(hdr.name) == lname)
			return hdr.value;
	}
	return nil;
}

get(requrl: string): (ref Response, string)
{
	return request("GET", requrl, nil, nil);
}

post(requrl, contenttype: string, body: array of byte): (ref Response, string)
{
	hdrs: list of Header;
	if(contenttype != nil)
		hdrs = Header("Content-Type", contenttype) :: hdrs;
	return request("POST", requrl, hdrs, body);
}

tlsdial(addr, servername: string): (ref Sys->FD, string)
{
	err := loadtls();
	if(err != nil)
		return (nil, err);

	c := dial->dial(addr, nil);
	if(c == nil)
		return (nil, sys->sprint("dial %s: %r", addr));

	cfg := tls->defaultconfig();
	cfg.servername = servername;

	(conn, terr) := tls->client(c.dfd, cfg);
	if(terr != nil)
		return (nil, "tls: " + terr);

	# Wrap TLS conn as a pipe-like FD pair
	return tlsconnfd(conn);
}

# [private]
# Create a bidirectional FD from a TLS connection using a pipe
tlsconnfd(conn: ref Conn): (ref Sys->FD, string)
{
	fds := array [2] of ref Sys->FD;
	if(sys->pipe(fds) < 0)
		return (nil, sys->sprint("pipe: %r"));

	# Spawn read and write pumps
	spawn tlsreadpump(conn, fds[1]);
	spawn tlswritepump(conn, fds[1]);

	return (fds[0], nil);
}

# [private]
tlsreadpump(conn: ref Conn, fd: ref Sys->FD)
{
	buf := array [16384] of byte;
	for(;;) {
		n := conn.read(buf, len buf);
		if(n <= 0)
			break;
		if(sys->write(fd, buf[:n], n) != n)
			break;
	}
	# Signal EOF by closing our end
	fd = nil;
}

# [private]
tlswritepump(conn: ref Conn, fd: ref Sys->FD)
{
	buf := array [16384] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		if(conn.write(buf[:n], n) != n)
			break;
	}
	conn.close();
}

request(method, requrl: string, hdrs: list of Header, body: array of byte): (ref Response, string)
{
	for(redir := 0; redir < MAXREDIRECTS; redir++) {
		(resp, err) := dorequest(method, requrl, hdrs, body);
		if(err != nil)
			return (nil, err);

		# Handle redirects
		case resp.statuscode {
		301 or 302 or 303 or 307 or 308 =>
			loc := resp.hdrval("Location");
			if(loc == nil)
				return (resp, nil);
			# Resolve relative URL
			if(len loc > 0 && loc[0] == '/')
				requrl = schemehost(requrl) + loc;
			else
				requrl = loc;
			# 303 always changes to GET
			if(resp.statuscode == 303) {
				method = "GET";
				body = nil;
			}
		* =>
			return (resp, nil);
		}
	}
	return (nil, "too many redirects");
}

# [private]
schemehost(requrl: string): string
{
	u := url->makeurl(requrl);
	if(u == nil)
		return "";
	port := u.port;
	if(port == nil) {
		case u.scheme {
		Url->HTTPS => port = "443";
		* => port = "80";
		}
	}
	s := url->schemes[u.scheme] + "://" + u.host;
	if(port != "80" && port != "443")
		s += ":" + port;
	return s;
}

# [private]
dorequest(method, requrl: string, hdrs: list of Header, body: array of byte): (ref Response, string)
{
	u := url->makeurl(requrl);
	if(u == nil)
		return (nil, "bad url: " + requrl);

	host := u.host;
	port := u.port;
	ishttps := u.scheme == Url->HTTPS;

	if(port == nil) {
		if(ishttps)
			port = "443";
		else
			port = "80";
	}

	addr := "tcp!" + host + "!" + port;

	fd: ref Sys->FD;
	if(ishttps) {
		err := loadtls();
		if(err != nil)
			return (nil, err);
		c := dial->dial(addr, nil);
		if(c == nil)
			return (nil, sys->sprint("dial %s: %r", addr));
		cfg := tls->defaultconfig();
		cfg.servername = host;
		(conn, terr) := tls->client(c.dfd, cfg);
		if(terr != nil)
			return (nil, "tls: " + terr);
		# Use TLS conn's read/write directly
		return dotlsrequest(conn, method, u, host, hdrs, body);
	} else {
		c := dial->dial(addr, nil);
		if(c == nil)
			return (nil, sys->sprint("dial %s: %r", addr));
		fd = c.dfd;
	}

	return dofdrequest(fd, method, u, host, hdrs, body);
}

# [private]
dotlsrequest(conn: ref Conn, method: string, u: ref ParsedUrl, host: string,
	hdrs: list of Header, body: array of byte): (ref Response, string)
{
	req := buildrequest(method, u, host, hdrs, body);
	reqbytes := array of byte req;
	if(conn.write(reqbytes, len reqbytes) != len reqbytes)
		return (nil, "write failed");
	if(body != nil && len body > 0) {
		if(conn.write(body, len body) != len body)
			return (nil, "write body failed");
	}

	return readtlsresponse(conn);
}

# [private]
dofdrequest(fd: ref Sys->FD, method: string, u: ref ParsedUrl, host: string,
	hdrs: list of Header, body: array of byte): (ref Response, string)
{
	req := buildrequest(method, u, host, hdrs, body);
	reqbytes := array of byte req;
	if(sys->write(fd, reqbytes, len reqbytes) != len reqbytes)
		return (nil, "write failed");
	if(body != nil && len body > 0) {
		if(sys->write(fd, body, len body) != len body)
			return (nil, "write body failed");
	}

	return readfdresponse(fd);
}

# [private]
buildrequest(method: string, u: ref ParsedUrl, host: string,
	hdrs: list of Header, body: array of byte): string
{
	path := u.pstart + u.path;
	if(path == nil || path == "")
		path = "/";
	if(u.query != nil)
		path += "?" + u.query;

	req := method + " " + path + " HTTP/1.1\r\n";
	req += "Host: " + host + "\r\n";
	req += "Connection: close\r\n";
	req += "User-Agent: Infernode/1.0\r\n";

	if(body != nil && len body > 0)
		req += "Content-Length: " + string len body + "\r\n";

	# Add user headers
	for(h := hdrs; h != nil; h = tl h) {
		hdr := hd h;
		req += hdr.name + ": " + hdr.value + "\r\n";
	}

	req += "\r\n";
	return req;
}

# [private]
# Read HTTP response from a TLS connection
readtlsresponse(conn: ref Conn): (ref Response, string)
{
	# Read headers
	hbuf := array [32768] of byte;
	hlen := 0;
	headersdone := 0;
	while(!headersdone && hlen < len hbuf) {
		n := conn.read(hbuf[hlen:], 1);
		if(n <= 0)
			break;
		hlen += n;
		if(hlen >= 4 && hbuf[hlen-4] == byte '\r' && hbuf[hlen-3] == byte '\n'
		   && hbuf[hlen-2] == byte '\r' && hbuf[hlen-1] == byte '\n')
			headersdone = 1;
	}

	if(!headersdone && hlen == 0)
		return (nil, "empty response");

	hdrstr := string hbuf[:hlen];
	(resp, bodystart, err) := parseresponse(hdrstr);
	if(err != nil)
		return (nil, err);

	# Read body
	clen := resp.hdrval("Content-Length");
	te := resp.hdrval("Transfer-Encoding");

	if(te != nil && str->tolower(te) == "chunked") {
		# Read chunked body via TLS
		(bdata, berr) := readchunked_tls(conn);
		if(berr != nil)
			return (nil, berr);
		resp.body = bdata;
	} else if(clen != nil) {
		nbytes := int clen;
		if(nbytes > MAXBODY)
			nbytes = MAXBODY;
		if(nbytes > 0) {
			resp.body = array [nbytes] of byte;
			off := 0;
			# Copy any body data already read in header buffer
			if(bodystart < len hdrstr) {
				extra := array of byte hdrstr[bodystart:];
				ncopy := len extra;
				if(ncopy > nbytes)
					ncopy = nbytes;
				for(ci := 0; ci < ncopy; ci++)
					resp.body[ci] = extra[ci];
				off = ncopy;
			}
			while(off < nbytes) {
				n := conn.read(resp.body[off:], nbytes - off);
				if(n <= 0)
					break;
				off += n;
			}
			if(off < nbytes)
				resp.body = resp.body[:off];
		}
	} else {
		# Read until close
		chunks: list of array of byte;
		total := 0;
		rbuf := array [16384] of byte;
		done := 0;
		while(!done && total < MAXBODY) {
			n := conn.read(rbuf, len rbuf);
			if(n <= 0)
				done = 1;
			else {
				chunk := array [n] of byte;
				chunk[:] = rbuf[:n];
				chunks = chunk :: chunks;
				total += n;
			}
		}
		resp.body = concatchunks(chunks, total);
	}

	return (resp, nil);
}

# [private]
# Read HTTP response from a plain FD
readfdresponse(fd: ref Sys->FD): (ref Response, string)
{
	# Read headers
	hbuf := array [32768] of byte;
	hlen := 0;
	headersdone := 0;
	while(!headersdone && hlen < len hbuf) {
		n := sys->read(fd, hbuf[hlen:], 1);
		if(n <= 0)
			break;
		hlen += n;
		if(hlen >= 4 && hbuf[hlen-4] == byte '\r' && hbuf[hlen-3] == byte '\n'
		   && hbuf[hlen-2] == byte '\r' && hbuf[hlen-1] == byte '\n')
			headersdone = 1;
	}

	if(!headersdone && hlen == 0)
		return (nil, "empty response");

	hdrstr := string hbuf[:hlen];
	(resp, nil, err) := parseresponse(hdrstr);
	if(err != nil)
		return (nil, err);

	# Read body
	clen := resp.hdrval("Content-Length");
	te := resp.hdrval("Transfer-Encoding");

	if(te != nil && str->tolower(te) == "chunked") {
		(bdata, berr) := readchunked_fd(fd);
		if(berr != nil)
			return (nil, berr);
		resp.body = bdata;
	} else if(clen != nil) {
		nbytes := int clen;
		if(nbytes > MAXBODY)
			nbytes = MAXBODY;
		if(nbytes > 0) {
			resp.body = array [nbytes] of byte;
			off := 0;
			while(off < nbytes) {
				n := sys->read(fd, resp.body[off:], nbytes - off);
				if(n <= 0)
					break;
				off += n;
			}
			if(off < nbytes)
				resp.body = resp.body[:off];
		}
	} else {
		# Read until close
		chunks: list of array of byte;
		total := 0;
		rbuf := array [16384] of byte;
		done := 0;
		while(!done && total < MAXBODY) {
			n := sys->read(fd, rbuf, len rbuf);
			if(n <= 0)
				done = 1;
			else {
				chunk := array [n] of byte;
				chunk[:] = rbuf[:n];
				chunks = chunk :: chunks;
				total += n;
			}
		}
		resp.body = concatchunks(chunks, total);
	}

	return (resp, nil);
}

# [private]
parseresponse(hdrstr: string): (ref Response, int, string)
{
	# Find end of status line
	(statusline, rest) := splitline(hdrstr);
	if(statusline == nil)
		return (nil, 0, "no status line");

	# Parse "HTTP/1.1 200 OK"
	(nf, fields) := sys->tokenize(statusline, " ");
	if(nf < 2)
		return (nil, 0, "bad status line: " + statusline);
	code := int hd tl fields;
	status := statusline;

	# Parse headers
	headers: list of Header;
	bodystart := len statusline + 2;	# past \r\n

	for(;;) {
		(line, nrest) := splitline(rest);
		if(line == nil || line == "")
			break;
		bodystart += len line + 2;
		rest = nrest;
		(hname, hval) := splitheader(line);
		if(hname != nil)
			headers = Header(hname, hval) :: headers;
	}
	bodystart += 2;	# past final \r\n

	resp := ref Response(code, status, headers, nil);
	return (resp, bodystart, nil);
}

# [private]
splitline(s: string): (string, string)
{
	for(i := 0; i < len s - 1; i++) {
		if(s[i] == '\r' && s[i+1] == '\n')
			return (s[:i], s[i+2:]);
	}
	return (s, "");
}

# [private]
splitheader(line: string): (string, string)
{
	for(i := 0; i < len line; i++) {
		if(line[i] == ':') {
			name := line[:i];
			val := line[i+1:];
			# Strip leading whitespace from value
			j := 0;
			while(j < len val && (val[j] == ' ' || val[j] == '\t'))
				j++;
			return (name, val[j:]);
		}
	}
	return (nil, nil);
}

# [private]
readchunked_tls(conn: ref Conn): (array of byte, string)
{
	chunks: list of array of byte;
	total := 0;
	linebuf := array [64] of byte;

	for(;;) {
		# Read chunk size line
		llen := 0;
		while(llen < len linebuf) {
			n := conn.read(linebuf[llen:], 1);
			if(n <= 0)
				break;
			llen++;
			if(llen >= 2 && linebuf[llen-2] == byte '\r' && linebuf[llen-1] == byte '\n')
				break;
		}
		if(llen < 2)
			break;
		sizestr := string linebuf[:llen-2];
		chunksize := hexval(sizestr);
		if(chunksize <= 0)
			break;
		if(total + chunksize > MAXBODY)
			chunksize = MAXBODY - total;

		chunk := array [chunksize] of byte;
		off := 0;
		while(off < chunksize) {
			n := conn.read(chunk[off:], chunksize - off);
			if(n <= 0)
				break;
			off += n;
		}
		if(off < chunksize)
			chunk = chunk[:off];
		chunks = chunk :: chunks;
		total += off;

		# Read trailing \r\n
		conn.read(linebuf[:2], 2);

		if(total >= MAXBODY)
			break;
	}

	return (concatchunks(chunks, total), nil);
}

# [private]
readchunked_fd(fd: ref Sys->FD): (array of byte, string)
{
	chunks: list of array of byte;
	total := 0;
	linebuf := array [64] of byte;

	for(;;) {
		llen := 0;
		while(llen < len linebuf) {
			n := sys->read(fd, linebuf[llen:], 1);
			if(n <= 0)
				break;
			llen++;
			if(llen >= 2 && linebuf[llen-2] == byte '\r' && linebuf[llen-1] == byte '\n')
				break;
		}
		if(llen < 2)
			break;
		sizestr := string linebuf[:llen-2];
		chunksize := hexval(sizestr);
		if(chunksize <= 0)
			break;
		if(total + chunksize > MAXBODY)
			chunksize = MAXBODY - total;

		chunk := array [chunksize] of byte;
		off := 0;
		while(off < chunksize) {
			n := sys->read(fd, chunk[off:], chunksize - off);
			if(n <= 0)
				break;
			off += n;
		}
		if(off < chunksize)
			chunk = chunk[:off];
		chunks = chunk :: chunks;
		total += off;

		sys->read(fd, linebuf[:2], 2);

		if(total >= MAXBODY)
			break;
	}

	return (concatchunks(chunks, total), nil);
}

# [private]
hexval(s: string): int
{
	# Strip any extension (e.g., ";ext")
	for(i := 0; i < len s; i++) {
		if(s[i] == ';') {
			s = s[:i];
			break;
		}
	}
	s = str->drop(s, " \t");
	n := 0;
	for(i = 0; i < len s; i++) {
		c := s[i];
		d := 0;
		if(c >= '0' && c <= '9')
			d = c - '0';
		else if(c >= 'a' && c <= 'f')
			d = c - 'a' + 10;
		else if(c >= 'A' && c <= 'F')
			d = c - 'A' + 10;
		else
			break;
		n = n * 16 + d;
	}
	return n;
}

# [private]
# Concatenate a list of byte arrays (in reverse order) into one
concatchunks(chunks: list of array of byte, total: int): array of byte
{
	if(total <= 0)
		return nil;
	result := array [total] of byte;
	# chunks is in reverse order, reverse it first
	rev: list of array of byte;
	for(l := chunks; l != nil; l = tl l)
		rev = hd l :: rev;
	off := 0;
	for(l = rev; l != nil; l = tl l) {
		chunk := hd l;
		result[off:] = chunk;
		off += len chunk;
	}
	return result;
}
