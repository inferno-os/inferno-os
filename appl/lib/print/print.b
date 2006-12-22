implement Print;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Font, Rect, Point, Image, Screen: import draw;
include "bufio.m";
	bufio: Bufio;
include "string.m";
	str: String;
	
include "print.m";

MAXNAME: con 80;
DEFMODE: con 8r664;

PAPER_CONFIG: con CONFIG_PATH + "paper.cfg";
PTYPE_CONFIG: con CONFIG_PATH + "ptype.cfg";
PMODE_CONFIG: con CONFIG_PATH + "pmode.cfg";
POPT_CONFIG: con CONFIG_PATH + "popt.cfg";
PRINTER_CONFIG: con CONFIG_PATH + "printer.cfg";
DEFPRINTER: con CONFIG_PATH + "defprinter";


Cfg: adt {
	name: string;
	pairs: list of (string, string);
};

DEBUG :=0;


all_papers: list of ref Paper;
all_pmodes: list of ref Pmode;
all_ptypes: list of ref Ptype;
all_popts: list of ref Popt;
all_printers: list of ref Printer;
default_printer: ref Printer;
stderr: ref Sys->FD;
printfd: ref Sys->FD;

# Initialization

init(): int
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	all_papers = read_paper_config();
	if (all_papers == nil) return 1;
	all_pmodes = read_pmode_config();
	if (all_pmodes == nil) return 1;
	all_ptypes = read_ptype_config();
	if (all_ptypes == nil) return 1;
	all_printers = read_printer_config();
	if (all_printers == nil) return 1;
	all_popts = read_popt_config();
	for (pl:=all_printers; pl!=nil; pl=tl pl) {
		p := hd pl;
		opt := find_popt(all_popts, p.name);
		if (opt != nil) p.popt = opt;
		else {
			p.popt = ref Popt (p.name, hd all_pmodes, hd all_papers, 0, 0);
			all_popts = p.popt :: all_popts;
		}
	}
	return 0;
}

# Set printer FD

set_printfd(fd: ref Sys->FD)
{
	printfd = fd;	
}


# Get default printer

get_defprinter(): ref Printer
{
	if (len all_printers == 1) return hd all_printers;		# If there's only 1 printer
	df := sys->open(DEFPRINTER, Sys->OREAD);
	if (df == nil) {
		if (all_printers != nil) return hd all_printers;
		else return nil;
	}
	a := array[MAXNAME] of byte;
	nb := sys->read(df, a, MAXNAME);
	if (nb < 2) return nil;
	name := string a[:nb-1];
	def := find_printer(all_printers, name);
	if (def != nil) return def;
	else return hd all_printers;
}

# Set default printer

set_defprinter(p: ref Printer)
{
	df := sys->create(DEFPRINTER, Sys->OWRITE, DEFMODE);
	if (df == nil) return;
	sys->fprint(df, "%s\n", p.name);
}

# Set paper size

get_size(p: ref Printer): (int, int, int)	# dpi, xpixels, ypixels
{
	if (p == nil) return (0, 0, 0);
	load_driver(p);
	dpi := p.popt.mode.resx;
	(xpix, ypix) := p.pdriver->printable_pixels(p);	# This takes account of orientation
	return (dpi, xpix, ypix);
}



# Get list of all printers

get_printers(): list of ref Printer
{
	return all_printers;
}

# Return list of printer types

get_ptypes(): list of ref Ptype
{
	return all_ptypes;
}

# Return list of print modes

get_pmodes(): list of ref Pmode
{
	return all_pmodes;
}

# Return list of paper types

get_papers(): list of ref Paper
{
	return all_papers;
}

# Return list of print options

get_popts(): list of ref Popt
{
	return all_popts;
}

# Save option settings

save_settings(): int
{
	return write_popt_config(all_popts);

}


# Print an image

print_image(p: ref Printer, display: ref Draw->Display, im: ref Draw->Image, pcwidth: int, cancel: chan of int): int
{
	if (p == nil || im == nil) return 1;
	load_driver(p);
	popen(p);
	(xpix, ypix) := p.pdriver->printable_pixels(p);
	imwidth := im.r.max.x - im.r.min.x;
	imheight := im.r.max.y - im.r.min.y;
	if (pcwidth > 0) pixwidth := int (real xpix * real pcwidth/100.0);
	else pixwidth = imwidth;
	lmar := (xpix - pixwidth)/2;
	fpixwidth := pixwidth;
	if (p.popt.orientation != PORTRAIT) {
		lmar += pixwidth;
		fpixwidth = pixwidth*imheight/imwidth;
	}
	if (lmar < 0) lmar = 0;
	return p.pdriver->sendimage(p, printfd, display, im, fpixwidth, lmar, cancel);
}

# Print text

print_textfd(p: ref Printer, fd: ref Sys->FD, ps: real, pr: int, wrap: int): int
{
	load_driver(p);
	popen(p);
	return p.pdriver->sendtextfd(p, printfd, fd, ps, pr, wrap);

}


# Open printer device if necessary

popen(p: ref Printer)
{
	if (printfd != nil) return;
	printfd = sys->create(p.device, Sys->OWRITE, DEFMODE);
}

# Find printer item

find_printer(all: list of ref Printer, name: string): ref Printer
{
	for (p:=all; p!=nil; p=tl p) if ((hd p).name == name) return hd p;
	return nil;
}

# Find popt item

find_popt(all: list of ref Popt, name: string): ref Popt
{
	for (p:=all; p!=nil; p=tl p) if ((hd p).name == name) return hd p;
	return nil;
}


# Find paper item

find_paper(all: list of ref Paper, name: string): ref Paper
{
	for (p:=all; p!=nil; p=tl p) if ((hd p).name == name) return hd p;
	return nil;
}

# Find pmode item

find_pmode(all: list of ref Pmode, name: string): ref Pmode
{
	for (p:=all; p!=nil; p=tl p) if ((hd p).name == name) return hd p;
	return nil;
}

# Find ptype item

find_ptype(all: list of ref Ptype, name: string): ref Ptype
{
	for (p:=all; p!=nil; p=tl p) if ((hd p).name == name) return hd p;
	return nil;
}


# Read paper config file

read_paper_config(): list of ref Paper
{
	(clist, aliases) := read_config(PAPER_CONFIG);
	rlist: list of ref Paper;
	while (clist != nil) {
		this := hd clist;
		clist = tl clist;
		item := ref Paper(this.name, "", 0.0, 0.0);
		for (pairs:= this.pairs; pairs != nil; pairs = tl pairs) {
			(name, value) := hd pairs;
			case (name) {
				"hpcode" =>
					item.hpcode = value;

				"width_inches" =>
					item.width_inches = real value;

				"height_inches" =>
					item.height_inches = real value;

				* =>
					sys->fprint(stderr, "Unknown paper config file option: %s\n", name);
			}
		}
		rlist =item :: rlist;
	}
	for (al:=aliases; al!=nil; al=tl al) {
		(new, old) := hd al;
		olda := find_paper(rlist, old);
		if (olda == nil) sys->fprint(stderr, "Paper alias %s not found\n", old);
		else {
			newa := ref *olda;
			newa.name = new;
			rlist = newa :: rlist;
			}
	}
	return rlist;
}


# Read pmode config file

read_pmode_config(): list of ref Pmode
{
	(clist, aliases)  := read_config(PMODE_CONFIG);
	rlist: list of ref Pmode;
	while (clist != nil) {
		this := hd clist;
		clist = tl clist;
		item := ref Pmode(this.name, "", 0, 0, 1, 1, 1);
		for (pairs:= this.pairs; pairs != nil; pairs = tl pairs) {
			(name, value) := hd pairs;
			case (name) {
				"desc" =>
					item.desc = value;

				"resx" =>
					item.resx = int value;

				"resy" =>
					item.resy = int value;

				"coldepth" =>
					item.coldepth = int value;

				"blackdepth" =>
					item.blackdepth = int value;

				"blackresmult" =>
					item.blackresmult = int value;

				* =>
					sys->fprint(stderr, "Unknown pmode config file option: %s\n", name);

			}
		}
		rlist =item :: rlist;
	}
	for (al:=aliases; al!=nil; al=tl al) {
		(new, old) := hd al;
		olda := find_pmode(rlist, old);
		if (olda == nil) sys->fprint(stderr, "Pmode alias %s not found\n", old);
		else {
			newa := ref *olda;
			newa.name = new;
			rlist = newa :: rlist;
			}
	}
	return rlist;
}




# Readp Ptype config file

read_ptype_config(): list of ref Ptype
{
	(clist, aliases)  := read_config(PTYPE_CONFIG);
	rlist: list of ref Ptype;
	while (clist != nil) {
		this := hd clist;
		clist = tl clist;
		item := ref Ptype(this.name, "", nil, "", "");
		for (pairs:= this.pairs; pairs != nil; pairs = tl pairs) {
			(name, value) := hd pairs;
			case (name) {
				"desc" =>
					item.desc = value;

				"driver" =>
					item.driver = value;

				"hpmapfile" =>
					item.hpmapfile = value;

				"modes" =>
					item.modes = make_pmode_list(value);

				* =>
					sys->fprint(stderr, "Unknown ptype config file option: %s\n", name);
			}
		}
		if (item.modes == nil) {
			sys->fprint(stderr, "No print modes for ptype %s\n", item.name);
			continue;
		}			
		rlist = item :: rlist;
	}
	for (al:=aliases; al!=nil; al=tl al) {
		(new, old) := hd al;
		olda := find_ptype(rlist, old);
		if (olda == nil) sys->fprint(stderr, "Ptype alias %s not found\n", old);
		else {
			newa := ref *olda;
			newa.name = new;
			rlist = newa :: rlist;
			}
	}
	return rlist;
}


# Make a list of pmodes from a string

make_pmode_list(sl: string): list of ref Pmode
{
	pml: list of ref Pmode;
	(n, toks) := sys->tokenize(sl, " \t");
	if (n == 0) return nil;
	for (i:=0; i<n; i++) {
		pms := hd toks;
		toks = tl toks;
		pm := find_pmode(all_pmodes, pms);
		if (pm == nil) {
			sys->fprint(stderr, "unknown pmode: %s\n", pms);
			continue;
		}
		pml = pm :: pml;
	}
	return pml;
}


# Read popt config file

read_popt_config(): list of ref Popt
{
	(clist, aliases)  := read_config(POPT_CONFIG);
	rlist: list of ref Popt;
	while (clist != nil) {
		this := hd clist;
		clist = tl clist;
		item := ref Popt(this.name, nil, nil, 0, 0);
		for (pairs:= this.pairs; pairs != nil; pairs = tl pairs) {
			(name, value) := hd pairs;
			case (name) {

				"mode" =>
					item.mode = find_pmode(all_pmodes, value);
					if (item.mode == nil) sys->fprint(stderr, "Config error: Pmode not found: %s\n", value);

				"paper" =>
					item.paper = find_paper(all_papers, value);
					if (item.paper == nil) sys->fprint(stderr, "Config error: paper not found: %s\n", value);

				"orientation" =>
					item.orientation = int value;
				"duplex" =>
					item.duplex = int value;

				* =>
					sys->fprint(stderr, "Unknown popt config file option: %s\n", name);
			}
		}
		if (item.mode == nil) {
			sys->fprint(stderr, "No print mode for printer %s\n", item.name);
			continue;
		}			
		if (item.paper == nil) {
			sys->fprint(stderr, "No paper size for printer %s\n", item.name);
			continue;
		}			
		rlist = item :: rlist;
	}
	for (al:=aliases; al!=nil; al=tl al) {
		(new, old) := hd al;
		olda := find_popt(rlist, old);
		if (olda == nil) sys->fprint(stderr, "Popt alias %s not found\n", old);
		else {
			newa := ref *olda;
			newa.name = new;
			rlist = newa :: rlist;
			}
	}
	return rlist;
}




# Read printer config file

read_printer_config(): list of ref Printer
{
	(clist, aliases)  := read_config(PRINTER_CONFIG);
	rlist: list of ref Printer;
	while (clist != nil) {
		this := hd clist;
		clist = tl clist;
		item := ref Printer(this.name, nil, "", nil, nil);
		for (pairs:= this.pairs; pairs != nil; pairs = tl pairs) {
			(name, value) := hd pairs;
			case (name) {
				"ptype" =>
					item.ptype = find_ptype(all_ptypes, value);
					if (item.ptype == nil) sys->fprint(stderr, "Config error: Ptype not found: %s\n", value);

				"device" =>
					item.device = value;

				* =>
					sys->fprint(stderr, "Unknown printer config file option: %s\n", name);
			}
		}
		if (item.ptype == nil) {
			sys->fprint(stderr, "No printer type for printer %s\n", item.name);
			continue;
		}			
		rlist = item :: rlist;
	}
	for (al:=aliases; al!=nil; al=tl al) {
		(new, old) := hd al;
		olda := find_printer(rlist, old);
		if (olda == nil) sys->fprint(stderr, "Ptype alias %s not found\n", old);
		else {
			newa := ref *olda;
			newa.name = new;
			rlist = newa :: rlist;
			}
	}
	return rlist;
}

# Write opt config file

write_popt_config(plist: list of ref Popt): int
{
	cfl: list of Cfg;
	for (pl:=plist; pl!=nil; pl=tl pl) {
		po := hd pl;
		cf := Cfg(po.name, nil);
		cf.pairs = ("mode", po.mode.name) :: cf.pairs;
		cf.pairs = ("paper", po.paper.name) :: cf.pairs;
		cf.pairs = ("orientation", sys->sprint("%d", po.orientation)) :: cf.pairs;
		cf.pairs = ("duplex", sys->sprint("%d", po.duplex)) :: cf.pairs;
		cfl = cf :: cfl;
	}
	return write_config(POPT_CONFIG, cfl, nil);
}


write_config(fspec: string, clist: list of Cfg, aliases: list of (string, string)): int
{
	fd := sys->create(fspec, Sys->OWRITE, DEFMODE);
	if (fd == nil) {
		sys->fprint(stderr, "Failed to write to config file %s: %r\n", fspec);
		return 1;
	}
	for (cfl:=clist; cfl!=nil; cfl=tl cfl) {
		cf := hd cfl;
		sys->fprint(fd, "%s=\n", cf.name);
		for (pl:=cf.pairs; pl!=nil; pl=tl pl) {
			(name, value) := hd pl;
			if (sys->fprint(fd, "\t%s=%s\n", name, value) < 0) return 2;
		}
	}
	for (al:=aliases; al!=nil; al=tl al) {
		(new, old) := hd al;
		if (sys->fprint(fd, "%s=%s\n", new, old)) return 2;
	}
	return 0;	
}


# Read in a config file and return list of items and aliases

read_config(fspec: string): (list of Cfg, list of (string, string))
{
	ib := bufio->open(fspec, Bufio->OREAD);
	if (ib == nil) {
		sys->fprint(stderr, "Failed to open config file %s: %r\n", fspec);
		return (nil, nil);
	}
	clist: list of Cfg;
	plist: list of (string, string);
	section := "";
	aliases : list of (string, string);
	while ((line := bufio->ib.gets('\n')) != nil) {
		if (line[0] == '#') continue;
		if (line[len line-1] == '\n') line = line[:len line-1];
		if (len line == 0) continue;
		if (line[0] != ' ' && line[0] != '\t') {
			if (section != "") clist = Cfg (section, plist) :: clist;
			section = "";
			plist = nil;
			sspec := strip(line);
			(n, toks) := sys->tokenize(sspec, "=");
			if (n == 0) continue;
			if (n > 2) {
				sys->fprint(stderr, "Error in config file %s\n", fspec);
				continue;
			}
			if (n == 2) {
				asection := hd toks;
				toks = tl toks;
				alias := hd toks;
				aliases = (asection, alias) :: aliases; 
				continue;
			}
			section = hd toks;
		} else {
			(n, toks) := sys->tokenize(line, "=");
			if (n == 2) {
				name := strip(hd toks);
				toks = tl toks;
				value := strip(hd toks);
				plist = (name, value) :: plist;
			}
		}
	}
	if (section != "") clist = Cfg (section, plist) :: clist;
	return (clist, aliases);
}


# Load printer driver if necessary
load_driver(p: ref Printer)
{
	if (p.pdriver != nil) return;
	modpath := Pdriver->PATHPREFIX + p.ptype.driver;
	p.pdriver = load Pdriver modpath;
	if (p.pdriver == nil) sys->fprint(stderr, "Failed to load driver %s: %r\n", modpath);
	p.pdriver->init(DEBUG);
}


# Strip leading/trailing spaces

strip(s: string): string
{
	(dummy1, s1) := str->splitl(s, "^ \t");
	(s2, dummy2) := str->splitr(s1, "^ \t");
	return s2;
}	
