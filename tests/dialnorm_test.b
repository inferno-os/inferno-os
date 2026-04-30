implement DialnormTest;

#
# Tests for the Dialnorm module (dialnorm.m)
#
# Covers normalize(): coercion of user-typed dial addresses into
# Inferno's tcp!host!port form, and pass-through for inputs that
# are already in dial form or don't match the host:port pattern.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "dialnorm.m";
	dialnorm: Dialnorm;

include "testing.m";
	testing: Testing;
	T: import testing;

DialnormTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/dialnorm_test.b";

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
	* =>
		t.failed = 1;
	}
	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

testHostPort(t: ref T)
{
	t.assertseq(dialnorm->normalize("10.243.169.78:5640"),
		"tcp!10.243.169.78!5640", "ipv4 host:port → tcp!host!port");
	t.assertseq(dialnorm->normalize("hephaestus:5640"),
		"tcp!hephaestus!5640", "hostname:port → tcp!host!port");
	t.assertseq(dialnorm->normalize("a:1"),
		"tcp!a!1", "single-char host and port still normalize");
}

testAlreadyDialForm(t: ref T)
{
	t.assertseq(dialnorm->normalize("tcp!10.243.169.78!5640"),
		"tcp!10.243.169.78!5640", "tcp! prefix passes through unchanged");
	t.assertseq(dialnorm->normalize("udp!host!9"),
		"udp!host!9", "non-tcp dial form passes through unchanged");
	t.assertseq(dialnorm->normalize("net!host!service"),
		"net!host!service", "service name (not numeric) passes through");
}

testNoPort(t: ref T)
{
	t.assertseq(dialnorm->normalize("hephaestus"),
		"hephaestus", "bare hostname is not coerced");
	t.assertseq(dialnorm->normalize("10.243.169.78"),
		"10.243.169.78", "bare ipv4 is not coerced");
}

testInvalidPort(t: ref T)
{
	t.assertseq(dialnorm->normalize("host:abc"),
		"host:abc", "non-numeric port is not coerced");
	t.assertseq(dialnorm->normalize("host:5640x"),
		"host:5640x", "trailing non-digit means do not coerce");
	t.assertseq(dialnorm->normalize("host:"),
		"host:", "empty port is not coerced");
	t.assertseq(dialnorm->normalize(":5640"),
		":5640", "empty host is not coerced");
}

testIPv6LikeAmbiguity(t: ref T)
{
	# Multiple ':' is ambiguous (IPv6 literal). We deliberately
	# do not try to coerce — leave it for the caller / dial syscall.
	t.assertseq(dialnorm->normalize("::1:5640"),
		"::1:5640", "ipv6-ish input is left untouched");
	t.assertseq(dialnorm->normalize("a::b"),
		"a::b", "any input with multiple colons is left untouched");
}

testEdgeCases(t: ref T)
{
	t.assertseq(dialnorm->normalize(""),
		"", "empty string returns empty");
	t.assertseq(dialnorm->normalize(":"),
		":", "lone colon is not coerced");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;
	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	dialnorm = load Dialnorm Dialnorm->PATH;
	if(dialnorm == nil) {
		sys->fprint(sys->fildes(2), "cannot load dialnorm module: %r\n");
		raise "fail:cannot load dialnorm";
	}

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("HostPort", testHostPort);
	run("AlreadyDialForm", testAlreadyDialForm);
	run("NoPort", testNoPort);
	run("InvalidPort", testInvalidPort);
	run("IPv6LikeAmbiguity", testIPv6LikeAmbiguity);
	run("EdgeCases", testEdgeCases);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
