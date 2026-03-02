implement VeltroConcurrentTest;

#
# Veltro Concurrent Namespace Test (v3)
#
# Tests that concurrent namespace restriction operations don't crash.
# Each worker forks its own namespace, so restrictions are isolated.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

VeltroConcurrentTest: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

include "nsconstruct.m";
	nsconstruct: NsConstruct;

SRCFILE: con "/tests/veltro_concurrent_test.b";

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

# ============================================================================
# Test 1: Concurrent nsconstruct init
# Spawns multiple threads that all call init() simultaneously
# ============================================================================
testConcurrentInit(t: ref T)
{
	done := chan of int;
	errors := chan of string;
	nthreads := 10;

	# Spawn threads that all call init
	for(i := 0; i < nthreads; i++)
		spawn initworker(done, errors);

	# Collect results
	errs: list of string;
	for(i = 0; i < nthreads; i++) {
		alt {
		e := <-errors =>
			errs = e :: errs;
		<-done =>
			;
		}
	}

	t.assert(errs == nil, "all init calls should succeed");
	for(; errs != nil; errs = tl errs)
		t.log(hd errs);
}

initworker(done: chan of int, errors: chan of string)
{
	# Small random delay to increase chance of race
	sys->sleep(sys->millisec() % 10);

	nsconstruct->init();
	done <-= 1;
}

# ============================================================================
# Test 2: Concurrent restrictdir
# Multiple threads each fork namespace and call restrictdir concurrently
# ============================================================================
testConcurrentRestrictDir(t: ref T)
{
	done := chan of int;
	errors := chan of string;
	nworkers := 3;

	# Create test directory with known contents
	testdir := "/tmp/veltro/test-concurrent";
	mkdirp(testdir);
	mkdirp(testdir + "/a");
	mkdirp(testdir + "/b");
	mkdirp(testdir + "/c");

	for(j := 0; j < nworkers; j++)
		spawn restrictdirworker(testdir, done, errors);

	# Collect results
	succeeded := 0;
	errs: list of string;
	for(k := 0; k < nworkers; k++) {
		alt {
		e := <-errors =>
			errs = e :: errs;
		<-done =>
			succeeded++;
		}
	}

	t.assert(succeeded == nworkers,
		sys->sprint("all %d workers should succeed (got %d)", nworkers, succeeded));

	for(; errs != nil; errs = tl errs)
		t.log(hd errs);
}

restrictdirworker(testdir: string, done: chan of int, errors: chan of string)
{
	# Each worker forks its own namespace
	sys->pctl(Sys->FORKNS, nil);

	err := nsconstruct->restrictdir(testdir, "a" :: nil);
	if(err != nil) {
		errors <-= sys->sprint("restrictdir failed: %s", err);
		return;
	}

	# Verify restriction worked
	(ok, nil) := sys->stat(testdir + "/a");
	if(ok < 0) {
		errors <-= "a should be visible after restrictdir";
		return;
	}

	(ok2, nil) := sys->stat(testdir + "/b");
	if(ok2 >= 0) {
		errors <-= "b should NOT be visible after restrictdir";
		return;
	}

	done <-= 1;
}

# ============================================================================
# Test 3: Concurrent restrictns
# Multiple threads each fork namespace and apply full restriction policy
# ============================================================================
testConcurrentRestrictNs(t: ref T)
{
	done := chan of int;
	errors := chan of string;
	nworkers := 3;

	for(m := 0; m < nworkers; m++)
		spawn restrictnsworker(done, errors);

	# Collect results
	succeeded := 0;
	errs: list of string;
	for(n := 0; n < nworkers; n++) {
		alt {
		e := <-errors =>
			errs = e :: errs;
		<-done =>
			succeeded++;
		}
	}

	t.assert(succeeded == nworkers,
		sys->sprint("all %d restrictns workers should succeed (got %d)", nworkers, succeeded));

	for(; errs != nil; errs = tl errs)
		t.log(hd errs);
}

restrictnsworker(done: chan of int, errors: chan of string)
{
	# Each worker forks its own namespace
	sys->pctl(Sys->FORKNS, nil);

	caps := ref NsConstruct->Capabilities(
		"read" :: nil,
		nil,
		nil,
		nil,
		0 :: 1 :: 2 :: nil,
		nil,
		0,
		0
	);

	err := nsconstruct->restrictns(caps);
	if(err != nil) {
		errors <-= sys->sprint("restrictns failed: %s", err);
		return;
	}

	# Verify basic restrictions held
	(ok, nil) := sys->stat("/dis/lib");
	if(ok < 0) {
		errors <-= "/dis/lib should exist after restrictns";
		return;
	}

	done <-= 1;
}

# ============================================================================
# Helpers
# ============================================================================
mkdirp(path: string)
{
	(ok, nil) := sys->stat(path);
	if(ok >= 0)
		return;

	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			mkdirp(path[0:i]);
			break;
		}
	}

	sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
}

# ============================================================================
# Main
# ============================================================================
init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;
	nsconstruct = load NsConstruct NsConstruct->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	if(nsconstruct == nil) {
		sys->fprint(sys->fildes(2), "cannot load nsconstruct module: %r\n");
		raise "fail:cannot load nsconstruct";
	}

	testing->init();
	nsconstruct->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	run("ConcurrentInit", testConcurrentInit);
	run("ConcurrentRestrictDir", testConcurrentRestrictDir);

	# Allow previous threads to fully exit and release forked namespaces
	# before spawning new workers that do namespace operations
	sys->sleep(200);

	run("ConcurrentRestrictNs", testConcurrentRestrictNs);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
