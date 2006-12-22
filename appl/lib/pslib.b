implement Pslib;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw : Draw;
Image, Display,Rect,Point : import draw;

include "bufio.m";
	bufmod : Bufio;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

Iobuf : import bufmod;

include "string.m";
	str : String;

include "daytime.m";
	time : Daytime;

include "pslib.m";

# old module declaration.
# this whole thing needs a revamp, so almost all the old external
# linkages have been removed until there's time to do it properly.
#Pslib : module 
#{
#	PATH:		con "/dis/lib/pslib.dis";
#
#	init:	fn(env: ref Draw->Context, t: ref Tk->Toplevel, boxes: int, deb: int): string;
#	getfonts:		fn(input: string): string;
#	preamble:		fn(ioutb: ref Bufio->Iobuf, bbox: Draw->Rect): string;
#	trailer:		fn(ioutb: ref Bufio->Iobuf, pages: int): string;
#	printnewpage:	fn(pagenum: int, end: int, ioutb: ref Bufio->Iobuf);
#	parseTkline:	fn(ioutb: ref Bufio->Iobuf, input: string): string;
#	stats:		fn(): (int, int, int);
#	deffont:		fn(): string;
#	image2psfile:	fn(ioutb: ref Bufio->Iobuf, im: ref Draw->Image, dpi: int) : string;
#};

ASCII,RUNE,IMAGE : con iota;

Iteminfo : adt
{
	itype: int;
	offset: int;		# offset from the start of line.
	width: int;		# width....
	ascent: int;	# ascent of the item
	font: int;		# font 
	line : int;		# line its on
	buf : string;	
};

Lineinfo : adt
{
	xorg: int;
	yorg: int;
	width: int;
	height: int;
	ascent: int;
};


font_arr := array[256] of {* => (-1,"")};
remap := array[20] of (string,string);

PXPI : con 100;
PTPI : con 100;

boxes: int;
debug: int;
totitems: int;
totlines: int;
curfont: int;
def_font: string;
def_font_type: int;
curfonttype: int;
pagestart: int;
ctxt: ref Draw->Context;
t: ref Toplevel;

nomod(s: string)
{
	sys->print("pslib: cannot load %s: %r\n", s);
	raise "fail:bad module";
}

init(bufio: Bufio)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk= load Tk Tk->PATH;
	if (tk == nil)
		nomod(Tk->PATH);
	str = load String String->PATH;
	if (str == nil)
		nomod(String->PATH);
	bufmod = bufio;
}


oldinit(env: ref Draw->Context, d: ref Toplevel, nil: int,deb: int): string
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	draw = load Draw Draw->PATH;
	tk= load Tk Tk->PATH;
	bufmod = load Bufio Bufio->PATH;
	ctxt=env;
	t=d;
	debug = deb;
	totlines=0;
	totitems=0;
	pagestart=0;
	boxes=0; #box;
	curfont=0;
	e := loadfonts();
	if (e != "")
		return e;
	return "";
}

stats(): (int,int,int)
{
	return (totitems,totlines,curfont);
}

loadfonts() : string
{
	input : string;
	iob:=bufmod->open("/fonts/psrename",bufmod->OREAD);
	if (iob==nil)
		return sys->sprint("can't open /fonts/psrename: %r");
	i:=0;
	while((input=iob.gets('\n'))!=nil){
		(tkfont,psfont):=str->splitl(input," ");
		psfont=psfont[1:len psfont -1];
		remap[i]=(tkfont,psfont);
		i++;
	}
	return "";
}

preamble(ioutb: ref Iobuf, bb: Rect)
{
	time = load Daytime Daytime->PATH;
	username := "";
	fd := sys->open("/dev/user", sys->OREAD);
	if(fd != nil) {
		b := array[128] of byte;
		n := sys->read(fd, b, len b);
		b=b[0:n];
		username = string b;
		fd = nil;
	}
	if(bb.max.x == 0 && bb.max.y == 0) {
		bb.max.x = 612;
		bb.max.y = 792;
	}
	ioutb.puts("%!PS-Adobe-3.0\n");
	ioutb.puts(sys->sprint("%%%%Creator: Pslib 1.0 (%s)\n",username));
	ioutb.puts(sys->sprint("%%%%CreationDate: %s\n",time->time()));
	ioutb.puts("%%Pages: (atend) \n");
	ioutb.puts(sys->sprint("%%%%BoundingBox: %d %d %d %d\n", bb.min.x, bb.min.y, bb.max.x, bb.max.y));
	ioutb.puts("%%EndComments\n");
	ioutb.puts("%%BeginProlog\n");
	ioutb.puts("/doimage {\n");
	ioutb.puts("/bps exch def\n");
	ioutb.puts("/width exch def\n");
	ioutb.puts("/height exch def\n");
	ioutb.puts("/xstart exch def\n");
	ioutb.puts("/ystart exch def\n");
	ioutb.puts("/iwidth exch def\n");
	ioutb.puts("/ascent exch def\n");
	ioutb.puts("/iheight exch def\n");
	ioutb.puts("gsave\n");
	if(boxes)
		ioutb.puts("xstart ystart iwidth iheight rectstroke\n");
	# if bps==8, use inferno colormap; else (bps < 8) it's grayscale
	ioutb.puts("bps 8 eq\n");
	ioutb.puts("{\n");
	ioutb.puts("[/Indexed /DeviceRGB 255 \n");
	ioutb.puts("<ffffff ffffaa ffff55 ffff00 ffaaff ffaaaa ffaa55 ffaa00 ff55ff ff55aa ff5555 ff5500\n");
	ioutb.puts("ff00ff ff00aa ff0055 ff0000 ee0000 eeeeee eeee9e eeee4f eeee00 ee9eee ee9e9e ee9e4f\n");
	ioutb.puts("ee9e00 ee4fee ee4f9e ee4f4f ee4f00 ee00ee ee009e ee004f dd0049 dd0000 dddddd dddd93\n");
	ioutb.puts("dddd49 dddd00 dd93dd dd9393 dd9349 dd9300 dd49dd dd4993 dd4949 dd4900 dd00dd dd0093\n");
	ioutb.puts("cc0088 cc0044 cc0000 cccccc cccc88 cccc44 cccc00 cc88cc cc8888 cc8844 cc8800 cc44cc\n");
	ioutb.puts("cc4488 cc4444 cc4400 cc00cc aaffaa aaff55 aaff00 aaaaff bbbbbb bbbb5d bbbb00 aa55ff\n");
	ioutb.puts("bb5dbb bb5d5d bb5d00 aa00ff bb00bb bb005d bb0000 aaffff 9eeeee 9eee9e 9eee4f 9eee00\n");
	ioutb.puts("9e9eee aaaaaa aaaa55 aaaa00 9e4fee aa55aa aa5555 aa5500 9e00ee aa00aa aa0055 aa0000\n");
	ioutb.puts("990000 93dddd 93dd93 93dd49 93dd00 9393dd 999999 99994c 999900 9349dd 994c99 994c4c\n");
	ioutb.puts("994c00 9300dd 990099 99004c 880044 880000 88cccc 88cc88 88cc44 88cc00 8888cc 888888\n");
	ioutb.puts("888844 888800 8844cc 884488 884444 884400 8800cc 880088 55ff55 55ff00 55aaff 5dbbbb\n");
	ioutb.puts("5dbb5d 5dbb00 5555ff 5d5dbb 777777 777700 5500ff 5d00bb 770077 770000 55ffff 55ffaa\n");
	ioutb.puts("4fee9e 4fee4f 4fee00 4f9eee 55aaaa 55aa55 55aa00 4f4fee 5555aa 666666 666600 4f00ee\n");
	ioutb.puts("5500aa 660066 660000 4feeee 49dddd 49dd93 49dd49 49dd00 4993dd 4c9999 4c994c 4c9900\n");
	ioutb.puts("4949dd 4c4c99 555555 555500 4900dd 4c0099 550055 550000 440000 44cccc 44cc88 44cc44\n");
	ioutb.puts("44cc00 4488cc 448888 448844 448800 4444cc 444488 444444 444400 4400cc 440088 440044\n");
	ioutb.puts("00ff00 00aaff 00bbbb 00bb5d 00bb00 0055ff 005dbb 007777 007700 0000ff 0000bb 000077\n");
	ioutb.puts("333333 00ffff 00ffaa 00ff55 00ee4f 00ee00 009eee 00aaaa 00aa55 00aa00 004fee 0055aa\n");
	ioutb.puts("006666 006600 0000ee 0000aa 000066 222222 00eeee 00ee9e 00dd93 00dd49 00dd00 0093dd\n");
	ioutb.puts("009999 00994c 009900 0049dd 004c99 005555 005500 0000dd 000099 000055 111111 00dddd\n");
	ioutb.puts("00cccc 00cc88 00cc44 00cc00 0088cc 008888 008844 008800 0044cc 004488 004444 004400\n");
	ioutb.puts("0000cc 000088 000044 000000>\n");
	ioutb.puts("] setcolorspace\n");
	ioutb.puts("/decodemat [0 255] def\n");
	ioutb.puts("}\n");
	# else, bps != 8
	ioutb.puts("{\n");
	ioutb.puts("[/DeviceGray] setcolorspace\n");
	ioutb.puts("/decodemat [1 0] def\n");
	ioutb.puts("}\n");
	ioutb.puts("ifelse\n");
	ioutb.puts("xstart ystart translate \n");
	ioutb.puts("iwidth iheight scale \n");
	ioutb.puts("<<\n");
	ioutb.puts("/ImageType 1\n");
	ioutb.puts("/Width width \n");
	ioutb.puts("/Height height \n");
	ioutb.puts("/BitsPerComponent bps %bits/sample\n");
	ioutb.puts("/Decode decodemat % Inferno cmap or DeviceGray value\n");
	ioutb.puts("/ImageMatrix [width 0 0 height neg 0 height]\n");
	ioutb.puts("/DataSource currentfile /ASCII85Decode filter\n");
	ioutb.puts(">> \n");
	ioutb.puts("image\n");
	ioutb.puts("grestore\n");
	ioutb.puts("} def\n");
	ioutb.puts("%%EndProlog\n");	
}

trailer(ioutb : ref Iobuf,pages : int)
{
	ioutb.puts("%%Trailer\n%%Pages: "+string pages+"\n%%EOF\n");
}


printnewpage(pagenum : int,end : int, ioutb : ref Iobuf)
{
	pnum:=string pagenum;
	if (end){			
		# bounding box
		if (boxes){
			ioutb.puts("18 18 moveto 594 18 lineto 594 774 lineto 18 774 lineto"+
								" closepath stroke\n");
		}
		ioutb.puts("showpage\n%%EndPage "+pnum+" "+pnum+"\n");
	} else 
		ioutb.puts("%%Page: "+pnum+" "+pnum+"\n");
}

printimage(ioutb: ref Iobuf, line: Lineinfo, imag: Iteminfo): (string,string)
{
	RM:=612-18;
	class:=tk->cmd(t,"winfo class "+imag.buf);
#sys->print("Looking for [%s] of type [%s]\n",imag.buf,class);
	if (line.xorg+imag.offset+imag.width>RM)
		imag.width=RM-line.xorg-imag.offset;
	case class {
		"button" or "menubutton" =>
			# try to get the text out and print it....
			ioutb.puts(sys->sprint("%d %d moveto\n",line.xorg+imag.offset,
							line.yorg));
			msg:=tk->cmd(t,sys->sprint("%s cget -text",imag.buf));
			ft:=tk->cmd(t,sys->sprint("%s cget -font",imag.buf));
			sys->print("font is [%s]\n",ft);
			ioutb.puts(sys->sprint("%d %d %d %d rectstroke\n",
						line.xorg+imag.offset,line.yorg,imag.width,
						line.height));
			return (class,msg);
		"label" =>
			(im,im2,err) := tk->getimage(t,imag.buf);
			if (im!=nil){
				bps := im.depth;
				ioutb.puts(sys->sprint("%d %d %d %d %d %d %d %d doimage\n",
						im.r.dy(),line.ascent,im.r.dx(),line.yorg,
						line.xorg+imag.offset,im.r.dy(), im.r.dx(), bps));
				imagebits(ioutb,im);
			}
			return (class,"");
		"entry" =>
			ioutb.puts(sys->sprint("%d %d moveto\n",line.xorg+imag.offset,
					line.yorg));
			ioutb.puts(sys->sprint("%d %d %d %d rectstroke\n",
					line.xorg+imag.offset,line.yorg,imag.width,
					line.height));
			return (class,"");
		* =>
			sys->print("Unhandled class [%s]\n",class);
			return (class,"Error");
		
	}
	return ("","");	
}

printline(ioutb: ref Iobuf,line : Lineinfo,items : array of Iteminfo)
{
	xstart:=line.xorg;
	wid:=xstart;
	# items
	if (len items == 0) return;
	for(j:=0;j<len items;j++){
		msg:="";
		class:="";
		if (items[j].itype==IMAGE)
			(class,msg)=printimage(ioutb,line,items[j]);
		if (items[j].itype!=IMAGE || class=="button"|| class=="menubutton"){
			setfont(ioutb,items[j].font);
			if (msg!=""){ 
				# position the text in the center of the label
				# moveto curpoint
				# (msg) stringwidth pop xstart sub 2 div
				ioutb.puts(sys->sprint("%d %d moveto\n",xstart+items[j].offset,
						line.yorg+line.height-line.ascent));
				ioutb.puts(sys->sprint("(%s) dup stringwidth pop 2 div",
								msg));
				ioutb.puts(" 0 rmoveto show\n");
			}
			else {
				ioutb.puts(sys->sprint("%d %d moveto\n",
					xstart+items[j].offset,line.yorg+line.height
					-line.ascent));
				ioutb.puts(sys->sprint("(%s) show\n",items[j].buf));
			}
		}
		wid=xstart+items[j].offset+items[j].width;
	}
	if (boxes)
		ioutb.puts(sys->sprint("%d %d %d %d rectstroke\n",line.xorg,line.yorg,
									wid,line.height));
}

setfont(ioutb: ref Iobuf, font: int)
{
	ftype : int;
	fname : string;
	if ((curfonttype & font) != curfonttype){
		for(f:=0;f<curfont;f++){
			(ftype,fname)=font_arr[f];
				if ((ftype&font)==ftype)
					break;
		}
		if (f==curfont){
			fname=def_font;
			ftype=def_font_type;
		}
		ioutb.puts(sys->sprint("%s setfont\n",fname));
		curfonttype=ftype;
	}
}
	
parseTkline(ioutb: ref Iobuf, input: string): string
{
	thisline : Lineinfo;
	PS:=792-18-18;	# page size in points	
	TM:=792-18;	# top margin in points
	LM:=18;		# left margin 1/4 in. in
	BM:=18;		# bottom margin 1/4 in. in
	x : int;
	(x,input)=str->toint(input,10);
	thisline.xorg=(x*PTPI)/PXPI;
	(x,input)=str->toint(input,10);
	thisline.yorg=(x*PTPI)/PXPI;
	(x,input)=str->toint(input,10);
	thisline.width=(x*PTPI)/PXPI;
	(x,input)=str->toint(input,10);
	thisline.height=(x*PTPI)/PXPI;
	(x,input)=str->toint(input,10);
	thisline.ascent=(x*PTPI)/PXPI;
	(x,input)=str->toint(input,10);
	# thisline.numitems=x;
	if (thisline.width==0 || thisline.height==0)
		return "";
	if (thisline.yorg+thisline.height-pagestart>PS){
		pagestart=thisline.yorg;
		return "newpage";
		# must resend this line....
	}
	thisline.yorg=TM-thisline.yorg-thisline.height+pagestart;
	thisline.xorg+=LM;
	(items, err) :=getline(totlines,input);
	if(err != nil)
		return err;
	totitems+=len items;
	totlines++;
	printline(ioutb,thisline,items);
	return "";
}

getfonts(input: string) : string
{
	tkfont,psfont : string;
	j : int;
	retval := "";
	if (input[0]=='%')
			return "";
	# get a line of the form 
	# 5::/fonts/lucida/moo.16.font
	# translate it to...
	# 32 f32.16
	# where 32==1<<5 and f32.16 is a postscript function that loads the 
	# appropriate postscript font (from remap)
	# and writes it to fonts....
	(bits,font):=str->toint(input,10);
	if (bits!=-1)
		bits=1<<bits;
	else{
		bits=1;
		def_font_type=bits;
		curfonttype=def_font_type;
	}
	font=font[2:];
	for(i:=0;i<len remap;i++){
		(tkfont,psfont)=remap[i];
		if (tkfont==font)
			break;
	}
	if (i==len remap)
		psfont="Times-Roman";
	(font,nil)=str->splitr(font,".");
	(nil,font)=str->splitr(font[0:len font-1],".");
	(fsize,nil):=str->toint(font,10);
	fsize=(PTPI*3*fsize)/(2*PXPI);
	enc_font:="f"+string bits+"."+string fsize;
	ps_func:="/"+enc_font+" /"+psfont+" findfont "+string fsize+
							" scalefont def\n";
	sy_font:="sy"+string fsize;
	xtra_func:="/"+sy_font+" /Symbol findfont "+string fsize+
							" scalefont def\n";
	for(i=0;i<len font_arr;i++){
		(j,font)=font_arr[i];
		if (j==-1) break;
	}
	if (j==len font_arr)
		return "Error";
	font_arr[i]=(bits,enc_font);
	if (bits==1)
		def_font=enc_font;
	curfont++;
	retval+= ps_func;
	retval+= xtra_func;	
	return retval;
}

deffont() : string
{
	return def_font;
}
	
getline(k : int,  input : string) : (array of Iteminfo, string)
{
	lineval,args : string;
	j, nb : int;
	lw:=0;
	wid:=0;
	flags:=0;
	item_arr := array[32] of {* => Iteminfo(-1,-1,-1,-1,-1,-1,"")};
	curitem:=0;
	while(input!=nil){
		(nil,input)=str->splitl(input,"[");
		if (input==nil)
			break;
		com:=input[1];
		input=input[2:];
		case com {
		'A' =>
			nb=0;
			# get the width of the item
			(wid,input)=str->toint(input,10);
			wid=(wid*PTPI)/PXPI;
			if (input[0]!='{')
				return (nil, sys->sprint(
					"line %d item %d Bad Syntax : '{' expected",
						k,curitem));
			# get the args.
			(args,input)=str->splitl(input,"}");
			# get the flags.
			# assume there is only one int flag..
			(flags,args)=str->toint(args[1:],16);
			if (args!=nil && debug){
				sys->print("line %d item %d extra flags=%s\n",
						k,curitem,args);
			}
			if (flags<1024) flags=1;
			item_arr[curitem].font=flags;
			item_arr[curitem].offset=lw;
			item_arr[curitem].width=wid;
			lw+=wid;
			for(j=1;j<len input;j++){
				if ((input[j]==')')||(input[j]=='('))
						lineval[len lineval]='\\';
				if (input[j]=='[')
					nb++;
				if (input[j]==']')
					if (nb==0)
						break;
					else 
						nb--;
				lineval[len lineval]=input[j];
			}
			if (j<len input)
				input=input[j:];
			item_arr[curitem].buf=lineval;
			item_arr[curitem].line=k;
			item_arr[curitem].itype=ASCII;
			curitem++;
			lineval="";
		'R' =>
			nb=0;
			# get the width of the item
			(wid,input)=str->toint(input,10);
			wid=(wid*PTPI)/PXPI;
			if (input[0]!='{')
				return (nil, "Bad Syntax : '{' expected");
			# get the args.
			(args,input)=str->splitl(input,"}");
			# get the flags.
			# assume there is only one int flag..
			(flags,args)=str->toint(args[1:],16);
			if (args!=nil && debug){
				sys->print("line %d item %d Bad Syntax args=%s",
						k,curitem,args);
			}
			item_arr[curitem].font=flags;
			item_arr[curitem].offset=lw;
			item_arr[curitem].width=wid;
			lw+=wid;
			for(j=1;j<len input;j++){
				if (input[j]=='[')
					nb++;
				if (input[j]==']')
					if (nb==0)
						break;
					else 
						nb--;
				case input[j] {
					8226 => # bullet
						lineval+="\\267 ";
					169 =>  # copyright
						lineval+="\\251 ";
						curitem++;			
					* =>
						lineval[len lineval]=input[j];
				}
			}
			if (j>len input)
				input=input[j:];
			item_arr[curitem].buf=lineval;
			item_arr[curitem].line=k;
			item_arr[curitem].itype=RUNE;
			curitem++;
			lineval="";
		'N' or 'C'=>
			# next item
			for(j=0;j<len input;j++)
				if (input[j]==']')
					break;
			if (j>len input)
				input=input[j:];
		'T' =>
			(wid,input)=str->toint(input,10);
			wid=(wid*PTPI)/PXPI;
			item_arr[curitem].offset=lw;
			item_arr[curitem].width=wid;
			lw+=wid;
			lineval[len lineval]='\t';
			# next item
			for(j=0;j<len input;j++)
				if (input[j]==']')
					break;
			if (j>len input)
				input=input[j:];
			item_arr[curitem].buf=lineval;
			item_arr[curitem].line=k;
			item_arr[curitem].itype=ASCII;
			curitem++;
			lineval="";
		'W' =>
			(wid,input)=str->toint(input,10);
			wid=(wid*PTPI)/PXPI;
			item_arr[curitem].offset=lw;
			item_arr[curitem].width=wid;
			item_arr[curitem].itype=IMAGE;
			lw+=wid;
			# next item
			for(j=1;j<len input;j++){
				if (input[j]==']')
					break;
				lineval[len lineval]=input[j];
			}
			item_arr[curitem].buf=lineval;
			if (j>len input)
				input=input[j:];
			curitem++;
			lineval="";
		* =>
			# next item
			for(j=0;j<len input;j++)
				if (input[j]==']')
					break;
			if (j>len input)
				input=input[j:];
				
		}
	}
	return (item_arr[0:curitem], "");	
}

writeimage(ioutb: ref Iobuf, im: ref Draw->Image, dpi: int)
{
	r := im.r;
	width := r.dx();
	height := r.dy();
	iwidth := width * 72 / dpi;
	iheight := height * 72 / dpi;
	xstart := 72;
	ystart := 720 - iheight;
	bbox := Rect((xstart,ystart), (xstart+iwidth,ystart+iheight));
	preamble(ioutb, bbox);
	ioutb.puts("%%Page: 1\n%%BeginPageSetup\n");
	ioutb.puts("/pgsave save def\n");
	ioutb.puts("%%EndPageSetup\n");
	bps := im.depth;
	ioutb.puts(sys->sprint("%d 0 %d %d %d %d %d %d doimage\n", iheight, iwidth, ystart, xstart, height, width, bps));
	imagebits(ioutb, im);
	ioutb.puts("pgsave restore\nshowpage\n");
	trailer(ioutb, 1);
	ioutb.flush();
}

imagebits(ioutb: ref Iobuf, im: ref Draw->Image)
{
	if(debug)
		sys->print("imagebits, r=%d %d %d %d, depth=%d\n",
			im.r.min.x, im.r.min.y, im.r.max.x, im.r.max.y, im.depth);
	width:=im.r.dx();
	height:=im.r.dy();
	bps:=im.depth;	# bits per sample
	spb := 1;			# samples per byte
	bitoff := 0;			# bit offset of beginning sample within first byte
	linebytes := width;
	if(bps < 8) {
		spb=8/bps;
		bitoff=(im.r.min.x % spb) * bps;
		linebytes=(bitoff + (width-1)*bps) / 8 + 1;
	}
	arr:=array[linebytes*height] of byte;
	n:=im.readpixels(im.r,arr);
	if(debug)
		sys->print("linebytes=%d, height=%d, readpixels returned %d\n",
			linebytes, height, n);
	if(n < 0) {
		n = len arr;
		for(i := 0; i < n; i++)
			arr[i] = byte 0;
	}
	if(bitoff != 0) {
		# Postscript image wants beginning of line at beginning of byte
		pslinebytes := (width-1)*bps + 1;
		if(debug)
			sys->print("bitoff=%d, pslinebytes=%d\n", bitoff, pslinebytes);
		old:=arr;
		n = pslinebytes*height;
		arr=array[n] of byte;
		a0 := 0;
		o0 := 0;
		for(y := 0; y < height; y++) {
			for(i:=0; i < pslinebytes; i++)
				arr[a0+i] = (old[o0+i]<<bitoff) | (old[o0+i+1]>>(8-bitoff));
			a0 += pslinebytes;
			o0 += linebytes;
		}
	}
	lsf:=0;
	n4 := (n/4)*4;
	for(i:=0;i<n4;i+=4){
		s:=cmap2ascii85(arr[i:i+4]);
		lsf+=len s;
		ioutb.puts(s);
		if (lsf>74){
		  ioutb.puts("\n");
		  lsf=0;
		}
	}
	nrest:=n-n4;
	if(nrest!=0){
		foo:=array[4] of {* => byte 0};
		foo[0:]=arr[n4:n];
		s:=cmap2ascii85(foo);
		if(s=="z")
			s="!!!!!";
		ioutb.puts(s[0:nrest+1]);
	}
	ioutb.puts("~>\n");
	ioutb.flush();
}


cmap2ascii85(arr : array of byte) : string
{
	b := array[4] of {* => big 0};
	for(i:=0;i<4;i++)
		b[i]=big arr[i];
	i1:=(b[0]<<24)+(b[1]<<16)+(b[2]<<8)+b[3];
	c1:=sys->sprint("%c%c%c%c%c",'!'+int ((i1/big (85*85*85*85))%big 85),
					'!'+int ((i1/big (85*85*85))%big 85),
					'!'+int ((i1/big (85*85))% big 85),
					'!'+int ((i1/big 85)% big 85),'!'+int(i1% big 85));
	if (c1=="!!!!!") c1="z";
	return c1;
}
