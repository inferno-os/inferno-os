implement DialTest;

#
# Tests for the Dial module (dial.m)
#
# Covers: netmkaddr, dial (with graceful skip on network unavailability),
#         announce/listen/accept, connection info
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "dial.m";
	dial: Dial;

include "testing.m";
	testing: Testing;
	T: import testing;

DialTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/dial_test.b";

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

# ── netmkaddr tests ──────────────────────────────────────────────────────────

testNetmkaddr(t: ref T)
{
	# Full address passes through
	addr := dial->netmkaddr("tcp!example.com!80", "tcp", "80");
	t.assertnotnil(addr, "netmkaddr full address");
	t.log(sys->sprint("netmkaddr full: %s", addr));

	# Add default net
	addr = dial->netmkaddr("example.com!80", "tcp", "http");
	t.assertnotnil(addr, "netmkaddr add net");
	t.log(sys->sprint("netmkaddr add net: %s", addr));

	# Add default service
	addr = dial->netmkaddr("tcp!example.com", "tcp", "80");
	t.assertnotnil(addr, "netmkaddr add service");
	t.log(sys->sprint("netmkaddr add svc: %s", addr));
}

testNetmkaddrMinimal(t: ref T)
{
	# Just a hostname - should add both net and service
	addr := dial->netmkaddr("localhost", "tcp", "80");
	t.assertnotnil(addr, "netmkaddr minimal");
	t.log(sys->sprint("netmkaddr minimal: %s", addr));
}

testNetmkaddrEmpty(t: ref T)
{
	# Empty defaults
	addr := dial->netmkaddr("tcp!host!port", "", "");
	t.assertnotnil(addr, "netmkaddr empty defaults");
}

# ── Local loopback dial/announce ─────────────────────────────────────────────

testLoopback(t: ref T)
{
	# Announce on a local port
	c := dial->announce("tcp!*!0");
	if(c == nil) {
		t.skip(sys->sprint("cannot announce: %r"));
		return;
	}

	# Get the actual port assigned
	t.assertnotnil(c.dir, "announce dir");
	t.log(sys->sprint("announced on: %s", c.dir));

	# Get connection info to find the port
	info := dial->netinfo(c);
	if(info == nil) {
		t.skip("netinfo not available");
		return;
	}
	t.assertnotnil(info.laddr, "local address");
	t.log(sys->sprint("local addr: %s", info.laddr));
	t.log(sys->sprint("local serv: %s", info.lserv));
}

testDialRefused(t: ref T)
{
	# Try to dial a port that should be refused (very high port, unlikely in use)
	c := dial->dial("tcp!127.0.0.1!39999", nil);
	if(c != nil) {
		t.log("port 39999 unexpectedly accepted connection");
		return;
	}
	# Expected to fail - connection refused
	t.log("dial to closed port correctly failed");
}

testDialLoopback(t: ref T)
{
	# Announce
	ac := dial->announce("tcp!*!0");
	if(ac == nil) {
		t.skip(sys->sprint("cannot announce for loopback test: %r"));
		return;
	}

	info := dial->netinfo(ac);
	if(info == nil || info.lserv == nil || info.lserv == "") {
		t.skip("cannot determine local port");
		return;
	}

	port := info.lserv;
	t.log(sys->sprint("testing loopback on port %s", port));

	# Channel for results
	done := chan of int;

	# Spawn listener
	spawn listener(ac, done);

	# Give listener a moment
	sys->sleep(100);

	# Dial
	dc := dial->dial("tcp!127.0.0.1!" + port, nil);
	if(dc == nil) {
		t.skip(sys->sprint("cannot dial loopback: %r"));
		<-done;
		return;
	}

	# Write some data
	msg := array of byte "hello";
	n := sys->write(dc.dfd, msg, len msg);
	t.assert(n > 0, "wrote data to connection");

	# Wait for listener
	result := <-done;
	t.asserteq(result, 1, "listener got data");
}

listener(c: ref Dial->Connection, done: chan of int)
{
	lc := dial->listen(c);
	if(lc == nil) {
		done <-= 0;
		return;
	}
	fd := dial->accept(lc);
	if(fd == nil) {
		done <-= 0;
		return;
	}
	buf := array[100] of byte;
	n := sys->read(fd, buf, len buf);
	if(n > 0)
		done <-= 1;
	else
		done <-= 0;
}

# ── Connection info tests ───────────────────────────────────────────────────

testConninfo(t: ref T)
{
	c := dial->announce("tcp!*!0");
	if(c == nil) {
		t.skip(sys->sprint("cannot announce: %r"));
		return;
	}

	info := dial->netinfo(c);
	if(info == nil) {
		t.skip("netinfo returned nil");
		return;
	}

	t.assertnotnil(info.dir, "conninfo dir");
	t.assertnotnil(info.root, "conninfo root");
	t.log(sys->sprint("conninfo: dir=%s root=%s lsys=%s lserv=%s",
		info.dir, info.root, info.lsys, info.lserv));
}

# ── Reject test ──────────────────────────────────────────────────────────────

testReject(t: ref T)
{
	c := dial->announce("tcp!*!0");
	if(c == nil) {
		t.skip(sys->sprint("cannot announce: %r"));
		return;
	}

	info := dial->netinfo(c);
	if(info == nil || info.lserv == nil || info.lserv == "") {
		t.skip("cannot determine port for reject test");
		return;
	}

	port := info.lserv;
	done := chan of int;

	# Spawn rejecter
	spawn rejecter(c, done);

	sys->sleep(100);

	# Dial — may or may not succeed depending on timing
	dc := dial->dial("tcp!127.0.0.1!" + port, nil);
	result := <-done;
	t.log(sys->sprint("rejecter result: %d", result));

	# If dial succeeded, the rejected connection should have been closed
	if(dc != nil) {
		buf := array[10] of byte;
		n := sys->read(dc.dfd, buf, len buf);
		t.log(sys->sprint("read after reject: %d", n));
	}
}

rejecter(c: ref Dial->Connection, done: chan of int)
{
	lc := dial->listen(c);
	if(lc == nil) {
		done <-= 0;
		return;
	}
	ok := dial->reject(lc, "test rejection");
	done <-= ok;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	dial = load Dial Dial->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(dial == nil) {
		sys->fprint(sys->fildes(2), "cannot load dial module: %r\n");
		raise "fail:cannot load dial";
	}

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	# netmkaddr (pure logic, no network needed)
	run("Netmkaddr", testNetmkaddr);
	run("NetmkaddrMinimal", testNetmkaddrMinimal);
	run("NetmkaddrEmpty", testNetmkaddrEmpty);

	# Network tests (skip gracefully if unavailable)
	run("Loopback", testLoopback);
	run("DialRefused", testDialRefused);
	run("DialLoopback", testDialLoopback);
	run("Conninfo", testConninfo);
	run("Reject", testReject);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
