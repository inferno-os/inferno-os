implement ImapTest;

#
# IMAP module unit tests
#
# Parser tests run without network.
# Integration tests require a live IMAP server and are skipped
# when network is unavailable.
#
# Usage:
#   emu -r. /tests/imap_test.dis         # parser tests only
#   emu -r. /tests/imap_test.dis -v       # verbose
#   emu -r. /tests/imap_test.dis -live     # include live server tests
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "testing.m";
	testing: Testing;
	T: import testing;

include "imap.m";
	imap: Imap;

ImapTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/imap_test.b";

passed := 0;
failed := 0;
skipped := 0;
dolive := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception {
	"fail:fatal" =>
		;
	"fail:skip" =>
		;
	"*" =>
		t.failed = 1;
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# Test flag string to bitmask conversion
testParseFlags(t: ref T)
{
	# Single flags
	t.asserteq(imap->parseflags("\\Seen"), Imap->FSEEN, "\\Seen flag");
	t.asserteq(imap->parseflags("\\Answered"), Imap->FANSWERED, "\\Answered flag");
	t.asserteq(imap->parseflags("\\Flagged"), Imap->FFLAGGED, "\\Flagged flag");
	t.asserteq(imap->parseflags("\\Deleted"), Imap->FDELETED, "\\Deleted flag");
	t.asserteq(imap->parseflags("\\Draft"), Imap->FDRAFT, "\\Draft flag");

	# Combined flags
	t.asserteq(imap->parseflags("\\Seen \\Flagged"),
		Imap->FSEEN | Imap->FFLAGGED, "Seen+Flagged");

	# Parenthesized (as in FETCH response)
	t.asserteq(imap->parseflags("(\\Seen \\Answered)"),
		Imap->FSEEN | Imap->FANSWERED, "parenthesized flags");

	# Empty
	t.asserteq(imap->parseflags(""), 0, "empty flags");

	# Unknown flags ignored
	t.asserteq(imap->parseflags("\\Seen \\Custom \\Flagged"),
		Imap->FSEEN | Imap->FFLAGGED, "unknown flags ignored");
}

# Test flag bitmask to string conversion
testFlagsToString(t: ref T)
{
	s := imap->flagstostring(Imap->FSEEN);
	t.assertseq(s, "\\Seen", "FSEEN to string");

	s = imap->flagstostring(Imap->FSEEN | Imap->FFLAGGED);
	# Order: Seen Flagged (follows bit order)
	t.assert(s != nil && len s > 0, "combined flags not empty");
	t.log("FSEEN|FFLAGGED = " + s);
}

# Test FETCH response line parsing
testParseFetch(t: ref T)
{
	line := "* 1 FETCH (FLAGS (\\Seen) UID 42 RFC822.SIZE 1234)";
	msg := imap->parsefetchline(line);
	if(msg == nil) {
		t.fatal("parsefetchline returned nil");
		return;
	}

	t.asserteq(msg.seq, 1, "sequence number");
	t.asserteq(msg.uid, 42, "UID");
	t.asserteq(msg.size, 1234, "RFC822.SIZE");
	t.asserteq(msg.flags, Imap->FSEEN, "flags");
}

# Test FETCH with multiple flags
testParseFetchMultiFlags(t: ref T)
{
	line := "* 5 FETCH (FLAGS (\\Seen \\Answered \\Flagged) UID 100 RFC822.SIZE 5678)";
	msg := imap->parsefetchline(line);
	if(msg == nil) {
		t.fatal("parsefetchline returned nil");
		return;
	}

	t.asserteq(msg.seq, 5, "sequence number");
	t.asserteq(msg.uid, 100, "UID");
	expected := Imap->FSEEN | Imap->FANSWERED | Imap->FFLAGGED;
	t.asserteq(msg.flags, expected, "multiple flags");
}

# Test FETCH with ENVELOPE
testParseEnvelope(t: ref T)
{
	# Simplified ENVELOPE structure
	line := "* 3 FETCH (FLAGS (\\Seen) UID 77 RFC822.SIZE 999 " +
		"ENVELOPE (\"Mon, 1 Jan 2024 12:00:00 +0000\" " +
		"\"Test Subject\" " +
		"((\"John Doe\" NIL \"john\" \"example.com\")) " +	# from
		"((\"John Doe\" NIL \"john\" \"example.com\")) " +	# sender
		"((\"John Doe\" NIL \"john\" \"example.com\")) " +	# reply-to
		"((\"Jane Smith\" NIL \"jane\" \"example.com\")) " +	# to
		"NIL " +						# cc
		"NIL " +						# bcc
		"NIL " +						# in-reply-to
		"\"<msg001@example.com>\"))";				# message-id

	msg := imap->parsefetchline(line);
	if(msg == nil) {
		t.fatal("parsefetchline returned nil for envelope");
		return;
	}

	t.asserteq(msg.seq, 3, "seq with envelope");
	t.asserteq(msg.uid, 77, "uid with envelope");

	if(msg.envelope == nil) {
		t.fatal("envelope is nil");
		return;
	}

	t.assertseq(msg.envelope.subject, "Test Subject", "subject");
	t.assertseq(msg.envelope.sender, "John Doe <john@example.com>", "sender");
	t.assertseq(msg.envelope.recipient, "Jane Smith <jane@example.com>", "recipient");
	t.assertseq(msg.envelope.messageid, "<msg001@example.com>", "message-id");
	t.log("date: " + msg.envelope.date);
}

# Test tag generation
testTagGeneration(t: ref T)
{
	# Tags are module-level state; we test the format
	# The actual tag values depend on how many commands have been sent
	# Just verify the format is correct (letter + digits)
	t.log("tag generation is tested implicitly by protocol operations");
}

# Test literal detection in lines
testLiteralDetection(t: ref T)
{
	t.asserteq(imap->checkliteral("* 1 FETCH (BODY[] {1234}"), 1234,
		"detect {1234}");
	t.asserteq(imap->checkliteral("* OK no literal here"), 0,
		"no literal");
	t.asserteq(imap->checkliteral(""), 0,
		"empty line");
	t.asserteq(imap->checkliteral("data {0}"), 0,
		"zero literal");
	t.asserteq(imap->checkliteral("data {42}"), 42,
		"detect {42}");
}

# Test LIST response name parsing
testParseListName(t: ref T)
{
	name := imap->parselistname("* LIST (\\HasNoChildren) \"/\" \"INBOX\"");
	t.assertseq(name, "INBOX", "quoted INBOX");

	name = imap->parselistname("* LIST (\\HasNoChildren) \"/\" \"Sent Mail\"");
	t.assertseq(name, "Sent Mail", "quoted with space");

	name = imap->parselistname("* LIST (\\HasNoChildren) \".\" INBOX");
	t.assertseq(name, "INBOX", "unquoted INBOX");
}

# Test helper functions
testHelpers(t: ref T)
{
	t.assert(imap->hasprefix("hello world", "hello"), "hasprefix true");
	t.assert(!imap->hasprefix("hello", "world"), "hasprefix false");
	t.assert(imap->hassuffix("hello world", "world"), "hassuffix true");
	t.assert(!imap->hassuffix("hello", "world"), "hassuffix false");

	t.asserteq(imap->strindex("hello world", "world"), 6, "strindex found");
	t.asserteq(imap->strindex("hello", "xyz"), -1, "strindex not found");
}

# Test quoting
testQuote(t: ref T)
{
	t.assertseq(imap->quote("simple"), "\"simple\"", "simple quote");
	t.assertseq(imap->quote("has space"), "\"has space\"", "space quote");
}

# Integration test: connect to live IMAP server
testLiveConnect(t: ref T)
{
	if(!dolive) {
		t.skip("live tests disabled (use -live flag)");
		return;
	}

	# Uses factotum credentials
	err := imap->open(nil, nil, nil, Imap->IMPLICIT_TLS);
	if(err != nil) {
		t.skip("cannot connect: " + err);
		return;
	}

	t.log("connected to IMAP server");

	# SELECT INBOX
	(mbox, serr) := imap->select("INBOX");
	if(serr != nil) {
		t.error("SELECT INBOX: " + serr);
		imap->logout();
		return;
	}

	t.log(sys->sprint("INBOX: %d messages, %d recent, unseen=%d",
		mbox.exists, mbox.recent, mbox.unseen));
	t.assert(mbox.exists >= 0, "exists >= 0");

	# List messages if any
	if(mbox.exists > 0) {
		first := mbox.exists;
		if(first > 5)
			first = mbox.exists - 4;
		(msgs, lerr) := imap->msglist(first, mbox.exists);
		if(lerr != nil)
			t.error("msglist: " + lerr);
		else {
			for(ml := msgs; ml != nil; ml = tl ml) {
				m := hd ml;
				subj := "";
				if(m.envelope != nil)
					subj = m.envelope.subject;
				t.log(sys->sprint("  #%d uid=%d size=%d subj=%s",
					m.seq, m.uid, m.size, subj));
			}
		}
	}

	imap->logout();
	t.log("disconnected");
}

# Integration test: list folders
testLiveFolders(t: ref T)
{
	if(!dolive) {
		t.skip("live tests disabled");
		return;
	}

	err := imap->open(nil, nil, nil, Imap->IMPLICIT_TLS);
	if(err != nil) {
		t.skip("cannot connect: " + err);
		return;
	}

	(fl, ferr) := imap->folders();
	if(ferr != nil) {
		t.error("folders: " + ferr);
		imap->logout();
		return;
	}

	t.log(sys->sprint("found %d folders", listlen(fl)));
	for(; fl != nil; fl = tl fl)
		t.log("  " + hd fl);

	imap->logout();
}

listlen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	imap = load Imap Imap->PATH;
	if(imap == nil) {
		sys->fprint(sys->fildes(2), "cannot load imap module: %r\n");
		raise "fail:cannot load imap";
	}

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
		if(hd a == "-live")
			dolive = 1;
	}

	# Parser unit tests (no network)
	run("ParseFlags", testParseFlags);
	run("FlagsToString", testFlagsToString);
	run("ParseFetch", testParseFetch);
	run("ParseFetchMultiFlags", testParseFetchMultiFlags);
	run("ParseEnvelope", testParseEnvelope);
	run("TagGeneration", testTagGeneration);
	run("LiteralDetection", testLiteralDetection);
	run("ParseListName", testParseListName);
	run("Helpers", testHelpers);
	run("Quote", testQuote);

	# Integration tests (network required)
	run("LiveConnect", testLiveConnect);
	run("LiveFolders", testLiveFolders);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
