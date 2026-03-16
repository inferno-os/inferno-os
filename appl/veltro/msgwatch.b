implement Msgwatch;

#
# msgwatch - Message notification watcher daemon for Veltro
#
# Thin relay between /n/msg/notify and the Meta Agent.
#
# Lucifer mode (when /n/ui is mounted):
#   Reads blocking notifications from /n/msg/notify.
#   Writes each notification to /n/ui/activity/0/conversation/input
#   so the Meta Agent receives and classifies it.
#
# Headless mode (no /n/ui):
#   Creates own LLM session, loads secretary policy,
#   classifies and handles messages autonomously.
#
# Usage: msgwatch [-v] [-p policyfile] [-a actid]
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "arg.m";

include "../agentlib.m";
	agentlib: AgentLib;

Msgwatch: module {
	PATH: con "/dis/veltro/msgwatch.dis";
	init: fn(nil: ref Draw->Context, args: list of string);
};

stderr: ref Sys->FD;
verbose := 0;
actid := 0;
policyfile := "/lib/veltro/policies/secretary.txt";

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	str = load String String->PATH;
	if(str == nil)
		fatal("cannot load String");

	agentlib = load AgentLib AgentLib->PATH;
	if(agentlib == nil)
		fatal("cannot load AgentLib");
	agentlib->init();

	arg := load Arg Arg->PATH;
	if(arg == nil)
		fatal("cannot load Arg");
	arg->init(args);

	while((o := arg->opt()) != 0)
		case o {
		'v' =>
			verbose = 1;
			agentlib->setverbose(1);
		'p' =>
			policyfile = arg->earg();
		'a' =>
			actid = int arg->earg();
		* =>
			sys->fprint(stderr, "usage: msgwatch [-v] [-p policyfile] [-a actid]\n");
			raise "fail:usage";
		}
	arg = nil;

	# Determine mode: Lucifer (has /n/ui) or headless
	uipath := sys->sprint("/n/ui/activity/%d/conversation/input", actid);
	fd := sys->open(uipath, Sys->OWRITE);
	if(fd != nil) {
		fd = nil;
		log("Lucifer mode: relaying to activity " + string actid);
		luciferloop(uipath);
	} else {
		log("Headless mode: autonomous classification");
		headlessloop();
	}
}

# Lucifer mode: relay notifications to Meta Agent conversation
luciferloop(inputpath: string)
{
	notifypath := "/n/msg/notify";

	for(;;) {
		# Blocking read on /n/msg/notify
		notifyfd := sys->open(notifypath, Sys->OREAD);
		if(notifyfd == nil) {
			log("cannot open " + notifypath + ", retrying in 5s");
			sys->sleep(5000);
			continue;
		}

		notification := blockread(notifyfd);
		notifyfd = nil;

		if(notification == nil) {
			log("notify closed, retrying in 1s");
			sys->sleep(1000);
			continue;
		}

		log("notification: " + truncate(notification, 80));

		# Write notification to Meta Agent's conversation input
		inputfd := sys->open(inputpath, Sys->OWRITE);
		if(inputfd == nil) {
			log("cannot open " + inputpath + ": " + sys->sprint("%r"));
			continue;
		}

		data := array of byte notification;
		n := sys->write(inputfd, data, len data);
		inputfd = nil;

		if(n != len data)
			log("short write to input: " + sys->sprint("%r"));
		else
			log("relayed to Meta Agent");
	}
}

# Headless mode: classify and handle autonomously
headlessloop()
{
	# Load policy
	policy := agentlib->readfile(policyfile);
	if(policy == nil) {
		log("warning: cannot read policy " + policyfile + ", using defaults");
		policy = "Classify messages as IGNORE (spam), DEFER (legitimate, non-urgent), or NOTIFY (urgent).";
	}

	# Create LLM session for classification
	sessionid := agentlib->createsession();
	if(sessionid == "") {
		fatal("cannot create LLM session for headless classification");
	}
	log("LLM session: " + sessionid);

	# Set system prompt with policy
	systemprompt := "You are a message classifier for an autonomous agent.\n\n" +
		policy + "\n\n" +
		"For each message notification, respond with exactly one line:\n" +
		"IGNORE - for spam, marketing, automated notifications\n" +
		"DECLINE <brief reason> - for solicitations to politely refuse\n" +
		"DEFER <brief reason> - for legitimate but non-urgent messages\n" +
		"NOTIFY <brief reason> - for urgent messages needing attention\n\n" +
		"Then on the next line, if DECLINE/DEFER/NOTIFY, include a suggested reply draft.";

	systempath := "/n/llm/" + sessionid + "/system";
	agentlib->setsystemprompt(systempath, systemprompt);

	# Open persistent ask fd
	askpath := "/n/llm/" + sessionid + "/ask";
	llmfd := sys->open(askpath, Sys->ORDWR);
	if(llmfd == nil) {
		fatal("cannot open " + askpath);
	}

	notifypath := "/n/msg/notify";

	for(;;) {
		notifyfd := sys->open(notifypath, Sys->OREAD);
		if(notifyfd == nil) {
			log("cannot open " + notifypath + ", retrying in 5s");
			sys->sleep(5000);
			continue;
		}

		notification := blockread(notifyfd);
		notifyfd = nil;

		if(notification == nil) {
			log("notify closed, retrying in 1s");
			sys->sleep(1000);
			continue;
		}

		log("notification: " + truncate(notification, 80));

		# Classify via LLM
		response := agentlib->queryllmfd(llmfd, notification);
		if(response == nil || response == "") {
			log("LLM returned empty response, skipping");
			continue;
		}

		log("classification: " + truncate(response, 120));

		# Parse and act on classification
		handleclassification(response, notification);
	}
}

# Handle a classification result in headless mode
handleclassification(response, notification: string)
{
	line := firstline(response);
	lline := str->tolower(line);

	if(agentlib->hasprefix(lline, "ignore")) {
		# Extract message ID and mark as seen
		msgid := extractmsgid(notification);
		if(msgid != nil) {
			result := agentlib->calltool("mail", "flag " + msgid + " seen");
			log("IGNORE: archived " + msgid + ": " + truncate(result, 60));
		} else {
			log("IGNORE: no message ID found");
		}

	} else if(agentlib->hasprefix(lline, "decline")) {
		msgid := extractmsgid(notification);
		if(msgid != nil) {
			# Read the full message, draft refusal, send it
			draft := extractdraft(response);
			if(draft != nil) {
				result := agentlib->calltool("mail", "reply " + msgid + " " + draft);
				log("DECLINE: " + truncate(result, 80));
			} else {
				log("DECLINE: no draft in LLM response for " + msgid);
			}
		}

	} else if(agentlib->hasprefix(lline, "defer")) {
		msgid := extractmsgid(notification);
		log("DEFER: " + msgid + " — draft saved for user review");
		# In headless mode, just log it. The draft is in the LLM response.

	} else if(agentlib->hasprefix(lline, "notify")) {
		msgid := extractmsgid(notification);
		log("NOTIFY: urgent message " + msgid);
		# In headless mode, log urgently. Could write to a file for monitoring.

	} else {
		log("unrecognized classification: " + truncate(line, 60));
	}
}

# ---- Helpers ----

blockread(fd: ref Sys->FD): string
{
	buf := array[65536] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	s := string buf[0:n];
	if(len s > 0 && s[len s - 1] == '\n')
		s = s[0:len s - 1];
	return s;
}

# Extract message ID from notification text
# Looks for "Message ID: email/42" or similar patterns
extractmsgid(notification: string): string
{
	lines := splitlines(notification);
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		if(agentlib->hasprefix(line, "Message ID: ")) {
			id := line[len "Message ID: ":];
			# Extract just the numeric part after source/
			for(i := len id - 1; i >= 0; i--) {
				if(id[i] == '/') {
					return id[i+1:];
				}
			}
			return id;
		}
	}
	return nil;
}

# Extract draft reply from LLM response (everything after the first line)
extractdraft(response: string): string
{
	for(i := 0; i < len response; i++) {
		if(response[i] == '\n') {
			draft := response[i+1:];
			# Trim leading whitespace
			return agentlib->strip(draft);
		}
	}
	return nil;
}

firstline(s: string): string
{
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n')
			return s[:i];
	}
	return s;
}

splitlines(s: string): list of string
{
	result: list of string;
	start := 0;
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n') {
			result = s[start:i] :: result;
			start = i + 1;
		}
	}
	if(start < len s)
		result = s[start:] :: result;

	# Reverse
	rev: list of string;
	for(; result != nil; result = tl result)
		rev = hd result :: rev;
	return rev;
}

truncate(s: string, max: int): string
{
	if(len s <= max)
		return s;
	return s[:max] + "...";
}

log(msg: string)
{
	if(verbose)
		sys->fprint(stderr, "msgwatch: %s\n", msg);
}

fatal(msg: string)
{
	sys->fprint(stderr, "msgwatch: %s\n", msg);
	raise "fail:" + msg;
}
