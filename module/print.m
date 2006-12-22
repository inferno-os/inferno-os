Print: module
{
	PATH: con "/dis/lib/print/print.dis";
	CONFIG_PATH: con "/lib/print/";

	init: fn(): int;
	set_printfd: fn(fd: ref Sys->FD);
	print_image: fn(p: ref Printer, display: ref Draw->Display, im: ref Draw->Image, pcwidth: int, cancel: chan of int): int;
	print_textfd: fn(p: ref Printer, fd: ref Sys->FD, ps: real, pr: int, wrap: int): int;
	get_defprinter: fn(): ref Printer;
	set_defprinter: fn(p: ref Printer);
	get_size: fn(p: ref Printer): (int, int, int);	# dpi, xpixels, ypixels
	get_printers: fn(): list of ref Printer;
	get_papers: fn(): list of ref Paper;
	save_settings: fn(): int;

	# Printer types
	
	Ptype: adt {
		name: string;
		desc: string;
		modes: list of ref Pmode;
		driver: string;
		hpmapfile: string;
	};
	
	# Paper sizes
	
	Paper: adt {
		name: string;
		hpcode: string;
		width_inches: real;
		height_inches: real;
	};
	
	# Print modes
	
	Pmode: adt {
		name: string;
		desc: string;
		resx: int;
		resy: int;
		blackdepth: int;
		coldepth: int;
		blackresmult: int;
	};
	
	# Print options
	
	Popt: adt {
		name: string;
		mode: ref Pmode;
		paper: ref Paper;
		orientation: int;
		duplex: int;
	};
	
	# Printer instance
	
	PORTRAIT: con 0;
	LANDSCAPE: con 1;
	
	DUPLEX_OFF: con 0;
	DUPLEX_LONG: con 1;
	DUPLEX_SHORT: con 2;
	
	Printer: adt {
		name: string;
		ptype: ref Ptype;
		device: string;
		popt: ref Popt;
		pdriver: Pdriver;
	};

};


Pdriver: module
{
	PATHPREFIX: con "/dis/lib/print/";
	DATAPREFIX: con "/lib/print/";

	init: fn(debug: int);
	sendimage: fn(p: ref Print->Printer, tfd: ref Sys->FD, display: ref Draw->Display, im: ref Draw->Image, width: int, lmargin: int, cancel: chan of int): int;
	sendtextfd: fn(p: ref Print->Printer, pfd, tfd: ref Sys->FD, ps: real, pr: int, wrap: int): int;
	printable_pixels: fn(p: ref Print->Printer): (int, int);

};
