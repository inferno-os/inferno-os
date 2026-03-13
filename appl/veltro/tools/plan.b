implement ToolPlan;

#
# plan - Structured planning tool for Veltro agent
#
# Manages structured plans for complex, multi-step work.
# A plan captures the goal, approach, steps, and status of a
# non-trivial task before execution begins.
#
# Plans persist in the session directory (or /tmp/veltro/plans/).
# Only one plan can be "active" at a time.
#
# Usage:
#   plan create <title>              Create a new plan (becomes active)
#   plan goal <text>                 Set the goal/objective
#   plan approach <text>             Set the approach/strategy
#   plan step <text>                 Add a step to the plan
#   plan context <text>              Add context/notes
#   plan show                        Show the active plan
#   plan approve                     Mark plan as approved for execution
#   plan progress <n>                Mark step N as done
#   plan skip <n> [reason]           Skip step N with optional reason
#   plan revise <n> <text>           Revise step N text
#   plan addstep <after_n> <text>    Insert step after position N
#   plan complete                    Mark plan as complete
#   plan abandon [reason]            Abandon the active plan
#   plan list                        List all plans
#   plan switch <id>                 Switch active plan
#   plan export-todo                 Export pending steps to todo tool
#   plan export-memory <key>         Save plan summary to memory
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolPlan: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

PLAN_DEFAULT_DIR: con "/tmp/veltro/plans";

# Resolved at init from VELTRO_SESSION or PLAN_DEFAULT_DIR
plandir: string;

# Plan statuses
STATUS_DRAFT:     con "draft";
STATUS_APPROVED:  con "approved";
STATUS_ACTIVE:    con "active";
STATUS_COMPLETE:  con "complete";
STATUS_ABANDONED: con "abandoned";

# Step statuses
STEP_PENDING:  con "pending";
STEP_DONE:     con "done";
STEP_SKIPPED:  con "skipped";

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	plandir = getplandir();
	return nil;
}

name(): string
{
	return "plan";
}

doc(): string
{
	return "plan - Structured planning for complex tasks\n\n" +
		"Usage:\n" +
		"  plan create <title>           Create a new plan (becomes active)\n" +
		"  plan goal <text>              Set the goal/objective\n" +
		"  plan approach <text>          Set the approach/strategy\n" +
		"  plan step <text>              Add a step to the plan\n" +
		"  plan context <text>           Add context/notes\n" +
		"  plan show                     Show the active plan\n" +
		"  plan approve                  Mark plan as approved (ready to execute)\n" +
		"  plan progress <n>             Mark step N as done\n" +
		"  plan skip <n> [reason]        Skip step N\n" +
		"  plan revise <n> <text>        Revise step N\n" +
		"  plan addstep <after_n> <text> Insert step after position N\n" +
		"  plan complete                 Mark plan as complete\n" +
		"  plan abandon [reason]         Abandon the active plan\n" +
		"  plan list                     List all plans\n" +
		"  plan switch <id>              Switch active plan\n" +
		"  plan export-todo              Export pending steps to todo\n" +
		"  plan export-memory <key>      Save plan summary to memory\n\n" +
		"Workflow: create → goal → approach → step(s) → approve → progress → complete\n\n" +
		"MANDATORY for complex tasks: create a plan before starting work.\n" +
		"Break the approach into concrete steps. Approve before executing.\n" +
		"Mark steps done as you go. Complete or abandon when finished.";
}

exec(args: string): string
{
	if(sys == nil)
		init();
	if(plandir == "")
		plandir = getplandir();

	args = strip(args);
	if(args == "")
		return "error: usage: plan <create|goal|approach|step|context|show|approve|progress|skip|revise|addstep|complete|abandon|list|switch|export-todo|export-memory>";

	(cmd, rest) := splitfirst(args);
	cmd = str->tolower(cmd);

	case cmd {
	"create" =>
		return docreate(rest);
	"goal" =>
		return dogoal(rest);
	"approach" =>
		return doapproach(rest);
	"step" =>
		return dostep(rest);
	"context" =>
		return docontext(rest);
	"show" =>
		return doshow();
	"approve" =>
		return doapprove();
	"progress" =>
		return doprogress(rest);
	"skip" =>
		return doskip(rest);
	"revise" =>
		return dorevise(rest);
	"addstep" =>
		return doaddstep(rest);
	"complete" =>
		return docomplete();
	"abandon" =>
		return doabandon(rest);
	"list" =>
		return dolist();
	"switch" =>
		return doswitch(rest);
	"export-todo" =>
		return doexporttodo();
	"export-memory" =>
		return doexportmemory(rest);
	* =>
		return "error: unknown command: " + cmd;
	}
}

# ==================== Plan file format ====================
#
# Each plan is a directory: plandir/<id>/
# Files within:
#   meta     — id|status|title
#   goal     — goal text
#   approach — approach text
#   context  — context notes (appended)
#   steps    — one line per step: n|status|text[|reason]
#   active   — presence indicates this is the active plan
#
# The "current" symlink (plandir/current) contains the active plan id.

# Create a new plan
docreate(title: string): string
{
	title = strip(title);
	if(title == "")
		return "error: usage: plan create <title>";

	err := ensuredir(plandir);
	if(err != nil)
		return "error: " + err;

	# Generate next plan ID
	id := nextid();
	pdir := plandir + "/" + string id;

	err = ensuredir(pdir);
	if(err != nil)
		return "error: " + err;

	# Write metadata
	err = writefile(pdir + "/meta", string id + "|" + STATUS_DRAFT + "|" + title);
	if(err != nil)
		return "error: " + err;

	# Set as active plan
	err = writefile(plandir + "/current", string id);
	if(err != nil)
		return "error: " + err;

	return sys->sprint("created plan %d: %s [draft]\nUse 'plan goal', 'plan approach', and 'plan step' to flesh it out.", id, title);
}

# Set goal for active plan
dogoal(text: string): string
{
	text = strip(text);
	if(text == "")
		return "error: usage: plan goal <text>";

	(pdir, err) := activedir();
	if(err != nil)
		return err;

	werr := writefile(pdir + "/goal", text);
	if(werr != nil)
		return "error: " + werr;

	return "goal set";
}

# Set approach for active plan
doapproach(text: string): string
{
	text = strip(text);
	if(text == "")
		return "error: usage: plan approach <text>";

	(pdir, err) := activedir();
	if(err != nil)
		return err;

	werr := writefile(pdir + "/approach", text);
	if(werr != nil)
		return "error: " + werr;

	return "approach set";
}

# Add a step to active plan
dostep(text: string): string
{
	text = strip(text);
	if(text == "")
		return "error: usage: plan step <text>";

	(pdir, err) := activedir();
	if(err != nil)
		return err;

	steps := loadsteps(pdir);

	# Find max step number
	maxn := 0;
	for(l := steps; l != nil; l = tl l) {
		(nstr, nil) := spliton(hd l, '|');
		n := int(nstr);
		if(n > maxn)
			maxn = n;
	}

	newn := maxn + 1;
	newstep := string newn + "|" + STEP_PENDING + "|" + text;
	steps = appenditem(steps, newstep);

	werr := writesteps(pdir, steps);
	if(werr != nil)
		return "error: " + werr;

	return sys->sprint("added step %d: %s", newn, text);
}

# Add context notes
docontext(text: string): string
{
	text = strip(text);
	if(text == "")
		return "error: usage: plan context <text>";

	(pdir, err) := activedir();
	if(err != nil)
		return err;

	# Append to existing context
	existing := "";
	(content, rerr) := readfile(pdir + "/context");
	if(rerr == nil && content != "")
		existing = content + "\n";

	werr := writefile(pdir + "/context", existing + text);
	if(werr != nil)
		return "error: " + werr;

	return "context added";
}

# Show the active plan
doshow(): string
{
	(pdir, err) := activedir();
	if(err != nil)
		return err;

	# Read metadata
	(meta, merr) := readfile(pdir + "/meta");
	if(merr != nil)
		return "error: cannot read plan metadata";

	(idstr, rest) := spliton(meta, '|');
	(status, title) := spliton(rest, '|');

	result := sys->sprint("Plan %s: %s [%s]\n", idstr, title, status);

	# Goal
	(goal, nil) := readfile(pdir + "/goal");
	if(goal != "" && goal != nil)
		result += "\nGoal: " + goal + "\n";

	# Approach
	(approach, nil) := readfile(pdir + "/approach");
	if(approach != "" && approach != nil)
		result += "\nApproach: " + approach + "\n";

	# Context
	(context, nil) := readfile(pdir + "/context");
	if(context != "" && context != nil)
		result += "\nContext:\n" + context + "\n";

	# Steps
	steps := loadsteps(pdir);
	if(steps != nil) {
		npending := 0;
		ndone := 0;
		nskipped := 0;
		for(l := steps; l != nil; l = tl l) {
			(nil, srest) := spliton(hd l, '|');
			(sstatus, nil) := spliton(srest, '|');
			case sstatus {
			STEP_DONE    => ndone++;
			STEP_SKIPPED => nskipped++;
			*            => npending++;
			}
		}

		total := npending + ndone + nskipped;
		result += sys->sprint("\nSteps (%d/%d done", ndone, total);
		if(nskipped > 0)
			result += sys->sprint(", %d skipped", nskipped);
		result += "):\n";

		for(l = steps; l != nil; l = tl l) {
			item := hd l;
			(nstr, srest) := spliton(item, '|');
			(sstatus, stext) := spliton(srest, '|');
			marker := "[ ]";
			case sstatus {
			STEP_DONE    => marker = "[x]";
			STEP_SKIPPED => marker = "[-]";
			}
			result += sys->sprint("  %s %s %s\n", nstr, marker, stext);
		}
	}

	# Strip trailing newline
	if(len result > 0 && result[len result - 1] == '\n')
		result = result[0:len result - 1];

	return result;
}

# Approve the plan for execution
doapprove(): string
{
	(pdir, err) := activedir();
	if(err != nil)
		return err;

	(meta, merr) := readfile(pdir + "/meta");
	if(merr != nil)
		return "error: cannot read plan metadata";

	(idstr, rest) := spliton(meta, '|');
	(status, title) := spliton(rest, '|');

	if(status == STATUS_APPROVED || status == STATUS_ACTIVE)
		return "plan already approved";
	if(status == STATUS_COMPLETE || status == STATUS_ABANDONED)
		return sys->sprint("error: plan is %s", status);

	# Check that plan has steps
	steps := loadsteps(pdir);
	if(steps == nil)
		return "error: plan has no steps — add steps before approving";

	# Update status to approved
	werr := writefile(pdir + "/meta", idstr + "|" + STATUS_APPROVED + "|" + title);
	if(werr != nil)
		return "error: " + werr;

	nsteps := listlen(steps);
	return sys->sprint("plan %s approved with %d steps — ready to execute", idstr, nsteps);
}

# Mark step N as done
doprogress(nstr: string): string
{
	nstr = strip(nstr);
	if(nstr == "")
		return "error: usage: plan progress <step_number>";

	n := int(nstr);
	if(n <= 0)
		return "error: invalid step number";

	(pdir, err) := activedir();
	if(err != nil)
		return err;

	# Ensure plan is approved or active
	(meta, merr) := readfile(pdir + "/meta");
	if(merr != nil)
		return "error: cannot read plan metadata";
	(idstr, rest) := spliton(meta, '|');
	(status, title) := spliton(rest, '|');

	if(status == STATUS_DRAFT)
		return "error: plan not yet approved — use 'plan approve' first";
	if(status == STATUS_COMPLETE || status == STATUS_ABANDONED)
		return sys->sprint("error: plan is %s", status);

	# Promote to active on first progress
	if(status == STATUS_APPROVED) {
		writefile(pdir + "/meta", idstr + "|" + STATUS_ACTIVE + "|" + title);
	}

	steps := loadsteps(pdir);
	found := 0;
	foundtext := "";
	acc: list of string;

	for(l := steps; l != nil; l = tl l) {
		item := hd l;
		(sid, srest) := spliton(item, '|');
		if(int(sid) == n) {
			(nil, stext) := spliton(srest, '|');
			acc = (sid + "|" + STEP_DONE + "|" + stext) :: acc;
			found = 1;
			foundtext = stext;
		} else {
			acc = item :: acc;
		}
	}

	if(!found)
		return sys->sprint("error: step %d not found", n);

	werr := writesteps(pdir, reverselist(acc));
	if(werr != nil)
		return "error: " + werr;

	# Count remaining
	remaining := 0;
	for(l = reverselist(acc); l != nil; l = tl l) {
		(nil, srest) := spliton(hd l, '|');
		(sstatus, nil) := spliton(srest, '|');
		if(sstatus == STEP_PENDING)
			remaining++;
	}

	msg := sys->sprint("step %d done: %s", n, foundtext);
	if(remaining == 0)
		msg += "\nAll steps complete! Use 'plan complete' to finish.";
	else
		msg += sys->sprint(" (%d remaining)", remaining);

	return msg;
}

# Skip step N
doskip(args: string): string
{
	args = strip(args);
	if(args == "")
		return "error: usage: plan skip <n> [reason]";

	(nstr, reason) := splitfirst(args);
	n := int(nstr);
	if(n <= 0)
		return "error: invalid step number";

	(pdir, err) := activedir();
	if(err != nil)
		return err;

	steps := loadsteps(pdir);
	found := 0;
	foundtext := "";
	acc: list of string;

	for(l := steps; l != nil; l = tl l) {
		item := hd l;
		(sid, srest) := spliton(item, '|');
		if(int(sid) == n) {
			(nil, stext) := spliton(srest, '|');
			entry := sid + "|" + STEP_SKIPPED + "|" + stext;
			if(reason != "")
				entry += "|" + reason;
			acc = entry :: acc;
			found = 1;
			foundtext = stext;
		} else {
			acc = item :: acc;
		}
	}

	if(!found)
		return sys->sprint("error: step %d not found", n);

	werr := writesteps(pdir, reverselist(acc));
	if(werr != nil)
		return "error: " + werr;

	msg := sys->sprint("step %d skipped: %s", n, foundtext);
	if(reason != "")
		msg += " (reason: " + reason + ")";
	return msg;
}

# Revise step N text
dorevise(args: string): string
{
	args = strip(args);
	if(args == "")
		return "error: usage: plan revise <n> <new_text>";

	(nstr, newtext) := splitfirst(args);
	n := int(nstr);
	if(n <= 0)
		return "error: invalid step number";
	if(newtext == "")
		return "error: usage: plan revise <n> <new_text>";

	(pdir, err) := activedir();
	if(err != nil)
		return err;

	steps := loadsteps(pdir);
	found := 0;
	acc: list of string;

	for(l := steps; l != nil; l = tl l) {
		item := hd l;
		(sid, srest) := spliton(item, '|');
		if(int(sid) == n) {
			(sstatus, nil) := spliton(srest, '|');
			acc = (sid + "|" + sstatus + "|" + newtext) :: acc;
			found = 1;
		} else {
			acc = item :: acc;
		}
	}

	if(!found)
		return sys->sprint("error: step %d not found", n);

	werr := writesteps(pdir, reverselist(acc));
	if(werr != nil)
		return "error: " + werr;

	return sys->sprint("step %d revised: %s", n, newtext);
}

# Insert a step after position N (0 = insert at beginning)
doaddstep(args: string): string
{
	args = strip(args);
	if(args == "")
		return "error: usage: plan addstep <after_n> <text>";

	(nstr, text) := splitfirst(args);
	after := int(nstr);
	if(after < 0)
		return "error: invalid position";
	if(text == "")
		return "error: usage: plan addstep <after_n> <text>";

	(pdir, err) := activedir();
	if(err != nil)
		return err;

	steps := loadsteps(pdir);

	# Find max step number for new ID
	maxn := 0;
	for(sl := steps; sl != nil; sl = tl sl) {
		(sid, nil) := spliton(hd sl, '|');
		sn := int(sid);
		if(sn > maxn)
			maxn = sn;
	}

	newn := maxn + 1;
	newstep := string newn + "|" + STEP_PENDING + "|" + text;

	# Insert after position
	if(after == 0) {
		steps = newstep :: steps;
	} else {
		acc: list of string;
		inserted := 0;
		for(l := steps; l != nil; l = tl l) {
			acc = hd l :: acc;
			(sid, nil) := spliton(hd l, '|');
			if(int(sid) == after && !inserted) {
				acc = newstep :: acc;
				inserted = 1;
			}
		}
		if(!inserted)
			acc = newstep :: acc;
		steps = reverselist(acc);
	}

	werr := writesteps(pdir, steps);
	if(werr != nil)
		return "error: " + werr;

	return sys->sprint("inserted step %d after %d: %s", newn, after, text);
}

# Mark plan as complete
docomplete(): string
{
	(pdir, err) := activedir();
	if(err != nil)
		return err;

	(meta, merr) := readfile(pdir + "/meta");
	if(merr != nil)
		return "error: cannot read plan metadata";

	(idstr, rest) := spliton(meta, '|');
	(status, title) := spliton(rest, '|');

	if(status == STATUS_COMPLETE)
		return "plan already complete";
	if(status == STATUS_ABANDONED)
		return "error: plan is abandoned";

	# Check for pending steps
	steps := loadsteps(pdir);
	npending := 0;
	for(l := steps; l != nil; l = tl l) {
		(nil, srest) := spliton(hd l, '|');
		(sstatus, nil) := spliton(srest, '|');
		if(sstatus == STEP_PENDING)
			npending++;
	}

	werr := writefile(pdir + "/meta", idstr + "|" + STATUS_COMPLETE + "|" + title);
	if(werr != nil)
		return "error: " + werr;

	msg := sys->sprint("plan %s complete: %s", idstr, title);
	if(npending > 0)
		msg += sys->sprint(" (%d steps were still pending)", npending);

	# Clear current pointer
	writefile(plandir + "/current", "");

	return msg;
}

# Abandon the plan
doabandon(reason: string): string
{
	reason = strip(reason);

	(pdir, err) := activedir();
	if(err != nil)
		return err;

	(meta, merr) := readfile(pdir + "/meta");
	if(merr != nil)
		return "error: cannot read plan metadata";

	(idstr, rest) := spliton(meta, '|');
	(nil, title) := spliton(rest, '|');

	werr := writefile(pdir + "/meta", idstr + "|" + STATUS_ABANDONED + "|" + title);
	if(werr != nil)
		return "error: " + werr;

	if(reason != "") {
		# Save abandonment reason in context
		existing := "";
		(content, nil) := readfile(pdir + "/context");
		if(content != "")
			existing = content + "\n";
		writefile(pdir + "/context", existing + "[ABANDONED] " + reason);
	}

	# Clear current pointer
	writefile(plandir + "/current", "");

	msg := sys->sprint("plan %s abandoned: %s", idstr, title);
	if(reason != "")
		msg += " (reason: " + reason + ")";
	return msg;
}

# List all plans
dolist(): string
{
	fd := sys->open(plandir, Sys->OREAD);
	if(fd == nil)
		return "(no plans)";

	# Read current active plan id
	currentid := "";
	(cid, nil) := readfile(plandir + "/current");
	if(cid != nil)
		currentid = strip(cid);

	result := "";
	count := 0;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			dname := dirs[i].name;
			if(dname == "." || dname == ".." || dname == "current")
				continue;
			# Must be a directory (plan id)
			if(!(dirs[i].mode & Sys->DMDIR))
				continue;

			(meta, merr) := readfile(plandir + "/" + dname + "/meta");
			if(merr != nil)
				continue;

			(idstr, rest) := spliton(strip(meta), '|');
			(status, title) := spliton(rest, '|');

			marker := " ";
			if(idstr == currentid)
				marker = "*";

			if(result != "")
				result += "\n";
			result += sys->sprint("%s %s: %s [%s]", marker, idstr, title, status);
			count++;
		}
	}
	fd = nil;

	if(count == 0)
		return "(no plans)";

	return sys->sprint("%d plans (* = active):\n%s", count, result);
}

# Switch active plan
doswitch(idstr: string): string
{
	idstr = strip(idstr);
	if(idstr == "")
		return "error: usage: plan switch <id>";

	id := int(idstr);
	if(id <= 0)
		return "error: invalid plan id";

	pdir := plandir + "/" + string id;
	(meta, merr) := readfile(pdir + "/meta");
	if(merr != nil)
		return sys->sprint("error: plan %d not found", id);

	(nil, rest) := spliton(strip(meta), '|');
	(status, title) := spliton(rest, '|');

	if(status == STATUS_COMPLETE || status == STATUS_ABANDONED)
		return sys->sprint("error: plan %d is %s", id, status);

	err := writefile(plandir + "/current", string id);
	if(err != nil)
		return "error: " + err;

	return sys->sprint("switched to plan %d: %s [%s]", id, title, status);
}

# Export pending steps to the todo tool
doexporttodo(): string
{
	(pdir, err) := activedir();
	if(err != nil)
		return err;

	(meta, merr) := readfile(pdir + "/meta");
	if(merr != nil)
		return "error: cannot read plan metadata";

	(nil, rest) := spliton(strip(meta), '|');
	(nil, title) := spliton(rest, '|');

	steps := loadsteps(pdir);
	exported := 0;
	result := "";

	for(l := steps; l != nil; l = tl l) {
		item := hd l;
		(nstr, srest) := spliton(item, '|');
		(sstatus, stext) := spliton(srest, '|');
		if(sstatus == STEP_PENDING) {
			if(result != "")
				result += "\n";
			result += sys->sprint("[plan:%s step:%s] %s", title, nstr, stext);
			exported++;
		}
	}

	if(exported == 0)
		return "no pending steps to export";

	# The result is formatted for the caller (agent) to pass to todo
	return sys->sprint("export %d pending steps to todo:\n%s\n\nUse 'todo add' for each line above.", exported, result);
}

# Export plan summary to memory
doexportmemory(key: string): string
{
	key = strip(key);
	if(key == "")
		return "error: usage: plan export-memory <key>";

	(pdir, err) := activedir();
	if(err != nil)
		return err;

	(meta, merr) := readfile(pdir + "/meta");
	if(merr != nil)
		return "error: cannot read plan metadata";

	(nil, rest) := spliton(strip(meta), '|');
	(status, title) := spliton(rest, '|');

	summary := "Plan: " + title + " [" + status + "]\n";

	(goal, nil) := readfile(pdir + "/goal");
	if(goal != "")
		summary += "Goal: " + goal + "\n";

	(approach, nil) := readfile(pdir + "/approach");
	if(approach != "")
		summary += "Approach: " + approach + "\n";

	steps := loadsteps(pdir);
	if(steps != nil) {
		summary += "Steps:\n";
		for(l := steps; l != nil; l = tl l) {
			(nstr, srest) := spliton(hd l, '|');
			(sstatus, stext) := spliton(srest, '|');
			marker := "[ ]";
			case sstatus {
			STEP_DONE    => marker = "[x]";
			STEP_SKIPPED => marker = "[-]";
			}
			summary += "  " + nstr + " " + marker + " " + stext + "\n";
		}
	}

	# Format for caller to pass to memory tool
	return sys->sprint("Save this to memory with: memory save %s <content>\n\nContent:\n%s", key, summary);
}


# ==================== Helper functions ====================

# Get plan directory from environment or default
getplandir(): string
{
	fd := sys->open("/env/VELTRO_SESSION", Sys->OREAD);
	if(fd == nil)
		return PLAN_DEFAULT_DIR;
	buf := array[512] of byte;
	n := sys->read(fd, buf, len buf);
	fd = nil;
	if(n <= 0)
		return PLAN_DEFAULT_DIR;
	sdir := string buf[0:n];
	j := len sdir;
	while(j > 0 && (sdir[j-1] == ' ' || sdir[j-1] == '\n' || sdir[j-1] == '\r'))
		j--;
	sdir = sdir[0:j];
	if(sdir == "")
		return PLAN_DEFAULT_DIR;
	return sdir + "/plans";
}

# Get the active plan directory, or error
activedir(): (string, string)
{
	(cid, cerr) := readfile(plandir + "/current");
	if(cerr != nil || strip(cid) == "")
		return ("", "error: no active plan — use 'plan create' or 'plan switch'");

	id := strip(cid);
	pdir := plandir + "/" + id;

	# Verify it exists
	(ok, nil) := sys->stat(pdir);
	if(ok < 0)
		return ("", sys->sprint("error: active plan %s not found", id));

	return (pdir, nil);
}

# Get next plan ID
nextid(): int
{
	fd := sys->open(plandir, Sys->OREAD);
	if(fd == nil)
		return 1;

	maxid := 0;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++) {
			dname := dirs[i].name;
			if(dname == "." || dname == ".." || dname == "current")
				continue;
			id := int(dname);
			if(id > maxid)
				maxid = id;
		}
	}
	fd = nil;
	return maxid + 1;
}

# Load steps from plan directory
loadsteps(pdir: string): list of string
{
	(content, err) := readfile(pdir + "/steps");
	if(err != nil)
		return nil;

	items: list of string;
	nc := len content;
	i := 0;
	while(i <= nc) {
		j := i;
		while(j < nc && content[j] != '\n')
			j++;
		line := strip(content[i:j]);
		if(line != "")
			items = line :: items;
		i = j + 1;
	}
	return reverselist(items);
}

# Write steps to plan directory
writesteps(pdir: string, steps: list of string): string
{
	if(steps == nil) {
		sys->remove(pdir + "/steps");
		return nil;
	}

	content := "";
	for(l := steps; l != nil; l = tl l) {
		if(content != "")
			content += "\n";
		content += hd l;
	}

	return writefile(pdir + "/steps", content);
}

# Write a file atomically
writefile(path, data: string): string
{
	# Ensure parent directory exists
	parent := "";
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			parent = path[0:i];
			break;
		}
	}
	if(parent != "") {
		err := ensuredir(parent);
		if(err != nil)
			return err;
	}

	fd := sys->create(path, Sys->OWRITE, 8r600);
	if(fd == nil)
		return sys->sprint("cannot create %s: %r", path);

	b := array of byte data;
	if(sys->write(fd, b, len b) < 0) {
		fd = nil;
		return sys->sprint("write failed: %r");
	}
	fd = nil;
	return nil;
}

# Read entire file
readfile(path: string): (string, string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return ("", sys->sprint("cannot open %s: %r", path));

	content := "";
	buf := array[8192] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0)
		content += string buf[0:n];

	fd = nil;
	return (content, nil);
}

# Ensure directory exists
ensuredir(path: string): string
{
	(ok, nil) := sys->stat(path);
	if(ok >= 0)
		return nil;

	parent := "";
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			parent = path[0:i];
			break;
		}
	}
	if(parent != "" && parent != "/") {
		err := ensuredir(parent);
		if(err != nil)
			return err;
	}

	fd := sys->create(path, Sys->OREAD, 8r700 | Sys->DMDIR);
	if(fd == nil)
		return sys->sprint("cannot create %s: %r", path);
	fd = nil;
	return nil;
}

# Append item to list
appenditem(items: list of string, item: string): list of string
{
	if(items == nil)
		return item :: nil;
	return hd items :: appenditem(tl items, item);
}

# Reverse list
reverselist(l: list of string): list of string
{
	rev: list of string;
	for(; l != nil; l = tl l)
		rev = hd l :: rev;
	return rev;
}

# Count list length
listlen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

# Split on first character
spliton(s: string, c: int): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == c)
			return (s[0:i], s[i+1:]);
	}
	return (s, "");
}

# Strip whitespace
strip(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n'))
		j--;
	if(i >= j)
		return "";
	return s[i:j];
}

# Split on first whitespace
splitfirst(s: string): (string, string)
{
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], strip(s[i:]));
	}
	return (s, "");
}
