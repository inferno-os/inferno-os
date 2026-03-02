implement ToolMail;

#
# mail - Email tool for Veltro agent
#
# IMAP client for reading, searching, and managing email.
# SMTP for sending. Uses factotum for credentials.
#
# Usage:
#   mail config <server>               Set IMAP server
#   mail check                         Check inbox status
#   mail list [N]                      List last N messages (default 10)
#   mail read <N>                      Read message N
#   mail search <terms>                Server-side search
#   mail flag <N> seen|unseen|flagged|unflagged  Set/clear flags
#   mail send <to> <subject> <body>    Send via SMTP
#   mail folders                       List mailboxes
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "imap.m";
	imap: Imap;
	Msg, Envelope, Mailbox: import imap;

include "smtp.m";
	smtp: Smtp;

include "../tool.m";

ToolMail: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

imapserver: string;
imapconnected := 0;
currentmbox: ref Mailbox;

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	imap = load Imap Imap->PATH;
	if(imap == nil)
		return "cannot load Imap";
	smtp = load Smtp Smtp->PATH;
	# smtp is optional - don't fail if unavailable
	return nil;
}

name(): string
{
	return "mail";
}

doc(): string
{
	return "Mail - IMAP email client\n\n" +
		"Usage:\n" +
		"  mail config <server>              Set IMAP server and connect\n" +
		"  mail check                        Check inbox (message/unseen count)\n" +
		"  mail list [N]                     List last N messages (default 10)\n" +
		"  mail read <N>                     Fetch and display message N\n" +
		"  mail search <terms>               Server-side IMAP SEARCH\n" +
		"  mail flag <N> seen|unseen|flagged|unflagged  Set/clear flags\n" +
		"  mail send <to> <subject> <body>   Send email via SMTP\n" +
		"  mail folders                      List available mailboxes\n\n" +
		"Arguments:\n" +
		"  server - IMAP server hostname (e.g. imap.gmail.com)\n" +
		"  N      - Message sequence number\n" +
		"  terms  - IMAP SEARCH criteria (e.g. FROM smith, SUBJECT report)\n\n" +
		"Notes:\n" +
		"  - Credentials from factotum (proto=pass service=imap dom=<server>)\n" +
		"  - Connects via TLS on port 993\n" +
		"  - Connection persists across commands\n" +
		"  - Requires /net access";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	(n, argv) := sys->tokenize(args, " \t");
	if(n < 1)
		return "error: usage: mail <command> [args...]";

	cmd := str->tolower(hd argv);
	argv = tl argv;

	case cmd {
	"config" =>
		return doconfig(argv);
	"check" =>
		return docheck();
	"list" =>
		return dolist(argv);
	"read" =>
		return doread(argv);
	"search" =>
		return dosearch(argv);
	"flag" =>
		return doflag(argv);
	"send" =>
		return dosend(argv);
	"folders" =>
		return dofolders();
	* =>
		return "error: unknown command: " + cmd +
			"\nCommands: config, check, list, read, search, flag, send, folders";
	}
}

# Connect to IMAP server
doconfig(argv: list of string): string
{
	if(argv == nil)
		return "error: usage: mail config <server>";

	server := hd argv;

	# Disconnect if already connected
	if(imapconnected) {
		imap->logout();
		imapconnected = 0;
	}

	imapserver = server;

	# Connect using factotum credentials (user=nil, password=nil triggers factotum)
	err := imap->open(nil, nil, server, Imap->IMPLICIT_TLS);
	if(err != nil)
		return "error: connect to " + server + ": " + err;

	imapconnected = 1;

	# Auto-select INBOX
	(mbox, serr) := imap->select("INBOX");
	if(serr != nil)
		return "Connected to " + server + " but SELECT INBOX failed: " + serr;

	currentmbox = mbox;

	return sys->sprint("Connected to %s\nINBOX: %d messages, %d unseen",
		server, mbox.exists, mbox.unseen);
}

# Check inbox status
docheck(): string
{
	err := ensureconnected();
	if(err != nil)
		return err;

	# Re-SELECT to refresh counts
	(mbox, serr) := imap->select("INBOX");
	if(serr != nil)
		return "error: SELECT INBOX: " + serr;

	currentmbox = mbox;

	return sys->sprint("INBOX: %d messages, %d recent, unseen from #%d",
		mbox.exists, mbox.recent, mbox.unseen);
}

# List recent messages
dolist(argv: list of string): string
{
	err := ensureconnected();
	if(err != nil)
		return err;

	count := 10;
	if(argv != nil)
		count = int hd argv;
	if(count <= 0)
		count = 10;

	if(currentmbox == nil || currentmbox.exists == 0)
		return "No messages in mailbox";

	first := currentmbox.exists - count + 1;
	if(first < 1)
		first = 1;

	(msgs, ferr) := imap->msglist(first, currentmbox.exists);
	if(ferr != nil)
		return "error: " + ferr;

	result := "";
	for(ml := msgs; ml != nil; ml = tl ml) {
		m := hd ml;
		flagstr := formatflags(m.flags);
		from := "?";
		subject := "(no subject)";
		if(m.envelope != nil) {
			if(m.envelope.sender != nil)
				from = m.envelope.sender;
			if(m.envelope.subject != nil)
				subject = m.envelope.subject;
		}

		# Truncate from/subject for display
		if(len from > 30)
			from = from[:27] + "...";
		if(len subject > 50)
			subject = subject[:47] + "...";

		if(result != "")
			result += "\n";
		result += sys->sprint("%4d %s %-30s %s",
			m.seq, flagstr, from, subject);
	}

	return result;
}

# Format flags for display
formatflags(flags: int): string
{
	s := "";
	if(flags & Imap->FSEEN)
		s += "R";	# Read
	else
		s += "N";	# New/unread
	if(flags & Imap->FANSWERED)
		s += "A";
	else
		s += " ";
	if(flags & Imap->FFLAGGED)
		s += "*";
	else
		s += " ";
	return s;
}

# Read a message
doread(argv: list of string): string
{
	if(argv == nil)
		return "error: usage: mail read <N>";

	err := ensureconnected();
	if(err != nil)
		return err;

	seq := int hd argv;
	if(seq <= 0)
		return "error: invalid message number";

	# Fetch headers first for display
	(hdr, herr) := imap->fetchhdr(seq);
	if(herr != nil)
		return "error: fetch headers: " + herr;

	# Fetch full body
	(body, berr) := imap->fetch(seq);
	if(berr != nil)
		return "error: fetch body: " + berr;

	# Mark as seen
	imap->store(seq, Imap->FSEEN, 1);

	# Format for display
	result := "";
	if(hdr != nil && hdr != body)
		result = formatheaders(hdr) + "\n---\n";
	result += body;

	# Truncate if very large
	if(len result > 32768)
		result = result[:32768] + "\n... (truncated)";

	return result;
}

# Extract useful headers from raw header text
formatheaders(hdr: string): string
{
	result := "";
	lines := splitlines(hdr);
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		lline := str->tolower(line);
		if(hasprefix(lline, "from:") || hasprefix(lline, "to:") ||
		   hasprefix(lline, "cc:") || hasprefix(lline, "subject:") ||
		   hasprefix(lline, "date:")) {
			if(result != "")
				result += "\n";
			result += line;
		}
	}
	return result;
}

# Search messages
dosearch(argv: list of string): string
{
	if(argv == nil)
		return "error: usage: mail search <criteria>";

	err := ensureconnected();
	if(err != nil)
		return err;

	# Join all args as search criteria
	criteria := "";
	for(; argv != nil; argv = tl argv) {
		if(criteria != "")
			criteria += " ";
		criteria += hd argv;
	}

	(seqs, serr) := imap->search(criteria);
	if(serr != nil)
		return "error: " + serr;

	if(seqs == nil)
		return "No messages match: " + criteria;

	# Fetch summaries for matching messages (up to 20)
	count := 0;
	result := "";
	for(sl := seqs; sl != nil && count < 20; sl = tl sl) {
		seq := hd sl;
		(msgs, ferr) := imap->msglist(seq, seq);
		if(ferr != nil)
			continue;
		for(ml := msgs; ml != nil; ml = tl ml) {
			m := hd ml;
			from := "?";
			subject := "(no subject)";
			if(m.envelope != nil) {
				if(m.envelope.sender != nil)
					from = m.envelope.sender;
				if(m.envelope.subject != nil)
					subject = m.envelope.subject;
			}
			if(len from > 30)
				from = from[:27] + "...";
			if(len subject > 50)
				subject = subject[:47] + "...";
			if(result != "")
				result += "\n";
			result += sys->sprint("%4d %-30s %s", m.seq, from, subject);
			count++;
		}
	}

	nmatches := intlistlen(seqs);
	if(nmatches > 20)
		result += sys->sprint("\n... and %d more", nmatches - 20);

	return result;
}

# Set/clear message flags
doflag(argv: list of string): string
{
	if(argv == nil || tl argv == nil)
		return "error: usage: mail flag <N> seen|unseen|flagged|unflagged";

	err := ensureconnected();
	if(err != nil)
		return err;

	seq := int hd argv;
	if(seq <= 0)
		return "error: invalid message number";

	action := str->tolower(hd tl argv);

	flags := 0;
	add := 1;

	case action {
	"seen" or "read" =>
		flags = Imap->FSEEN;
		add = 1;
	"unseen" or "unread" =>
		flags = Imap->FSEEN;
		add = 0;
	"flagged" or "star" =>
		flags = Imap->FFLAGGED;
		add = 1;
	"unflagged" or "unstar" =>
		flags = Imap->FFLAGGED;
		add = 0;
	* =>
		return "error: unknown flag action: " + action +
			"\nUse: seen, unseen, flagged, unflagged";
	}

	ferr := imap->store(seq, flags, add);
	if(ferr != nil)
		return "error: " + ferr;

	return sys->sprint("Message %d: %s", seq, action);
}

# Send email via SMTP
dosend(argv: list of string): string
{
	if(smtp == nil)
		return "error: SMTP module not available";

	if(argv == nil || tl argv == nil || tl tl argv == nil)
		return "error: usage: mail send <to> <subject> <body>";

	rcpt := hd argv;
	subject := hd tl argv;
	argv = tl tl argv;

	# Join remaining as body
	body := "";
	for(; argv != nil; argv = tl argv) {
		if(body != "")
			body += " ";
		body += hd argv;
	}

	# Get sender from /dev/user
	sender := readfile("/dev/user");
	if(sender == nil)
		sender = "inferno";

	# Build message lines
	msg: list of string;
	msg = "Subject: " + subject :: msg;
	msg = "To: " + rcpt :: msg;
	msg = "From: " + sender :: msg;
	msg = "" :: msg;
	msg = body :: msg;

	# Reverse since we built in reverse order
	rmsg: list of string;
	for(; msg != nil; msg = tl msg)
		rmsg = hd msg :: rmsg;

	# Try to determine SMTP server from IMAP server
	smtpserver := imapserver;
	if(smtpserver == nil)
		smtpserver = "$smtp";

	(ok, serr) := smtp->open(smtpserver);
	if(ok < 0)
		return "error: SMTP connect: " + serr;

	(ok, serr) = smtp->sendmail(sender, rcpt :: nil, nil, rmsg);
	smtp->close();

	if(ok < 0)
		return "error: send failed: " + serr;

	return "Sent to " + rcpt;
}

# List mailbox folders
dofolders(): string
{
	err := ensureconnected();
	if(err != nil)
		return err;

	(fl, ferr) := imap->folders();
	if(ferr != nil)
		return "error: " + ferr;

	if(fl == nil)
		return "No folders found";

	result := "";
	for(; fl != nil; fl = tl fl) {
		if(result != "")
			result += "\n";
		result += hd fl;
	}
	return result;
}

# Ensure IMAP connection is active, reconnect if needed
ensureconnected(): string
{
	if(!imapconnected) {
		if(imapserver == nil)
			return "error: not configured. Use: mail config <server>";
		# Try to reconnect
		err := imap->open(nil, nil, imapserver, Imap->IMPLICIT_TLS);
		if(err != nil)
			return "error: reconnect to " + imapserver + ": " + err;
		imapconnected = 1;

		(mbox, serr) := imap->select("INBOX");
		if(serr == nil)
			currentmbox = mbox;
	}
	return nil;
}

# ---- Helpers ----

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[:n];
}

splitlines(s: string): list of string
{
	result: list of string;
	start := 0;
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n') {
			line := s[start:i];
			if(len line > 0 && line[len line - 1] == '\r')
				line = line[:len line - 1];
			result = line :: result;
			start = i + 1;
		}
	}
	if(start < len s) {
		line := s[start:];
		if(len line > 0 && line[len line - 1] == '\r')
			line = line[:len line - 1];
		result = line :: result;
	}

	# Reverse
	rev: list of string;
	for(; result != nil; result = tl result)
		rev = hd result :: rev;
	return rev;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[:len prefix] == prefix;
}

intlistlen(l: list of int): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}
