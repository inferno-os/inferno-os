implement URIs;

#
# RFC3986, URI Generic Syntax
#

include "sys.m";
	sys: Sys;

include "string.m";
	S: String;

include "uris.m";

Alpha: con "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
Digit: con "0123456789";

GenDelims: con ":/?#[]@";
SubDelims: con "!$&'()*+,;=";
Reserved: con GenDelims + SubDelims;
HexDigit: con Digit+"abcdefABCDEF";

Escape: con GenDelims+"%";	# "%" must be encoded as %25

Unreserved: con Alpha+Digit+"-._~";

F_Esc, F_Scheme: con byte(1<<iota);

ctype: array of byte;

classify(s: string, f: byte)
{
	for(i := 0; i < len s; i++)
		ctype[s[i]] |= f;
}

init()
{
	sys = load Sys Sys->PATH;
	S = load String String->PATH;
	if(S == nil)
		raise sys->sprint("can't load %s: %r", String->PATH);

	ctype = array [256] of { * => byte 0 };
	classify(Escape, F_Esc);
	for(i := 0; i <= ' '; i++)
		ctype[i] |= F_Esc;
	for(i = 16r80; i <= 16rFF; i++)
		ctype[i] |= F_Esc;
	classify(Alpha+Digit+"+-.", F_Scheme);
}

#      scheme://<user>:<passwd>@<host>:<port>/<path>?<query>#<fragment>
#
#      ^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?
#
#	delimiters:  :/?#  /?#  ?#  #
#
URI.parse(url: string): ref URI
{
	scheme, userinfo, host, port, path, query, frag: string;
	for(i := 0; i < len url; i++){
		c := url[i];
		if(c == ':'){
			scheme = S->tolower(url[0:i]);
			url = url[i+1:];
			break;
		}
		if(c < 0 || c >= len ctype || (ctype[c] & F_Scheme) == byte 0)
			break;
	}

	if(S->prefix("//", url)){
		authority: string;
		(authority, path) = S->splitstrl(url[2:], "/");
		(up, hp) := splitl(authority, "@");
		if(hp == "")
			hp = authority;
		else
			userinfo = up;
		if(hp != nil && hp[0] == '['){	# another rfc hack, for IPv6 addresses, which contain :
			(host, hp) = S->splitstrr(hp, "]");
			if(hp != nil && hp[0] == ':')
				port = hp[1:];
			else
				host += hp;	# put it back
		}else
			(host, port) = splitl(hp, ":");
		if(path == nil)
			path = "/";
	}else
		path = url;
	(path, frag) = S->splitstrl(path, "#");		# includes # in frag
	(path, query) = S->splitstrl(path, "?");	#  includes ? in query
	return ref URI(scheme, dec(userinfo), dec(host), port, dec(path), query, dec(frag));
}

URI.userpw(u: self ref URI): (string, string)
{
	return splitl(u.userinfo, ":");
}

URI.text(u: self ref URI): string
{
	s := "";
	if(u.scheme != nil)
		s += u.scheme + ":";
	if(u.hasauthority())
		s += "//" + u.authority();
	return s + enc(u.path, "/@:") + u.query + enc1(u.fragment, "@:/?");
}

URI.copy(u: self ref URI): ref URI
{
	return ref *u;
}

URI.pathonly(u: self ref URI): ref URI
{
	v := ref *u;
	v.userinfo = nil;
	v.query = nil;
	v.fragment = nil;
	return v;
}

URI.addbase(u: self ref URI, b: ref URI): ref URI
{
	# RFC3986 5.2.2, rearranged
	r := ref *u;
	if(r.scheme == nil && b != nil){
		r.scheme = b.scheme;
		if(!r.hasauthority()){
			r.userinfo = b.userinfo;
			r.host = b.host;
			r.port = b.port;
			if(r.path == nil){
				r.path = b.path;
				if(r.query == nil)
					r.query = b.query;
			}else if(r.path[0] != '/'){
				# 5.2.3: merge paths
				if(b.path == "" && b.hasauthority())
					p1 := "/";
				else
					(p1, nil) = S->splitstrr(b.path, "/");
				r.path = p1 + r.path;
			}
		}
	}
	r.path = removedots(r.path);
	return r;
}

URI.nodots(u: self ref URI): ref URI
{
	return u.addbase(nil);
}

URI.hasauthority(u: self ref URI): int
{
	return u.host != nil || u.userinfo != nil || u.port != nil;
}

URI.isabsolute(u: self ref URI): int
{
	return u.scheme != nil;
}

URI.authority(u: self ref URI): string
{
	s := enc(u.userinfo, ":");
	if(s != nil)
		s += "@";
	if(u.host != nil){
		s += enc(u.host, "[]:");	# assumes : appears inside []; could enforce it
		if(u.port != nil)
			s += ":" + enc(u.port,nil);
	}
	return s;
}

#
# simplified version of procedure in RFC3986 5.2.4:
# it extracts a complete segment from the input first, then analyses it
#
removedots(s: string): string
{
	if(s == nil)
		return "";
	out := "";
	for(p := 0; p < len s;){
		# extract the first segment and any preceding /
		q := p;
		if(++p < len s){
			while(++p < len s && s[p] != '/')
				{}
		}
		seg := s[q: p];
		if((e := p) < len s)
			e++;
		case s[q: e] {	# includes any following /
		"../" or "./" =>	;
		"/./" or "/." =>
			if(p >= len s)
				s += "/";
		"/../" or "/.." =>
			if(p >= len s)
				s += "/";
			if(out != nil){
				for(q = len out; --q > 0 && out[q] != '/';)
					{}	# skip
				out = out[0: q];
			}
		"." or ".." =>	;	# null effect
		* =>		# including "/"
			out += seg;
		}
	}
	return out;
}

#
# similar to splitstrl but trims the matched character from the result
#
splitl(s, c: string): (string, string)
{
	(a, b) := S->splitstrl(s, c);
	if(b != "")
		b = b[1:];
	return (a, b);
}

hex2(s: string): int
{
	n := 0;
	for(i := 0; i < 2; i++){
		if(i >= len s)
			return -1;
		n <<= 4;
		case c := s[i] {
		'0' to '9' =>
			n += c-'0';
		'a' to 'f' =>
			n += 10+(c-'a');
		'A' to 'F' =>
			n += 10+(c-'A');
		* =>
			return -1;
		}
	}
	return n;
}

dec(s: string): string
{
	for(i := 0;; i++){
		if(i >= len s)
			return s;
		if(s[i] == '%' || s[i] == 0)
			break;
	}
	t := s[0:i];
	a := array[Sys->UTFmax*len s] of byte;	# upper bound
	o := 0;
	while(i < len s){
		c := s[i++];
		if(c < 16r80){
			case c {
			'%' =>
				if((v := hex2(s[i:])) > 0){
					c = v;
					i += 2;
				}
			0 =>
				c = ' ';	# shouldn't happen
			}
			a[o++] = byte c;
		}else
			o += sys->char2byte(c, a, o);	# string contained Unicode
	}
	return t + string a[0:o];
}

enc1(s: string, safe: string): string
{
	if(len s > 1)
		return s[0:1] + enc(s[1:], safe);
	return s;
}

# encoding depends on context (eg, &=/: not escaped in `query' string)
enc(s: string, safe: string): string
{
	for(i := 0;; i++){
		if(i >= len s)
			return s;	# use as-is
		c := s[i];
		if(c >= 16r80 || (ctype[c] & F_Esc) != byte 0 && !S->in(c, safe))
			break;
	}
	t := s[0: i];
	b := array of byte s[i:];
	for(i = 0; i < len b; i++){
		c := int b[i];
		if((ctype[c] & F_Esc) != byte 0 && !S->in(c, safe))
			t += sys->sprint("%%%.2X", c);
		else
			t[len t] = c;
	}
	return t; 
}

URI.eq(u: self ref URI, v: ref URI): int
{
	if(v == nil)
		return 0;
	return u.scheme == v.scheme && u.userinfo == v.userinfo &&
		u.host == v.host && u.port == v.port && u.path == v.path &&	# path might need canon
		u.query == v.query;	# not fragment
}

URI.eqf(u: self ref URI, v: ref URI): int
{
	return u.eq(v) && u.fragment == v.fragment;
}
