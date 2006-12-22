implement Brutusext;

# <Extension image imagefile>

Name:	con "Brutus image";

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Context, Image, Display, Rect: import draw;

include	"bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";
	imageremap: Imageremap;
	readgif: RImagefile;
	readjpg: RImagefile;

include "tk.m";
	tk: Tk;

include	"tkclient.m";
	tkclient: Tkclient;

include "pslib.m";
	pslib: Pslib;

include	"brutus.m";
include	"brutusext.m";

stderr: ref Sys->FD;

Cache: adt
{
	args:		string;
	name:	string;
	r:		Rect;
};

init(s: Sys, d: Draw, b: Bufio, t: Tk, w: Tkclient)
{
	sys = s;
	draw = d;
	bufio = b;
	tk = t;
	tkclient = w;
	imageremap = load Imageremap Imageremap->PATH;
	stderr = sys->fildes(2);
}

cache: list of ref Cache;

create(parent: string, t: ref Tk->Toplevel, name, args: string): string
{
	if(imageremap == nil)
		return sys->sprint(Name + ": can't load remap: %r");
	display := t.image.display;
	file := args;

	for(cl:=cache; cl!=nil; cl=tl cl)
		if((hd cl).args == args)
			break;

	c: ref Cache;
	if(cl != nil)
		c = hd cl;
	else{
		(im, mask, err) := loadimage(display, parent, file);
		if(err != "")
			return err;
		imagename := name+file;
		err = tk->cmd(t, "image create bitmap "+imagename);
		if(len err > 0 && err[0] == '!')
			return err;
		err = tk->putimage(t, imagename, im, mask);
		if(len err > 0 && err[0] == '!')
			return err;
		c = ref Cache(args, imagename, im.r);
		cache = c :: cache;
	}

	err := tk->cmd(t, "canvas "+name+" -height "+string c.r.dy()+" -width "+string c.r.dx());
	if(len err > 0 && err[0] == '!')
		return err;
	err = tk->cmd(t, name+" create image 0 0 -anchor nw -image "+c.name);

	return "";
}

loadimage(display: ref Display, parent, file: string) : (ref Image, ref Image, string)
{
	im := display.open(fullname(parent, file));
	mask: ref Image;

	if(im == nil){
		fd := bufio->open(fullname(parent, file), Bufio->OREAD);
		if(fd == nil)
			return (nil, nil, sys->sprint(Name + ": can't open %s: %r", file));

		mod := filetype(file, fd);
		if(mod == nil)
			return (nil, nil, sys->sprint(Name + ": can't find decoder module for %s: %r", file));

		(ri, err) := mod->read(fd);
		if(ri == nil)
			return (nil, nil, sys->sprint(Name + ": %s: %s", file, err));
		if(err != "")
			sys->fprint(stderr, Name + ": %s: %s", file, err);
		mask = transparency(display, ri);

		# if transparency is enabled, errdiff==1 is probably a mistake,
		# but there's no easy solution.
		(im, err) = imageremap->remap(ri, display, 1);
		if(im == nil)
			return (nil, nil, sys->sprint(Name+": remap %s: %s\n", file, err));
		if(err != "")
			sys->fprint(stderr, Name+": remap %s: %s\n", file, err);
		ri = nil;
	}
	return(im, mask, "");
}

cook(parent: string, fmt: int, args: string): (ref Brutusext->Celem, string)
{
	file := args;
	ans : ref Brutusext->Celem = nil;
	if(fmt == Brutusext->FHtml) {
		s := "<IMG SRC=\"" + file + "\">";
		ans = ref Brutusext->Celem(Brutusext->Special, s, nil, nil, nil, nil);
	}
	else {
		(rc, dir) := sys->stat(file);
		if(rc < 0)
			return (nil, "can't find " + file);
		mtime := dir.mtime;

		# psfile name: in dir of file, with .ps suffix
		psfile := file;
		for(i := (len psfile)-1; i >= 0; i--) {
			if(psfile[i] == '.') {
				psfile = psfile[0:i];
				break;
			}
		}
		psfile = psfile + ".ps";
		(rc, dir) = sys->stat(psfile);
		if(rc < 0 || dir.mtime < mtime) {
			iob := bufio->create(psfile, Bufio->OWRITE, 8r664);
			if(iob == nil)
				return (nil, "can't create " + psfile);

			display := draw->Display.allocate("");
			(im, mask, err) := loadimage(display, parent, file);
			if(err != "")
				return (nil, err);
			pslib = load Pslib Pslib->PATH;
			if(pslib == nil)
				return (nil, "can't load Pslib");
			pslib->init(bufio);
			pslib->writeimage(iob, im, 100);
			iob.close();
		}
		s := "\\epsfbox{" + psfile + "}\n";
		ans = ref Brutusext->Celem(Brutusext->Special, s, nil, nil, nil, nil);
	}
	return (ans, "");
}

fullname(parent, file: string): string
{
	if(len parent==0 || (len file>0 && (file[0]=='/' || file[0]=='#')))
		return file;

	for(i:=len parent-1; i>=0; i--)
		if(parent[i] == '/')
			return parent[0:i+1] + file;
	return file;
}

#
# rest of this is all borrowed from wm/view.
# should probably be packaged - perhaps in RImagefile?
#
filetype(file: string, fd: ref Iobuf): RImagefile
{
	if(len file>4 && file[len file-4:]==".gif")
		return loadgif();
	if(len file>4 && file[len file-4:]==".jpg")
		return loadjpg();

	# sniff the header looking for a magic number
	buf := array[20] of byte;
	if(fd.read(buf, len buf) != len buf){
		sys->fprint(stderr, "View: can't read %s: %r\n", file);
		return nil;
	}
	fd.seek(big 0, 0);
	if(string buf[0:6]=="GIF87a" || string buf[0:6]=="GIF89a")
		return loadgif();
	jpmagic := array[] of {byte 16rFF, byte 16rD8, byte 16rFF, byte 16rE0,
		byte 0, byte 0, byte 'J', byte 'F', byte 'I', byte 'F', byte 0};
	for(i:=0; i<len jpmagic; i++)
		if(jpmagic[i]>byte 0 && buf[i]!=jpmagic[i])
			break;
	if(i == len jpmagic)
		return loadjpg();
	return nil;
}

loadgif(): RImagefile
{
	if(readgif == nil){
		readgif = load RImagefile RImagefile->READGIFPATH;
		if(readgif == nil)
			sys->fprint(stderr, "Brutus image: can't load readgif: %r\n");
		else
			readgif->init(bufio);
	}
	return readgif;
}

loadjpg(): RImagefile
{
	if(readjpg == nil){
		readjpg = load RImagefile RImagefile->READJPGPATH;
		if(readjpg == nil)
			sys->fprint(stderr, "Brutus image: can't load readjpg: %r\n");
		else
			readjpg->init(bufio);
	}
	return readjpg;
}

transparency(display: ref Display, r: ref RImagefile->Rawimage): ref Image
{
	if(r.transp == 0)
		return nil;
	if(r.nchans != 1)
		return nil;
	i := display.newimage(r.r, display.image.chans, 0, 0);
	if(i == nil){
		return nil;
	}
	pic := r.chans[0];
	npic := len pic;
	mpic := array[npic] of byte;
	index := r.trindex;
	for(j:=0; j<npic; j++)
		if(pic[j] == index)
			mpic[j] = byte 0;
		else
			mpic[j] = byte 16rFF;
	i.writepixels(i.r, mpic);
	return i;
}
