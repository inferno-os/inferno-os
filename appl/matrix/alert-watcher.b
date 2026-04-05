implement AlertWatcher;

#
# alert-watcher - Matrix service module for TBL4 alerts
#
# Monitors /n/tbl4/signals for high-confidence signals and
# /n/tbl4/portfolio/defense/status for status changes.
# Writes alert files to its output directory.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "matrix.m";

AlertWatcher: module
{
	init:	fn(mount: string, outdir: string): string;
	run:	fn();
	shutdown:	fn();
};

mountpath: string;
outdir_g: string;
running: int;
alertseq: int;
lastdefense: string;

POLL_MS: con 5000;
CONFIDENCE_THRESHOLD: con "0.7";

init(mount: string, outdir: string): string
{
	sys = load Sys Sys->PATH;

	mountpath = mount;
	outdir_g = outdir;
	running = 1;
	alertseq = 0;
	lastdefense = "";
	return nil;
}

run()
{
	while(running) {
		checksignals();
		checkdefense();
		sys->sleep(POLL_MS);
	}
}

shutdown()
{
	running = 0;
}

# Parse Plan 9 text: one signal per line
# Format: id asset direction confidence signal_type timestamp
checksignals()
{
	fd := sys->open(mountpath + "/signals", Sys->OREAD);
	if(fd == nil)
		return;
	content := "";
	buf := array[32768] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		content += string buf[0:n];
	}
	fd = nil;
	if(content == "")
		return;

	# Process line by line
	start := 0;
	for(i := 0; i <= len content; i++) {
		if(i == len content || content[i] == '\n') {
			if(i > start) {
				line := content[start:i];
				(ntoks, toks) := sys->tokenize(line, " \t");
				if(ntoks >= 6) {
					toks = tl toks;  # skip id
					asset := hd toks; toks = tl toks;
					dir := hd toks; toks = tl toks;
					conf := hd toks; toks = tl toks;
					stype := hd toks;
					if(conf >= CONFIDENCE_THRESHOLD) {
						msg := sys->sprint(
							"high-confidence signal: %s %s %s (conf=%s)",
							asset, dir, stype, conf);
						writealert(msg);
					}
				}
			}
			start = i + 1;
		}
	}
}

checkdefense()
{
	fd := sys->open(mountpath + "/portfolio/defense/status", Sys->OREAD);
	if(fd == nil)
		return;
	buf := array[64] of byte;
	n := sys->read(fd, buf, len buf);
	fd = nil;
	if(n <= 0)
		return;
	status := trim(string buf[0:n]);
	if(lastdefense != "" && status != lastdefense) {
		msg := sys->sprint("defense status changed: %s -> %s", lastdefense, status);
		writealert(msg);
	}
	lastdefense = status;
}

writealert(msg: string)
{
	path := sys->sprint("%s/alert-%04d", outdir_g, alertseq);
	afd := sys->create(path, Sys->OWRITE, 8r644);
	if(afd != nil) {
		data := array of byte msg;
		sys->write(afd, data, len data);
		afd = nil;
	}
	alertseq++;
}

trim(s: string): string
{
	end := len s;
	while(end > 0 && (s[end-1] == '\n' || s[end-1] == ' '))
		end--;
	return s[0:end];
}
