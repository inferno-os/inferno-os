implement Msgio;

# probably need Authio or Auth instead, to include Authinfo, Certificate and signing operations?
# eliminates certificates and sigalgs from Keyring
# might be better just to have mp.m and sec.m?
# general signature module?
# Keyring->dhparams is is only needed by createsignerkey (and others creating Authinfo)
# should also improve pkcs

include "sys.m";
	sys: Sys;

include "keyring.m";

include "msgio.m";

init()
{
	sys = load Sys Sys->PATH;
}

seterr(r: int)
{
	if(r > 0)
		sys->werrstr("input or format error");
	else if(r == 0)
		sys->werrstr("hungup");
}

#
# i/o on a channel that might or might not retain record boundaries
#
getmsg(fd: ref Sys->FD): array of byte
{
	num := array[5] of byte;
	r := sys->readn(fd, num, len num);
	if(r != len num) {
		seterr(r);
		return nil;
	}
	h := string num;
	if(h[0] == '!')
		m := int h[1:];
	else
		m = int h;
	if(m < 0 || m > Maxmsg) {
		seterr(1);
		return nil;
	}
	buf := array[m] of byte;
	r = sys->readn(fd, buf, m);
	if(r != m){
		seterr(r);
		return nil;
	}
	if(h[0] == '!'){
		sys->werrstr(string buf);
		return nil;
	}
	return buf;
}

sendmsg(fd: ref Sys->FD, buf: array of byte, n: int): int
{
	if(sys->fprint(fd, "%4.4d\n", n) < 0)
		return -1;
	return sys->write(fd, buf, n);
}

senderrmsg(fd: ref Sys->FD, s: string): int
{
	buf := array of byte s;
	if(sys->fprint(fd, "!%3.3d\n", len buf) < 0)
		return -1;
	if(sys->write(fd, buf, len buf) <= 0)
		return -1;
	return 0;
}

#
# i/o on a delimited channel
#
getbuf(fd: ref Sys->FD, buf: array of byte, n: int): (int, string)
{
	n = sys->read(fd, buf, n);
	if(n <= 0){
		seterr(n);
		return (-1, sys->sprint("%r"));
	}
	if(buf[0] == byte 0)
		return (n, nil);
	if(buf[0] == byte 16rFF){
		# garbled, possibly the wrong encryption
		return (-1, "failure");
	}
	# error string
	if(--n < 1)
		return (-1, "unknown");
	return (-1, string buf[1:]);
}

getbytearray(fd: ref Sys->FD): (array of byte, string)
{
	buf := array[Maxmsg] of byte;
	(n, err) := getbuf(fd, buf, len buf);
	if(n < 0)
		return (nil, err);
	return (buf[1: n], nil);
}

getstring(fd: ref Sys->FD): (string, string)
{
	(a, err) := getbytearray(fd);
	if(a != nil)
		return (string a, err);
	return (nil, err);
}

putbuf(fd: ref Sys->FD, data: array of byte, n: int): int
{
	buf := array[Maxmsg] of byte;
	if(n < 0) {
		buf[0] = byte 16rFF;
		n = -n;
	}else
		buf[0] = byte 0;
	if(n >= Maxmsg)
		n = Maxmsg-1;
	buf[1:] = data;
	return sys->write(fd, buf, n+1);
}

putstring(fd: ref Sys->FD, s: string): int
{
	a := array of byte s;
	return putbuf(fd, a, len a);
}

putbytearray(fd: ref Sys->FD, a: array of byte, n: int): int
{
	if(n > len a)
		n = len a;
	return putbuf(fd, a, n);
}

puterror(fd: ref Sys->FD, s: string): int
{
	if(s == nil)
		s = "unknown";
	a := array of byte s;
	return putbuf(fd, a, -len a);
}
