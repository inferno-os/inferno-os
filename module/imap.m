#
# IMAP4rev1 client module
#
# Connects to IMAP servers over TLS (port 993) or STARTTLS (port 143).
# Uses webclient->tlsdial() for TLS, factotum for credentials.
#
# Keeps mail on server; supports folders, flags, search, and IDLE push.
#

Imap: module
{
	PATH: con "/dis/lib/imap.dis";

	# Connection modes
	IMPLICIT_TLS: con 0;	# port 993, TLS from start
	STARTTLS: con 1;	# port 143, upgrade with STARTTLS

	# Message flags (bitmask)
	FSEEN:		con 1;
	FANSWERED:	con 2;
	FFLAGGED:	con 4;
	FDELETED:	con 8;
	FDRAFT:		con 16;

	# Envelope: parsed RFC 2822 header fields
	Envelope: adt {
		date:		string;
		subject:	string;
		sender:		string;		# From: header
		recipient:	string;		# To: header
		cc:		string;
		replyto:	string;
		messageid:	string;
	};

	# Msg: per-message metadata from FETCH
	Msg: adt {
		seq:		int;		# sequence number
		uid:		int;		# unique identifier
		flags:		int;		# FSEEN|FANSWERED|...
		size:		int;		# RFC822.SIZE
		envelope:	ref Envelope;
	};

	# Mailbox: status from SELECT
	Mailbox: adt {
		name:		string;
		exists:		int;		# total messages
		recent:		int;		# recent messages
		unseen:		int;		# first unseen seq
		uidnext:	int;
		uidvalidity:	int;
	};

	# Connect, authenticate, return error string or nil
	open:		fn(user, password, server: string, mode: int): string;

	# List all mailbox names
	folders:	fn(): (list of string, string);

	# SELECT a mailbox, return status
	select:		fn(mailbox: string): (ref Mailbox, string);

	# FETCH envelope/flags/size for sequence range first:last
	msglist:	fn(first, last: int): (list of ref Msg, string);

	# SEARCH with IMAP criteria string, return matching sequence numbers
	search:		fn(criteria: string): (list of int, string);

	# FETCH full RFC822 message text
	fetch:		fn(seq: int): (string, string);

	# FETCH headers only (BODY[HEADER])
	fetchhdr:	fn(seq: int): (string, string);

	# STORE flags: if add != 0, add flags; else remove flags
	store:		fn(seq, flags, add: int): string;

	# COPY messages to another mailbox
	copy:		fn(seqs: string, dest: string): string;

	# IDLE: pushes untagged EXISTS/EXPUNGE lines to updates channel.
	# Send anything on stop channel to end IDLE.
	idle:		fn(updates: chan of string, stop: chan of int): string;

	# Clean disconnect
	logout:		fn(): string;

	# Parsing helpers (exported for testing)
	parseflags:	fn(s: string): int;
	flagstostring:	fn(flags: int): string;
	parsefetchline:	fn(line: string): ref Msg;
	checkliteral:	fn(line: string): int;
	parselistname:	fn(line: string): string;
	hasprefix:	fn(s, prefix: string): int;
	hassuffix:	fn(s, suffix: string): int;
	strindex:	fn(s, sub: string): int;
	quote:		fn(s: string): string;
};
