implement PlanTest;

#
# Tests for the plan tool
#
# To run: cd $ROOT && ./emu/MacOSX/o.emu -r. /tests/plan_test.dis
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

# Tool interface (same as /appl/veltro/tool.m)
Tool: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

PlanTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/plan_test.b";

passed := 0;
failed := 0;
skipped := 0;

plantool: Tool;

run(testname: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(testname, SRCFILE);
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

# Helper: check result does NOT start with "error:"
assertok(t: ref T, result, msg: string)
{
	if(len result >= 6 && result[0:6] == "error:")
		t.error(msg + ": got error: " + result);
}

# Helper: check result starts with "error:"
asserterr(t: ref T, result, msg: string)
{
	if(len result < 6 || result[0:6] != "error:")
		t.error(msg + ": expected error, got: " + result);
}

# Helper: check that result contains substring
assertcontains(t: ref T, result, sub, msg: string)
{
	if(!contains(result, sub))
		t.error(msg + ": expected '" + sub + "' in: " + result);
}

contains(s, sub: string): int
{
	slen := len sub;
	for(i := 0; i <= len s - slen; i++) {
		if(s[i:i+slen] == sub)
			return 1;
	}
	return 0;
}

# Clean up plans directory before tests
cleanup()
{
	# Remove test plans dir
	rmdir("/tmp/veltro/plans");
}

rmdir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			child := path + "/" + dirs[i].name;
			if(dirs[i].mode & Sys->DMDIR)
				rmdir(child);
			else
				sys->remove(child);
		}
	}
	fd = nil;
	sys->remove(path);
}

# Test: load plan tool
testLoad(t: ref T)
{
	if(plantool == nil)
		t.fatal("cannot load plan tool");
	t.assert(plantool->name() == "plan", "tool name is 'plan'");
}

# Test: no command
testNoCommand(t: ref T)
{
	result := plantool->exec("");
	asserterr(t, result, "empty command");
}

# Test: unknown command
testUnknownCommand(t: ref T)
{
	result := plantool->exec("bogus");
	asserterr(t, result, "bogus command");
}

# Test: no active plan
testNoActivePlan(t: ref T)
{
	result := plantool->exec("show");
	asserterr(t, result, "show with no plan");
	assertcontains(t, result, "no active plan", "error message");
}

# Test: create a plan
testCreate(t: ref T)
{
	result := plantool->exec("create Refactor authentication");
	assertok(t, result, "create plan");
	assertcontains(t, result, "created plan 1", "plan id");
	assertcontains(t, result, "Refactor authentication", "title");
	assertcontains(t, result, "draft", "status");
}

# Test: set goal
testGoal(t: ref T)
{
	result := plantool->exec("goal Replace session-based auth with JWT tokens");
	assertok(t, result, "set goal");
	assertcontains(t, result, "goal set", "confirmation");
}

# Test: set approach
testApproach(t: ref T)
{
	result := plantool->exec("approach Create JWT middleware, migrate endpoints one by one, then remove old session code");
	assertok(t, result, "set approach");
	assertcontains(t, result, "approach set", "confirmation");
}

# Test: add steps
testAddSteps(t: ref T)
{
	result := plantool->exec("step Create JWT signing module");
	assertok(t, result, "step 1");
	assertcontains(t, result, "step 1", "step number");

	result = plantool->exec("step Add JWT middleware to router");
	assertok(t, result, "step 2");
	assertcontains(t, result, "step 2", "step number");

	result = plantool->exec("step Migrate login endpoint");
	assertok(t, result, "step 3");

	result = plantool->exec("step Remove old session code");
	assertok(t, result, "step 4");

	result = plantool->exec("step Run tests");
	assertok(t, result, "step 5");
}

# Test: add context
testContext(t: ref T)
{
	result := plantool->exec("context Using RS256 for token signing");
	assertok(t, result, "add context");
	assertcontains(t, result, "context added", "confirmation");
}

# Test: show plan
testShow(t: ref T)
{
	result := plantool->exec("show");
	assertok(t, result, "show plan");
	assertcontains(t, result, "Refactor authentication", "title");
	assertcontains(t, result, "draft", "status");
	assertcontains(t, result, "JWT", "goal");
	assertcontains(t, result, "middleware", "approach");
	assertcontains(t, result, "RS256", "context");
	assertcontains(t, result, "0/5 done", "step count");
	assertcontains(t, result, "[ ]", "pending markers");
}

# Test: approve without steps (should fail) — tested implicitly, we have steps

# Test: approve
testApprove(t: ref T)
{
	result := plantool->exec("approve");
	assertok(t, result, "approve plan");
	assertcontains(t, result, "approved", "status");
	assertcontains(t, result, "5 steps", "step count");
}

# Test: double approve
testDoubleApprove(t: ref T)
{
	result := plantool->exec("approve");
	assertcontains(t, result, "already approved", "already approved");
}

# Test: progress step 1
testProgress(t: ref T)
{
	result := plantool->exec("progress 1");
	assertok(t, result, "progress step 1");
	assertcontains(t, result, "step 1 done", "confirmation");
	assertcontains(t, result, "4 remaining", "remaining count");
}

# Test: show after progress
testShowAfterProgress(t: ref T)
{
	result := plantool->exec("show");
	assertok(t, result, "show after progress");
	assertcontains(t, result, "1/5 done", "updated count");
	assertcontains(t, result, "[x]", "done marker");
}

# Test: skip step
testSkip(t: ref T)
{
	result := plantool->exec("skip 4 Not needed with JWT");
	assertok(t, result, "skip step 4");
	assertcontains(t, result, "step 4 skipped", "confirmation");
	assertcontains(t, result, "Not needed", "reason");
}

# Test: revise step
testRevise(t: ref T)
{
	result := plantool->exec("revise 3 Migrate login and signup endpoints");
	assertok(t, result, "revise step 3");
	assertcontains(t, result, "step 3 revised", "confirmation");
}

# Test: addstep (insert after step 2)
testAddStep(t: ref T)
{
	result := plantool->exec("addstep 2 Add token refresh endpoint");
	assertok(t, result, "addstep");
	assertcontains(t, result, "step 6", "new step id");
	assertcontains(t, result, "after 2", "position");
}

# Test: progress remaining and complete
testComplete(t: ref T)
{
	# Progress remaining steps
	plantool->exec("progress 2");
	plantool->exec("progress 3");
	plantool->exec("progress 5");
	plantool->exec("progress 6");

	result := plantool->exec("complete");
	assertok(t, result, "complete plan");
	assertcontains(t, result, "complete", "status");
}

# Test: list plans
testList(t: ref T)
{
	result := plantool->exec("list");
	assertok(t, result, "list plans");
	assertcontains(t, result, "Refactor authentication", "title");
	assertcontains(t, result, "complete", "status");
}

# Test: create second plan and switch
testSwitchPlan(t: ref T)
{
	result := plantool->exec("create Fix database indexes");
	assertok(t, result, "create second plan");
	assertcontains(t, result, "plan 2", "plan id 2");

	# Verify list shows both
	result = plantool->exec("list");
	assertcontains(t, result, "Refactor authentication", "plan 1 in list");
	assertcontains(t, result, "Fix database indexes", "plan 2 in list");
	assertcontains(t, result, "*", "active marker");
}

# Test: abandon
testAbandon(t: ref T)
{
	result := plantool->exec("abandon Priorities changed");
	assertok(t, result, "abandon plan");
	assertcontains(t, result, "abandoned", "status");
	assertcontains(t, result, "Priorities changed", "reason");
}

# Test: export-todo with no active plan
testExportNoActive(t: ref T)
{
	result := plantool->exec("export-todo");
	asserterr(t, result, "export-todo with no plan");
}

# Test: export-memory with no active plan
testExportMemoryNoActive(t: ref T)
{
	result := plantool->exec("export-memory testkey");
	asserterr(t, result, "export-memory with no plan");
}

# Test: progress invalid step number
testProgressInvalid(t: ref T)
{
	# Create a plan for this test
	plantool->exec("create Test plan");
	plantool->exec("step Do something");
	plantool->exec("approve");

	result := plantool->exec("progress 99");
	asserterr(t, result, "progress nonexistent step");
}

# Test: progress on draft plan
testProgressDraft(t: ref T)
{
	plantool->exec("complete");
	plantool->exec("create Draft plan");

	result := plantool->exec("progress 1");
	asserterr(t, result, "progress on draft");
	assertcontains(t, result, "not yet approved", "draft message");
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

	# Clean slate
	cleanup();

	# Load plan tool
	plantool = load Tool "/dis/veltro/tools/plan.dis";
	if(plantool != nil)
		plantool->init();

	# Run tests in order (they build on each other)
	run("Load", testLoad);
	run("NoCommand", testNoCommand);
	run("UnknownCommand", testUnknownCommand);
	run("NoActivePlan", testNoActivePlan);
	run("Create", testCreate);
	run("Goal", testGoal);
	run("Approach", testApproach);
	run("AddSteps", testAddSteps);
	run("Context", testContext);
	run("Show", testShow);
	run("Approve", testApprove);
	run("DoubleApprove", testDoubleApprove);
	run("Progress", testProgress);
	run("ShowAfterProgress", testShowAfterProgress);
	run("Skip", testSkip);
	run("Revise", testRevise);
	run("AddStep", testAddStep);
	run("Complete", testComplete);
	run("List", testList);
	run("SwitchPlan", testSwitchPlan);
	run("Abandon", testAbandon);
	run("ExportNoActive", testExportNoActive);
	run("ExportMemoryNoActive", testExportMemoryNoActive);
	run("ProgressInvalid", testProgressInvalid);
	run("ProgressDraft", testProgressDraft);

	# Cleanup
	cleanup();

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
