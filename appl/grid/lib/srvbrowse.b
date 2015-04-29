implement Srvbrowse;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#


include "sys.m";
	sys : Sys;
include "draw.m";
	draw: Draw;
	Rect: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "grid/srvbrowse.m";
include "registries.m";
	registries: Registries;
	Registry, Attributes, Service: import registries;

init()
{
	sys = load Sys Sys->PATH;
	if (sys == nil)
		badmod(Sys->PATH);
	draw = load Draw Draw->PATH;
	if (draw == nil)
		badmod(Draw->PATH);
	tk = load Tk Tk->PATH;
	if (tk == nil)
		badmod(Tk->PATH);
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmod(Tkclient->PATH);
	tkclient->init();
	registries = load Registries Registries->PATH;
	if (registries == nil)
		badmod(Registries->PATH);
	registries->init();
	reg = Registry.new("/mnt/registry");
	if (reg == nil) {
		reg = Registry.connect(nil, nil, nil);
		if (reg == nil)
			error("Could not find registry");
	}
	qids = array[511] of { * => "" };
}

reg : ref Registry;
qids : array of string;

# Qid stuff is a bit rubbish at the mo but waiting for registries to change: 
#	currently address is unique but will not be in the future so waiting
#	for another id to uniquely identify a resource

addqid(srvc: ref Service): int
{
	addr := srvc.addr;
	qid := addr2qid(addr);
	for (;;) {
		if (qids[qid] == nil)
			break;
		else if (qids[qid] == addr)
			return qid;
		qid++;
		if (qid >= len qids)
			qid = 0;				
	}
	qids[qid] = addr;
#	sys->print("adding %s (%s) to %d\n",srvc.attrs.get("resource"), addr, qid);
	return qid;
}

getqid(srvc: ref Service): string
{
	addr := srvc.addr;
	qid := addr2qid(addr);
	startqid := qid;
	for (;;) {
		if (qids[qid] == addr)
			return string qid;
		qid++;
		if (qid == startqid)
			break;
		if (qid >= len qids)
			qid = 0;				
	}
	return nil;
}

addr2qid(addr: string): int
{
	qid := 0;
	# assume addr starts 'tcp!...'
	for (i := 4; i < len addr; i++) {
		qid += addr[i] * 2**(i%10);
		qid = qid % len qids;
	}
	return qid;
}

addservice(srvc: ref Service)
{
	services = srvc :: services;
	addqid(srvc);
}

find(filter: list of list of (string, string)): list of ref Service
{
	lsrv : list of ref Service = nil;
	if (filter == nil)
		(lsrv, nil) = reg.services();
	else {
		for (; filter != nil; filter = tl filter) {
			attr := hd filter;
			(s, nil) := reg.find(attr);		
			for (; s != nil; s = tl s)
				lsrv = hd s :: lsrv;
		}
	}
	return sortservices(lsrv);
}

refreshservices(filter: list of list of (string, string))
{
	services = find(filter);
}

servicepath2Service(path, qid: string): list of ref Service
{
	srvl : list of ref Service = nil;
	(nil, lst) := sys->tokenize(path, "/");
	pname: string;
	l := len lst;
	if (l < 2 || l > 3)
		return nil;
	presource := hd tl lst;
	if (l == 3)
		pname = hd tl tl lst;
	
	for (tmpl := services; tmpl != nil; tmpl = tl tmpl) {
		srvc := hd tmpl;
		(resource, name) := getresname(srvc);
		if (l == 2) {
			if (resource == presource)
				srvl = srvc :: srvl;
		}
		else if (l == 3) {
			if (resource == presource) {
				if (name == pname && qid == getqid(srvc)) {
					srvl = srvc :: srvl;
					break;
				}
			}
		}
	}
	return srvl;
}

servicepath2Dir(path: string, qid: int): (array of ref sys->Dir, int)
{
	# sys->print("srvcPath2Dir: '%s' %d\n",path, qid);
	res : list of (string, string) = nil;
	(nil, lst) := sys->tokenize(path, "/");
	presource, pname: string;
	pattrib := 0;
	l := len lst;
	if (l > 1)
		presource = hd tl lst;
	if (l > 2)
		pname = hd tl tl lst;
	if (l == 4 && hd tl tl tl lst == "attributes")
			pattrib = 1;	
	for (tmpl := services; tmpl != nil; tmpl = tl tmpl) {
		srvc := hd tmpl;
		(resource, name) := getresname(srvc);
		if (l == 1) {
			if (!isin(res, resource))
				res = (resource, nil) :: res;
		}
		else if (l == 2) {
			if (resource == presource)
				res = (name, string getqid(srvc)) :: res;
		}
		else if (l == 3) {
			if (resource == presource && name == pname) {
				if (qid == int getqid(srvc)) {
					if (srvc.addr[0] == '@')
						res = (srvc.addr[1:], string getqid(srvc)) :: res;
					else {
						if (srvc.attrs != nil)
							res = ("attributes", string getqid(srvc)) :: res;
						res = ("address:\0"+srvc.addr+"}", string getqid(srvc)) :: res;
					}
					break;
				}
			}
		}
		else if (l == 4) {
			if (resource == presource && name == pname && pattrib) {
				if (qid == int getqid(srvc)) {
					for (tmpl2 := srvc.attrs.attrs; tmpl2 != nil; tmpl2 = tl tmpl2) {
						(attrib, val) := hd tmpl2;
						if (attrib != "name" && attrib != "resource")
							res = (attrib+":\0"+val, string getqid(srvc)) :: res;
					}
					break;
				}
			}
		}
	}
	resa := array [len res] of ref sys->Dir;
	i := len resa - 1;
	for (; res != nil; res = tl res) {
		dir : sys->Dir;
		qid: string;
		(dir.name, qid) = hd res;
		if (l < 3 || dir.name == "attributes")
			dir.mode = 8r777 | sys->DMDIR;
		else
			dir.mode = 8r777;
		if (qid != nil)
			dir.qid.path = big qid;
		resa[i--] = ref dir;
	}
	dups := 0;
	if (l >= 2)
		dups = 1;
	return (resa, dups);
}

isin(l: list of (string, string), s: string): int
{
	for (; l != nil; l = tl l)
		if ((hd l).t0 == s)
			return 1;
	return 0;
}

getresname(srvc: ref Service): (string, string)
{
	resource := srvc.attrs.get("resource");
	if (resource == nil)
		resource = "Other";
	name := srvc.attrs.get("name");
	if (name == nil)
		name = "?????";
	return (resource,name);
}

badmod(path: string)
{
	sys->print("Srvbrowse: failed to load: %s\n",path);
	exit;
}

sortservices(lsrv: list of ref Service): list of ref Service
{
	a := array[len lsrv] of ref Service;
	i := 0;
	for (; lsrv != nil; lsrv = tl lsrv) {
		addqid(hd lsrv);
		a[i++] = hd lsrv;
	}
	heapsort(a);
	lsrvsorted: list of ref Service = nil;
	for (i = len a - 1; i >= 0; i--)
		lsrvsorted = a[i] :: lsrvsorted;
	return lsrvsorted;
}


heapsort(a: array of ref Service)
{
	for (i := (len a / 2) - 1; i >= 0; i--)
		movedownheap(a, i, len a - 1);

	for (i = len a - 1; i > 0; i--) {
		tmp := a[0];
		a[0] = a[i];
		a[i] = tmp;
		movedownheap(a, 0, i - 1);
	}
}

movedownheap(a: array of ref Service, root, end: int)
{
	max: int;
	while (2*root <= end) {
		r2 := root * 2;
		if (2*root == end || comp(a[r2], a[r2+1]) == GT)
			max = r2;
		else
			max = r2 + 1;

		if (comp(a[root], a[max]) == LT) {
			tmp := a[root];
			a[root] = a[max];
			a[max] = tmp;
			root = max;
		}
		else
			break;
	}	
}

LT: con -1;
EQ: con 0;
GT: con 1;

comp(a1, a2: ref Service): int
{
	(resource1, name1) := getresname(a1);
	(resource2, name2) := getresname(a2);
	if (resource1 < resource2)
		return LT;
	if (resource1 > resource2)
		return GT;
	if (name1 < name2)
		return LT;
	if (name1 > name2)
		return GT;
	return EQ;
}

error(e: string)
{
	sys->fprint(sys->fildes(2), "Srvbrowse: %s\n", e);
	raise "fail:error";
}

searchscr := array[] of {
	"frame .f",
	"scrollbar .f.sy -command {.f.c yview}",
	"scrollbar .f.sx -command {.f.c xview} -orient horizontal",
	"canvas .f.c -yscrollcommand {.f.sy set} -xscrollcommand {.f.sx set} -bg white -width 414 -borderwidth 2 -relief sunken -height 180 -xscrollincrement 10 -yscrollincrement 19",
	"grid .f.sy -row 0 -column 0 -sticky ns -rowspan 2",
	"grid .f.sx -row 1 -column 1 -sticky ew",
	"grid .f.c -row 0 -column 1",
	"pack .f -fill both -expand 1 ; pack propagate . 0; update",
};

SEARCH, RESULTS: con iota;

searchwin(ctxt: ref Draw->Context, chanout: chan of string, filter: list of list of (string, string))
{
	(top, titlebar) := tkclient->toplevel(ctxt,"","Search", tkclient->Appl);
	butchan := chan of string;
	tk->namechan(top, butchan, "butchan");
	tkcmds(top, searchscr);
	makesearchframe(top);
	flid := setframe(top, ".fsearch", nil);
	selected := "";
	lresults : list of ref Service = nil;
	resultstart := 0;
	resize(top, 368,220);
	maxresults := getmaxresults(top);
	currmode := SEARCH;
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);

	main: for (;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		inp := <-butchan =>
			(nil, lst) := sys->tokenize(inp, " ");
			case hd lst {
				"key" =>
					s := " ";
					id := hd tl lst;
					nv := hd tl tl lst;
					tkp : string;
					if (id != "-1")
						tkp = ".fsearch.ea"+nv+id;
					else
						tkp = ".fsearch.e"+nv;
					char := int hd tl tl tl lst;
					s[0] = char;
					if (char == '\n' || char == '\t') {
						newtkp := ".fsearch";
						if (nv == "n")
							newtkp += ".eav"+id;
						else if (nv == "v") {
							newid := string ((int id)+1);
							e := tk->cmd(top, ".fsearch.ean"+newid+" cget -width");
							if (e == "" || e[0] == '!') {
								insertattribrow(top);
								newtkp += ".ean"+newid;
							}
							else
								newtkp += ".ean"+newid;
						}
						focus(top, newtkp);
					}
					else {
						tkcmd(top, tkp+" insert insert {"+s+"}");
						tkcmd(top, tkp+" see "+tkcmd(top, tkp+" index insert"));
					}
				"go" =>
					lresults = search(top, filter);
					resultstart = 0;
					makeresultsframe(top, lresults, 0, maxresults);
					selected = nil;
					flid = setframe(top, ".fresults", flid);
					currmode = RESULTS;
					if (chanout != nil)
						chanout <-= "search search";
				"prev" =>
					selected = nil;
					resultstart -= maxresults;
					if (resultstart < 0)
						resultstart = 0;
					makeresultsframe(top, lresults, resultstart, maxresults);
					flid = setframe(top, ".fresults", flid);
				"next" =>
					selected = nil;
					if (resultstart < 0)
						resultstart = 0;
					resultstart += maxresults;
					if (resultstart >= len lresults)
						resultstart -= maxresults;
					makeresultsframe(top, lresults, resultstart, maxresults);
					flid = setframe(top, ".fresults", flid);
				"backto" =>
					flid = setframe(top, ".fsearch", flid);
					tkcmd(top, ".f.c see 0 "+tkcmd(top, ".fsearch cget -height"));
					currmode = SEARCH;
				"new" =>
					resetsearchscr(top);
					tkcmd(top, ".f.c see 0 0");
					setscrollr(top, ".fsearch");
				"select" =>
					if (selected != nil)
						tkcmd(top, selected+" configure -bg white");
					if (selected == hd tl lst)
						selected = nil;
					else {
						selected = hd tl lst;
						tkcmd(top, hd tl lst+" configure -bg #5555FF");
						if (chanout != nil)
							chanout <-= "search select " +
										tkcmd(top, selected+" cget -text") +													" " + hd tl tl lst;
					}
			}
			tkcmd(top, "update");
		title := <-top.ctxt.ctl or
		title = <-top.wreq or
		title = <-titlebar =>
			if (title == "exit" || title == "ok")
				break main;
			e := tkclient->wmctl(top, title);
			if (e == nil && title[0] == '!') {
				(nil, lst) := sys->tokenize(title, " \t\n");
				if (len lst >= 2 && hd lst == "!size" && hd tl lst == ".") {
					resize(top, -1,-1);
					maxresults = getmaxresults(top);
					if (currmode == RESULTS) {
						makeresultsframe(top, lresults, resultstart, maxresults);
						flid = setframe(top, ".fresults", flid);
						tkcmd(top, "update");
					}
				}
			}
		}
	}

}

getmaxresults(top: ref Tk->Toplevel): int
{
	val := ((int tkcmd(top, ".f.c cget -height")) - 65)/17;
	if (val < 1)
		return 1;
	return val;
}

setframe(top: ref Tk->Toplevel, f, oldflid: string): string
{
	if (oldflid != nil)
		tkcmd(top, ".f.c delete " + oldflid);
	newflid := tkcmd(top, ".f.c create window 0 0 -window "+f+" -anchor nw");
	setscrollr(top, f);
	return newflid;
}

setscrollr(top: ref Tk->Toplevel, f: string)
{
	h := tkcmd(top, f+" cget -height");
	w := tkcmd(top, f+" cget -width");
	tkcmd(top, ".f.c configure -scrollregion {0 0 "+w+" "+h+"}");
}

resize(top: ref Tk->Toplevel, width, height: int)
{
	if (width == -1) {
		width = int tkcmd(top, ". cget -width");
		height = int tkcmd(top, ". cget -height");
	}
	else
		tkcmd(top, sys->sprint(". configure -width %d -height %d", width, height));
	htitle := int tkcmd(top, ".f cget -acty") - int tkcmd(top, ". cget -acty");
	height -= htitle;
	ws := int tkcmd(top, ".f.sy cget -width");
	hs := int tkcmd(top, ".f.sx cget -height");

	tkcmd(top, ".f.c configure -width "+string (width - ws - 8)+
			" -height "+string (height - hs - 8));

	tkcmd(top, "update");
}

makesearchframe(top: ref Tk->Toplevel)
{
	font := " -font /fonts/charon/plain.normal.font";
	fontb := " -font /fonts/charon/bold.normal.font";
	f := ".fsearch";

	tkcmd(top, "frame "+f+" -bg white");
	tkcmd(top, "label "+f+".l -text {Search for Resource Attributes} -bg white" + fontb);
	tkcmd(top, "grid "+f+".l -row 0 -column 0 -columnspan 3 -sticky nw");

	tkcmd(top, "grid rowconfigure "+f+" 0 -minsize 30");
	tkcmd(top, "frame "+f+".fgo -bg white");
	tkcmd(top, "button "+f+".bs -text {Search} -command {send butchan go} "+font);
	tkcmd(top, "button "+f+".bc -text {Clear} -command {send butchan new} "+font);
	tkcmd(top, "grid "+f+".bs -row 3 -column 0 -sticky e -padx 2 -pady 5");
	tkcmd(top, "grid "+f+".bc -row 3 -column 1 -sticky w -pady 5");
	
	tkcmd(top, "label "+f+".la1 -text {name} -bg white "+fontb);
	tkcmd(top, "label "+f+".la2 -text {value} -bg white "+fontb);

	tkcmd(top, "grid "+f+".la1 "+f+".la2 -row 1");

	insertattribrow(top);
}

insertattribrow(top: ref Tk->Toplevel)
{
	(n, nil) := sys->tokenize(tkcmd(top, "grid slaves .fsearch -column 1"), " \t\n");
	row := string (n);
	sn := string (n - 2);
	fsn := ".fsearch.ean"+sn;
	fsv := ".fsearch.eav"+sn;
	font := " -font /fonts/charon/plain.normal.font";
	tkcmd(top, "entry "+fsn+" -width 170 -borderwidth 0 "+font);
	tkcmd(top, "bind "+fsn+" <Key> {send butchan key "+sn+" n %s}");
	tkcmd(top, "entry "+fsv+" -width 170 -borderwidth 0 "+font);
	tkcmd(top, "bind "+fsv+" <Key> {send butchan key "+sn+" v %s}");
	tkcmd(top, "grid rowinsert .fsearch "+row);
	tkcmd(top, "grid "+fsn+" -column 0 -row "+row+" -sticky w -pady 1 -padx 2");
	tkcmd(top, "grid "+fsv+" -column 1 -row "+row+" -sticky w -pady 1");
	setscrollr(top, ".fsearch");
}

min(a,b: int): int
{
	if (a < b)
		return a;
	return b;
}

max(a,b: int): int
{
	if (a > b)
		return a;
	return b;
}

makeresultsframe(top: ref Tk->Toplevel, lsrv: list of ref Service, resultstart, maxresults: int)
{
	font := " -font /fonts/charon/plain.normal.font";
	fontb := " -font /fonts/charon/bold.normal.font";
	f := ".fresults";
	nresults := len lsrv;
	row := 0;
	n := 0;
	tk->cmd(top, "destroy "+f);
	tkcmd(top, "frame "+f+" -bg white");
	title := "Search Results";
	if (nresults > 0) {
		from := resultstart+1;
		too := min(resultstart+maxresults, nresults);
		if (from == too)
			title += sys->sprint(" (displaying match %d of %d)", from, nresults);
		else
			title += sys->sprint(" (displaying matches %d - %d of %d)", from, too, nresults);
	}
	tkcmd(top, "label "+f+".l -text {"+title+"} -bg white -anchor w" + fontb);
	w1 := int tkcmd(top, f+".l cget -width");
	w2 := int tkcmd(top, ".f.c cget -width");
	tkcmd(top, f+".l configure -width "+string max(w1,w2));
	tkcmd(top, "grid "+f+".l -row 0 -column 0 -columnspan 3 -sticky nw");

	tkcmd(top, "grid rowconfigure "+f+" 0 -minsize 30");
	tkcmd(top, "frame "+f+".f -bg white");
	for (; lsrv != nil; lsrv = tl lsrv) {
		if (n >= resultstart && n < resultstart + maxresults) {
			srvc := hd lsrv;
			(resource, name) := getresname(srvc);
			qid := getqid(srvc);
			if (qid == nil)
				qid = string addqid(srvc);
			label := f+".f.lQ"+qid;
			tkcmd(top, "label "+label+" -bg white -text {services/"+
				resource+"/"+name+"/}"+font);
			tkcmd(top, "grid "+label+" -row "+string row+" -column 0 -sticky w");
			tkcmd(top, "bind "+label+" <Button-1> {send butchan select "+label+" "+qid+"}");
			row++;
		}
		n++;
	}
	if (nresults == 0) {
		tkcmd(top, "label "+f+".f.l0 -bg white -text {No matches found}"+font);
		tkcmd(top, "grid "+f+".f.l0 -row 0 -column 0 -columnspan 3 -sticky w");
	}
	else {
		tkcmd(top, "button "+f+".bprev -text {<<} "+
				"-command {send butchan prev}"+font);
		if (resultstart == 0)
			tkcmd(top, f+".bprev configure -state disabled");
		tkcmd(top, "button "+f+".bnext -text {>>} "+
				"-command {send butchan next}"+font);
		if (resultstart + maxresults >= nresults)
			tkcmd(top, f+".bnext configure -state disabled");
		tkcmd(top, "grid "+f+".bprev -column 0 -row 2 -padx 5 -pady 5");
		tkcmd(top, "grid "+f+".bnext -column 2 -row 2 -padx 5 -pady 5");
	}
	tkcmd(top, "grid "+f+".f -row 1 -column 0 -columnspan 3 -sticky nw");
	tkcmd(top, "grid rowconfigure "+f+" 1 -minsize "+string (maxresults*17));
	tkcmd(top, "button "+f+".bsearch -text {Back to Search} "+
			"-command {send butchan backto}"+font);
	tkcmd(top, "grid "+f+".bsearch -column 1 -row 2 -padx 5 -pady 5");
}

focus(top: ref Tk->Toplevel, newtkp: string)
{
	tkcmd(top, "focus "+newtkp);
	x1 := int tkcmd(top, newtkp + " cget -actx")
			- int tkcmd(top, ".fsearch cget -actx");
	y1 := int tkcmd(top, newtkp + " cget -acty")
			- int tkcmd(top, ".fsearch cget -acty");
	x2 := x1 + int tkcmd(top, newtkp + " cget -width");
	y2 := y1 + int tkcmd(top, newtkp + " cget -height") + 45;
	tkcmd(top, sys->sprint(".f.c see %d %d %d %d", x1,y1-30,x2,y2));
}

search(top: ref Tk->Toplevel, filter: list of list of (string, string)): list of ref Service
{	
	searchattrib: list of (string, string) = nil;
	(n, nil) := sys->tokenize(tkcmd(top, "grid slaves .fsearch -column 0"), " \t\n");
	for (i := 0; i < n - 3; i++) {
		attrib := tkcmd(top, ".fsearch.ean"+string i+" get");
		val := tkcmd(top, ".fsearch.eav"+string i+" get");
		if (val == nil)
			val = "*";
		if (attrib != nil)
			searchattrib = (attrib, val) :: searchattrib;
	}
	tmp : list of list of (string, string) = nil;
	for (; filter != nil; filter = tl filter) {
		l := hd filter;
		for (tmp2 := searchattrib; tmp2 != nil; tmp2 = tl tmp2)
			l = hd tmp2 :: l;
		tmp = l :: tmp;
	}
	filter = tmp;
	if (filter == nil)
		filter = searchattrib :: nil;
	return find(filter);
}

getitem(l : list of (string, ref Service), testid: string): ref Service
{
	for (; l != nil; l = tl l) {
		(id, srvc) := hd l;
		if (testid == id)
			return srvc;
	}
	return nil;
}

delitem(l : list of (string, ref Service), testid: string): list of (string, ref Service)
{
	l2 : list of (string, ref Service) = nil;
	for (; l != nil; l = tl l) {
		(id, srvc) := hd l;
		if (testid != id)
			l2 = (id, srvc) :: l2;
	}
	return l2;
}

resetsearchscr(top: ref Tk->Toplevel)
{
	(n, nil) := sys->tokenize(tkcmd(top, "grid slaves .fsearch -column 1"), " \t\n");
	for (i := 1; i < n - 2; i++)
		tkcmd(top, "destroy .fsearch.ean"+string i+" .fsearch.eav"+string i);
	s := " delete 0 end";
	tkcmd(top, ".fsearch.ean0"+s);
	tkcmd(top, ".fsearch.eav0"+s);
}

tkcmd(top: ref Tk->Toplevel, cmd: string): string
{
	e := tk->cmd(top, cmd);
	if (e != "" && e[0] == '!')
		sys->print("Tk error: '%s': %s\n",cmd,e);
	return e;
}

tkcmds(top: ref Tk->Toplevel, a: array of string)
{
	for (j := 0; j < len a; j++)
		tkcmd(top, a[j]);
}
