implement PresLaunchTest;

#
# pres_launch_test.b - Headless test for the pres-launch IPC mechanism
#
# Tests that exec.b/launch.b can signal lucifer's preslaunchpoll goroutine
# by writing to /tmp/veltro/pres-launch, which must survive the namespace
# restriction applied by nsconstruct's restrictns().
#
# Run: ./emu/MacOSX/o.emu -r. /tests/pres_launch_test.dis
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "../appl/veltro/nsconstruct.m";
	nsconstruct: NsConstruct;
	Capabilities: import nsconstruct;

PresLaunchTest: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

pass := 0;
fail := 0;

check(name, got, want: string)
{
	if(got == want) {
		sys->fprint(sys->fildes(1), "PASS: %s\n", name);
		pass++;
	} else {
		sys->fprint(sys->fildes(1), "FAIL: %s\n  got:  %q\n  want: %q\n", name, got, want);
		fail++;
	}
}

checkint(name: string, got, want: int)
{
	if(got == want) {
		sys->fprint(sys->fildes(1), "PASS: %s\n", name);
		pass++;
	} else {
		sys->fprint(sys->fildes(1), "FAIL: %s (got %d, want %d)\n", name, got, want);
		fail++;
	}
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	nsconstruct = load NsConstruct NsConstruct->PATH;
	if(nsconstruct == nil) {
		sys->fprint(sys->fildes(2), "FATAL: cannot load nsconstruct: %r\n");
		raise "fail:load";
	}

	# --- Phase 1: Before restriction ---

	(tok, nil) := sys->stat("/tmp");
	checkint("/tmp exists before restriction", tok >= 0, 1);

	# Clean up from previous run
	sys->remove("/tmp/veltro/pres-launch");

	# --- Phase 2: Apply namespace restriction (simulates tools9p serveloop) ---
	# FORKNS so the restriction doesn't affect the parent test process.
	result := chan of string;
	spawn restrictedworker(result);
	outcome := <-result;
	check("restricted worker: create /tmp/veltro/pres-launch", outcome, "ok");

	# --- Phase 3: Read the file back (from unrestricted namespace, like lucifer) ---
	sys->sleep(50);  # let the worker finish writing
	fd := sys->open("/tmp/veltro/pres-launch", Sys->OREAD);
	if(fd == nil) {
		sys->fprint(sys->fildes(1), "FAIL: cannot open /tmp/veltro/pres-launch after worker wrote it: %r\n");
		fail++;
	} else {
		buf := array[256] of byte;
		n := sys->read(fd, buf, len buf);
		fd = nil;
		if(n <= 0) {
			sys->fprint(sys->fildes(1), "FAIL: empty read from /tmp/veltro/pres-launch\n");
			fail++;
		} else {
			got := string buf[0:n];
			check("content written by restricted worker", got, "/dis/wm/clock.dis");
		}
	}

	# --- Phase 4: Open (not create) fallback path (as lucifer's exec tool uses) ---
	sys->remove("/tmp/veltro/pres-launch");
	spawn restrictedworker_open(result);
	outcome2 := <-result;
	check("restricted worker: open /n/pres-launch (expected fail)", outcome2, "open-failed");

	# --- Summary ---
	sys->fprint(sys->fildes(1), "\n%d passed, %d failed\n", pass, fail);
	if(fail > 0)
		raise "fail:tests failed";
}

# Simulates tools9p's restricted goroutine writing the pres-launch file.
# Forks namespace, applies restriction, creates /tmp/veltro/pres-launch.
restrictedworker(result: chan of string)
{
	# Fork namespace so restriction is isolated to this goroutine's thread
	sys->pctl(Sys->FORKNS, nil);

	caps := ref Capabilities(
		"exec" :: "launch" :: nil,
		"/dis/wm" :: nil,
		nil,
		nil,
		nil,
		nil,
		0,
		0
	);

	err := nsconstruct->restrictns(caps);
	if(err != nil) {
		result <-= "restrictns failed: " + err;
		return;
	}

	# Try to create /tmp/veltro/pres-launch (what exec.b/launch.b do)
	pfd := sys->create("/tmp/veltro/pres-launch", Sys->OWRITE, 8r644);
	if(pfd == nil) {
		creerr := sys->sprint("%r");
		(tok, nil) := sys->stat("/tmp");
		(vok, nil) := sys->stat("/tmp/veltro");
		result <-= sys->sprint("create failed: %s (stat /tmp=%d /tmp/veltro=%d)", creerr, tok, vok);
		return;
	}

	data := array of byte "/dis/wm/clock.dis";
	sys->write(pfd, data, len data);
	pfd = nil;
	result <-= "ok";
}

# Tests that /n/pres-launch (file2chan approach) correctly fails without lucifer.
restrictedworker_open(result: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);
	# Don't apply restriction — just test the open
	pfd := sys->open("/n/pres-launch", Sys->OWRITE);
	if(pfd == nil)
		result <-= "open-failed";
	else
		result <-= "open-succeeded";
}
