implement WmVt;

# note: this code was hacked together in a hurry from some decade-old C code
# of mine, so don't expect it to be pretty...
# Also, don't expect it to be finished... I had to rush to check this
# in... it's just been worked on as a side-project from time to time
# But it's good enough to be useful most of the time
 
include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
	draw: Draw;
	Display, Font, Black, Rect, Image, Point, Endsquare, Enddisc: import draw;
include "tk.m";
	tk: Tk;
	Toplevel: import tk;
include "tkclient.m";
	tkclient: Tkclient;
include "sh.m";

CON_Maxnpts:	con 1000;
Maxnhits:	con 5;

 
WmVt: module {
	init:   fn(ctxt: ref Draw->Context, argv: list of string);
};



VT_MAXPARAM: con 8;


Vt: adt {
	y1, y2: int;
	mode: int;	# misc mode parameters 
	qmode: int;	# extended mode parameters
	attr: int; 	# display attributes 
	fg: int;	# foreground color 
	bg: int;	# background color 

	# saved values:
	save_x, save_y: int;
	save_attr: int;
	save_fg, save_bg: int;
	save_mode: int;
	save_qmode: int;

	# escape code parsing:
	esc: int;	# escape mode 
	pcount: int;	# parameter count
	etype: int;	# escape code type
	ptype: int;	# current parameter type
	value: int;	# current value
	param: array of int;

	# display info:
	wid, hgt: int;
	x, y: int;
	dx, dy: int;
	nlcr: int;
	ccc: int;
	scr: array of string;
	cc: array of string;
};


display: ref Display;
t: ref Toplevel;
canvas: ref Image;
canvrect: Rect;
org: Point;
font: ref Font;
stderr: ref Sys->FD;
vt: ref Vt;
pad: string;
vtc := array[16] of ref Image;
raw := 0;
echo := 1;
reverse := 0;
sq := "";

inpchan: chan of string;


shwin_cfg := array[] of {
	"frame .f",
	"pack .c .f -side top -fill x",
	"pack propagate . 0",
	"focus .f",
	"bind .f <Key> {send keys {%A}}",
	"bind . <Configure> {send cmd resize}",
	"update"
};


titlebar()
{
	tk->cmd(t, "destroy .Wm_t.S");
	tk->cmd(t, "button .Wm_t.S -bg #aaaaaa -fg white -text {" +
		sprint("%d x %d", vt.wid, vt.hgt) + "}; " +
		"pack .Wm_t.S -side right");
	c := "green";
	if(raw)
		c = "red";
	tk->cmd(t, "destroy .Wm_t.k");
	tk->cmd(t, "button .Wm_t.k -bitmap keyboard.bit"+
		" -background "+c+" -command {send wm_title raw}; " +
		"pack .Wm_t.k -side right");
	c = "red";
	if(echo)
		c = "green";
	tk->cmd(t, "destroy .Wm_t.d");
	tk->cmd(t, "button .Wm_t.d -bitmap display.bit"+
		" -background "+c+" -command {send wm_title echo}; " +
				"pack .Wm_t.d -side right");
	c = "white";
	if(reverse)
		c = "black";
	tk->cmd(t, "destroy .Wm_t.r");
	tk->cmd(t, "button .Wm_t.r -width 24 -height 24 "+
		" -background "+c+" -command {send wm_title reverse}; " +
				"pack .Wm_t.r -side right");
	tk->cmd(t, "update");
}

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "vt: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;

	stderr = sys->fildes(2);

	sys->pctl(Sys->FORKNS, nil);
	sys->pctl(Sys->NEWPGRP, nil);

	menubut: chan of string;
	tkclient->init();
	(t, menubut) = tkclient->toplevel(ctxt, "", "WmVt", Tkclient->Appl);

	display = ctxt.display;	
	font = Font.open(display, "*default*");

	vt = ref Vt;
	vt.hgt = 24;
	vt.wid = 80;
	vt.scr = array[vt.hgt] of string;
	vt.cc = array[vt.hgt] of string;
	vt_init(vt);

	pad = "";
	for(i:=0; i<vt.wid; i++) 
		pad[i] = ' ';

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");
	tk->cmd(t, "canvas .c -height "
		+ string (vt.hgt*font.height) +
		+ " -width " + string (vt.wid*font.width("0")) +
		" -background red");
	tkcmds(t, shwin_cfg);
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);
	titlebar();

	keys := chan of string;
	tk->namechan(t, keys, "keys");
 
	canvas = t.image;
	canvrect = canvposn(t);
	org = canvrect.min;
	
	npts := 0;
	WasUp := 1;

	for(i=0; i<16; i++) {
		r := 0;
		g := 0;
		b := 0;
		v := 192;
		if(i&8)
			v = 255;
		if(i&1)
			r = v;
		if(i&2)
			g = v;
		if(i&4)
			b = v;
		vtc[i] = display.newimage(((0,0),(1,1)), t.image.chans,
				1, display.rgb2cmap(r, g, b));
		if (vtc[i] == nil) {
			sys->fprint(sys->fildes(2), "Failed to allocate image\n");
			exit;
		}
	}

	vt_write(vt, "\u001b[2J");

	ioc := chan of (int, ref Sys->FileIO, ref Sys->FileIO);
	spawn newsh(ctxt, ioc);
	
	(pid, file, filectl) := <- ioc;
	if((file == nil) || (filectl == nil)) {
		sys->print("newsh: %r\n");
		return;
	}

	# XXX - need to kill this later
	ic := chan of string;
	spawn consinp(ic, file.read);

	inpchan = ic;	# hack

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq =>
		tkclient->wmctl(t, s);
	menu := <- menubut =>
		if(menu == "exit") {
			kill(pid);
			return;
		}
		else if(menu == "raw") {
			raw = !raw;
			titlebar();
			redraw();
		}
		else if(menu == "echo") {
			echo = !echo;
			titlebar();
			redraw();
		}
		else if(menu == "reverse") {
			reverse = !reverse;
			tmp := vtc[0];
			vtc[0] = vtc[7];
			vtc[7] = tmp;
			titlebar();
			redraw();
		} else
			tkclient->wmctl(t, menu);
		tk->cmd(t, "focus .f");

	s := <- cmd =>
		(n, cmdstr) := sys->tokenize(s, " \t\n");
		case hd cmdstr {
		"quit" =>
			exit;
		"resize" =>
			# sys->print("resize\n");
			canvas = t.image;
			canvrect = canvposn(t);
			org = canvrect.min;
			# sys->print("%d,%d %d,%d\n", canvrect.max.x, canvrect.min.x,
			#	canvas.r.max.x, canvas.r.min.x);
			resize((canvrect.max.x-canvrect.min.x)/font.width("0"),
				(canvrect.max.y-canvrect.min.y)/font.height);
			titlebar();
			redraw();
		}

	c := <- keys =>
		ic <-= c[1:2];
		if(echo)
			scwrite(c[1:2]);

	(off, data, fid, wc) := <- file.write =>
		if(wc == nil)
			return;
		if(echo && !raw && sq != "") {
			s := "";
			for(i=0; i<len sq; i++)
				s += "\b \b";
			scwrite(s);
		}
		scwrite(string data);
		if(echo && !raw && sq != "")
			scwrite(sq);
		wc <-= (len data, nil);
	(off, data, fid, wc) := <- filectl.write =>
		if(string data == "rawon") {
			raw = 1;
			echo = 0;
			titlebar();
			redraw();
		}
		if(string data == "rawoff") {
			raw = 0;
			echo = 1;
			titlebar();
			redraw();
		}
		wc <-= (len data, nil);
	}
}

resize(wid,hgt: int)
{
	scr := array[hgt] of string;
	cc := array[hgt] of string;
	for(y :=0; y<hgt; y++) {
		oy := y + hgt - vt.hgt;
		if(oy < vt.hgt && oy >= 0) {
			scr[y] = vt.scr[oy];
			cc[y] = vt.cc[oy];
		} else {
			scr[y] = "";
			cc[y] = "";
		}
	}
	vt.x += wid - vt.wid;
	vt.y += hgt - vt.hgt;
	if(vt.x < 0)
		vt.x = 0;
	if(vt.x >= wid)
		vt.x = wid;
	if(vt.y < 0)
		vt.y = 0;
	if(vt.y >= hgt)
		vt.y = hgt;
	vt.wid = wid;
	vt.hgt = hgt;
	vt.scr = scr;
	vt.cc = cc;
}


fixdx := 0;
fixdy := 0;

canvposn(t: ref Toplevel): Rect
{
	r: Rect;

	r.min.x = int tk->cmd(t, ".c cget -actx") + int tk->cmd(t, ".dx get");
	r.min.y = int tk->cmd(t, ".c cget -acty") + int tk->cmd(t, ".dy get");
	r.max.x = r.min.x + int tk->cmd(t, ".c cget -width") + int tk->cmd(t, ".dw get");
	r.max.y = r.min.y + int tk->cmd(t, ".c cget -height") + int tk->cmd(t, ".dh get");

	# correction for Tk bug (width/height not correct):
	dx := (t.image.r.max.x - t.image.r.min.x) - (r.max.x - r.min.x);
	dy := (t.image.r.max.y - t.image.r.min.y) - (r.max.y - r.min.y);
	if(fixdx == 0) {
		fixdx = dx;
		fixdy = dy;
	} else {
		r.max.x += dx-fixdx;
		r.max.y += dy-fixdy;
	}
	return r;
}


redraw()
{
	# sys->print("redraw\n");
	for(y:=0; y<vt.hgt; y++) {
		xp := canvrect.min.x;
		yp := canvrect.max.y-(vt.hgt-y)*font.height;
		f := 0;
		for(x:=0; x<=len vt.cc[y]; x++) {
			if(x == len vt.cc[y] || (vt.cc[y][x]>>4) != (vt.cc[y][f]>>4)) {
				if(x == len vt.cc[y])
					w := canvrect.max.x-xp;
				else
					w = font.width(vt.scr[y][f:x]);
				if(len vt.cc[y] == 0)
					ccc := 7;
				else
					ccc = vt.cc[y][f];
				canvas.draw(((xp,yp),(xp+w,yp+font.height)),
					vtc[ccc>>4], nil, (0, 0));
				xp += w;
				f = x;
			}
		}
		xp = canvrect.min.x;
		f = 0;
		for(x=1; x<=len vt.scr[y]; x++) {
			if(x == len vt.scr[y] || (vt.cc[y][x]&15) != (vt.cc[y][f]&15)) {
				canvas.text((xp,yp), vtc[vt.cc[y][f]&15],
					(0, 0), font, vt.scr[y][f:x]);
				xp += font.width(vt.scr[y][f:x]);
				f = x;
			}
		}
	}
}



scwrite(s: string)
{
	putchar(vt.x, vt.y, vtscr(vt.y, vt.x), vtcc(vt.y, vt.x));
	vt_write(vt, s);
	putchar(vt.x, vt.y, vtscr(vt.y, vt.x), vtcc(vt.y, vt.x) ^ 16rff);
}

putchar(x,y: int, ch: int, ccc: int)
{
	if(len vt.scr[y] < x) {
		vt.scr[y] += pad[0:x-len vt.scr[y]];
		vt.cc[y] += pad[0:x-len vt.cc[y]];
	}
	xp := canvrect.min.x+font.width(vt.scr[y][0:x]);
	yp := canvrect.max.y-(vt.hgt-y)*font.height;
	s: string;
	s[0] = ch;
	canvas.draw(((xp,yp),(xp+font.width(s),yp+font.height)),
				vtc[ccc>>4], nil, (0, 0));
	canvas.text((xp,yp), vtc[ccc&15], (0, 0), font, s);
}

VT_PUTCHAR(vt: ref Vt, x,y: int, ch: int)
{
	if(len vt.scr[y] < x) {
		vt.scr[y] += pad[0:x-len vt.scr[y]];
		vt.cc[y] += pad[0:x-len vt.cc[y]];
	}
	vt.scr[y][x] = ch;
	vt.cc[y][x] = vt.ccc;
	putchar(x, y, ch, int vt.ccc);
}

VT_SCROLL_UP(vt: ref Vt, x1,y1,x2,y2,n: int)
{
	# XXX - needs to handle vertical slices
	for(i:=y1; i<=y2-n; i++) {
		vt.scr[i] = vt.scr[i+n];
		vt.cc[i] = vt.cc[i+n];
	}
	r: Rect;
	r.min.x = canvrect.min.x;
	r.max.x = r.min.x+(x2-x1+1)*font.width(" ");
	r.min.y = canvrect.max.y-(vt.hgt-y1)*font.height;
	r.max.y = r.min.y+(y2-y1-n+1)*font.height;
	canvas.draw(r, canvas, nil, (r.min.x, r.min.y+font.height*n));
	VT_CLEAR(vt, x1,y2-n+1,x2,y2);
}

VT_SCROLL_DOWN(vt: ref Vt, x1,y1,x2,y2,n: int)
{
	# XXX - needs to handle vertical slices
	for(i:=y2; i>=y1+n; i--) {
		vt.scr[i] = vt.scr[i-n];
		vt.cc[i] = vt.cc[i-n];
	}
	VT_CLEAR(vt, x1,y1,x2,y1+n-1);
	redraw();
}

VT_SCROLL_LEFT(vt: ref Vt, x1,y1,x2,y2,n: int)
{
	# XXX - shouldn't always scroll whole line
	for(y:=y1; y<=y2; y++) {
		if(len vt.scr[y] > n) {
			vt.scr[y] = vt.scr[y][n:];
			vt.cc[y] = vt.cc[y][n:];
		} else {
			vt.scr[y] = "";
			vt.cc[y] = "";
		}
	}
	redraw();
}

VT_SCROLL_RIGHT(vt: ref Vt, x1,y1,x2,y2,n: int)
{
	# XXX - shouldn't always scroll whole line
	for(y:=y1; y<=y2; y++) {
		vt.scr[y] = pad[0:n] + vt.scr[y];
		vt.cc[y] = pad[0:n] + vt.cc[y];
	}
	redraw();
}

VT_CLEAR(vt: ref Vt, x1,y1,x2,y2: int)
{
	# XXX - needs to handle vertical slices
	for(y:=y1; y<=y2; y++) {
		vt.scr[y] = "";
		vt.cc[y] = "";
	}
	r: Rect;
	r.min.x = canvrect.min.x;
	r.max.x = r.min.x + (x2-x1+1)*font.width(" ");
	r.min.y = canvrect.max.y-(vt.hgt-y1)*font.height;
	r.max.y = r.min.y + (y2-y1+1)*font.height;
	canvas.draw(r, vtc[vt.ccc>>4], nil, (0, 0));
}

VT_SET_COLOR(vt: ref Vt)
{
	if(vt.attr & (1<<7))
		vt.ccc = ((vt.fg<<4) | vt.bg);
	else
		vt.ccc = ((vt.bg<<4) | vt.fg);
	if(vt.attr & (1<<1))
		vt.ccc ^= (1<<3);
}

vtscr(y,x: int): int
{
	if(vt.scr[y] == nil)
		return ' ';
	if(x >= len vt.scr[y])
		return ' ';
	return vt.scr[y][x];
}

vtcc(y,x: int): int
{
	if(vt.cc[y] == nil)
		return 7;
	if(x >= len vt.cc[y])
		return 7;
	return vt.cc[y][x];
}

VT_SET_CURSOR(nil: ref Vt, x,y: int)
{
}

VT_BEEP(nil: ref Vt)
{
	redraw();
}

# function for simulated typing (for returning status)
VT_TYPE(vt: ref Vt, b: string)
{
	inpchan <-= b;
}


#############################################################################


vt_save_state(vt: ref Vt)
{
	vt.save_x = vt.x;
	vt.save_y = vt.y;
	vt.save_attr = vt.attr;
	vt.save_fg = vt.fg;
	vt.save_bg = vt.bg;
	vt.save_mode = vt.mode;
	vt.save_qmode = vt.qmode;
}

vt_restore_state(vt: ref Vt)
{
	vt.x = vt.save_x;
	vt.y = vt.save_y;
	vt.attr = vt.save_attr;
	vt.fg = vt.save_fg;
	vt.bg = vt.save_bg;
	vt.mode = vt.save_mode;
	vt.qmode = vt.save_qmode;
	VT_SET_COLOR(vt);
}



# expects vt.wid, vt.hgt and implementation
# variables to be initialized first: 

vt_init(vt: ref Vt)
{
	vt.fg = 7;
	vt.bg = 0;
	vt.attr = 0;
	vt.mode = 0;
	vt.qmode = (1<<7);
	vt.y1 = 0;
	vt.y2 = vt.hgt-1;
	vt.x = 0;
	vt.y = 0;
	vt.dx = 1;
	vt.dy = 1;
	vt.esc = 0;
	vt.pcount = 0;
	vt.param = array[VT_MAXPARAM] of int;
	vt_save_state(vt);
	VT_SET_COLOR(vt);
}


vt_checkscroll(vt: ref Vt, s: string)
{
	i := 0;
	n: int;
	if (vt.y == vt.y2+1 || vt.y >= vt.hgt) {
		n = 1;
		while(i < len s && n < (vt.y2-vt.y1)) {
			c := s[i++];
			if(c == 27 || c > 126 || c < 0)
				break;
			if(c == '\n')
				n++;
		}
              	vt.y = vt.y2-n+1;
		VT_SCROLL_UP(vt,0,vt.y1,vt.wid-1,vt.y2,n);
       	} else if (vt.y == vt.y1-1) {
		vt.y = vt.y1;
		VT_SCROLL_DOWN(vt,0,vt.y1,vt.wid-1,vt.y2,1);
	} else if (vt.y < 0)
		vt.y = 0;
}

vt_write(vt: ref Vt, s: string)
{
	ch: int;
	check_scroll: int;
	n: int;
	i := 0;

        while(i < len s) {
	    check_scroll = 0;
            ch = s[i++];
	    case vt.esc {
	    1 =>
		if(ch == '[') {
			vt.etype = ch;
			vt.esc++;
			vt.value = 0;
			vt.pcount = 0;
			vt.ptype = 1;
			for(n=0; n<VT_MAXPARAM; n++)
				vt.param[n] = 0;
		} else {
			check_scroll = vt_call_ncsi(vt, ch);
			vt.esc = 0;
		}	
	    2 =>
		if(ch >= '0' && ch <= '9') 
			vt.value=(vt.value)*10+(ch-'0');
		else if(ch == '?')
			vt.ptype = -1;
		else {
			vt.param[vt.pcount++] = vt.value*vt.ptype;
			if(ch == ';') {
				if(vt.pcount >= VT_MAXPARAM)
					vt.pcount = VT_MAXPARAM-1;
				vt.value = 0;
			} else {
				check_scroll = vt_call_csi(vt, ch);
				vt.esc = 0;
			}
		}
	    * =>
		case ch {
                '\n' =>
                        vt.y += vt.dy;
			check_scroll = 1;
			if(vt.nlcr)
                        	vt.x = 0;
                '\r' =>
                        vt.x = 0;
                '\b' =>
                        if (vt.x > 0)
                                vt.x -= vt.dx;
                '\t' =>
			n = (vt.x & ~7)+8;
			if(vt.mode & (1<<4))
				VT_SCROLL_RIGHT(vt, vt.x,vt.y,
				  vt.wid-1,vt.y, n - vt.x);
                        vt.x = n;
			if(vt.x > vt.wid) {
				vt.x = 0; 
				vt.y++;
				check_scroll = 1;
			}
		7 =>
			VT_BEEP(vt);
		11 =>
			vt.x = 0;
			vt.y = vt.y1;
		12 =>
			VT_CLEAR(vt,0,vt.y1,vt.wid-1,vt.y2);
		27 =>
			vt.esc++;
		133 =>
			vt.x = 0;
			vt.y++;
			check_scroll = 1;
		132 =>
			vt.y++;
			check_scroll = 1;
		136 =>	# XXX - set a tabstop 
			;
		141 =>
			vt.y--;
			check_scroll = 1;
		142 =>	# XXX -- map G2 into GL for next char only
			;
		143 =>	# XXX -- map G3 into GL for next char 
			;
		144 =>	# XXX -- device control string 
			;
		145 =>	# XXX -- start of string - ignored 
			;
		146 =>	# XXX -- device attribute request 
			;
		147 =>
			vt.esc = 2;
			vt.etype = '[';
			vt.esc++;
			vt.value = 0;
			vt.pcount = 0;
			vt.ptype = 1;
			for(n=0; n<VT_MAXPARAM; n++)
				vt.param[n] = 0;
                * =>
			if(vt.mode & (1<<4))
				VT_SCROLL_RIGHT(vt,vt.x,vt.y,
				  vt.wid-1,vt.y,1);	
			if(ch>=32 || ch <=126) {
				if(vt.qmode & (1<<15)) {
					if(vt.x >= vt.wid-1 && (vt.qmode & (1<<7))) {
						vt.x = 0;
						vt.y += vt.dy;
						vt_checkscroll(vt, s[i:]);
					}
					vt.qmode &= ~(1<<15);
				}
				VT_PUTCHAR(vt,vt.x,vt.y,ch);
                       		if((vt.x += vt.dx) >= vt.wid) {
					vt.x = vt.wid-1; 
					vt.qmode |= (1<<15);
                        	}
			}
                }
	    }
	    if(check_scroll)
		vt_checkscroll(vt, s[i:]); 
	    if(vt.x < 0)
		vt.x = 0;
	    else if(vt.x >= vt.wid)
		vt.x = vt.wid-1;
	    if(vt.y < 0)
		vt.y = 0;
	    else if(vt.y >= vt.hgt)
		vt.y = vt.hgt-1;
	}
	VT_SET_CURSOR(vt, vt.x, vt.y);
}




vt_call_csi(vt: ref Vt, ch: int): int
{
	i, n: int;
	case ch {
	'A' =>
		vt.y -= vt_param(vt, 1,1,1,vt.hgt);
	'B' =>
		vt.y += vt_param(vt, 1,1,1,vt.hgt);
	'C' =>
		vt.x += vt_param(vt, 1,1,1,vt.wid);
	'D' =>
		vt.x -= vt_param(vt, 1,1,1,vt.wid);
	'f' or 'H' =>
		vt.y = vt_param(vt, 0,1,1,vt.hgt)-1;
		vt.x = vt_param(vt, 1,1,1,vt.wid)-1;
	'J' =>
		case vt.param[0] {
		0 => VT_CLEAR(vt,vt.x,vt.y,vt.wid-1,vt.y);
			VT_CLEAR(vt,0,vt.y+1,vt.wid-1,vt.y2); 
		1 => VT_CLEAR(vt,0,0,vt.wid-1,vt.y-1); 
			VT_CLEAR(vt,0,vt.y,vt.x,vt.y); 
		2 => VT_CLEAR(vt,0,vt.y1,vt.wid-1,vt.y2);	
		}
	'K' =>
		case vt.param[0] {
		0 => VT_CLEAR(vt,vt.x,vt.y,vt.wid-1,vt.y);
		1 => VT_CLEAR(vt,0,vt.y,vt.x,vt.y);
		2 => VT_CLEAR(vt,0,vt.y,vt.wid-1,vt.y); 
		}
	'L' =>
		n = vt_param(vt, 0,1,1,vt.hgt);
		VT_SCROLL_DOWN(vt,0,vt.y,vt.wid-1,vt.y2,n);	
	'M' =>
		n = vt_param(vt,0,1,1,vt.hgt);
		VT_SCROLL_UP(vt,0,vt.y,vt.wid-1,vt.y2,n);	
	'@' =>
		n = vt_param(vt,0,1,1,vt.wid-1-vt.x);
		VT_SCROLL_RIGHT(vt,vt.x,vt.y,vt.wid-1,vt.y,n);	
	'P' =>
		n = vt_param(vt,0,1,1,vt.wid-1-vt.x);
		VT_SCROLL_LEFT(vt,vt.x,vt.y,vt.wid-1,vt.y,n);	
	'X' =>
		n = vt_param(vt,0,1,1,vt.wid-1-vt.x);
		VT_CLEAR(vt,vt.x,vt.y,vt.x+n-1,vt.y);
	'm' =>
		if(vt.pcount == 0)
			vt.pcount++;
		for(i=0; i<vt.pcount; i++) {
			n = vt.param[i];
			if(!n) {
				vt.attr = 0; 
				vt.fg = 7;
				vt.bg = 0;
			} else if (n < 16)
				vt.attr |= (1<<n);
			else if (n < 28)
				vt.attr &= ~(1<<(n-20));
			else if (n < 38)
				vt.fg = n-30;
			else if (n < 48)
				vt.bg = n-40;
			else if (n < 58)
				vt.fg = n-50+8;
			else if (n < 68)
				vt.bg = n-60+8;
		}
		VT_SET_COLOR(vt);
	'c' =>
		if(vt.wid >= 132)
			VT_TYPE(vt, "\u001b[?61;1;6c");
		else
			VT_TYPE(vt, "\u001b[?61;6c");
	'n' => 
		n = vt_param(vt, 0,0,0,9);
		if(n == 5)
			VT_TYPE(vt, "\u001b[0n");
		if(n == 5 || n == 6) 
			VT_TYPE(vt, sprint("\u001b[%d;%dR",vt.y+1,vt.x+1));
	'r' =>
		vt.y1 = vt_param(vt, 0,1,1,vt.hgt)-1;
		vt.y2 = vt_param(vt, 1,vt.hgt,1,vt.hgt)-1;
	's' =>
		vt_save_state(vt);
	'u' =>
		vt_restore_state(vt);
	'h' =>
		for(i=0; i<vt.pcount; i++) {
			n = vt.param[i];
			if(n >= 0)
				vt.mode |= (1<<n);
			else
				vt.qmode |= (1<<(-n));
		}
	'l' =>
		for(i=0; i<vt.pcount; i++) {
			n = vt.param[i];
			if(n >= 0)
				vt.mode &= ~(1<<n);
			else
				vt.qmode &= ~(1<<(-n));
		}
	}

	if(vt.y < 0)
		vt.y = 0;
	if(vt.y >= vt.hgt)
		vt.y = vt.hgt-1;
	if(vt.x < 0)
		vt.x = 0;
	if(vt.x >= vt.wid)
		vt.x = vt.wid-1;
	return 0;
}

vt_call_ncsi(vt: ref Vt, ch: int): int
{
	case ch {
	'E' =>
		vt.x = 0;
	'9' =>
		;
	'D' =>
		vt.y++;
		return 1;
	'H' =>	# XXX -- horizontal tab set
		;
	'6' =>
		;
	'M' =>
		vt.y--;
		return 1;
	'7' =>
		vt_save_state(vt);
	'8' =>
		vt_restore_state(vt);
	'=' =>
		;
	'>' =>
		;
	'#' =>
		;
	'(' =>
		;
	')' =>
		;
	}
	return 0;
}


vt_param(vt: ref Vt, n: int, def: int, min, max: int): int
{
	param := vt.param[n];
	if(param == 0)
		param = def;
	if(param < min)
		param = min;
	if(param > max)
		param = max;
	return param;
}

#############################################################################


consinp(cs: chan of string, cr: chan of (int, int, int, Sys->Rread))
{
	for(;;) {
		alt {
		sq += <- cs => ;

		(nil, nbytes, nil, rc) := <- cr =>
			p := 0;
			for(;;) {
				if(raw)
					p = len sq;
				else
					forloop:
					for(i := 0; i < len sq; i++) {
						case sq[i] {
						'\b' =>
							if(i > 0) {
								sq = sq[0:i-1] + sq[i+1:];
								--i;
							}
						'\n' =>
							p = i+1;
							break forloop;
						}
					}
				if(p > 0)
					break;
				sq += <- cs;
			}
			if(nbytes > p)
				nbytes = p;
			alt {
			rc <-= (array of byte sq[0:nbytes], "") =>
				sq = sq[nbytes:];
			* => ;
			}
		}
	}
}

newsh(ctxt: ref Draw->Context, ioc: chan of (int, ref Sys->FileIO, ref Sys->FileIO))
{
	pid := sys->pctl(sys->NEWFD, nil);

	sh := load Command "/dis/sh.dis";
	if(sh == nil) {
		ioc <-= (0, nil, nil);
		return;
	}

	tty := "cons."+string pid;

	sys->bind("#s","/chan",sys->MBEFORE);
	fio := sys->file2chan("/chan", tty);
	fioctl := sys->file2chan("/chan", tty + "ctl");
	ioc <-= (pid, fio, fioctl);
	if ((fio == nil) || (fioctl == nil))
		return;

	sys->bind("/chan/"+tty, "/dev/cons", sys->MREPL);
	sys->bind("/chan/"+tty+"ctl", "/dev/consctl", sys->MREPL);

	fd0 := sys->open("/dev/cons", sys->OREAD|sys->ORCLOSE);
	fd1 := sys->open("/dev/cons", sys->OWRITE);
	fd2 := sys->open("/dev/cons", sys->OWRITE);

	sh->init(ctxt, "sh" :: "-n" :: nil);
}

kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
}

tkcmds(t: ref Tk->Toplevel, cfg: array of string)
{
	for(i := 0; i < len cfg; i++)
		tk->cmd(t, cfg[i]);
}
