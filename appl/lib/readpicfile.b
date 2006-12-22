implement RImagefile;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";

Header: adt
{
	fd:	ref Iobuf;
	ch:	chan of (ref Rawimage, string);
	# variables in i/o routines
	buf:	array of byte;
	bufi:	int;
	nbuf:	int;

	TYPE:	string;
	CHAN:	string;
	NCHAN:	string;
	CMAP:	int;

	dx:	int;
	dy:	int;
};

NBUF:	con 8*1024;

init(iomod: Bufio)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	bufio = iomod;
}

read(fd: ref Iobuf): (ref Rawimage, string)
{
	# spawn a subprocess so I/O errors can clean up easily

	ch := chan of (ref Rawimage, string);
	spawn readslave(fd, ch);

	return <-ch;
}

readmulti(fd: ref Iobuf): (array of ref Rawimage, string)
{
	(i, err) := read(fd);
	if(i != nil){
		a := array[1] of { i };
		return (a, err);
	}
	return (nil, err);
}

readslave(fd: ref Iobuf, ch: chan of (ref Rawimage, string))
{
	(header, err) := header(fd, ch);
	if(header == nil){
		ch <-= (nil, err);
		exit;
	}

	ch <-= image(header);
}

readerror(): string
{
	return sys->sprint("ReadPIC: read error: %r");
}

header(fd: ref Iobuf, ch: chan of (ref Rawimage, string)): (ref Header, string)
{
	h := ref Header;

	h.fd = fd;
	h.ch = ch;
	h.CMAP = 0;
	h.dx = 0;
	h.dy = 0;
	cantparse := "ReadPIC: can't parse header";
	for(;;){
		s := fd.gets('\n');
		if(s==nil || s[len s-1]!='\n')
			return (nil, cantparse);
		if(s == "\n")
			break;
		addfield(h, s[0:len s-1]);
	}
	if(h.dx<=0 || h.dy<=0)
		return (nil, "ReadPIC: empty picture or WINDOW not set");
	return (h, nil);
}

addfield(h: ref Header, s: string)
{
	baddata := "ReadPIC: not a PIC header";
	for(i:=0; i<len s; i++){
		if(s[i] == '=')
			break;
		if(s[i]==0 || s[i]>16r7f){
			h.ch <-= (nil, baddata);
			exit;
		}
	}
	if(i == len s){
		h.ch <-= (nil, baddata);
		exit;
	}
	case s[0:i]{
	"TYPE" =>
		h.TYPE = s[i+1:];
	"CHAN" =>
		h.CHAN = s[i+1:];
	"NCHAN" =>
		h.NCHAN = s[i+1:];
	"CMAP" =>
		h.CMAP = 1;
	"WINDOW" =>
		(n, l) := sys->tokenize(s[i+1:], " ");
		if(n != 4){
			h.ch <-= (nil, "ReadPIC: bad WINDOW specification");
			exit;
		}
		x0 := int hd l;
		l = tl l;
		y0 := int hd l;
		l = tl l;
		h.dx = int hd l - x0;
		l = tl l;
		h.dy = int hd l - y0;
	}
}

image(h: ref Header): (ref Rawimage, string)
{
	if(h.TYPE!="dump" || h.CHAN!="rgb" || h.NCHAN!="3" || h.CMAP)
		return (nil, "ReadPIC: can't handle this type of picture");

	i := ref Rawimage;
	i.r = ((0,0), (h.dx, h.dy));
	i.cmap = nil;
	i.transp = 0;
	i.trindex = byte 0;
	i.nchans = int h.NCHAN;
	i.chans = array[i.nchans] of array of byte;
	for(j:=0; j<i.nchans; j++)
		i.chans[j] = array[h.dx*h.dy] of byte;
	i.chandesc = CRGB;
	n := h.dx*h.dy;
	b := array[i.nchans*n] of byte;
	if(h.fd.read(b, len b) != len b)
		return (nil, "ReadPIC: file too short");
	l := 0;
	for(j=0; j<n; j++)
		for(k:=0; k<i.nchans; k++)
			i.chans[k][j] = b[l++];
	return (i, nil);
}
