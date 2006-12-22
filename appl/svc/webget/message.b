implement Message;

include "sys.m";
	sys: Sys;

include "string.m";
	S : String;

include "bufio.m";
	B : Bufio;
	Iobuf: import B;

include "message.m";
	msg: Message;

msglog: ref Sys->FD;

init(bufio: Bufio, smod: String)
{
	sys = load Sys Sys->PATH;
	S = smod;
	B = bufio;
}

sptab : con " \t";
crlf : con "\r\n";

Msg.newmsg() : ref Msg
{
	return ref Msg("", nil, nil, nil, 0);
}

# Read a message header from fd and return a Msg
# the header fields.
# If withprefix is true, read one line first and put it
# in the prefixline field of the Msg (without terminating \r\n)
# Return nil if there is a read error or eof before the
# header is completely read.
Msg.readhdr(io: ref Iobuf, withprefix: int) : (ref Msg, string)
{
	m := Msg.newmsg();
	l : list of Nameval = nil;
	needprefix := withprefix;
	for(;;) {
		line := getline(io);
		n := len line;
		if(n == 0) {
			if(withprefix && m.prefixline != "")
				break;
			return(nil, "msg read hdr error: no header");
		}
		if(line[n-1] != '\n')
			return (m, "msg read hdr error: incomplete header");
		if(n >= 2 && line[n-2] == '\r')
			line = line[0:n-2];
		else
			line = line[0:n-1];
		if(needprefix) {
			m.prefixline = line;
			needprefix = 0;
		}
		else {
			if(line == "")
				break;
			if(S->in(line[0], sptab)) {
				if(l == nil)
					continue;
				nv := hd l;
				l = Nameval(nv.name, nv.value + " " + S->drop(line, sptab)) :: tl l;
			}
			else {
				(nam, val) := S->splitl(line, ":");
				if(val == nil)
					continue;  # no colon
				l = Nameval(S->tolower(nam), S->drop(val[1:], sptab)) :: l;
			}
		}
	}
	nh := len l;
	if(nh > 0) {
		m.fields = array[nh] of Nameval;
		for(i := nh-1; i >= 0; i--) {
			m.fields[i] = hd l;
			l = tl l;
		}
	}
	return (m, "");
}

glbuf := array[300] of byte;

# Like io.gets('\n'), but assume Latin-1 instead of UTF encoding
getline(io: ref Iobuf): string
{
	imax := len glbuf - 1;
	for(i := 0; i < imax; ) {
		c := io.getb();
		if(c < 0)
			break;
		if(c < 128)
			glbuf[i++] = byte c;
		else
			i += sys->char2byte(c, glbuf, i);
		if(c == '\n')
			break;
		if(i == imax) {
			imax += 100;
			if(imax > 1000)
				break;	# Header lines aren't supposed to be > 1000
			newglbuf := array[imax] of byte;
			newglbuf[0:] = glbuf[0:i];
			glbuf = newglbuf;
		}
	}
	ans := string glbuf[0:i];
	return ans;
}

Bbufsize: con 8000;

# Read the body of the message, assuming the header has been processed.
# If content-length has been specified, read exactly that many bytes
# or until eof; else read until done.
# Return "" if all is OK, else return an error string.
Msg.readbody(m: self ref Msg, io: ref Iobuf) : string
{
	(clfnd, cl) := m.fieldval("content-length");
	if(clfnd) {
		clen := int cl;
		if(clen > 0) {
			m.body = array[clen] of byte;
			n := B->io.read(m.body, clen);
			m.bodylen = n;
			if(n != clen)
				return "short read";
		}
	}
	else {
		m.body = array[Bbufsize] of byte;
		curlen := 0;
		for(;;) {
			avail := len m.body - curlen;
			if(avail <= 0) {
				newa := array[len m.body + Bbufsize] of byte;
				if(curlen > 0)
					newa[0:] = m.body[0:curlen];
				m.body = newa;
				avail = Bbufsize;
			}
			n := B->io.read(m.body[curlen:], avail);
			if(n < 0)
				return sys->sprint("readbody error %r");
			if(n == 0)
				break;
			else
				curlen += n;
		}
		m.bodylen = curlen;
	}
	return "";
}

# Look for name (lowercase) in the fields of m
# and (1, field value) if found, or (0,"") if not.
# If multiple fields with the same name exist,
# the value is defined as the comma separated list
# of all such values.
Msg.fieldval(m: self ref Msg, name: string) : (int, string)
{
	n := len m.fields;
	ans := "";
	found := 0;
	for(i := 0; i < n; i++) {
		if(m.fields[i].name == name) {
			v := m.fields[i].value;
			if(found)
				ans = ans + ", " + v;
			else
				ans = v;
			found = 1;
		}
	}
	return (found, ans);
}

Msg.addhdrs(m: self ref Msg, hdrs: list of Nameval)
{
	nh := len hdrs;
	if(nh == 0)
		return;
	onh := len m.fields;
	newa := array[nh + onh] of Nameval;
	newa[0:] = m.fields;
	i := onh;
	while(hdrs != nil) {
		newa[i++] = hd hdrs;
		hdrs = tl hdrs;
	}
	m.fields = newa;
}

Msg.update(m: self ref Msg, name, value: string)
{
	for(i := 0; i < len m.fields; i++)
		if(m.fields[i].name == name) {
			m.fields[i] = Nameval(name, value);
			return;
		}
	m.addhdrs(Nameval(name, value) :: nil);
}

Msg.header(m: self ref Msg) : string
{
	s := "";
	for(i := 0; i < len m.fields; i++) {
		nv := m.fields[i];
		s += nv.name + ": " + nv.value + "\n";
	}
	return s;
}

Msg.writemsg(m: self ref Msg, io: ref Iobuf) : string
{
	n := 0;
	if(m.prefixline != nil) {
		n = B->io.puts(m.prefixline);
		if(n >= 0)
			n = B->io.puts(crlf);
	}
	for(i := 0; i < len m.fields; i++) {
		nv := m.fields[i];
		if(n >= 0)
			n = B->io.puts(nv.name);
		if(n >= 0)
			n = B->io.puts(": ");
		if(n >= 0)
			n = B->io.puts(nv.value);
		if(n >= 0)
			n = B->io.puts(crlf);
	}
	if(n >= 0)
		n = B->io.puts(crlf);
	if(n >= 0 && m.bodylen > 0)
		n = B->io.write(m.body, m.bodylen);
	if(n < 0)
		return sys->sprint("msg write error: %r");
	B->io.flush();
	return "";
}
