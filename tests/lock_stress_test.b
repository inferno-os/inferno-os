implement LockStressTest;

#
# lock_stress_test - ARM64 lock contention stress test
#
# Validates the STLR (store-release) unlock fix under heavy
# concurrent load. Before the fix, plain STR in unlock() on
# ARM64 allowed other cores to see stale lock state, causing
# intermittent crashes under contention.
#
# Tests:
# - Channel fan-out/fan-in with many goroutines
# - Concurrent shared channel reads/writes
# - Rapid spawn/exit cycling
# - Parallel channel select contention
# - Memory allocation under concurrent load
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

LockStressTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/lock_stress_test.b";

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

# ============================================================
# Test: fan-out / fan-in with many workers
# Each worker computes a partial sum and sends it back.
# The coordinator sums all results and verifies correctness.
# ============================================================
fanout_worker(id: int, n: int, result: chan of int)
{
	sum := 0;
	for(i := 0; i < n; i++)
		sum += id + i;
	result <-= sum;
}

test_fanout(t: ref T)
{
	WORKERS : con 50;
	ITERS : con 100;

	result := chan of int;
	for(w := 0; w < WORKERS; w++)
		spawn fanout_worker(w, ITERS, result);

	total := 0;
	for(w = 0; w < WORKERS; w++)
		total += <-result;

	# Expected: sum over w=0..49 of sum(w+i, i=0..99)
	# = sum over w of (100*w + 100*99/2)
	# = 100 * (49*50/2) + 50 * 4950
	# = 100*1225 + 247500 = 122500 + 247500 = 370000
	n370000 := 370000;
	t.asserteq(total, n370000, "fan-out/fan-in total");
}

# ============================================================
# Test: pipeline - chain of workers passing values through
# ============================================================
pipeline_stage(inch: chan of int, outch: chan of int, add: int)
{
	for(;;) {
		v := <-inch;
		if(v < 0)
			break;
		outch <-= v + add;
	}
	outch <-= -1;  # propagate sentinel
}

pipeline_sender(ch: chan of int, n: int)
{
	for(i := 0; i < n; i++)
		ch <-= i;
	ch <-= -1;  # sentinel
}

test_pipeline(t: ref T)
{
	STAGES : con 20;
	MSGS : con 50;

	# Build pipeline: ch[0] -> stage0 -> ch[1] -> stage1 -> ... -> ch[STAGES]
	chs := array[STAGES + 1] of chan of int;
	for(i := 0; i < STAGES + 1; i++)
		chs[i] = chan of int;

	for(i = 0; i < STAGES; i++)
		spawn pipeline_stage(chs[i], chs[i+1], i + 1);

	# Send values concurrently (unbuffered channels deadlock if
	# sender and reader are in the same thread)
	spawn pipeline_sender(chs[0], MSGS);

	# Read results: each value should have sum(1..STAGES) added
	# sum(1..20) = 210
	n210 := 210;
	ok := 1;
	for(i = 0; i < MSGS; i++) {
		v := <-chs[STAGES];
		if(v != i + n210) {
			t.error(sys->sprint("pipeline msg %d: got %d, want %d", i, v, i + n210));
			ok = 0;
		}
	}
	sentinel := <-chs[STAGES];
	t.asserteq(sentinel, -1, "pipeline sentinel");
	if(ok)
		t.log("pipeline: all 50 messages correct through 20 stages");
}

# ============================================================
# Test: rapid spawn/exit - many short-lived processes
# ============================================================
quick_worker(id: int, done: chan of int)
{
	# Do minimal work and exit
	x := id * id;
	x = x + 1;
	done <-= x;
}

test_rapid_spawn(t: ref T)
{
	ROUNDS : con 5;
	BATCH : con 100;

	for(r := 0; r < ROUNDS; r++) {
		done := chan of int;
		for(i := 0; i < BATCH; i++)
			spawn quick_worker(i, done);

		total := 0;
		for(i = 0; i < BATCH; i++)
			total += <-done;

		# Expected: sum(i*i + 1, i=0..99) = sum(i^2) + 100
		# sum(i^2, i=0..99) = 99*100*199/6 = 328350
		# total = 328350 + 100 = 328450
		n328450 := 328450;
		t.asserteq(total, n328450, sys->sprint("rapid spawn round %d", r));
	}
	t.log(sys->sprint("rapid spawn: %d rounds x %d workers = %d total spawns",
		ROUNDS, BATCH, ROUNDS * BATCH));
}

# ============================================================
# Test: channel select contention - multiple readers, multiple writers
# ============================================================
select_writer(ch: chan of int, n: int, done: chan of int)
{
	for(i := 0; i < n; i++)
		ch <-= 1;
	done <-= 1;
}

select_reader(ch: chan of int, count: chan of int)
{
	n := 0;
	done := 0;
	while(!done) {
		alt {
		v := <-ch =>
			if(v < 0)
				done = 1;
			else
				n += v;
		}
	}
	count <-= n;
}

test_select_contention(t: ref T)
{
	WRITERS : con 10;
	MSGS_PER : con 100;
	READERS : con 5;

	ch := chan of int;
	wdone := chan of int;
	rcount := chan of int;

	# Start readers
	for(i := 0; i < READERS; i++)
		spawn select_reader(ch, rcount);

	# Start writers
	for(i = 0; i < WRITERS; i++)
		spawn select_writer(ch, MSGS_PER, wdone);

	# Wait for all writers
	for(i = 0; i < WRITERS; i++)
		<-wdone;

	# Send poison pills to readers
	for(i = 0; i < READERS; i++)
		ch <-= -1;

	# Collect reader counts
	total := 0;
	for(i = 0; i < READERS; i++)
		total += <-rcount;

	expected := WRITERS * MSGS_PER;
	t.asserteq(total, expected, "select contention total");
}

# ============================================================
# Test: concurrent string allocation - exercises heap locking
# ============================================================
string_worker(id: int, n: int, result: chan of string)
{
	s := "";
	for(i := 0; i < n; i++)
		s += "x";
	result <-= s;
}

test_concurrent_alloc(t: ref T)
{
	WORKERS : con 20;
	STRLEN : con 50;

	result := chan of string;
	for(w := 0; w < WORKERS; w++)
		spawn string_worker(w, STRLEN, result);

	ok := 1;
	for(w = 0; w < WORKERS; w++) {
		s := <-result;
		if(len s != STRLEN) {
			t.error(sys->sprint("worker %d: string len %d, want %d", w, len s, STRLEN));
			ok = 0;
		}
	}
	if(ok)
		t.log(sys->sprint("concurrent alloc: %d workers x %d chars OK", WORKERS, STRLEN));
}

# ============================================================
# Test: channel ping-pong - two processes exchange rapidly
# ============================================================
pong(ch1: chan of int, ch2: chan of int, n: int)
{
	for(i := 0; i < n; i++) {
		v := <-ch1;
		ch2 <-= v + 1;
	}
}

test_pingpong(t: ref T)
{
	ROUNDS : con 1000;

	ch1 := chan of int;
	ch2 := chan of int;
	spawn pong(ch1, ch2, ROUNDS);

	ch1 <-= 0;
	v := 0;
	for(i := 0; i < ROUNDS; i++) {
		v = <-ch2;
		if(i < ROUNDS - 1)
			ch1 <-= v;
	}
	# After 1000 round trips, value should be 1000
	t.asserteq(v, ROUNDS, "ping-pong count");
}

# ============================================================
# Test: multi-channel alt stress - select across many channels
# ============================================================
alt_sender(ch: chan of int, val: int, delay: int)
{
	if(delay > 0)
		sys->sleep(delay);
	ch <-= val;
}

test_alt_stress(t: ref T)
{
	CHANS : con 10;
	ROUNDS : con 20;

	chs := array[CHANS] of chan of int;
	for(i := 0; i < CHANS; i++)
		chs[i] = chan of int;

	total_expected := 0;
	total_got := 0;

	for(r := 0; r < ROUNDS; r++) {
		# Send one value on each channel from a spawned process
		for(i = 0; i < CHANS; i++) {
			val := r * CHANS + i;
			total_expected += val;
			spawn alt_sender(chs[i], val, 0);
		}

		# Read all values using alt
		for(i = 0; i < CHANS; i++) {
			alt {
			v := <-chs[0] => total_got += v;
			v := <-chs[1] => total_got += v;
			v := <-chs[2] => total_got += v;
			v := <-chs[3] => total_got += v;
			v := <-chs[4] => total_got += v;
			v := <-chs[5] => total_got += v;
			v := <-chs[6] => total_got += v;
			v := <-chs[7] => total_got += v;
			v := <-chs[8] => total_got += v;
			v := <-chs[9] => total_got += v;
			}
		}
	}

	t.asserteq(total_got, total_expected, "alt stress totals");
}

# ============================================================
# Test: recursive spawn tree - binary tree of processes
# ============================================================
tree_worker(depth: int, result: chan of int)
{
	if(depth <= 0) {
		result <-= 1;
		return;
	}
	ch := chan of int;
	spawn tree_worker(depth - 1, ch);
	spawn tree_worker(depth - 1, ch);
	left := <-ch;
	right := <-ch;
	result <-= left + right;
}

test_spawn_tree(t: ref T)
{
	DEPTH : con 7;  # 2^7 = 128 leaf processes, 255 total

	result := chan of int;
	spawn tree_worker(DEPTH, result);

	v := <-result;
	# 2^DEPTH leaves, each contributing 1
	expected := 1;
	for(i := 0; i < DEPTH; i++)
		expected *= 2;
	t.asserteq(v, expected, sys->sprint("spawn tree depth %d", DEPTH));
	t.log(sys->sprint("spawn tree: %d leaf processes, %d total", expected, 2 * expected - 1));
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

	run("FanOutFanIn", test_fanout);
	run("Pipeline", test_pipeline);
	run("RapidSpawn", test_rapid_spawn);
	run("SelectContention", test_select_contention);
	run("ConcurrentAlloc", test_concurrent_alloc);
	run("PingPong", test_pingpong);
	run("AltStress", test_alt_stress);
	run("SpawnTree", test_spawn_tree);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
