implement Smenu;

include "sys.m";
	sys: Sys;
include "draw.m";
include "tk.m";
	tk: Tk;
include "smenu.m";

Scrollmenu.new(t: ref Tk->Toplevel, name: string, labs: array of string, e: int, o: int): ref Scrollmenu
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(tk == nil)
		tk = load Tk Tk->PATH;
	m := ref Scrollmenu;
	n := len labs;
	if(n < e)
		e = n;
	if(o > n-e)
		o = n-e;
	l := 0;
	for(i := 0; i < n; i++){
		if(len labs[i] > l)
			l = len labs[i];
		i++;
	}
	nlabs := array[n] of string;
	sp := string array[l] of { * => byte ' ' };
	for(i = 0; i < n; i++)
		nlabs[i] = labs[i] + sp[0: l - len labs[i]];
	sch := cname(name);
	cmd(t, "menu " + name);
	for(i = 0; i < e; i++){
		cmd(t, name + " add command -label {" + nlabs[o+i] + "} -command {send " + sch + " " + string i + "}");
	}
	# cmd(t, "bind " + name + " <ButtonPress-1> +{send " + sch + " b}");
	# cmd(t, "bind " + name + " <ButtonRelease-1> +{send " + sch + " b}");
	cmd(t, "bind " + name + " <Motion> +{send " + sch + " M %x %y}");
	cmd(t, "bind " + name + " <Map> +{send " + sch + " m}");
	cmd(t, "bind " + name + " <Unmap> +{send " + sch + " u}");
	cmd(t, "update");
	m.name = name;
	m.labs = nlabs;
	m.c = nil;
	m.t = t;
	m.m = e;
	m.n = n;
	m.o = o;
	m.timer = 1;
	return m;
}

Scrollmenu.post(m: self ref Scrollmenu, x: int, y: int, resc: chan of string, prefix: string)
{
	sync := chan of int;
	spawn listen(m, sync, resc, prefix);
	<- sync;
	cmd(m.t, m.name + " post " + string x + " " + string y);
	cmd(m.t, "update");
}

Scrollmenu.destroy(m: self ref Scrollmenu)
{
	if(m.c != nil){
		m.c <-= "u";	# fake unmap message
		m.c = nil;
	}
	m.name = nil;
	m.labs = nil;
	m.t = nil;
}

timer(t: int, sync: chan of int, c: chan of int)
{
	sync <-= 0;
	for(;;){
		alt{
			c <-= 0 =>
				sys->sleep(t);
			<- sync =>
				exit;
		}
	}
}

TINT: con 100;
SEC: con 1000/TINT;
		
listen(m: ref Scrollmenu, sync: chan of int, resc: chan of string, prefix: string)
{
	timerc := chan of int;
	cmdc := chan of string;
	m.c = cmdc;
	tk->namechan(m.t, cmdc, cname(m.name));
	sync <-= 0;
	x := y := ly := w := h := -1;
	for(;;){
		alt{
			<- timerc =>
				if(x > 0 && x < w){
					if(y < 0 && y > -h/m.m)
						menudir(m, -1);
					else if(y > 0+h && y < h+h/m.m)
						menudir(m, 1);
				}
			s := <- cmdc =>
				(nil, toks) := sys->tokenize(s, " ");
				case hd toks{
					"M" =>
						x = int hd tl toks;
						y = int hd tl tl toks;
						if(!m.timer && x > 0 && x < w){
							mv := 0;
							if(y < ly && y < 0)
								mv = y/(h/m.m)-1;
							else if(y > ly && y > h)
								mv = (y-h)/(h/m.m)+1;
							if(mv != 0)
								menudirs(m, mv);
							ly = y;
						}
					"m" =>
						w = int cmd(m.t, m.name + " cget -actwidth");
						h = int cmd(m.t, m.name + " cget -actheight");
						ly = -1;
						if(m.timer){
							spawn timer(TINT, sync, timerc);
							<- sync;
						}
					"u" =>
						if(m.timer)
							sync <-= 0;
						m.c = nil;
						exit;
					* =>
						# do not block
						res := prefix + string (int hd toks + m.o);
						for(t := 0; t < SEC; ){
							if(m.timer)
								alt{
									resc <-=  res =>
										t = SEC;
									<- timerc =>
										t++;
								}
							else
								alt{
									resc <-= res =>
										t = SEC;
									* =>
										sys->sleep(TINT);
										t++;
								}
						}
				}
		}
	}
}

menudirs(sm: ref Scrollmenu, n: int)
{
	if(n < 0)
		(a, d) := (-n, -1);
	else
		(a, d) = (n, 1);
	for(i := 0; i < a; i++)
		menudir(sm, d);
}

menudir(sm: ref Scrollmenu, d: int)
{
	o := sm.o;
	n := sm.n;
	m := sm.m;
	if(d == -1){
		if(o == 0)
			return;
		for(i := 0; i < m; i++)
			cmd(sm.t, sm.name + " entryconfigure " + string i + " -label {" + sm.labs[o-1+i] + "}");
		sm.o = o-1;
	}
	else{
		if(o+m == n)
			return;
		for(i := 0; i < m; i++)
			cmd(sm.t, sm.name + " entryconfigure " + string i + " -label {" + sm.labs[o+1+i] + "}");
		sm.o = o+1;
	}
	cmd(sm.t, "update");	
}

cname(s: string): string
{
	return "sm_" + s + "_sm";
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "Smenu: tk error on '%s': %s\n", s, e);
	return e;
}
