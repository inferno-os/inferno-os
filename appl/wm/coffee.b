implement Coffee;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Context, Display, Point, Rect, Image, Screen: import draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include	"tkclient.m";
	tkclient: Tkclient;

Coffee: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

display: ref Display;
t: ref Toplevel;

NC: con 6;

task_cfg := array[] of {
	"frame .f",
	"frame .b",
	"button .b.Stop -text Stop -command {send cmd stop}",
	"scale .b.Rate -from 1 -to 10 -orient horizontal"+
		" -showvalue 0 -command {send cmd rate}",
	"scale .b.Jitter -from 0 -to 5 -orient horizontal"+
		" -showvalue 0 -command {send cmd jitter}",
	"scale .b.Skip -from 0 -to 25 -orient horizontal"+
		" -showvalue 0 -command {send cmd skip}",
	".b.Rate set 3",
	".b.Jitter set 2",
	".b.Skip set 5",
	"pack .b.Stop .b.Rate .b.Jitter .b.Skip -side left",
	"pack .b -anchor w",
	"pack .f -side bottom -fill both -expand 1",
};

init(ctxt: ref Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;

	sys->pctl(Sys->NEWPGRP, nil);

	tkclient->init();
	if(ctxt == nil)
		ctxt = tkclient->makedrawcontext();
	display = ctxt.display;

	menubut: chan of string;
	(t, menubut) = tkclient->toplevel(ctxt, "", "Infernal Coffee", 0);

	cmdch := chan of string;
	tk->namechan(t, cmdch, "cmd");

	for (i := 0; i < len task_cfg; i++)
		cmd(t, task_cfg[i]);

	tk->cmd(t, "update");
	tkclient->startinput(t, "ptr"::"kbd"::nil);
	tkclient->onscreen(t, nil);

	ctl := chan of (string, int, int);
	spawn animate(ctl);

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-menubut =>
		tkclient->wmctl(t, s);
	press := <-cmdch =>
		(nil, word) := sys->tokenize(press, " ");
		case hd word {
		"stop" or "go" =>
			ctl <-= (hd word, 0, 0);
		"rate" or "jitter" or "skip" =>
			ctl <-= (hd word, int hd tl word, 0);
		}
	}

}

animate(ctl: chan of (string, int, int))
{
	stopped := 0;

	fill := display.open("/icons/bigdelight.bit");
	if (fill == nil) {
		sys->fprint(sys->fildes(2), "coffee: failed to allocate image\n");	
		exit;
	}

	c := array[NC] of ref Image;
	m := array[NC] of ref Image;

	for(i:=0; i<NC; i++){
		c[i] = display.open("/icons/coffee"+string i+".bit");
		m[i] = display.open("/icons/coffee"+string i+".mask");
	if (c[i] == nil || m[i] == nil) {
		sys->fprint(sys->fildes(2), "coffee: failed to allocate image\n");	
		exit;
	}
	}

	r := Rect((0, 0), (400, 300));
	buffer := display.newimage(r, t.image.chans, 0, Draw->Black);
	if (buffer == nil) {
		sys->fprint(sys->fildes(2), "coffee: failed to allocate image\n");	
		exit;
	}
	cmd(t, "panel .f.p -bd 3 -relief flat");
	cmd(t, "pack .f.p -fill both -expand 1");
	cmd(t, "update");
	# org := buffer.r.min;
	tk->putimage(t, ".f.p", buffer, nil);

	rate := 3;
	jitter := 2;
	skip := 5;

	i = 0;
	for(k:=0; ; k++){
		sys->sleep(1);
		if(k%25 > 25-skip)
			i -= rate;
		else
			i += rate;
		buffer.draw(buffer.clipr, fill, nil, fill.r.min);
		center := buffer.r.max.div(2);
		for(j:=0; j<NC; j++){
			(sin, cos) := sincos(i+j*(360/NC));
			x := (sin*150)/1000 + jitter*(k%5);
			y := (cos*100)/1000 + jitter*(k%5);
			p0 := center.add((x-c[j].r.dx()/2, y-c[j].r.dy()/2));
			buffer.draw(c[j].r.addpt(p0), c[j], m[j], (0,0));
			if(j & 1)	# be nice from time to time
				sys->sleep(0);
		}
		tk->cmd(t, ".f.p dirty; update");
		sys->sleep(5);
		alt{
		(cmd, i0, i1) := <-ctl =>
	Pause:
			for(;;){
				case cmd{
				"go" =>
					if(stopped){
						tk->cmd(t, ".b.Stop configure -text Stop -command {send cmd stop}");
						tk->cmd(t, "update");
						stopped = 0;
					}
					break Pause;
				"stop" =>
					if(!stopped){
						tk->cmd(t, ".b.Stop configure -text { Go } -command {send cmd go}");
						tk->cmd(t, "update");
						stopped = 1;
					}
				"rate" =>
					rate = i0;
					if(stopped == 0)
						break Pause;
				"jitter" =>
					jitter = i0;
					if(stopped == 0)
						break Pause;
				"skip" =>
					skip = i0;
					if(stopped == 0)
						break Pause;
				}
				(cmd, i0, i1) = <-ctl;
			}
		* =>
			;
		}
	}
}

sintab := array[] of {
	0000, 0017, 0035, 0052, 0070, 0087, 0105, 0122, 0139, 0156,
	0174, 0191, 0208, 0225, 0242, 0259, 0276, 0292, 0309, 0326,
	0342, 0358, 0375, 0391, 0407, 0423, 0438, 0454, 0469, 0485,
	0500, 0515, 0530, 0545, 0559, 0574, 0588, 0602, 0616, 0629,
	0643, 0656, 0669, 0682, 0695, 0707, 0719, 0731, 0743, 0755,
	0766, 0777, 0788, 0799, 0809, 0819, 0829, 0839, 0848, 0857,
	0866, 0875, 0883, 0891, 0899, 0906, 0914, 0921, 0927, 0934,
	0940, 0946, 0951, 0956, 0961, 0966, 0970, 0974, 0978, 0982,
	0985, 0988, 0990, 0993, 0995, 0996, 0998, 0999, 0999, 1000,
	1000, };

sincos(a: int): (int, int)
{
	a %= 360;
	if(a < 0)
		a += 360;

	if(a <= 90)
		return (sintab[a], sintab[90-a]);
	if(a <= 180)
		return (sintab[180-a], -sintab[a-90]);
	if(a <= 270)
		return (-sintab[a-180], -sintab[270-a]);
	return (-sintab[360-a], sintab[a-270]);
}

cmd(win: ref Tk->Toplevel, s: string): string
{
	r := tk->cmd(win, s);
	if (len r > 0 && r[0] == '!') {
		sys->print("error executing '%s': %s\n", s, r[1:]);
	}
	return r;
}
