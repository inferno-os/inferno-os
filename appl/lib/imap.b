implement Imap;

#
# IMAP4rev1 client (RFC 3501)
#
# Connects over TLS (port 993) using webclient->tlsdial().
# Tagged command/response protocol with untagged data parsing.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

include "dial.m";
	dial: Dial;

include "keyring.m";

include "tls.m";
	tls: TLS;
	Conn: import tls;

include "webclient.m";
	webclient: Webclient;

include "factotum.m";
	factotum: Factotum;

include "imap.m";

DEBUG: con 0;

# Connection state
fd: ref Sys->FD;
ibuf: ref Iobuf;
tagnum := 0;
connected := 0;
currentmbox: string;

# Ensure core modules are loaded (needed for parser functions called without open())
ensureloaded()
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(str == nil)
		str = load String String->PATH;
}

open(user, password, server: string, mode: int): string
{
	if(sys == nil) {
		sys = load Sys Sys->PATH;
		bufio = load Bufio Bufio->PATH;
		if(bufio == nil)
			return "cannot load Bufio";
		str = load String String->PATH;
		if(str == nil)
			return "cannot load String";
		webclient = load Webclient Webclient->PATH;
		if(webclient == nil)
			return "cannot load Webclient";
		err := webclient->init();
		if(err != nil)
			return "webclient init: " + err;
	}

	if(connected)
		return "already connected";

	# Try factotum first if no credentials given
	if(user == nil || password == nil) {
		factotum = load Factotum Factotum->PATH;
		if(factotum != nil) {
			factotum->init();
			(u, p) := factotum->getuserpasswd(
				"proto=pass service=imap dom=" + server);
			if(u != nil && p != nil) {
				user = u;
				password = p;
			}
		}
		if(user == nil || password == nil)
			return "no credentials: supply user/password or configure factotum";
	}

	port := "993";
	if(mode == STARTTLS)
		port = "143";

	addr := "tcp!" + server + "!" + port;

	if(mode == IMPLICIT_TLS) {
		# TLS from the start (port 993)
		(tlsfd, terr) := webclient->tlsdial(addr, server);
		if(terr != nil)
			return "tlsdial: " + terr;
		fd = tlsfd;
	} else {
		# Plaintext connect, then STARTTLS
		# For now, only IMPLICIT_TLS is supported
		return "STARTTLS not yet implemented";
	}

	ibuf = bufio->fopen(fd, Bufio->OREAD);
	if(ibuf == nil)
		return "cannot open bufio on connection";

	tagnum = 0;
	connected = 1;

	# Read server greeting
	(greeting, gerr) := readline();
	if(gerr != nil) {
		disconnect();
		return "greeting: " + gerr;
	}
	if(DEBUG)
		sys->print("S: %s\n", greeting);

	# Check for OK greeting
	if(!hasprefix(greeting, "* OK")) {
		disconnect();
		return "bad greeting: " + greeting;
	}

	# Authenticate
	err := authenticate(user, password);
	if(err != nil) {
		disconnect();
		return err;
	}

	return nil;
}

# Authenticate with LOGIN command
# SASL PLAIN would be better but LOGIN works everywhere over TLS
authenticate(user, password: string): string
{
	tag := nexttag();
	cmd := tag + " LOGIN " + quote(user) + " " + quote(password);
	err := writeline(cmd);
	if(err != nil)
		return "LOGIN write: " + err;

	(resp, rerr) := readresponse(tag);
	if(rerr != nil)
		return "LOGIN: " + rerr;
	if(resp.status != "OK")
		return "LOGIN failed: " + resp.statusline;

	return nil;
}

folders(): (list of string, string)
{
	if(!connected)
		return (nil, "not connected");

	tag := nexttag();
	err := writeline(tag + " LIST \"\" *");
	if(err != nil)
		return (nil, "LIST write: " + err);

	(resp, rerr) := readresponse(tag);
	if(rerr != nil)
		return (nil, "LIST: " + rerr);
	if(resp.status != "OK")
		return (nil, "LIST failed: " + resp.statusline);

	# Parse untagged LIST responses
	# * LIST (\HasNoChildren) "/" "INBOX"
	result: list of string;
	for(l := resp.untagged; l != nil; l = tl l) {
		line := hd l;
		if(!hasprefix(line, "* LIST "))
			continue;
		# Find the last quoted string or atom
		name := parselistname(line);
		if(name != nil)
			result = name :: result;
	}

	return (reverse(result), nil);
}

select(mailbox: string): (ref Mailbox, string)
{
	if(!connected)
		return (nil, "not connected");

	tag := nexttag();
	err := writeline(tag + " SELECT " + quote(mailbox));
	if(err != nil)
		return (nil, "SELECT write: " + err);

	(resp, rerr) := readresponse(tag);
	if(rerr != nil)
		return (nil, "SELECT: " + rerr);
	if(resp.status != "OK")
		return (nil, "SELECT failed: " + resp.statusline);

	mbox := ref Mailbox(mailbox, 0, 0, 0, 0, 0);

	# Parse untagged responses for mailbox info
	for(l := resp.untagged; l != nil; l = tl l) {
		line := hd l;
		# * 172 EXISTS
		if(hassuffix(line, " EXISTS"))
			mbox.exists = parsenumber(line);
		# * 1 RECENT
		else if(hassuffix(line, " RECENT"))
			mbox.recent = parsenumber(line);
		# * OK [UNSEEN 12]
		else if(hasprefix(line, "* OK [UNSEEN "))
			mbox.unseen = parsebracketnum(line, "UNSEEN");
		# * OK [UIDNEXT 4392]
		else if(hasprefix(line, "* OK [UIDNEXT "))
			mbox.uidnext = parsebracketnum(line, "UIDNEXT");
		# * OK [UIDVALIDITY 3857529045]
		else if(hasprefix(line, "* OK [UIDVALIDITY "))
			mbox.uidvalidity = parsebracketnum(line, "UIDVALIDITY");
	}

	currentmbox = mailbox;
	return (mbox, nil);
}

msglist(first, last: int): (list of ref Msg, string)
{
	if(!connected)
		return (nil, "not connected");

	range := string first + ":" + string last;
	tag := nexttag();
	cmd := tag + " FETCH " + range +
		" (FLAGS UID RFC822.SIZE ENVELOPE)";
	err := writeline(cmd);
	if(err != nil)
		return (nil, "FETCH write: " + err);

	(resp, rerr) := readresponse(tag);
	if(rerr != nil)
		return (nil, "FETCH: " + rerr);
	if(resp.status != "OK")
		return (nil, "FETCH failed: " + resp.statusline);

	# Parse FETCH responses
	msgs: list of ref Msg;
	for(l := resp.untagged; l != nil; l = tl l) {
		line := hd l;
		if(!hasprefix(line, "* "))
			continue;
		# * N FETCH (...)
		msg := parsefetchline(line);
		if(msg != nil)
			msgs = msg :: msgs;
	}

	return (reversemsg(msgs), nil);
}

search(criteria: string): (list of int, string)
{
	if(!connected)
		return (nil, "not connected");

	tag := nexttag();
	err := writeline(tag + " SEARCH " + criteria);
	if(err != nil)
		return (nil, "SEARCH write: " + err);

	(resp, rerr) := readresponse(tag);
	if(rerr != nil)
		return (nil, "SEARCH: " + rerr);
	if(resp.status != "OK")
		return (nil, "SEARCH failed: " + resp.statusline);

	# Parse * SEARCH 2 5 7 ...
	result: list of int;
	for(l := resp.untagged; l != nil; l = tl l) {
		line := hd l;
		if(!hasprefix(line, "* SEARCH"))
			continue;
		rest := line[len "* SEARCH":];
		(nil, toks) := sys->tokenize(rest, " ");
		for(; toks != nil; toks = tl toks)
			result = int hd toks :: result;
	}

	return (reverseint(result), nil);
}

fetch(seq: int): (string, string)
{
	return fetchsection(seq, "BODY[]");
}

fetchhdr(seq: int): (string, string)
{
	return fetchsection(seq, "BODY[HEADER]");
}

fetchsection(seq: int, section: string): (string, string)
{
	if(!connected)
		return (nil, "not connected");

	tag := nexttag();
	cmd := tag + " FETCH " + string seq + " " + section;
	err := writeline(cmd);
	if(err != nil)
		return (nil, "FETCH write: " + err);

	(resp, rerr) := readresponse(tag);
	if(rerr != nil)
		return (nil, "FETCH: " + rerr);
	if(resp.status != "OK")
		return (nil, "FETCH failed: " + resp.statusline);

	# The body content may be in the literal data
	# attached to the FETCH response
	if(resp.literal != nil)
		return (string resp.literal, nil);

	# Try to extract from untagged data
	for(l := resp.untagged; l != nil; l = tl l) {
		line := hd l;
		if(hasprefix(line, "* " + string seq + " FETCH"))
			return (line, nil);
	}

	return (nil, "no content in FETCH response");
}

store(seq, flags, add: int): string
{
	if(!connected)
		return "not connected";

	action := "-FLAGS";
	if(add)
		action = "+FLAGS";

	flagstr := flagstostring(flags);
	tag := nexttag();
	cmd := tag + " STORE " + string seq + " " + action + " (" + flagstr + ")";
	err := writeline(cmd);
	if(err != nil)
		return "STORE write: " + err;

	(resp, rerr) := readresponse(tag);
	if(rerr != nil)
		return "STORE: " + rerr;
	if(resp.status != "OK")
		return "STORE failed: " + resp.statusline;

	return nil;
}

copy(seqs: string, dest: string): string
{
	if(!connected)
		return "not connected";

	tag := nexttag();
	cmd := tag + " COPY " + seqs + " " + quote(dest);
	err := writeline(cmd);
	if(err != nil)
		return "COPY write: " + err;

	(resp, rerr) := readresponse(tag);
	if(rerr != nil)
		return "COPY: " + rerr;
	if(resp.status != "OK")
		return "COPY failed: " + resp.statusline;

	return nil;
}

idle(updates: chan of string, stop: chan of int): string
{
	if(!connected)
		return "not connected";

	tag := nexttag();
	err := writeline(tag + " IDLE");
	if(err != nil)
		return "IDLE write: " + err;

	# Server sends + continuation, then untagged updates
	# Read lines until stop channel fires
	done := 0;
	spawn idlereader(updates, tag, done);

	<-stop;

	# Send DONE to end IDLE
	writeline("DONE");

	return nil;
}

idlereader(updates: chan of string, tag: string, done: int)
{
	while(!done) {
		(line, err) := readline();
		if(err != nil)
			return;

		# + continuation response - IDLE started
		if(hasprefix(line, "+"))
			continue;

		# Tagged response - IDLE ended
		if(hasprefix(line, tag))
			return;

		# Untagged data (EXISTS, EXPUNGE, etc.)
		updates <-= line;
	}
}

logout(): string
{
	if(!connected)
		return "not connected";

	tag := nexttag();
	writeline(tag + " LOGOUT");
	# Read BYE and tagged OK, but don't fail on errors
	readresponse(tag);
	disconnect();
	return nil;
}

# ---- Protocol I/O ----

# Tagged response structure
Response: adt {
	status:		string;		# "OK", "NO", "BAD"
	statusline:	string;		# full status line text
	untagged:	list of string;	# untagged * lines
	literal:	array of byte;	# literal data from {N}
};

nexttag(): string
{
	tagnum++;
	return sys->sprint("A%03d", tagnum);
}

writeline(s: string): string
{
	if(DEBUG)
		sys->print("C: %s\n", s);
	buf := array of byte (s + "\r\n");
	n := sys->write(fd, buf, len buf);
	if(n != len buf)
		return sys->sprint("write failed: %r");
	return nil;
}

readline(): (string, string)
{
	line := ibuf.gets('\n');
	if(line == nil)
		return (nil, "connection closed");

	# Strip trailing \r\n
	l := len line;
	if(l > 0 && line[l-1] == '\n')
		l--;
	if(l > 0 && line[l-1] == '\r')
		l--;
	line = line[0:l];

	if(DEBUG)
		sys->print("S: %s\n", line);

	return (line, nil);
}

# Read response lines until we see our tag.
# Collects untagged * lines and handles {N} literals.
readresponse(tag: string): (ref Response, string)
{
	untagged: list of string;
	literal: array of byte;

	for(;;) {
		(line, err) := readline();
		if(err != nil)
			return (nil, err);

		# Check for literal: line ends with {N}
		lit := checkliteral(line);
		if(lit > 0) {
			literal = readliteral(lit);
			# Read the continuation line after the literal
			(cont, cerr) := readline();
			if(cerr == nil && cont != nil)
				line = line + string literal + cont;
		}

		# Tagged response: our tag followed by OK/NO/BAD
		if(hasprefix(line, tag + " ")) {
			rest := line[len tag + 1:];
			status := "BAD";
			(nil, toks) := sys->tokenize(rest, " ");
			if(toks != nil)
				status = hd toks;
			resp := ref Response(
				str->toupper(status),
				rest,
				reversestr(untagged),
				literal);
			return (resp, nil);
		}

		# Untagged response
		if(hasprefix(line, "* "))
			untagged = line :: untagged;
		# + continuation (for IDLE, AUTHENTICATE, etc.)
		# Just collect it
		else if(hasprefix(line, "+"))
			untagged = line :: untagged;
	}
}

# Check if line ends with {N} literal indicator
checkliteral(line: string): int
{
	l := len line;
	if(l < 3 || line[l-1] != '}')
		return 0;

	# Find matching {
	i := l - 2;
	while(i > 0 && line[i] != '{')
		i--;
	if(i <= 0)
		return 0;

	numstr := line[i+1:l-1];
	n := int numstr;
	if(n <= 0)
		return 0;
	return n;
}

# Read exactly n bytes of literal data
readliteral(n: int): array of byte
{
	buf := array[n] of byte;
	off := 0;
	while(off < n) {
		# Read raw bytes from the underlying FD since bufio
		# may have buffered data -- use ibuf.read instead
		got := ibuf.read(buf[off:], n - off);
		if(got <= 0)
			break;
		off += got;
	}
	if(off < n)
		return buf[:off];
	return buf;
}

disconnect()
{
	connected = 0;
	ibuf = nil;
	fd = nil;
	currentmbox = nil;
}

# ---- FETCH response parser ----

# Parse "* N FETCH (...)" line into a Msg
parsefetchline(line: string): ref Msg
{
	ensureloaded();
	# * 1 FETCH (FLAGS (\Seen) UID 123 RFC822.SIZE 4567 ENVELOPE (...))
	if(!hasprefix(line, "* "))
		return nil;

	# Extract sequence number
	rest := line[2:];
	(seq, rest2) := gettoken(rest);
	seqnum := int seq;
	if(seqnum <= 0)
		return nil;

	# Skip "FETCH"
	(tok, rest3) := gettoken(rest2);
	if(str->toupper(tok) != "FETCH")
		return nil;

	# Parse the parenthesized data
	msg := ref Msg(seqnum, 0, 0, 0, nil);
	parsefetchdata(rest3, msg);
	return msg;
}

# Parse the parenthesized FETCH data items
parsefetchdata(data: string, msg: ref Msg)
{
	# Strip outer parens
	data = stripws(data);
	if(len data > 0 && data[0] == '(')
		data = data[1:];
	if(len data > 0 && data[len data - 1] == ')')
		data = data[:len data - 1];

	# Parse key-value pairs
	i := 0;
	while(i < len data) {
		# Skip whitespace
		while(i < len data && (data[i] == ' ' || data[i] == '\t'))
			i++;
		if(i >= len data)
			break;

		# Read key
		keystart := i;
		while(i < len data && data[i] != ' ' && data[i] != '(')
			i++;
		key := str->toupper(data[keystart:i]);

		# Skip whitespace
		while(i < len data && data[i] == ' ')
			i++;

		case key {
		"FLAGS" =>
			# (flag flag ...)
			(flags, ni) := parseflaglist(data, i);
			msg.flags = flags;
			i = ni;
		"UID" =>
			(val, ni) := getint(data, i);
			msg.uid = val;
			i = ni;
		"RFC822.SIZE" =>
			(val, ni) := getint(data, i);
			msg.size = val;
			i = ni;
		"ENVELOPE" =>
			(env, ni) := parseenvelope(data, i);
			msg.envelope = env;
			i = ni;
		* =>
			# Skip unknown item value
			i = skipvalue(data, i);
		}
	}
}

# Parse a parenthesized flag list like (\Seen \Flagged)
parseflaglist(data: string, pos: int): (int, int)
{
	flags := 0;
	if(pos >= len data || data[pos] != '(')
		return (0, pos);
	pos++;

	while(pos < len data && data[pos] != ')') {
		# Skip whitespace
		while(pos < len data && data[pos] == ' ')
			pos++;
		if(pos >= len data || data[pos] == ')')
			break;

		# Read flag atom
		start := pos;
		while(pos < len data && data[pos] != ' ' && data[pos] != ')')
			pos++;
		flag := data[start:pos];
		flags |= flagfromstring(flag);
	}

	if(pos < len data && data[pos] == ')')
		pos++;

	return (flags, pos);
}

# Parse ENVELOPE structure
# (date subject from to cc bcc replyto messageid)
# Each address is ((name route mailbox host)) or NIL
parseenvelope(data: string, pos: int): (ref Envelope, int)
{
	if(pos >= len data || data[pos] != '(')
		return (nil, pos);
	pos++;	# skip (

	env := ref Envelope(nil, nil, nil, nil, nil, nil, nil);

	# date
	(env.date, pos) = parseatom(data, pos);
	pos = skipws2(data, pos);

	# subject
	(env.subject, pos) = parseatom(data, pos);
	pos = skipws2(data, pos);

	# from (address list) -> stored in .sender
	(env.sender, pos) = parseaddrlist(data, pos);
	pos = skipws2(data, pos);

	# sender (IMAP envelope sender) - skip
	(nil, pos) = parseaddrlist(data, pos);
	pos = skipws2(data, pos);

	# reply-to
	(env.replyto, pos) = parseaddrlist(data, pos);
	pos = skipws2(data, pos);

	# to -> stored in .recipient
	(env.recipient, pos) = parseaddrlist(data, pos);
	pos = skipws2(data, pos);

	# cc
	(env.cc, pos) = parseaddrlist(data, pos);
	pos = skipws2(data, pos);

	# bcc - skip
	(nil, pos) = parseaddrlist(data, pos);
	pos = skipws2(data, pos);

	# in-reply-to - skip
	(nil, pos) = parseatom(data, pos);
	pos = skipws2(data, pos);

	# message-id
	(env.messageid, pos) = parseatom(data, pos);

	# Find closing paren
	while(pos < len data && data[pos] != ')')
		pos++;
	if(pos < len data)
		pos++;

	return (env, pos);
}

# Parse an IMAP atom, quoted string, literal, or NIL
parseatom(data: string, pos: int): (string, int)
{
	pos = skipws2(data, pos);
	if(pos >= len data)
		return (nil, pos);

	# NIL
	if(pos + 3 <= len data && str->toupper(data[pos:pos+3]) == "NIL") {
		return (nil, pos + 3);
	}

	# Quoted string
	if(data[pos] == '"') {
		pos++;
		start := pos;
		while(pos < len data && data[pos] != '"') {
			if(data[pos] == '\\')
				pos++;	# skip escaped char
			pos++;
		}
		val := data[start:pos];
		if(pos < len data)
			pos++;	# skip closing "
		return (val, pos);
	}

	# Literal {N}
	if(data[pos] == '{') {
		lend := pos + 1;
		while(lend < len data && data[lend] != '}')
			lend++;
		# Literal data should already be inlined by readresponse
		if(lend < len data)
			return (nil, lend + 1);
		return (nil, pos);
	}

	# Parenthesized list - skip it
	if(data[pos] == '(') {
		depth := 0;
		start := pos;
		while(pos < len data) {
			if(data[pos] == '(')
				depth++;
			else if(data[pos] == ')') {
				depth--;
				if(depth == 0) {
					pos++;
					return (data[start:pos], pos);
				}
			} else if(data[pos] == '"') {
				pos++;
				while(pos < len data && data[pos] != '"') {
					if(data[pos] == '\\')
						pos++;
					pos++;
				}
			}
			pos++;
		}
		return (data[start:pos], pos);
	}

	# Bare atom
	start := pos;
	while(pos < len data && data[pos] != ' ' && data[pos] != ')'
		&& data[pos] != '(' && data[pos] != '"')
		pos++;
	return (data[start:pos], pos);
}

# Parse an address list: ((name route mbox host) ...) or NIL
# Returns a formatted string like "Name <mbox@host>"
parseaddrlist(data: string, pos: int): (string, int)
{
	pos = skipws2(data, pos);
	if(pos >= len data)
		return (nil, pos);

	# NIL
	if(pos + 3 <= len data && str->toupper(data[pos:pos+3]) == "NIL")
		return (nil, pos + 3);

	if(data[pos] != '(')
		return (nil, pos);
	pos++;	# skip outer (

	addrs := "";
	while(pos < len data && data[pos] != ')') {
		pos = skipws2(data, pos);
		if(pos >= len data || data[pos] == ')')
			break;

		if(data[pos] != '(') {
			pos++;
			continue;
		}
		pos++;	# skip (

		# (name route mailbox host)
		(name, npos) := parseatom(data, pos);
		pos = npos;
		pos = skipws2(data, pos);

		# route - skip
		(nil, rpos) := parseatom(data, pos);
		pos = rpos;
		pos = skipws2(data, pos);

		# mailbox
		(mbox, mpos) := parseatom(data, pos);
		pos = mpos;
		pos = skipws2(data, pos);

		# host
		(host, hpos) := parseatom(data, pos);
		pos = hpos;

		# Skip to closing )
		while(pos < len data && data[pos] != ')')
			pos++;
		if(pos < len data)
			pos++;

		# Format address
		addr := "";
		if(mbox != nil && host != nil)
			addr = mbox + "@" + host;
		else if(mbox != nil)
			addr = mbox;

		if(name != nil && addr != nil)
			addr = name + " <" + addr + ">";

		if(addrs != "" && addr != "")
			addrs += ", ";
		if(addr != "")
			addrs += addr;
	}

	# Skip closing )
	if(pos < len data && data[pos] == ')')
		pos++;

	return (addrs, pos);
}

# Skip a value in FETCH data (atom, quoted string, or paren list)
skipvalue(data: string, pos: int): int
{
	pos = skipws2(data, pos);
	if(pos >= len data)
		return pos;

	if(data[pos] == '(') {
		depth := 0;
		while(pos < len data) {
			if(data[pos] == '(')
				depth++;
			else if(data[pos] == ')') {
				depth--;
				if(depth == 0) {
					pos++;
					return pos;
				}
			} else if(data[pos] == '"') {
				pos++;
				while(pos < len data && data[pos] != '"') {
					if(data[pos] == '\\')
						pos++;
					pos++;
				}
			}
			pos++;
		}
		return pos;
	}

	if(data[pos] == '"') {
		pos++;
		while(pos < len data && data[pos] != '"') {
			if(data[pos] == '\\')
				pos++;
			pos++;
		}
		if(pos < len data)
			pos++;
		return pos;
	}

	# Atom
	while(pos < len data && data[pos] != ' ' && data[pos] != ')')
		pos++;
	return pos;
}

# ---- Flag conversion ----

flagfromstring(s: string): int
{
	ls := str->tolower(s);
	case ls {
	"\\seen" =>		return FSEEN;
	"\\answered" =>	return FANSWERED;
	"\\flagged" =>	return FFLAGGED;
	"\\deleted" =>	return FDELETED;
	"\\draft" =>	return FDRAFT;
	}
	return 0;
}

flagstostring(flags: int): string
{
	s := "";
	if(flags & FSEEN) s = addws(s, "\\Seen");
	if(flags & FANSWERED) s = addws(s, "\\Answered");
	if(flags & FFLAGGED) s = addws(s, "\\Flagged");
	if(flags & FDELETED) s = addws(s, "\\Deleted");
	if(flags & FDRAFT) s = addws(s, "\\Draft");
	return s;
}

addws(a, b: string): string
{
	if(a == "")
		return b;
	return a + " " + b;
}

# Parse flags string to bitmask (exported for testing)
parseflags(s: string): int
{
	ensureloaded();
	flags := 0;
	(nil, toks) := sys->tokenize(s, " ()");
	for(; toks != nil; toks = tl toks)
		flags |= flagfromstring(hd toks);
	return flags;
}

# ---- LIST response parsing ----

# Parse mailbox name from LIST response
# * LIST (\HasNoChildren) "/" "INBOX"
# * LIST (\HasNoChildren) "/" INBOX
parselistname(line: string): string
{
	# Find the delimiter (second quoted string or second space-separated section)
	# The name is the last token after the delimiter

	# Strategy: find last space-separated token or quoted string
	i := len line - 1;

	# Handle trailing whitespace
	while(i >= 0 && (line[i] == ' ' || line[i] == '\t'))
		i--;

	if(i < 0)
		return nil;

	# Quoted name
	if(line[i] == '"') {
		end := i;
		i--;
		while(i >= 0 && line[i] != '"')
			i--;
		if(i >= 0)
			return line[i+1:end];
		return nil;
	}

	# Unquoted name
	end := i + 1;
	while(i >= 0 && line[i] != ' ')
		i--;
	return line[i+1:end];
}

# ---- Helper functions ----

# Get an integer from data at position pos
getint(data: string, pos: int): (int, int)
{
	pos = skipws2(data, pos);
	start := pos;
	while(pos < len data && data[pos] >= '0' && data[pos] <= '9')
		pos++;
	if(start == pos)
		return (0, pos);
	return (int data[start:pos], pos);
}

# Get a whitespace-delimited token
gettoken(s: string): (string, string)
{
	# Skip leading whitespace
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;
	start := i;
	while(i < len s && s[i] != ' ' && s[i] != '\t')
		i++;
	if(start == i)
		return (nil, s);
	return (s[start:i], s[i:]);
}

# Parse "* N SOMETHING" -- extract N
parsenumber(line: string): int
{
	# Skip "* "
	if(len line < 3)
		return 0;
	rest := line[2:];
	(tok, nil) := gettoken(rest);
	return int tok;
}

# Parse "* OK [KEY N]" -- extract N for the given KEY
parsebracketnum(line: string, key: string): int
{
	target := "[" + key + " ";
	i := strindex(line, target);
	if(i < 0)
		return 0;
	start := i + len target;
	end := start;
	while(end < len line && line[end] != ']' && line[end] != ' ')
		end++;
	return int line[start:end];
}

# IMAP quoting: wrap in double quotes, escape \ and "
quote(s: string): string
{
	result := "\"";
	for(i := 0; i < len s; i++) {
		if(s[i] == '"' || s[i] == '\\')
			result += "\\";
		result += s[i:i+1];
	}
	result += "\"";
	return result;
}

strindex(s, sub: string): int
{
	if(len sub > len s)
		return -1;
	for(i := 0; i <= len s - len sub; i++) {
		if(s[i:i+len sub] == sub)
			return i;
	}
	return -1;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

hassuffix(s, suffix: string): int
{
	return len s >= len suffix && s[len s - len suffix:] == suffix;
}

stripws(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t'))
		j--;
	return s[i:j];
}

skipws2(data: string, pos: int): int
{
	while(pos < len data && (data[pos] == ' ' || data[pos] == '\t'))
		pos++;
	return pos;
}

# List reversal helpers
reverse(l: list of string): list of string
{
	r: list of string;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

reversestr(l: list of string): list of string
{
	return reverse(l);
}

reversemsg(l: list of ref Msg): list of ref Msg
{
	r: list of ref Msg;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

reverseint(l: list of int): list of int
{
	r: list of int;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}
