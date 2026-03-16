implement EmailSrc;

#
# email - Email message source for Veltro
#
# Implements MsgSrc interface using IMAP (receive, IDLE push) and
# SMTP (send/reply). Credentials via factotum.
#
# Config format (key=value pairs):
#   server=imap.example.com
#   folder=INBOX                   (default: INBOX)
#   smtpserver=smtp.example.com    (default: same as server)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "daytime.m";
	daytime: Daytime;

include "imap.m";
	imap: Imap;
	Msg, Envelope, Mailbox: import imap;

include "smtp.m";
	smtp: Smtp;

include "msgsrc.m";

EmailSrc: module {
	init:    fn(config: string): string;
	name:    fn(): string;
	status:  fn(): string;
	close:   fn(): string;
	watch:   fn(updates: chan of ref MsgSrc->Notification, stop: chan of int): string;
	list:    fn(channel: string, count: int): (list of ref MsgSrc->Message, string);
	fetch:   fn(id: string): (ref MsgSrc->Message, string);
	search:  fn(query: string): (list of ref MsgSrc->Message, string);
	send:    fn(msg: ref MsgSrc->Message): string;
	reply:   fn(origid, body: string): string;
	setflag: fn(id: string, flag, add: int): string;
};

Message: import MsgSrc;
Notification: import MsgSrc;

# Configuration
imapserver: string;
smtpserver: string;
folder := "INBOX";
imapconnected := 0;
currentmbox: ref Mailbox;
prevexists := 0;	# track message count for IDLE new-message detection

stderr: ref Sys->FD;

init(config: string): string
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";

	imap = load Imap Imap->PATH;
	if(imap == nil)
		return "cannot load Imap";

	smtp = load Smtp Smtp->PATH;
	# smtp optional — don't fail

	daytime = load Daytime Daytime->PATH;

	# Parse key=value config
	imapserver = getcfg(config, "server");
	if(imapserver == nil)
		return "config: server= required";

	smtpserver = getcfg(config, "smtpserver");
	if(smtpserver == nil)
		smtpserver = imapserver;

	f := getcfg(config, "folder");
	if(f != nil)
		folder = f;

	# Connect
	err := imap->open(nil, nil, imapserver, Imap->IMPLICIT_TLS);
	if(err != nil)
		return "IMAP connect: " + err;

	imapconnected = 1;

	(mbox, serr) := imap->select(folder);
	if(serr != nil)
		return "SELECT " + folder + ": " + serr;

	currentmbox = mbox;
	prevexists = mbox.exists;

	return nil;
}

name(): string
{
	return "email";
}

status(): string
{
	if(!imapconnected)
		return "disconnected";
	if(currentmbox == nil)
		return "connected to " + imapserver + " (no mailbox)";
	return sys->sprint("connected %s/%s %d messages %d unseen",
		imapserver, folder, currentmbox.exists, currentmbox.unseen);
}

close(): string
{
	if(imapconnected) {
		imap->logout();
		imapconnected = 0;
	}
	return nil;
}

# watch: push interface using IMAP IDLE.
# Blocks, pushes new-message Notifications on updates channel.
# Send on stop channel to terminate.
watch(updates: chan of ref Notification, stop: chan of int): string
{
	if(!imapconnected)
		return "not connected";

	IDLE_TIMEOUT: con 29 * 60 * 1000;	# RFC 2177: re-issue every 29 min
	RECONNECT_MAX: con 60000;		# max backoff 60s

	backoff := 1000;

	for(;;) {
		# Ensure connected
		if(!imapconnected) {
			err := reconnect();
			if(err != nil) {
				updates <-= ref Notification("error", nil, "reconnect: " + err);
				sys->sleep(backoff);
				if(backoff < RECONNECT_MAX)
					backoff *= 2;
				# Check if we should stop
				alt {
				<-stop =>
					return nil;
				* =>
					;
				}
				continue;
			}
			backoff = 1000;	# reset on success
		}

		# Start IDLE session
		imapupdates := chan of string;
		imapstop := chan of int;

		# Timer goroutine: re-issue IDLE every 29 min
		timer := chan of int;
		spawn idletimer(timer, IDLE_TIMEOUT);

		# Start IDLE in background
		idledone := chan of string;
		spawn idlewrapper(imapupdates, imapstop, idledone);

		# Multiplex: IMAP updates, timer, stop
		idleloop: for(;;) alt {
		line := <-imapupdates =>
			if(line == nil) {
				# Reader exited — connection lost
				imapconnected = 0;
				break idleloop;
			}
			# Parse IDLE response line
			# Format: "* N EXISTS" or "* N EXPUNGE" etc.
			handleidleline(line, updates);

		<-timer =>
			# 29-min timeout: restart IDLE
			imapstop <-= 1;
			<-idledone;
			break idleloop;

		<-stop =>
			# Shutdown requested
			imapstop <-= 1;
			<-idledone;
			return nil;
		}
	}
}

# Wrapper to run imap->idle() and signal completion
idlewrapper(updates: chan of string, stop: chan of int, done: chan of string)
{
	err := imap->idle(updates, stop);
	if(err != nil)
		done <-= err;
	else
		done <-= "";
}

idletimer(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

# Parse an IDLE untagged response and push Notifications for new messages
handleidleline(line: string, updates: chan of ref Notification)
{
	# Format: "* 42 EXISTS"
	if(!hasprefix(line, "* "))
		return;

	rest := line[2:];
	(ntoks, toks) := sys->tokenize(rest, " ");
	if(ntoks < 2)
		return;

	numstr := hd toks;
	verb := str->toupper(hd tl toks);

	case verb {
	"EXISTS" =>
		newcount := int numstr;
		if(newcount > prevexists) {
			# New messages arrived — fetch envelopes
			for(seq := prevexists + 1; seq <= newcount; seq++)
				fetchandnotify(seq, updates);
		}
		prevexists = newcount;

	"EXPUNGE" =>
		prevexists--;
		if(prevexists < 0)
			prevexists = 0;
		updates <-= ref Notification("delete", nil, "message " + numstr + " expunged");
	}
}

# Fetch a single message envelope and push a "new" Notification
fetchandnotify(seq: int, updates: chan of ref Notification)
{
	(msgs, err) := imap->msglist(seq, seq);
	if(err != nil || msgs == nil)
		return;

	m := hd msgs;
	msg := imaptomsg(m);
	updates <-= ref Notification("new", msg, nil);
}

# Convert IMAP Msg/Envelope to MsgSrc Message
imaptomsg(m: ref Msg): ref Message
{
	msg := ref Message;
	msg.id = string m.seq;
	msg.source = "email";
	msg.channel = folder;
	msg.flags = 0;
	if(!(m.flags & Imap->FSEEN))
		msg.flags |= MsgSrc->FUNREAD;
	if(m.flags & Imap->FFLAGGED)
		msg.flags |= MsgSrc->FFLAGGED;
	msg.timestamp = "";
	msg.threadid = "";
	msg.replyto = "";
	msg.headers = "";
	msg.body = "";

	if(m.envelope != nil) {
		msg.sender = m.envelope.sender;
		msg.recipient = m.envelope.recipient;
		msg.subject = m.envelope.subject;
		msg.timestamp = m.envelope.date;
		msg.replyto = "";
		if(m.envelope.messageid != nil)
			msg.threadid = m.envelope.messageid;
	}

	return msg;
}

reconnect(): string
{
	err := imap->open(nil, nil, imapserver, Imap->IMPLICIT_TLS);
	if(err != nil)
		return err;
	imapconnected = 1;

	(mbox, serr) := imap->select(folder);
	if(serr != nil)
		return serr;
	currentmbox = mbox;
	prevexists = mbox.exists;
	return nil;
}

# list: return last N messages from the current folder
list(channel: string, count: int): (list of ref Message, string)
{
	err := ensureconnected();
	if(err != nil)
		return (nil, err);

	if(channel != "" && channel != folder) {
		(mbox, serr) := imap->select(channel);
		if(serr != nil)
			return (nil, "SELECT " + channel + ": " + serr);
		currentmbox = mbox;
	}

	if(currentmbox == nil || currentmbox.exists == 0)
		return (nil, nil);

	if(count <= 0)
		count = 10;
	first := currentmbox.exists - count + 1;
	if(first < 1)
		first = 1;

	(msgs, ferr) := imap->msglist(first, currentmbox.exists);
	if(ferr != nil)
		return (nil, ferr);

	result: list of ref Message;
	for(ml := msgs; ml != nil; ml = tl ml)
		result = imaptomsg(hd ml) :: result;

	# Reverse
	rev: list of ref Message;
	for(; result != nil; result = tl result)
		rev = hd result :: rev;
	return (rev, nil);
}

# fetch: return a single message with full body
fetch(id: string): (ref Message, string)
{
	err := ensureconnected();
	if(err != nil)
		return (nil, err);

	seq := int id;
	if(seq <= 0)
		return (nil, "invalid message id");

	# Get envelope
	(msgs, merr) := imap->msglist(seq, seq);
	if(merr != nil)
		return (nil, merr);
	if(msgs == nil)
		return (nil, "message not found");

	msg := imaptomsg(hd msgs);

	# Fetch body
	(body, berr) := imap->fetch(seq);
	if(berr != nil)
		return (nil, "fetch body: " + berr);
	msg.body = body;

	# Fetch headers for threading info
	(hdr, herr) := imap->fetchhdr(seq);
	if(herr == nil)
		msg.headers = hdr;

	return (msg, nil);
}

# search: server-side IMAP SEARCH
search(query: string): (list of ref Message, string)
{
	err := ensureconnected();
	if(err != nil)
		return (nil, err);

	(seqs, serr) := imap->search(query);
	if(serr != nil)
		return (nil, serr);

	result: list of ref Message;
	count := 0;
	for(sl := seqs; sl != nil && count < 20; sl = tl sl) {
		(msgs, ferr) := imap->msglist(hd sl, hd sl);
		if(ferr != nil)
			continue;
		for(ml := msgs; ml != nil; ml = tl ml) {
			result = imaptomsg(hd ml) :: result;
			count++;
		}
	}

	# Reverse
	rev: list of ref Message;
	for(; result != nil; result = tl result)
		rev = hd result :: rev;
	return (rev, nil);
}

# send: compose and send a new email via SMTP
send(msg: ref Message): string
{
	if(smtp == nil)
		return "SMTP module not available";
	if(msg.recipient == nil || msg.recipient == "")
		return "no recipient";

	sender := msg.sender;
	if(sender == nil || sender == "")
		sender = readfile("/dev/user");
	if(sender == nil)
		sender = "inferno";

	subject := msg.subject;
	if(subject == nil)
		subject = "";

	# Build message lines
	lines: list of string;
	lines = "From: " + sender :: lines;
	lines = "To: " + msg.recipient :: lines;
	lines = "Subject: " + subject :: lines;
	if(daytime != nil)
		lines = "Date: " + daytime->text(daytime->now()) :: lines;
	lines = "" :: lines;
	lines = msg.body :: lines;

	# Reverse
	rlines: list of string;
	for(; lines != nil; lines = tl lines)
		rlines = hd lines :: rlines;

	(ok, serr) := smtp->open(smtpserver);
	if(ok < 0)
		return "SMTP connect: " + serr;

	(ok, serr) = smtp->sendmail(sender, msg.recipient :: nil, nil, rlines);
	smtp->close();

	if(ok < 0)
		return "send failed: " + serr;

	return nil;
}

# reply: reply to a message preserving threading
reply(origid, body: string): string
{
	if(smtp == nil)
		return "SMTP module not available";

	err := ensureconnected();
	if(err != nil)
		return err;

	seq := int origid;
	if(seq <= 0)
		return "invalid message id";

	# Fetch original headers for threading
	(hdr, herr) := imap->fetchhdr(seq);
	if(herr != nil)
		return "fetch headers: " + herr;

	origmsgid := extractheader(hdr, "Message-ID");
	origsubject := extractheader(hdr, "Subject");
	origfrom := extractheader(hdr, "From");
	origrefs := extractheader(hdr, "References");

	if(origfrom == nil || origfrom == "")
		return "cannot determine sender of original message";

	# Build reply subject
	subject := origsubject;
	if(subject == nil)
		subject = "";
	if(!hasprefix(str->tolower(subject), "re:"))
		subject = "Re: " + subject;

	# Build References header for threading
	refs := "";
	if(origrefs != nil && origrefs != "")
		refs = origrefs;
	if(origmsgid != nil && origmsgid != "") {
		if(refs != "")
			refs += " ";
		refs += origmsgid;
	}

	# Get sender identity
	sender := readfile("/dev/user");
	if(sender == nil)
		sender = "inferno";

	# Build message lines
	lines: list of string;
	lines = "From: " + sender :: lines;
	lines = "To: " + origfrom :: lines;
	lines = "Subject: " + subject :: lines;
	if(origmsgid != nil && origmsgid != "")
		lines = "In-Reply-To: " + origmsgid :: lines;
	if(refs != "")
		lines = "References: " + refs :: lines;
	if(daytime != nil)
		lines = "Date: " + daytime->text(daytime->now()) :: lines;
	lines = "" :: lines;
	lines = body :: lines;

	# Reverse
	rlines: list of string;
	for(; lines != nil; lines = tl lines)
		rlines = hd lines :: rlines;

	(ok, serr) := smtp->open(smtpserver);
	if(ok < 0)
		return "SMTP connect: " + serr;

	(ok, serr) = smtp->sendmail(sender, origfrom :: nil, nil, rlines);
	smtp->close();

	if(ok < 0)
		return "reply failed: " + serr;

	# Mark as answered
	imap->store(seq, Imap->FANSWERED, 1);

	return nil;
}

# setflag: set/clear message flags
setflag(id: string, flag, add: int): string
{
	err := ensureconnected();
	if(err != nil)
		return err;

	seq := int id;
	if(seq <= 0)
		return "invalid message id";

	# Map MsgSrc flags to IMAP flags
	imapflags := 0;
	if(flag & MsgSrc->FUNREAD)
		imapflags |= Imap->FSEEN;	# invert: FUNREAD → clear FSEEN
	if(flag & MsgSrc->FFLAGGED)
		imapflags |= Imap->FFLAGGED;

	# FUNREAD is inverted: setting FUNREAD clears FSEEN
	if(flag & MsgSrc->FUNREAD)
		add = !add;

	return imap->store(seq, imapflags, add);
}

# --- Helpers ---

ensureconnected(): string
{
	if(imapconnected)
		return nil;
	return reconnect();
}

getcfg(config, key: string): string
{
	target := key + "=";
	tlen := len target;
	i := 0;
	for(;;) {
		# skip whitespace
		while(i < len config && (config[i] == ' ' || config[i] == '\t'))
			i++;
		if(i >= len config)
			return nil;
		if(i + tlen <= len config && config[i:i+tlen] == target) {
			start := i + tlen;
			end := start;
			while(end < len config && config[end] != ' ' && config[end] != '\t')
				end++;
			return config[start:end];
		}
		# skip to next whitespace
		while(i < len config && config[i] != ' ' && config[i] != '\t')
			i++;
	}
}

extractheader(hdr, name: string): string
{
	target := str->tolower(name) + ":";
	(nil, lines) := sys->tokenize(hdr, "\n");
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		if(len line > 0 && line[len line - 1] == '\r')
			line = line[:len line - 1];
		if(len line >= len target && str->tolower(line[:len target]) == target) {
			val := line[len target:];
			# Strip leading whitespace
			while(len val > 0 && (val[0] == ' ' || val[0] == '\t'))
				val = val[1:];
			return val;
		}
	}
	return nil;
}

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

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[:len prefix] == prefix;
}
