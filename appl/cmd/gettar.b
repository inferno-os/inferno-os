implement Gettar;

include "sys.m";
	sys: Sys;
	print, sprint, fprint: import sys;
	stdin, stderr: ref sys->FD;

include "draw.m";

include "arg.m";

TBLOCK: con 512;	# tar logical blocksize

Header: adt{
	name: string;
	size: int;
	mode: int;
	mtime: int;
	skip: int;
};

Gettar: module
{
	init:   fn(nil: ref Draw->Context, nil: list of string);
};

error(mess: string)
{
	fprint(stderr,"gettar: %s\n",mess);
	raise "fail:error";
}

verbose := 0;
NBLOCK: con 20;		# traditional blocking factor for efficient read
tarbuf := array[NBLOCK*TBLOCK] of byte;	# static buffer
nblock := NBLOCK;			# how many blocks of data are in tarbuf
recno := NBLOCK;			# how many blocks in tarbuf have been consumed

getblock(): array of byte
{
	if(recno>=nblock){
		i := sys->read(stdin,tarbuf,TBLOCK*NBLOCK);
		if(i==0)
			return nil;
		if(i<0)
			error(sys->sprint("read error: %r"));
		if(i%TBLOCK!=0)
			error("blocksize error");
		nblock = i/TBLOCK;
		recno = 0;
	}
	recno++;
	return tarbuf[(recno-1)*TBLOCK:recno*TBLOCK];
}


octal(b:array of byte): int
{
	sum := 0;
	for(i:=0; i<len b; i++){
		bi := int b[i];
		if(bi==' ') continue;
		if(bi==0) break;
		sum = 8*sum + bi-'0';
	}
	return sum;
}

nullterm(b:array of byte): string
{
	for(i:=0; i<len b; i++)
		if(b[i]==byte 0) break;
	return string b[0:i];
}

getdir(): ref Header
{
	dblock := getblock();
	if(len dblock==0)
		return nil;
	if(dblock[0]==byte 0)
		return nil;

	name := nullterm(dblock[0:100]);
	if(int dblock[345]!=0)
		name = nullterm(dblock[345:500])+"/"+name;
	if(!absolute){
		if(name[0] == '#')
			name = "./"+name;
		else if(name[0] == '/')
			name = "."+name;
	}

	magic := string(dblock[257:262]);
	if(magic[0]!=0 && magic!="ustar")
		error("bad magic "+name);
	chksum := octal(dblock[148:156]);
	for(ci:=148; ci<156; ci++)
		dblock[ci] = byte ' ';
	for(i:=0; i<TBLOCK; i++)
		chksum -= int dblock[i];
	if(chksum!=0)
		error("directory checksum error "+name);

	skip := 1;
	size := 0;
	mode := 0;
	mtime := 0;
	case int dblock[156]{
	'0' or '7' or 0 =>
		skip = 0;
		size = octal(dblock[124:136]);
		mode = 8r777 & octal(dblock[100: 108]);
		mtime = octal(dblock[136:148]);
	'1' =>
		fprint(stderr,"gettar: skipping link %s -> %s\n",name,string(dblock[157:257]));
	'2' or 's' =>
		fprint(stderr,"gettar: skipping symlink %s\n",name);
	'3' or '4' or '6' =>
		fprint(stderr,"gettar: skipping special file %s\n",name);
	'5' =>
		if(name[(len name)-1]=='/')
			checkdir(name+".");
		else
			checkdir(name+"/.");
	* =>
		error(sprint("unrecognized typeflag %d for %s",int dblock[156],name));
	}
	return ref Header(name, size, mode, mtime, skip);
}

keep := 0;
absolute := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stdin = sys->fildes(0);
	stderr = sys->fildes(2);
	ofile: ref sys->FD;

	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("gettar [-kTRv] [file ...]");
	while((o := arg->opt()) != 0)
		case o {
		'k' =>	keep = 1;
		'v' =>	verbose = 1;
		'R' =>	absolute = 1;
		* =>	arg->usage();
		}
	args = arg->argv();
	arg = nil;

	while((file := getdir())!=nil){
		if(!file.skip){
			if((args == nil || matched(file.name, args)) && !(keep && exists(file.name))){
				if(verbose)
					sys->fprint(stderr, "%s\n", file.name);
				checkdir(file.name);
				ofile = sys->create(file.name, Sys->OWRITE, 8r666);
				if(ofile==nil){
					fprint(stderr, "gettar: cannot create %s: %r\n",file.name);
					file.skip = 1;
				}
			}else
				file.skip = 1;
		}
		bytes := file.size;
		blocks := (bytes+TBLOCK-1)/TBLOCK;
		if(file.skip){
			for(; blocks>0; blocks--)
				getblock();
			continue;
		}

		for(; blocks>0; blocks--){
			buf := getblock();
			nwrite := bytes;
			if(nwrite>TBLOCK)
				nwrite = TBLOCK;
			if(sys->write(ofile,buf,nwrite)!=nwrite)
				error(sprint("write error for %s: %r",file.name));
			bytes -= nwrite;
		}
		ofile = nil;
		stat := sys->nulldir;
		stat.mode = file.mode;
		stat.mtime = file.mtime;
		rc := sys->wstat(file.name,stat);
		if(rc<0){
			# try just the mode
			stat.mtime = ~0;
			rc = sys->wstat(file.name, stat);
			if(rc < 0)
				fprint(stderr,"gettar: cannot set mode/mtime %s %#o %ud: %r\n",file.name, file.mode, file.mtime);
		}
	}
}

checkdir(name: string)
{
	(nc,compl) := sys->tokenize(name,"/");
	path := "";
	while(compl!=nil){
		comp := hd compl;
		if(comp=="..")
			error(".. pathnames forbidden");
		if(nc>1){
			if(path=="")
				path = comp;
			else
				path += "/"+comp;
			(rc,stat) := sys->stat(path);
			if(rc<0){
				fd := sys->create(path,Sys->OREAD,Sys->DMDIR+8r777);
				if(fd==nil)
					error(sprint("cannot mkdir %s: %r",path));
				fd = nil;
			}else if(stat.mode&Sys->DMDIR==0)
				error(sprint("found non-directory at %s",path));
		}
		nc--; compl = tl compl;
	}
}

exists(path: string): int
{
	return sys->stat(path).t0 >= 0;
}

matched(n: string, names: list of string): int
{
	for(; names != nil; names = tl names){
		p := hd names;
		if(prefix(p, n))
			return 1;
	}
	return 0;
}

prefix(p: string, s: string): int
{
	l := len p;
	if(l > len s)
		return 0;
	return p == s[0:l] && (l == len s || s[l] == '/');
}
