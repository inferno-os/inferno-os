# read list of pathnames on stdin, write POSIX.1 tar on stdout
# Copyright(c)1996 Lucent Technologies.  All Rights Reserved.
# 22 Dec 1996 ehg@bell-labs.com

implement puttar;
include "sys.m";
	sys: Sys;
	print, sprint, fprint: import sys;
	stdout, stderr: ref sys->FD;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

puttar: module{
	init:   fn(nil: ref Draw->Context, nil: list of string);
};

Warning(mess: string)
{
	fprint(stderr,"warning: puttar: %s: %r\n",mess);
}

Error(mess: string){
	fprint(stderr,"puttar: %s: %r\n",mess);
	exit;
}

TBLOCK: con 512;	# tar logical blocksize
NBLOCK: con 20;		# blocking factor for efficient write
tarbuf := array[NBLOCK*TBLOCK] of byte;	# for output
nblock := 0;		# how many blocks of data are in tarbuf

flushblocks(){
	if(nblock<=0) return;
	if(nblock<NBLOCK){
		for(i:=(nblock+1)*TBLOCK;i<NBLOCK*TBLOCK;i++)
			tarbuf[i] = byte 0;
	}
	i := sys->write(stdout,tarbuf,NBLOCK*TBLOCK);
	if(i!=NBLOCK*TBLOCK)
		Error("write error");
	nblock = 0;
}

putblock(data:array of byte){
	# all writes are done through here, so we can guarantee
	#              10kbyte blocks if writing to tape device
	if(len data!=TBLOCK)
		Error("putblock wants TBLOCK chunks");
	tarbuf[nblock*TBLOCK:] = data;
	nblock++;
	if(nblock>=NBLOCK)
		flushblocks();
}

packname(hdr:array of byte, name:string){
	utf := array of byte name;
	n := len utf;
	if(n<=100){
		hdr[0:] = utf;
		return;
	}
	for(i:=n-101; i<n && int utf[i] != '/'; i++){}
	if(i==n) Error(sprint("%s > 100 bytes",name));
	if(i>155) Error(sprint("%s too long\n",name));
	hdr[0:] = utf[i+1:n];
	hdr[345:] = utf[0:i];  # tar supplies implicit slash
}

octal(width:int, val:int):array of byte{
	octal := array of byte "01234567";
	a := array[width] of byte;
	for(i:=width-1; i>=0; i--){
		a[i] = octal[val&7];
		val >>= 3;
	}
	return a;
}

chksum(hdr: array of byte):int{
	sum := 0;
	for(i:=0; i<len hdr; i++)
		sum += int hdr[i];
	return sum;
}

hdr, zeros, ibuf : array of byte;

tar(file : string)
{
	ifile: ref sys->FD;

	(rc,stat) := sys->stat(file);
	if(rc<0){ Warning(sprint("cannot stat %s",file)); return; };
	ifile = sys->open(file,sys->OREAD);
	if(ifile==nil) Error(sprint("cannot open %s",file));
	hdr[0:] = zeros;
	packname(hdr,file);
	hdr[100:] = octal(7,stat.mode&8r777);
	hdr[108:] = octal(7,1);
	hdr[116:] = octal(7,1);
	hdr[124:] = octal(11,int stat.length);
	hdr[136:] = octal(11,stat.mtime);
	hdr[148:] = array of byte "        "; # for chksum
	hdr[156] = byte '0';
	if(stat.mode&Sys->DMDIR) hdr[156] = byte '5';
	hdr[257:] = array of byte "ustar";
	hdr[263:] = array of byte "00";
	hdr[265:] = array of byte stat.uid; # assumes len uid<=32
	hdr[297:] = array of byte stat.gid;
	hdr[329:] = octal(8,stat.dev);
	hdr[337:] = octal(8,int stat.qid.path);
	hdr[148:] = octal(7,chksum(hdr));
	hdr[155] = byte 0;
	putblock(hdr);
	for(bytes := int stat.length; bytes>0;){
		n := len ibuf;  if(n>bytes) n = bytes;  # min
		if(sys->read(ifile,ibuf,n)!=n)
			Error(sprint("read error on %s",file));
		nb := (n+TBLOCK-1)/TBLOCK;
		fill := nb*TBLOCK;
		for(i:=n; i<fill; i++) ibuf[i] = byte 0;
		for(i=0; i<nb; i++)
			putblock(ibuf[i*TBLOCK:(i+1)*TBLOCK]);
		bytes -= n;
	}
	ifile = nil;
}

rtar(file : string)
{
	tar(file);
	# recurse if directory
	(ok, dir) := sys->stat(file);
	if (ok < 0){
		Warning(sprint("cannot stat %s", file));
		return;
	}
	if (dir.mode & Sys->DMDIR) {
		fd := sys->open(file, sys->OREAD);
		if (fd == nil)
			Error(sprint("cannot open %s", file));
		for (;;) {
			(n, d) := sys->dirread(fd);
			if (n <= 0)
				break;
			for (i := 0; i < n; i++) {
				if (file[len file - 1] == '/')
					rtar(file + d[i].name);
				else
					rtar(file + "/" + d[i].name);
			}
		}
	}
}

init(nil: ref Draw->Context, args: list of string){
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);
	
	hdr = array[TBLOCK] of byte;
	zeros = array[TBLOCK] of {* => byte 0};
	ibuf = array[len tarbuf] of byte;

	if (tl args == nil) {
		stdin := bufio->fopen(sys->fildes(0),bufio->OREAD);
		if(stdin==nil) Error("can't fopen stdin");
		while((file := stdin.gets('\n'))!=nil){
			if(file[len file-1]=='\n') file = file[0:len file-1];
			tar(file);
		}
	}
	else {
		for (args = tl args; args != nil; args = tl args)
			rtar(hd args);
	}
	putblock(zeros);
	putblock(zeros);	# format requires two empty blocks at end
	flushblocks();
}
