implement Url;

include "sys.m";
	sys: Sys;

include "string.m";
	S: String;

include "url.m";

schemes = array[] of {
	NOSCHEME => "",
	HTTP => "http",
	HTTPS => "https",
	FTP => "ftp",
	FILE => "file",
	GOPHER => "gopher",
	MAILTO => "mailto",
	NEWS => "news",
	NNTP => "nntp",
	TELNET => "telnet",
	WAIS => "wais",
	PROSPERO => "prospero",
	JAVASCRIPT => "javascript",
	UNKNOWN => "unknown"
};

init()
{
	sys = load Sys Sys->PATH;
	S = load String String->PATH;
}

# To allow relative urls, only fill in specified pieces (don't apply defaults)
#  general syntax: <scheme>:<scheme-specific>
#  for IP schemes, <scheme-specific> is
#      //<user>:<passwd>@<host>:<port>/<path>?<query>#<fragment>
makeurl(surl: string): ref ParsedUrl
{
	scheme := NOSCHEME;
	user := "";
	passwd := "";
	host := "";
	port := "";
	pstart := "";
	path := "";
	query := "";
	frag := "";

	(sch, url) := split(surl, ":");
	if(url == "") {
		url = sch;
		sch = "";
	}
	else {
		(nil, x) := S->splitl(sch, "^-a-zA-Z0-9.+");
		if(x != nil) {
			url = surl;
			sch = "";
		}
		else {
			scheme = UNKNOWN;
			sch = S->tolower(sch);
			for(i := 0; i < len schemes; i++)
				if(schemes[i] == sch) {
					scheme = i;
					break;
				}
		}
	}
	if(scheme == MAILTO)
		path = url;
	else if (scheme == JAVASCRIPT)
		path = url;
	else {
		if(S->prefix("//", url)) {
			netloc: string;
			(netloc, path) = S->splitl(url[2:], "/");
			if(path != "")
				path = path[1:];
			pstart = "/";
			if(scheme == FILE)
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
		else {
			if(S->prefix("/", url)) {
				pstart = "/";
				path = url[1:];
			}
			else
				path = url;
		}
		if(scheme == FILE) {
			if(host == "")
				host = "localhost";
		}
		else {
			(path, frag) = split(path, "#");
			(path, query) = split(path, "?");
		}
	}

	return ref ParsedUrl(scheme, 1, user, passwd, host, port, pstart, path, query, frag);
}

ParsedUrl.tostring(u: self ref ParsedUrl) : string
{
	if (u == nil)
		return nil;

	ans := "";
	if(u.scheme > 0 && u.scheme < len schemes)
		ans = schemes[u.scheme] + ":";
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
	ans = ans + u.pstart + u.path;
	if(u.query != "")
		ans = ans + "?" + u.query;
	if(u.frag != "")
		ans = ans + "#" + u.frag;
	return ans;
}

ParsedUrl.makeabsolute(u: self ref ParsedUrl, b: ref ParsedUrl)
{
#	The following is correct according to RFC 1808, but is violated
#	by various extant web pages.

	if(u.scheme != NOSCHEME && u.scheme != HTTP)
		return;

	if(u.host == "" && u.path == "" && u.pstart == "" && u.query == "" && u.frag == "") {
		u.scheme = b.scheme;
		u.user = b.user;
		u.passwd = b.passwd;
		u.host = b.host;
		u.port = b.port;
		u.path = b.path;
		u.pstart = b.pstart;
		u.query = b.query;
		u.frag = b.frag;
		return;
	}
	if(u.scheme == NOSCHEME)
		u.scheme = b.scheme;
	if(u.host != "")
		return;
	u.user = b.user;
	u.passwd = b.passwd;
	u.host = b.host;
	u.port = b.port;
	if(u.pstart == "/")
		return;
	u.pstart = "/";
	if(u.path == "") {
		u.path = b.path;
		if(u.query == "")
			u.query = b.query;
	}
	else {
		(p1,nil) := S->splitr(b.path, "/");
		u.path = canonize(p1 + u.path);
	}
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
	(base, file) := S->splitr(s, "/");
	(n,path) := sys->tokenize(base, "/");
	revpath : list of string = nil;
	for(p := path; p != nil; p = tl p) {
		if(hd p == "..") {
			if(revpath != nil)
				revpath = tl revpath;
		}
		else if(hd p != ".")
			revpath = (hd p) :: revpath;
	}
	while(revpath != nil && hd revpath == "..")
		revpath = tl revpath;
	ans := "";
	if(revpath != nil) {
		ans = hd revpath;
		revpath = tl revpath;
		while(revpath != nil) {
			ans = (hd revpath) + "/" + ans;
			revpath = tl revpath;
		}
	}
	if (ans != nil)
		ans += "/";
	ans += file;
	return ans;
}

