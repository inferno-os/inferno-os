#
# msgsrc.m - Message Source interface
#
# Protocol-agnostic contract for bidirectional message channels.
# Email, WhatsApp, Telegram, trading signals, sensors — all implement
# this interface. The agent never knows or cares about the underlying
# protocol.
#
# Each source is a separate .dis module loaded by msg9p.
#

MsgSrc: module
{
	# Message: the universal unit across all sources
	Message: adt {
		id:        string;	# source-unique ID (IMAP UID, chat msg ID, etc.)
		source:    string;	# source name ("email", "telegram", "trading")
		channel:   string;	# sub-channel ("inbox", "group-name", "AAPL")
		sender:    string;	# who sent it
		recipient: string;	# who it's to
		subject:   string;	# subject/title (may be nil for some protocols)
		body:      string;	# message body text
		timestamp: string;	# RFC 3339 timestamp
		threadid:  string;	# conversation/thread ID for threading
		replyto:   string;	# message ID this replies to (nil if not a reply)
		flags:     int;		# bitmask: FUNREAD | FFLAGGED | FURGENT | FDRAFT
		headers:   string;	# source-specific raw metadata
	};

	# Notification: pushed on watch channel when something happens
	Notification: adt {
		kind:   string;		# "new", "update", "delete", "error"
		msg:    ref Message;	# the message (nil for "error")
		detail: string;		# extra detail (error text, flag changes, etc.)
	};

	# Flag constants (bitmask)
	FUNREAD:  con 1;
	FFLAGGED: con 2;
	FURGENT:  con 4;
	FDRAFT:   con 8;

	# Lifecycle
	init:    fn(config: string): string;	# configure source; return error or nil
	name:    fn(): string;			# source name ("email", "telegram")
	status:  fn(): string;			# human-readable status text
	close:   fn(): string;			# clean disconnect

	# Push interface: blocks, pushes Notifications on updates channel.
	# Send on stop channel to terminate. Returns error or nil.
	watch:   fn(updates: chan of ref Notification, stop: chan of int): string;

	# Pull interface (on-demand queries)
	list:    fn(channel: string, count: int): (list of ref Message, string);
	fetch:   fn(id: string): (ref Message, string);
	search:  fn(query: string): (list of ref Message, string);

	# Send/reply through the same channel
	send:    fn(msg: ref Message): string;		# send a new message
	reply:   fn(origid, body: string): string;	# reply preserving threading

	# Flag management
	setflag: fn(id: string, flag, add: int): string;
};
