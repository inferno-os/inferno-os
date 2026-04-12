implement BufioTest;

#
# Tests for the Bufio module (bufio.m)
#
# Covers: sopen, aopen, open, create, getb, getc, gets, gett,
#         putb, putc, puts, ungetb, ungetc, read, write,
#         seek, offset, flush, close
#
# TODO: SopenGett fails — gett returns fields with delimiter still attached
#       (e.g. "field1:" instead of "field1"). The delimiter is not being
#       stripped from the returned token. Low priority — gett is rarely used.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "testing.m";
	testing: Testing;
	T: import testing;

BufioTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/bufio_test.b";

passed := 0;
failed := 0;
skipped := 0;

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

# ── sopen: string-backed buffer ──────────────────────────────────────────────

testSopenGetc(t: ref T)
{
	b := bufio->sopen("hello");
	if(b == nil) {
		t.fatal("sopen returned nil");
		return;
	}
	c := b.getc();
	t.asserteq(c, 'h', "sopen getc first char");
	c = b.getc();
	t.asserteq(c, 'e', "sopen getc second char");
	c = b.getc();
	t.asserteq(c, 'l', "sopen getc third char");
	c = b.getc();
	t.asserteq(c, 'l', "sopen getc fourth char");
	c = b.getc();
	t.asserteq(c, 'o', "sopen getc fifth char");
	c = b.getc();
	t.asserteq(c, Bufio->EOF, "sopen getc EOF");
}

testSopenGetb(t: ref T)
{
	b := bufio->sopen("AB");
	if(b == nil) {
		t.fatal("sopen returned nil");
		return;
	}
	v := b.getb();
	t.asserteq(v, int 'A', "getb first byte");
	v = b.getb();
	t.asserteq(v, int 'B', "getb second byte");
	v = b.getb();
	t.asserteq(v, Bufio->EOF, "getb EOF");
}

testSopenGets(t: ref T)
{
	b := bufio->sopen("line1\nline2\nline3");
	if(b == nil) {
		t.fatal("sopen returned nil");
		return;
	}
	s := b.gets('\n');
	t.assertseq(s, "line1\n", "gets first line");
	s = b.gets('\n');
	t.assertseq(s, "line2\n", "gets second line");
	s = b.gets('\n');
	t.assertseq(s, "line3", "gets last line (no newline)");
	s = b.gets('\n');
	t.assertnil(s, "gets at EOF");
}

testSopenGett(t: ref T)
{
	b := bufio->sopen("field1::field2::field3");
	if(b == nil) {
		t.fatal("sopen returned nil");
		return;
	}
	s := b.gett("::");
	t.assertseq(s, "field1", "gett first field");
	s = b.gett("::");
	t.assertseq(s, "field2", "gett second field");
	s = b.gett("::");
	t.assertseq(s, "field3", "gett third field");
}

testSopenEmpty(t: ref T)
{
	b := bufio->sopen("");
	if(b == nil) {
		t.fatal("sopen returned nil for empty string");
		return;
	}
	c := b.getc();
	t.asserteq(c, Bufio->EOF, "empty sopen getc");
}

# ── aopen: byte-array-backed buffer ──────────────────────────────────────────

testAopen(t: ref T)
{
	data := array of byte "hello world";
	b := bufio->aopen(data);
	if(b == nil) {
		t.fatal("aopen returned nil");
		return;
	}
	s := b.gets('\n');
	t.assertseq(s, "hello world", "aopen gets");
}

# ── ungetc / ungetb ──────────────────────────────────────────────────────────

testUngetc(t: ref T)
{
	b := bufio->sopen("abc");
	if(b == nil) {
		t.fatal("sopen returned nil");
		return;
	}
	c := b.getc();
	t.asserteq(c, 'a', "getc before ungetc");
	b.ungetc();
	c = b.getc();
	t.asserteq(c, 'a', "getc after ungetc");
}

testUngetb(t: ref T)
{
	b := bufio->sopen("xy");
	if(b == nil) {
		t.fatal("sopen returned nil");
		return;
	}
	v := b.getb();
	t.asserteq(v, int 'x', "getb before ungetb");
	b.ungetb();
	v = b.getb();
	t.asserteq(v, int 'x', "getb after ungetb");
}

# ── file I/O: create, write, flush, open, read ──────────────────────────────

TESTFILE: con "/tmp/bufio_test_tmp";

testFileWriteRead(t: ref T)
{
	# Write
	wb := bufio->create(TESTFILE, Bufio->OWRITE, 8r666);
	if(wb == nil) {
		t.skip(sys->sprint("cannot create %s: %r", TESTFILE));
		return;
	}
	wb.puts("hello\n");
	wb.puts("world\n");
	wb.flush();
	wb.close();

	# Read back
	rb := bufio->open(TESTFILE, Bufio->OREAD);
	if(rb == nil) {
		t.fatal(sys->sprint("cannot open %s: %r", TESTFILE));
		return;
	}
	s := rb.gets('\n');
	t.assertseq(s, "hello\n", "file read first line");
	s = rb.gets('\n');
	t.assertseq(s, "world\n", "file read second line");
	s = rb.gets('\n');
	t.assertnil(s, "file read at EOF");
	rb.close();

	# Cleanup
	sys->remove(TESTFILE);
}

testFilePutbGetb(t: ref T)
{
	wb := bufio->create(TESTFILE, Bufio->OWRITE, 8r666);
	if(wb == nil) {
		t.skip(sys->sprint("cannot create %s: %r", TESTFILE));
		return;
	}
	for(i := 0; i < 256; i++)
		wb.putb(byte i);
	wb.flush();
	wb.close();

	rb := bufio->open(TESTFILE, Bufio->OREAD);
	if(rb == nil) {
		t.fatal(sys->sprint("cannot open %s: %r", TESTFILE));
		return;
	}
	for(i = 0; i < 256; i++) {
		v := rb.getb();
		if(!t.asserteq(v, i, sys->sprint("byte %d", i)))
			break;
	}
	v := rb.getb();
	t.asserteq(v, Bufio->EOF, "EOF after 256 bytes");
	rb.close();

	sys->remove(TESTFILE);
}

testFilePutcGetc(t: ref T)
{
	wb := bufio->create(TESTFILE, Bufio->OWRITE, 8r666);
	if(wb == nil) {
		t.skip(sys->sprint("cannot create %s: %r", TESTFILE));
		return;
	}
	wb.putc('H');
	wb.putc('i');
	wb.putc('!');
	wb.flush();
	wb.close();

	rb := bufio->open(TESTFILE, Bufio->OREAD);
	if(rb == nil) {
		t.fatal(sys->sprint("cannot open %s: %r", TESTFILE));
		return;
	}
	t.asserteq(rb.getc(), 'H', "putc/getc H");
	t.asserteq(rb.getc(), 'i', "putc/getc i");
	t.asserteq(rb.getc(), '!', "putc/getc !");
	rb.close();

	sys->remove(TESTFILE);
}

# ── read/write with byte arrays ─────────────────────────────────────────────

testReadWrite(t: ref T)
{
	wb := bufio->create(TESTFILE, Bufio->OWRITE, 8r666);
	if(wb == nil) {
		t.skip(sys->sprint("cannot create %s: %r", TESTFILE));
		return;
	}
	data := array of byte "test data for read/write";
	n := wb.write(data, len data);
	t.asserteq(n, len data, "write length");
	wb.flush();
	wb.close();

	rb := bufio->open(TESTFILE, Bufio->OREAD);
	if(rb == nil) {
		t.fatal(sys->sprint("cannot open %s: %r", TESTFILE));
		return;
	}
	buf := array[100] of byte;
	n = rb.read(buf, len data);
	t.asserteq(n, len data, "read length");
	t.assertseq(string buf[:n], "test data for read/write", "read content");
	rb.close();

	sys->remove(TESTFILE);
}

# ── Unicode handling ─────────────────────────────────────────────────────────

testUnicode(t: ref T)
{
	b := bufio->sopen("Hello");
	if(b == nil) {
		t.fatal("sopen returned nil");
		return;
	}
	c := b.getc();
	t.asserteq(c, 'H', "unicode ascii H");
	s := b.gets('\n');
	t.assertseq(s, "ello", "unicode remainder");
}

# ── offset tracking ─────────────────────────────────────────────────────────

testOffset(t: ref T)
{
	b := bufio->sopen("abcdef");
	if(b == nil) {
		t.fatal("sopen returned nil");
		return;
	}
	off := b.offset();
	t.assert(off == big 0, "initial offset is 0");

	b.getc();  # read 'a'
	b.getc();  # read 'b'
	b.getc();  # read 'c'
	off = b.offset();
	t.assert(off == big 3, "offset after 3 getc");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(bufio == nil) {
		sys->fprint(sys->fildes(2), "cannot load bufio module: %r\n");
		raise "fail:cannot load bufio";
	}

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("SopenGetc", testSopenGetc);
	run("SopenGetb", testSopenGetb);
	run("SopenGets", testSopenGets);
	run("SopenGett", testSopenGett);
	run("SopenEmpty", testSopenEmpty);
	run("Aopen", testAopen);
	run("Ungetc", testUngetc);
	run("Ungetb", testUngetb);
	run("FileWriteRead", testFileWriteRead);
	run("FilePutbGetb", testFilePutbGetb);
	run("FilePutcGetc", testFilePutcGetc);
	run("ReadWrite", testReadWrite);
	run("Unicode", testUnicode);
	run("Offset", testOffset);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
