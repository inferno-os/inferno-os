implement lstar;

include "sys.m";
	sys: Sys;
	print, sprint, fprint: import sys;
	stdin, stderr: ref sys->FD;
include "draw.m";

TBLOCK: con 512;	# tar logical blocksize
Header: adt{
	name: string;
	size: int;
	mtime: int;
	skip: int;
};

lstar: module{
	init:   fn(nil: ref Draw->Context, nil: list of string);
};

Error(mess: string){
	fprint(stderr,"lstar: %s: %r\n",mess);
	exit;
}


NBLOCK: con 20;		# blocking factor for efficient read
tarbuf := array[NBLOCK*TBLOCK] of byte;	# static buffer
nblock := NBLOCK;			# how many blocks of data are in tarbuf
recno := NBLOCK;			# how many blocks in tarbuf have been consumed
getblock():array of byte{
	if(recno>=nblock){
		i := sys->read(stdin,tarbuf,TBLOCK*NBLOCK);
		if(i==0)
			return tarbuf[0:0];
		if(i<0)
			Error("read error");
		if(i%TBLOCK!=0)
			Error("blocksize error");
		nblock = i/TBLOCK;
		recno = 0;
	}
	recno++;
	return tarbuf[(recno-1)*TBLOCK:recno*TBLOCK];
}

octal(b:array of byte):int{
	sum := 0;
	for(i:=0; i<len b; i++){
		bi := int b[i];
		if(bi==' ') continue;
		if(bi==0) break;
		sum = 8*sum + bi-'0';
	}
	return sum;
}

nullterm(b:array of byte):string{
	for(i:=0; i<len b; i++)
		if(b[i]==byte 0) break;
	return string b[0:i];
}

getdir():ref Header{
	dblock := getblock();
	if(len dblock==0)
		return nil;
	if(dblock[0]==byte 0)
		return nil;

	name := nullterm(dblock[0:100]);
	if(int dblock[345]!=0)
		name = nullterm(dblock[345:500])+"/"+name;

	magic := string(dblock[257:262]);
	if(magic[0]!=0 && magic!="ustar")
		Error("bad magic "+name);
	chksum := octal(dblock[148:156]);
	for(ci:=148; ci<156; ci++) dblock[ci] = byte ' ';
	for(i:=0; i<TBLOCK; i++)
		chksum -= int dblock[i];
	if(chksum!=0)
		Error("directory checksum error "+name);

	skip := 1;
	size := 0;
	mtime := 0;
	case int dblock[156]{
	'0' or '5' or '7' or 0 =>
		skip = 0;
		size = octal(dblock[124:136]);
		mtime = octal(dblock[136:148]);
	'1' =>
		fprint(stderr,"skipping link %s -> %s\n",name,string(dblock[157:257]));
	'2' or 's' =>
		fprint(stderr,"skipping symlink %s\n",name);
	'3' or '4' or '6' =>
		fprint(stderr,"skipping special file %s\n",name);
	* =>
		Error(sprint("unrecognized typeflag %d for %s",int dblock[156],name));
	}
	return ref Header(name,size,mtime,skip);
}


init(nil: ref Draw->Context, nil: list of string){
	sys = load Sys Sys->PATH;
	stdin = sys->fildes(0);
	stderr = sys->fildes(2);
	ofile: ref sys->FD;

	while((file := getdir())!=nil){
		bytes := file.size;
		blocks := (bytes+TBLOCK-1)/TBLOCK;
		for(; blocks>0; blocks--)
			getblock();
		print("%s %d %d 0\n",file.name,file.mtime,file.size);
		ofile = nil;
	}
}
