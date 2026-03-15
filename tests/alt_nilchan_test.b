implement AltNilchanTest;

#
# Regression test: alt send on nil channel raises "dereference of nil"
#
# In the Dis VM, alt send/recv on a nil channel is NOT a silent skip —
# it raises exNilref ("dereference of nil").  This bit us in lucipres:
# lucifer's nslistener called lucipres_g->deliverevent() which does
# alt { preseventch <-= ev => ; * => ; } before preseventch was
# initialized, killing the nslistener thread.
#
# Fix: initialize channels before they can be accessed by other threads.
#
# To run: emu tests/alt_nilchan_test.dis
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

AltNilchanTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/alt_nilchan_test.b";

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

# Test that alt send on nil channel raises "dereference of nil"
testAltSendNilChan(t: ref T)
{
	ch: chan of string;  # nil — never initialized

	caught := 0;
	{
		alt {
		ch <-= "test" =>
			;
		* =>
			;
		}
	} exception e {
	"dereference*" =>
		caught = 1;
		t.log("caught expected exception: " + e);
	}
	t.assert(caught == 1, "alt send on nil chan must raise exNilref");
}

# Test that alt recv on nil channel raises "dereference of nil"
testAltRecvNilChan(t: ref T)
{
	ch: chan of string;  # nil — never initialized

	caught := 0;
	{
		alt {
		<-ch =>
			;
		* =>
			;
		}
	} exception e {
	"dereference*" =>
		caught = 1;
		t.log("caught expected exception: " + e);
	}
	t.assert(caught == 1, "alt recv on nil chan must raise exNilref");
}

# Test that alt send on initialized channel works (sanity check)
testAltSendInitChan(t: ref T)
{
	ch := chan[1] of string;

	caught := 0;
	sent := 0;
	{
		alt {
		ch <-= "hello" =>
			sent = 1;
		* =>
			;
		}
	} exception e {
	"dereference*" =>
		caught = 1;
	}
	t.assert(caught == 0, "alt send on init chan must not raise exNilref");
	t.assert(sent == 1, "alt send on buffered chan should succeed");
}

# Regression test: simulates the lucipres/nslistener race condition.
# A "deliverevent" function does alt send on a channel.  If the channel
# is nil (not yet initialized), the calling thread dies.
testDeliverEventRace(t: ref T)
{
	ch := chan[8] of string;  # initialized (the fix)

	# Simulate deliverevent from another thread
	done := chan of int;
	spawn deliverer(ch, done);

	# Wait for deliverer to finish
	timeout := chan of int;
	spawn sleeper(timeout, 500);
	alt {
	<-done =>
		t.log("deliverer completed successfully");
	<-timeout =>
		t.fatal("deliverer timed out — likely crashed");
	}
}

deliverer(ch: chan of string, done: chan of int)
{
	# This is what lucipres.deliverevent() does
	alt {
	ch <-= "presentation new tasks" =>
		;
	* =>
		;
	}
	done <-= 1;
}

sleeper(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	run("AltSendNilChan", testAltSendNilChan);
	run("AltRecvNilChan", testAltRecvNilChan);
	run("AltSendInitChan", testAltSendInitChan);
	run("DeliverEventRace", testDeliverEventRace);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
