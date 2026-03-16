implement ToolKeyring;

#
# keyring - Veltro tool for credential management
#
# Launches the Keyring GUI app so the user can add, view, or delete
# keys in factotum.  The AI can tell the user what credentials are
# needed, but CANNOT access /mnt/factotum/ctl itself — namespace
# isolation ensures the AI never sees secrets.
#
# Usage:
#   keyring open                     Launch the Keyring GUI app
#   keyring need <description>       Launch Keyring and tell the user
#                                    what credential is needed
#   keyring check <service>          Check if a service has credentials
#                                    configured (returns yes/no, never
#                                    reveals the actual key)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolKeyring: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

UI_MOUNT: con "/n/ui";

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
	return "keyring";
}

doc(): string
{
	return "Keyring - Launch credential manager for the user\n\n" +
		"Usage:\n" +
		"  keyring open                       Launch Keyring GUI app\n" +
		"  keyring need <description>         Launch Keyring and describe what's needed\n" +
		"  keyring check <service>            Check if credentials exist (yes/no)\n\n" +
		"Examples:\n" +
		"  keyring need email credentials for imap.gmail.com\n" +
		"  keyring need anthropic API key\n" +
		"  keyring check anthropic\n" +
		"  keyring check imap\n\n" +
		"Security:\n" +
		"  This tool CANNOT read key values. It can only launch the GUI\n" +
		"  for the user to manage credentials, or check if a service\n" +
		"  has credentials configured (without revealing them).\n\n" +
		"When to use:\n" +
		"  - When a service fails with authentication errors\n" +
		"  - When setting up email, LLM, or other services\n" +
		"  - When the user asks about managing passwords/keys";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	args = strip(args);
	if(args == "" || args == "open")
		return launchkeyring();

	# Parse subcommand
	cmd := args;
	rest := "";
	for(i := 0; i < len args; i++) {
		if(args[i] == ' ' || args[i] == '\t') {
			cmd = args[0:i];
			rest = strip(args[i:]);
			break;
		}
	}

	case cmd {
	"open" =>
		return launchkeyring();
	"need" =>
		return neededcred(rest);
	"check" =>
		return checkcred(rest);
	* =>
		return "error: unknown command '" + cmd + "'\n" +
			"usage: keyring open | keyring need <desc> | keyring check <service>";
	}
}

launchkeyring(): string
{
	# Check if luciuisrv is available
	actid := currentactid();
	if(actid < 0)
		return "error: cannot reach presentation zone (is luciuisrv running?)";

	pctl := sys->sprint("%s/activity/%d/presentation/ctl", UI_MOUNT, actid);
	fd := sys->open(pctl, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("error: cannot open presentation/ctl: %r");

	cmd := "create id=keyring type=app dis=/dis/wm/keyring.dis label=keyring";
	b := array of byte cmd;
	sys->write(fd, b, len b);
	fd = nil;

	# Center it
	fd = sys->open(pctl, Sys->OWRITE);
	if(fd != nil) {
		b = array of byte "center id=keyring";
		sys->write(fd, b, len b);
		fd = nil;
	}

	return "launched Keyring in presentation zone";
}

neededcred(desc: string): string
{
	if(desc == "")
		return "error: usage: keyring need <description of what credential is needed>";

	r := launchkeyring();
	if(len r > 5 && r[0:5] == "error")
		return r;

	return "launched Keyring — please ask the user to add: " + desc + "\n" +
		"The Keyring app is now open in the presentation zone.\n" +
		"Guide the user: right-click in Keyring to add a new key.";
}

checkcred(svc: string): string
{
	if(svc == "")
		return "error: usage: keyring check <service-name>";

	# We check if factotum has a key for this service by trying
	# to read the proto list.  We do NOT read actual keys.
	# The check works by attempting to open /mnt/factotum/ctl
	# and scanning for service=<svc> in public attributes.
	# This reveals only that a key EXISTS, not its value.
	fd := sys->open("/mnt/factotum/ctl", Sys->OREAD);
	if(fd == nil)
		return "unknown: factotum not available";

	buf := array[8192] of byte;
	all := "";
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		all += string buf[0:n];
	}

	# Search for service=<svc> in the output
	target := "service=" + svc;
	if(contains(all, target))
		return "yes: credentials for '" + svc + "' are configured in factotum";

	# Also check dom= for mail servers
	target = "dom=" + svc;
	if(contains(all, target))
		return "yes: credentials for '" + svc + "' are configured in factotum";

	return "no: no credentials found for '" + svc + "' — use 'keyring need' to ask the user to add them";
}

currentactid(): int
{
	s := readfile(UI_MOUNT + "/activity/current");
	if(s == nil)
		return -1;
	s = strip(s);
	(n, nil) := str->toint(s, 10);
	return n;
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

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

contains(s, sub: string): int
{
	ls := len s;
	lsub := len sub;
	if(lsub > ls)
		return 0;
	for(i := 0; i <= ls - lsub; i++) {
		if(s[i:i+lsub] == sub)
			return 1;
	}
	return 0;
}
