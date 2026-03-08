implement ConcurrencyTest;

#
# Extended concurrency and channel tests
#
# Covers: channel timeouts, deadlock avoidance patterns,
#         multiple producer/consumer, fan-out/fan-in,
#         channel buffering behavior, spawn lifecycle
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

ConcurrencyTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/concurrency_test.b";

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

# ── Basic channel communication ──────────────────────────────────────────────

testChannelSendRecv(t: ref T)
{
	ch := chan of int;
	spawn sender(ch, 42);
	v := <-ch;
	t.asserteq(v, 42, "channel send/recv");
}

sender(ch: chan of int, val: int)
{
	ch <-= val;
}

# ── Channel with timeout ────────────────────────────────────────────────────

testChannelTimeout(t: ref T)
{
	ch := chan of string;
	timeout := chan of int;

	# Spawn something that will take longer than timeout
	spawn slowsender(ch, 2000);
	spawn timer(timeout, 200);

	alt {
	s := <-ch =>
		t.error(sys->sprint("should have timed out, got: %s", s));
	<-timeout =>
		t.log("correctly timed out");
	}
}

slowsender(ch: chan of string, ms: int)
{
	sys->sleep(ms);
	ch <-= "late";
}

timer(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

# ── Fast response beats timeout ─────────────────────────────────────────────

testFastResponse(t: ref T)
{
	ch := chan of string;
	timeout := chan of int;

	spawn fastsender(ch);
	spawn timer(timeout, 5000);

	alt {
	s := <-ch =>
		t.assertseq(s, "fast", "fast response");
	<-timeout =>
		t.fatal("fast sender timed out");
	}
}

fastsender(ch: chan of string)
{
	ch <-= "fast";
}

# ── Multiple producers, single consumer ─────────────────────────────────────

testMultiProducer(t: ref T)
{
	ch := chan of int;
	n := 5;

	for(i := 0; i < n; i++)
		spawn producer(ch, i);

	received := array[n] of {* => 0};
	timeout := chan of int;
	spawn timer(timeout, 3000);

	count := 0;
	done := 0;
	while(done == 0 && count < n) {
		alt {
		v := <-ch =>
			if(v >= 0 && v < n)
				received[v] = 1;
			count++;
		<-timeout =>
			done = 1;
		}
	}

	t.asserteq(count, n, "received all producer messages");
	for(i := 0; i < n; i++)
		t.asserteq(received[i], 1, sys->sprint("received from producer %d", i));
}

producer(ch: chan of int, id: int)
{
	ch <-= id;
}

# ── Fan-out: single producer, multiple consumers ────────────────────────────

testFanOut(t: ref T)
{
	nworkers := 3;
	work := chan of int;
	results := chan of int;

	# Start workers
	for(i := 0; i < nworkers; i++)
		spawn worker(work, results);

	# Send work
	nitems := 9;
	spawn workfeeder(work, nitems);

	# Collect results
	timeout := chan of int;
	spawn timer(timeout, 3000);

	total := 0;
	count := 0;
	done := 0;
	while(done == 0 && count < nitems) {
		alt {
		v := <-results =>
			total += v;
			count++;
		<-timeout =>
			done = 1;
		}
	}

	t.asserteq(count, nitems, "all work items processed");
	# Each item i is doubled: sum of 2*i for i=0..8 = 2*(0+1+...+8) = 72
	t.asserteq(total, 72, "fan-out total");
}

workfeeder(ch: chan of int, n: int)
{
	for(i := 0; i < n; i++)
		ch <-= i;
}

worker(work: chan of int, results: chan of int)
{
	for(;;) {
		v := <-work;
		results <-= v * 2;
	}
}

# ── Alt with multiple channels ──────────────────────────────────────────────

testAltMultiple(t: ref T)
{
	ch1 := chan of string;
	ch2 := chan of string;
	ch3 := chan of string;

	spawn stringsender(ch2, "second");
	sys->sleep(50);  # Give ch2 time to send

	alt {
	s := <-ch1 =>
		t.error(sys->sprint("unexpected from ch1: %s", s));
	s := <-ch2 =>
		t.assertseq(s, "second", "alt chose ch2");
	s := <-ch3 =>
		t.error(sys->sprint("unexpected from ch3: %s", s));
	}
}

stringsender(ch: chan of string, s: string)
{
	ch <-= s;
}

# ── Spawn many goroutines ───────────────────────────────────────────────────

testSpawnMany(t: ref T)
{
	n := 50;
	done := chan of int;

	for(i := 0; i < n; i++)
		spawn counter(done);

	timeout := chan of int;
	spawn timer(timeout, 5000);

	count := 0;
	timedout := 0;
	while(timedout == 0 && count < n) {
		alt {
		<-done =>
			count++;
		<-timeout =>
			timedout = 1;
		}
	}

	t.asserteq(count, n, sys->sprint("all %d spawns completed", n));
}

counter(done: chan of int)
{
	# Just do minimal work
	x := 0;
	for(i := 0; i < 100; i++)
		x += i;
	done <-= x;
}

# ── Pipeline: channel chaining ──────────────────────────────────────────────

testPipeline(t: ref T)
{
	c1 := chan of int;
	c2 := chan of int;
	c3 := chan of int;

	# Chain: c1 -> double -> c2 -> add10 -> c3
	spawn pipeDouble(c1, c2);
	spawn pipeAdd(c2, c3, 10);

	c1 <-= 5;  # 5 -> double -> 10 -> add10 -> 20

	timeout := chan of int;
	spawn timer(timeout, 2000);

	alt {
	v := <-c3 =>
		t.asserteq(v, 20, "pipeline result");
	<-timeout =>
		t.fatal("pipeline timed out");
	}
}

pipeDouble(in, out: chan of int)
{
	v := <-in;
	out <-= v * 2;
}

pipeAdd(in, out: chan of int, n: int)
{
	v := <-in;
	out <-= v + n;
}

# ── Spawn with exception handling ───────────────────────────────────────────

testSpawnException(t: ref T)
{
	result := chan of string;
	spawn exceptionWorker(result);

	timeout := chan of int;
	spawn timer(timeout, 2000);

	alt {
	s := <-result =>
		t.assertseq(s, "caught", "exception in spawned task caught");
	<-timeout =>
		t.fatal("exception worker timed out");
	}
}

exceptionWorker(result: chan of string)
{
	{
		raise "test exception";
	} exception {
	"test exception" =>
		result <-= "caught";
	}
}

# ── Sequential channel operations ───────────────────────────────────────────

testSequentialOps(t: ref T)
{
	ch := chan of int;
	n := 10;

	# Send n values, receive n values in order
	spawn sequentialSender(ch, n);

	for(i := 0; i < n; i++) {
		v := <-ch;
		t.asserteq(v, i, sys->sprint("sequential %d", i));
	}
}

sequentialSender(ch: chan of int, n: int)
{
	for(i := 0; i < n; i++)
		ch <-= i;
}

# ── Bidirectional communication ──────────────────────────────────────────────

testBidirectional(t: ref T)
{
	request := chan of int;
	response := chan of int;

	spawn echoserver(request, response);

	for(i := 1; i <= 5; i++) {
		request <-= i;
		v := <-response;
		t.asserteq(v, i * i, sys->sprint("echo %d^2", i));
	}
}

echoserver(req, resp: chan of int)
{
	for(;;) {
		v := <-req;
		resp <-= v * v;
	}
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

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	run("ChannelSendRecv", testChannelSendRecv);
	run("ChannelTimeout", testChannelTimeout);
	run("FastResponse", testFastResponse);
	run("MultiProducer", testMultiProducer);
	run("FanOut", testFanOut);
	run("AltMultiple", testAltMultiple);
	run("SpawnMany", testSpawnMany);
	run("Pipeline", testPipeline);
	run("SpawnException", testSpawnException);
	run("SequentialOps", testSequentialOps);
	run("Bidirectional", testBidirectional);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
