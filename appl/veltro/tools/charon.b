implement ToolCharon;

#
# charon - Veltro tool for controlling the Charon web browser
#
# Provides AI control over the Charon browser via its filesystem
# interface at /tmp/veltro/browser/. Supports navigation, reading
# page content, following links, and form interaction.
#
# Commands:
#   navigate <url>              Navigate to URL
#   back                        Go back in history
#   forward                     Go forward in history
#   reload                      Reload current page
#   follow <n>                  Follow link number n
#   read [body]                 Read page text
#   read url                    Read current URL
#   read title                  Read page title
#   read links                  Read numbered link index
#   read forms                  Read form fields
#   search <text>               Search in page text
#   status                      Show loading state
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolCharon: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

BROWSER_DIR: con "/tmp/veltro/browser";

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	return nil;
}

name(): string
{
	return "charon";
}

doc(): string
{
	return "Charon - AI control for the Charon web browser\n\n" +
		"Commands:\n" +
		"  navigate <url>        Navigate to a URL\n" +
		"  back                  Go back in history\n" +
		"  forward               Go forward in history\n" +
		"  reload                Reload current page\n" +
		"  follow <n>            Follow link number n\n" +
		"  read [body]           Read formatted page text\n" +
		"  read url              Read current URL\n" +
		"  read title            Read page title\n" +
		"  read links            Read numbered link index\n" +
		"  read forms            Read form fields\n" +
		"  search <text>         Search in page text\n" +
		"  status                Show loading state\n\n" +
		"The browser must be running for commands to work.\n" +
		"Use 'launch charon' to start it, optionally with a URL:\n" +
		"  launch charon https://example.com\n\n" +
		"Examples:\n" +
		"  charon navigate https://example.com\n" +
		"  charon read                    Read page text\n" +
		"  charon read links              See all links with numbers\n" +
		"  charon follow 3                Follow link #3\n" +
		"  charon back                    Go back\n" +
		"  charon search authentication   Find text on page\n";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	args = strip(args);
	if(args == "")
		return "error: no command. Use: navigate, back, forward, reload, follow, read, search, status";

	(cmd, rest) := splitfirst(args);
	cmd = str->tolower(cmd);

	case cmd {
	"navigate" or "go" =>
		return donavigate(rest);
	"back" =>
		return doctl("back");
	"forward" =>
		return doctl("forward");
	"reload" =>
		return doctl("reload");
	"follow" =>
		return dofollow(rest);
	"read" =>
		return doread(rest);
	"search" =>
		return dosearch(rest);
	"status" =>
		return dostatus();
	"stop" =>
		return doctl("stop");
	* =>
		return sys->sprint("error: unknown command '%s'", cmd);
	}
}

donavigate(url: string): string
{
	url = strip(url);
	if(url == "")
		return "error: usage: navigate <url>";
	err := writefile(BROWSER_DIR + "/ctl", "navigate " + url);
	if(err != nil)
		return err;
	# Wait briefly for page to start loading
	sys->sleep(500);
	# Poll for completion (up to 30 seconds)
	for(i := 0; i < 60; i++) {
		st := readfile(BROWSER_DIR + "/status");
		if(st == "ready" || hasprefix(st, "error:"))
			break;
		sys->sleep(500);
	}
	# Return page summary
	status := readfile(BROWSER_DIR + "/status");
	title := readfile(BROWSER_DIR + "/title");
	url = readfile(BROWSER_DIR + "/url");
	if(hasprefix(status, "error:"))
		return status;
	return sys->sprint("Loaded: %s\nTitle: %s\nURL: %s", status, title, url);
}

dofollow(args: string): string
{
	args = strip(args);
	if(args == "")
		return "error: usage: follow <link-number>";
	err := writefile(BROWSER_DIR + "/ctl", "follow " + args);
	if(err != nil)
		return err;
	sys->sleep(500);
	for(i := 0; i < 60; i++) {
		st := readfile(BROWSER_DIR + "/status");
		if(st == "ready" || hasprefix(st, "error:"))
			break;
		sys->sleep(500);
	}
	status := readfile(BROWSER_DIR + "/status");
	title := readfile(BROWSER_DIR + "/title");
	url := readfile(BROWSER_DIR + "/url");
	if(hasprefix(status, "error:"))
		return status;
	return sys->sprint("Followed link %s\nTitle: %s\nURL: %s", args, title, url);
}

doctl(cmd: string): string
{
	err := writefile(BROWSER_DIR + "/ctl", cmd);
	if(err != nil)
		return err;
	if(cmd == "back" || cmd == "forward" || cmd == "reload") {
		sys->sleep(500);
		for(i := 0; i < 60; i++) {
			st := readfile(BROWSER_DIR + "/status");
			if(st == "ready" || hasprefix(st, "error:"))
				break;
			sys->sleep(500);
		}
	}
	status := readfile(BROWSER_DIR + "/status");
	title := readfile(BROWSER_DIR + "/title");
	url := readfile(BROWSER_DIR + "/url");
	return sys->sprint("Title: %s\nURL: %s\nStatus: %s", title, url, status);
}

doread(args: string): string
{
	target := strip(args);
	if(target == "" || target == "body")
		return readfile(BROWSER_DIR + "/body");
	if(target == "url")
		return readfile(BROWSER_DIR + "/url");
	if(target == "title")
		return readfile(BROWSER_DIR + "/title");
	if(target == "links")
		return readfile(BROWSER_DIR + "/links");
	if(target == "forms")
		return readfile(BROWSER_DIR + "/forms");
	return "error: read target must be: body, url, title, links, or forms";
}

dosearch(query: string): string
{
	query = strip(query);
	if(query == "")
		return "error: usage: search <text>";
	return writefile(BROWSER_DIR + "/ctl", "search " + query);
}

dostatus(): string
{
	status := readfile(BROWSER_DIR + "/status");
	title := readfile(BROWSER_DIR + "/title");
	url := readfile(BROWSER_DIR + "/url");
	return sys->sprint("Title: %s\nURL: %s\nStatus: %s", title, url, status);
}

# --- I/O helpers ---

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("error: cannot open %s: %r (is charon running?)", path);

	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	fd = nil;
	return result;
}

writefile(path, data: string): string
{
	fd := sys->create(path, Sys->OWRITE, 8r666);
	if(fd == nil)
		return sys->sprint("error: cannot create %s: %r (is charon running?)", path);

	b := array of byte data;
	n := sys->write(fd, b, len b);
	fd = nil;

	if(n != len b)
		return sys->sprint("error: write failed: %r");

	return "ok";
}

# --- String helpers ---

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

splitfirst(s: string): (string, string)
{
	s = strip(s);
	for(i := 0; i < len s; i++) {
		if(s[i] == ' ' || s[i] == '\t')
			return (s[0:i], strip(s[i:]));
	}
	return (s, "");
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}
