implement Menuhit;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Image, Font, Rect, Point, Display, Screen, Pointer: import draw;
include "wmclient.m";
include "menuhit.m";


Margin : con 4;
Border : con 2;
Blackborder : con 2;
Vspacing : con 2;
Maxunscroll : con 25;
Nscroll : con 20;
Scrollwid : con 14;
Gap : con 4;

font: ref Font;
display: ref Display;
ptr: chan of ref Pointer;

menutxt, back, high, bord, text, htext : ref Image;


window: ref Wmclient->Window;

init(w: ref Wmclient->Window)
{
	window = w;
	display = w.display;
	draw = load Draw Draw->PATH;
	sys = load Sys Sys->PATH;
	font = draw->Font.open(display, "/fonts/combined/unicode.sans.14.font");
	if(font == nil)
		font = draw->Font.open(display, "*default*");
}


menucolors()
{
	back = display.colormix(Draw->Palegreen, Draw->White);
	high = display.color(Draw->Darkgreen);
	bord = display.color(Draw->Medgreen);
	text = display.color(Draw->Black);
	htext = display.color(Draw->White);
	return;
}

menurect(r: Rect, i: int): Rect
{
	if(i < 0)
		return ((0,0), (0,0));
	r.min.y += (font.height + Vspacing)*i;
	r.max.y = r.min.y + font.height + Vspacing;
	return r.inset(Border-Margin);
}

menusel(r: Rect, p: Point): int
{
	r = r.inset(Margin);
	if(!p.in(r))
		return -1;
	return (p.y-r.min.y)/(font.height+Vspacing);
}

paintitem(m: ref Image, menu: ref Menu, textr: Rect, off, i, highlight: int, save, restore: ref Image)
{
	item : string;
	r: Rect;
	pt: Point;
	
	if(i < 0 || i >= len menu.item)
		return;
	r = menurect(textr, i);
	if(restore != nil){
		m.draw(r, restore, nil, restore.r.min);
		return;
	}
	if(save != nil)
		save.draw(save.r, m, nil, r.min);
	if(menu.item != nil && (i+off) < len menu.item)
		item = menu.item[i+off];
	else if(menu.gen != nil)
		item = menu.gen(i+off);
	pt.x = (textr.min.x+textr.max.x-font.width(item))/2;
	pt.y = textr.min.y+i*(font.height+Vspacing);
	if(highlight){
		m.draw(r, high, nil, pt);
		m.text(pt, htext, pt, font, item);
	}else{
		m.draw(r, back, nil, pt);
		m.text(pt, text, pt, font, item);
	}
}

menuscan(m: ref Image, menu: ref Menu, but: int, mc: ref Mousectl, 
	textr: Rect, off, lasti: int, save: ref Image): int
{
	paintitem(m, menu, textr, off, lasti, 1, save, nil);
	for(readmouse(mc); mc.buttons & (1 <<(but-1)); readmouse(mc)){
		i := menusel(textr, mc.xy);
		if(i !=-1 && i == lasti)
			continue;
		paintitem(m, menu, textr, off, lasti, 0, nil, save);
		if(i == -1)
			return i;
		lasti = i;
		paintitem(m, menu, textr, off, lasti, 1, save, nil);
	}
	return lasti;
}


menupaint(m: ref Image, menu: ref Menu, textr: Rect, off, nitemdrawn: int)
{
	m.draw(textr.inset(Border-Margin), back, nil, (0,0));
	for(i := 0; i < nitemdrawn; i++)
		paintitem(m, menu, textr, off, i, 0, nil, nil);
}

menuscrollpaint(m: ref Image, scrollr: Rect, off, nitem, nitemdrawn: int)
{
	r : Rect;
	
	m.draw(scrollr, back, nil, (0,0));
	r.min.x = scrollr.min.x;
	r.max.x = scrollr.max.x;
	r.min.y = scrollr.min.y + (scrollr.dy()*off)/nitem;
	r.max.y = scrollr.min.y + (scrollr.dy()*(off+nitemdrawn))/nitem;
	if(r.max.y < r.min.y+2)
		r.max.y = r.min.y+2;
	m.border(r, 1, bord, (0,0));
	if(menutxt == nil)
		menutxt = display.newimage(Rect((0, 0), (1, 1)), display.image.chans, 1, Draw->Darkgreen);	
	if(menutxt != nil)
		m.draw(r.inset(1), menutxt, nil, (0,0));

}

menuhit(but: int, mc: ref Mousectl, menu: ref Menu, scr: ref Screen):int
{
	i, nitem, nitemdrawn, maxwid, lasti, off, noff, wid, screenitem: int;
	scrolling: int;
	r, menur, sc, textr, scrollr: Rect;
	b, save, backup: ref Image;
	pt: Point;
	item: string;
	
	if(back == nil)
		menucolors();
	screen := window.screen.image;
	sc = screen.clipr;
#	replclipr(screen, 0, screen.r);
	screen.repl = 0;
	screen.clipr = screen.r;
	maxwid = 0;
	nitem = 0;
	for(;;){
		if(menu.item != nil && nitem < len menu.item)
			item = menu.item[nitem];
		else if(menu.gen != nil)
			item = menu.gen(nitem);
		if(item == nil)
			break;
		i = font.width(item);
		if(i > maxwid)
			maxwid = i;
		nitem++;
		if(menu.item != nil && len menu.item <= nitem)
			break;
	}
	if(menu.lasthit<0 || menu.lasthit>=nitem)
		menu.lasthit = 0;
	screenitem = screen.r.dy()-10/(font.height+Vspacing);
	if(nitem>Maxunscroll || nitem>screenitem){
		scrolling = 1;
		nitemdrawn = Nscroll;
		if(nitemdrawn > screenitem)
			nitemdrawn = screenitem;
		wid = maxwid + Gap + Scrollwid;
		off = menu.lasthit - nitemdrawn/2;
		if(off < 0)
			off = 0;
		if(off > nitem-nitemdrawn)
			off = nitem-nitemdrawn;
		lasti = menu.lasthit-off;
	}else{
		scrolling = 0;
		nitemdrawn = nitem;
		wid = maxwid;
		off = 0;
		lasti = menu.lasthit;
	}
	r = Rect((0, 0), (wid, nitemdrawn*(font.height+Vspacing))).inset(-Margin);
	r = r.subpt(Point(wid/2, lasti*(font.height+Vspacing)+font.height/2));
	r = r.addpt(mc.xy);
	pt = (0,0);
	if(r.max.x>screen.r.max.x)
		pt.x = screen.r.max.x-r.max.x;
	if(r.max.y>screen.r.max.y)
		pt.y = screen.r.max.y-r.max.y;
	if(r.min.x<screen.r.min.x)
		pt.x = screen.r.min.x-r.min.x;
	if(r.min.y<screen.r.min.y)
		pt.y = screen.r.min.y-r.min.y;
	menur = r.addpt(pt);
	textr.max.x = menur.max.x-Margin;
	textr.min.x = textr.max.x-maxwid;
	textr.min.y = menur.min.y+Margin;
	textr.max.y = textr.min.y + nitemdrawn*(font.height+Vspacing);
	if(scrolling){
		scrollr = menur.inset(Border);
		scrollr.max.x = scrollr.min.x+Scrollwid;
	}else
		scrollr = Rect((0, 0), (0, 0));

	if(scr!=nil){
		b = scr.newwindow(menur, Draw->Refbackup, Draw->White);
		if(b == nil)
			b = screen;
		backup = nil;
	}else{
		b = screen;
		backup = display.newimage(menur, display.image.chans, 0, -1);
		if(backup!=nil)
			backup.draw(menur, screen, nil, menur.min);
	}
	b.draw(menur, back, nil, (0,0));
	b.border(menur, Blackborder, bord, (0,0));
	save = display.newimage(menurect(textr, 0), display.image.chans, 0, -1);
	r = menurect(textr, lasti);
#	moveto(mc, r.min.add(r.max).div(2));
	menupaint(b, menu, textr, off, nitemdrawn);
	if(scrolling)
		menuscrollpaint(b, scrollr, off, nitem, nitemdrawn);
	while(mc.buttons & (1<<(but-1))){
		lasti = menuscan(b, menu, but, mc, textr, off, lasti, save);
		if(lasti >= 0)
			break;
		while(!mc.xy.in(textr) && (mc.buttons & (1<<(but-1)))){
			if(scrolling && mc.xy.in(scrollr)){
				noff = ((mc.xy.y-scrollr.min.y)*nitem)/scrollr.dy();
				noff -= nitemdrawn/2;
				if(noff < 0)
					noff = 0;
				if(noff > nitem-nitemdrawn)
					noff = nitem-nitemdrawn;
				if(noff != off){
					off = noff;
					menupaint(b, menu, textr, off, nitemdrawn);
					menuscrollpaint(b, scrollr, off, nitem, nitemdrawn);
				}
			}
			readmouse(mc);
		}
	}
	if(backup!=nil){
		screen.draw(menur, backup, nil, menur.min);
	}
#	replclipr(screen, 0, sc);
	screen.repl = 0;
	screen.clipr = sc;
	display.image.flush(1);
	if(lasti >= 0){
		menu.lasthit = lasti+off;
		return menu.lasthit;
	}
	return -1;
}

readmouse(mc: ref Mousectl)
{
	p := <- mc.ptr;
	mc.buttons = p.buttons;
	mc.xy = p.xy;
	mc.msec = p.msec;
}
