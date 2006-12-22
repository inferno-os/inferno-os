implement RImagefile;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";

init(iomod: Bufio)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	bufio = iomod;
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

read(fd: ref Iobuf): (ref Rawimage, string)
{
	width, height, fnd: int;
	(fnd, width) = get_define(fd);
	if(fnd)
		(fnd, height) = get_define(fd);
	if(!fnd)
		return (nil, "xbitmap doesn't start with width and height");
	if(height <= 0 || width <= 0)
		return (nil, "xbitmap has bad width or height");
	# now, optional x_hot, y_hot
	(fnd, nil) = get_define(fd);
	if(fnd)
		(fnd, nil) = get_define(fd);
	# now expect 'static char x...x_bits[] = {'
	if(!get_to_char(fd, '{'))
		return (nil, "xbitmap premature eof");

	bytesperline := (width+7) / 8;
	pixels := array[width*height] of byte;
	pixi := 0;
	for(i := 0; i < height; i++) {
		for(j := 0; j < bytesperline; j++) {
			(vfnd, v) := get_hexbyte(fd);
			if(!vfnd)
				return (nil,  "xbitmap premature eof");
			kend := 7;
			if(j == bytesperline-1)
				kend = (width-1)%8;
			for(k := 0; k <= kend; k++) {
				if(v & (1<<k))
					pixels[pixi] = byte 0;
				else
					pixels[pixi] = byte 1;
				pixi++;
			}
		}
	}
	cmap := array[6] of {byte 0, byte 0, byte 0,
			byte 255, byte 255, byte 255};
	chans := array[1] of {pixels};
	ans := ref Rawimage(Draw->Rect((0,0),(width,height)), cmap, 0, byte 0, 1, chans, CRGB1, 0);
	return (ans, "");
}

# get a line, which should be of form
#	'#define fieldname val'
# and return (found, integer rep of val)
get_define(fd: ref Iobuf) : (int, int)
{
	c := fd.getc();
	if(c != '#') {
		fd.ungetc();
		return (0, 0);
	}
	line := fd.gets('\n');
	for(i := len line -1; i >= 0; i--)
		if(line[i] == ' ')
			break;
	val := int line[i+1:];
	return (1, val);
}

# read fd until get char cterm; return 1 if found
get_to_char(fd: ref Iobuf, cterm: int) : int
{
	for(;;) {
		c := fd.getc();
		if(c < 0)
			return c;
		if(c == cterm)
			return 1;
	}
}

# read fd until get xDD, were DD are hex digits.
# return (found, value of DD as integer)
get_hexbyte(fd: ref Iobuf) : (int, int)
{
	if(!get_to_char(fd, 'x'))
		return (0, 0);
	n1 := hexdig(fd.getc());
	n2 := hexdig(fd.getc());
	if(n1 < 0 || n2 < 0)
		return (0, 0);
	return (1, (n1<<4) | n2);
}

hexdig(c: int) : int
{
	if('0' <= c && c <= '9')
		c -= '0';
	else if('a' <= c && c <= 'f')
		c += 10 - 'a';
	else if('A' <= c && c <= 'F')
		c += 10 - 'A';
	else
		c = -1;
	return c;
}
