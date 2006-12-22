implement Url;

include "sys.m";
include "string.m";
include "url.m";

dbg: con 0;

sys: Sys;
S: String;
schemechars : array of byte;

init(): string
{
	sys = load Sys Sys->PATH;
	S = load String String->PATH;
	if (S == nil)
		return sys->sprint("cannot load %s: %r", String->PATH);

	schemechars = array [128] of { * => byte 0 };
	alphabet := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-.";
	for (i := 0; i < len alphabet; i++)
		schemechars[alphabet[i]] = byte 1;
	return nil;
}

# To allow relative urls, only fill in specified pieces (don't apply defaults)
#  general syntax: <scheme>:<scheme-specific>
#  for IP schemes, <scheme-specific> is
#      //<user>:<passwd>@<host>:<port>/<path>?<query>#<fragment>
#
parse(url: string): ref Parsedurl
{
	if (dbg)
		sys->print("URL parse: [%s]\n", url);
	scheme, user, passwd, host, port, path, params, query, frag : string;
	gotscheme := 0;
	for (i := 0; i < len url; i++) {
		c := url[i];
		if (c == ':') {
			gotscheme = 1;
			break;
		}
		if (c < 0 || c > len schemechars || schemechars[c] == byte 0)
			break;
	}
	if (gotscheme) {
		if (i > 0)
			scheme = S->tolower(url[0:i]);
		if (i+1 < len url)
			url = url[i+1:];
		else
			url = nil;
	}

	if (scheme != nil && !relscheme(scheme))
		path = url;
	else {
		if(!S->prefix("//", url))
			path = url;
		else {
			netloc: string;
			(netloc, path) = S->splitl(url[2:], "/");
			if(scheme == "file")
				host = netloc;
			else {
				(up,hp) := split(netloc, "@");
				if(hp == "")
					hp = up;
				else
					(user, passwd) = split(up, ":");
				(host, port) = split(hp, ":");
			}
		}
		if(scheme == "file") {
			if(host == "")
				host = "localhost";
		} else {
			if (path == nil)
				path = "/";
			else {
				(path, frag) = split(path, "#");
				(path, query) = split(path, "?");
				(path, params) = split(path, ";");
			}
		}
	}
	return ref Parsedurl(scheme, user, passwd, host, port, path, params, query, frag);
}

relscheme(s: string): int
{
	# schemes we know to be suitable as "Relative Uniform Resource Locators"
	# as defined in RFC1808 (+ others)
	return (s=="http" || s=="https" || s=="file" || s=="ftp" || s=="nntp");
}

Parsedurl.tostring(u: self ref Parsedurl): string
{
	return tostring(u);
}

tostring(u: ref Parsedurl) : string
{
	if (u == nil)
		return "";

	ans := "";
	if (u.scheme != nil)
		ans = u.scheme + ":";
	if(u.host != "") {
		ans = ans + "//";
		if(u.user != "") {
			ans = ans + u.user;
			if(u.passwd != "")
				ans = ans + ":" + u.passwd;
			ans = ans + "@";
		}
		ans = ans + u.host;
		if(u.port != "")
			ans = ans + ":" + u.port;
	}
	ans = ans + u.path;
	if(u.params != "")
		ans = ans + ";" + u.params;
	if(u.query != "")
		ans = ans + "?" + u.query;
	if(u.frag != "")
		ans = ans + "#" + u.frag;
	return ans;
}

mkabs(u, b: ref Parsedurl): ref Parsedurl
{
	if (dbg)
		sys->print("URL mkabs [%s] [%s]\n", tostring(u), tostring(b));
	if (tostring(b) == "")
		return u;
	if (tostring(u) == "")
		return b;

	if (u.scheme != nil && !relscheme(u.scheme))
		return u;

	if (u.scheme == nil) {
		if (b.scheme == nil)
			# try http
			u.scheme = "http";
		else {
			if (!relscheme(b.scheme))
				return nil;
			u.scheme = b.scheme;
		}
	}

	r := ref *u;
	if (r.host == nil) {
		r.user = b.user;
		r.passwd = b.passwd;
		r.host = b.host;
		r.port = b.port;
		if (r.path == nil || r.path[0] != '/') {
			if (r.path == nil) {
				r.path = b.path;
				if (r.params == nil) {
					r.params = b.params;
					if (r.query == nil)
						r.query = b.query;
				}
			} else {
				(p1,nil) := S->splitr(b.path, "/");
				r.path = canonize(p1 + r.path);
			}
		}
	}
	r.path = canonize(r.path);
	if (dbg)
		sys->print("URL mkabs returns [%s]\n", tostring(r));
	return r;
}

# Like splitl, but assume one char match, and omit that from second part.
# If c doesn't appear in s, the return is (s, "").
split(s, c: string) : (string, string)
{
	(a,b) := S->splitl(s, c);
	if(b != "")
		b = b[1:];
	return (a,b);
}

# remove ./ and ../ from s
canonize(s: string): string
{
	ans := "";
	(nil, file) := S->splitr(s, "/");
	if (file == nil || file == "." | file == "..")
		ans = "/";

	(nil,path) := sys->tokenize(s, "/");
	revpath : list of string = nil;
	for(p := path; p != nil; p = tl p) {
		seg := hd p;
		if(seg == "..") {
			if (revpath != nil)
				revpath = tl revpath;
		} else if(seg != ".")
			revpath = seg :: revpath;
	}
	while(revpath != nil && hd revpath == "..")
		revpath = tl revpath;
	if(revpath != nil) {
		ans ="/" +  (hd revpath) + ans;
		revpath = tl revpath;
		while(revpath != nil) {
			ans = "/" + (hd revpath) + ans;
			revpath = tl revpath;
		}
	}
	return ans;
}




