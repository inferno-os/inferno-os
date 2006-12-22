implement Samterm;

include "sys.m";
sys: Sys;
fprint, sprint, FD: import sys;
stderr, logfd: ref FD;

include "draw.m";
draw:	Draw;

include "samterm.m";

include "samtk.m";
samtk: Samtk;

include "samstub.m";
samstub: Samstub;
Samio, Sammsg: import samstub;

samio: ref Samio;

ctxt: ref Context;

init(context: ref draw->Context, nil: list of string)
{
	recvsam: chan of ref Sammsg;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	stderr = sys->fildes(2);

	logfd = sys->create("samterm.log", sys->OWRITE, 8r666);
	if (logfd == nil) {
		fprint(stderr, "Can't create samterm.log\n");
		logfd = stderr;
	}

	fprint(logfd, "Samterm started\n");

	pgrp := sys->pctl(sys->NEWPGRP, nil);

	ctxt = ref Context(
		context,
		1000,		# initial tag

		0,		# lock

		nil,		# keysel
		nil,		# scrollsel
		nil,		# buttonsel
		nil,		# menu2sel
		nil,		# menu3sel
		nil,		# titlesel
		nil,		# tags

		nil,		# menus
		nil,		# texts

		nil,		# cmd
		nil,		# which
		nil,		# work
		pgrp,		# pgrp
		logfd		# logging file descriptor
	);

	samtk = load Samtk Samtk->PATH;
	if (samtk == nil) {
		fprint(stderr, "Can't load %s\n", Samtk->PATH);
		return;
	}
	samtk->init(ctxt);

	samstub = load Samstub Samstub->PATH;
	if (samstub == nil) {
		fprint(stderr, "Can't load %s\n", Samstub->PATH);
		return;
	}
	samstub->init(ctxt);

	(samio, recvsam) = samstub->start();
	if (samio == nil) {
		fprint(stderr, "couldn't start samstub\n");
		return;
	}
	samstub->outTs(samstub->Tversion, samstub->VERSION);

	samstub->startcmdfile();

	samstub->setlock();

	for(;;) if (ctxt.lock == 0) alt {
	(win, menu) := <-ctxt.titlesel =>
		samstub->cleanout();
		fl := ctxt.flayers[win];
		tag := fl.tag;
		if ((i := samtk->whichtext(tag)) < 0)
			samtk->panic("samterm: whichtext");
		t := ctxt.texts[i];
		samtk->newcur(t, fl);
		case menu {
		"exit" =>
			if (ctxt.flayers[win].tag == 0) {
				samstub->outT0(samstub->Texit);
				f := sprint("#p/%d/ctl", pgrp);
				if ((fd := sys->open(f, sys->OWRITE)) != nil)
					sys->write(fd, array of byte "killgrp\n", 8);
				return;
			}
			samstub->close(win, tag);
		"resize" =>
			samtk->resize(fl);
			samstub->scrollto(fl, fl.scope.first);
		"task" =>
			spawn samtk->titlectl(win, menu);
		* =>
			samtk->titlectl(win, menu);
		}


	(win, m1) := <-ctxt.buttonsel =>
		samstub->cleanout();
		fl := ctxt.flayers[win];
		tag := fl.tag;
		if (samtk->buttonselect(fl, m1)) {
			samstub->outTsl(samstub->Tdclick, tag, fl.dot.first);
			samstub->setlock();
		}
	(win, m2) := <-ctxt.menu2sel =>
		samstub->cleanout();
		fl := ctxt.flayers[win];
		tag := fl.tag;
		if ((i := samtk->whichtext(tag)) < 0)
			samtk->panic("samterm: whichtext");
		t := ctxt.texts[i];
		samtk->newcur(t, fl);
		case m2 {
		"cut" =>
			samstub->cut(t, fl);
		"paste" =>
			samstub->paste(t, fl);
		"snarf" =>
			samstub->snarf(t, fl);
		"look" =>
			samstub->look(t, fl);
		"exch" =>
			fprint(ctxt.logfd, "debug -- exch: %d, %s\n", win, m2);
		"send" =>
			samstub->send(t, fl);
		"search" =>
			samstub->search(t, fl);
		* =>
			samtk->panic("samterm: editmenu");
		}
	(win, m3) := <-ctxt.menu3sel =>
		samstub->cleanout();
		fl := ctxt.flayers[win];
		tag := fl.tag;
		if ((i := samtk->whichtext(tag)) < 0)
			samtk->panic("samterm: whichtext");
		t := ctxt.texts[i];
		samtk->newcur(t, fl);
		case m3 {
		"new" =>
			samstub->startnewfile();
		"zerox" =>
			samstub->zerox(t);
		"close" =>
			if (win != 0) {
				samstub->close(win, tag);
			}
		"write" =>
			samstub->outTs(samstub->Twrite, tag);
			samstub->setlock();
		* =>
			for (i = 0; i < len ctxt.menus; i++) {
				if (ctxt.menus[i].name == m3) {
					break;
				}
			}
			if (i == len ctxt.menus)
				samtk->panic("init: can't find m3");
			t = ctxt.menus[i].text;
			t.flayers = samtk->append(tl t.flayers, hd t.flayers);
			samtk->newcur(t, hd t.flayers);
			
		}
	(win, c) := <-ctxt.keysel =>
		if (ctxt.which != ctxt.flayers[win]) {
			fprint(ctxt.logfd, "probably can't happen\n");
			samstub->cleanout();
			tag := ctxt.flayers[win].tag;
			if ((i := samtk->whichtext(tag)) < 0)
				samtk->panic("samterm: whichtext");
			samtk->newcur(ctxt.texts[i], ctxt.flayers[win]);
		}
		samstub->keypress(c[1:len c -1]);
	(win, c) := <-ctxt.scrollsel =>
		if (ctxt.which != ctxt.flayers[win]) {
			samstub->cleanout();
			tag := ctxt.flayers[win].tag;
			if ((i := samtk->whichtext(tag)) < 0)
				samtk->panic("samterm: whichtext");
			samtk->newcur(ctxt.texts[i], ctxt.flayers[win]);
		}
		(pos, lines) := samtk->scroll(ctxt.which, c);
		if (lines > 0) {
			samstub->outTsll(samstub->Torigin,
				ctxt.which.tag, pos, lines);
			samstub->setlock();
		} else if (pos != -1)
			samstub->scrollto(ctxt.which, pos);
	h := <-recvsam =>
		if (samstub->inmesg(h)) {
			samstub->outT0(samstub->Texit);
			fname := sprint("#p/%d/ctl", pgrp);
			if ((fdesc := sys->open(fname, sys->OWRITE)) != nil)
				sys->write(fdesc, array of byte "killgrp\n", 8);
			return;
		}
	} else {
		h := <-recvsam;
		if (samstub->inmesg(h)) {
			samstub->outT0(samstub->Texit);
			fname := sprint("#p/%d/ctl", pgrp);
			if ((fdesc := sys->open(fname, sys->OWRITE)) != nil)
				sys->write(fdesc, array of byte "killgrp\n", 8);
			return;
		}
	}
}
