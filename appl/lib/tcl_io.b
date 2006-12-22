implement TclLib;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufmod : Bufio;
Iobuf : import bufmod;

include "string.m";
	str : String;

include "tk.m";

include "tcl.m";

include "tcllib.m";

error : int;
started : int;
tclmod : ref Tcl_Core->TclData;

name2fid : array of (ref Iobuf,string,int);

valid_commands := array[] of {
		"close", 
		"eof" , 
		"file", 
		"flush",  
		"gets" , 
		"open",  
		"puts",  
		"read" , 
		"seek" , 
		"tell"  
};

init() : string {
	started=1;
	str = load String String->PATH;
	sys = load Sys Sys->PATH;
	bufmod = load Bufio Bufio->PATH;
	if (str==nil || bufmod==nil)
		return "Can't initialise IO package.";
	name2fid = array[100] of (ref Iobuf,string,int);
	stdout := bufmod->fopen(sys->fildes(1),bufmod->OWRITE);
	if (stdout==nil)
		return "cannot open stdout for writing.\n";
	name2fid[0]=(nil,"stdin",0);
	name2fid[1]=(stdout,"stdout",0);
	return nil;
}

about() : array of string{
	return valid_commands;
}
	
exec(tcl : ref Tcl_Core->TclData,argv : array of string) : (int,string) {
	tclmod=tcl;
	msg :string;
	if (!started) init();
	error=0;
	case argv[0] {
		"close" => 
			msg = do_close(argv);
			return (error,msg);
		"eof" => 
			msg = do_eof(argv);
			return (error,msg);
		"file" => 
			msg = do_nothing(argv);
			return (error,msg);				
		"flush" => 
			msg = do_nothing(argv);
			return (error,msg);
		"gets" => 
			msg = do_gets(argv);
			return (error,msg);
		"open" => 
			msg = do_open(argv);
			return (error,msg);
		"puts" => 
			msg = do_puts(argv);
			return (error,msg);
		"read" => 
			msg = do_read(argv);
			return (error,msg);
		"seek" => 
			msg = do_seek(argv);
			return (error,msg);
		"tell" => 
			msg = do_nothing(argv);
			return (error,msg);
	}
	return (1,nil);
}

do_nothing(argv : array of string) : string {
	if (len argv==0);
	return nil;
}

do_close(argv : array of string) : string {
	iob : ref Iobuf;
	name : string;
	j : int;
	iob=nil;
	if (len argv!=2)
		return notify(1,"close fileId");
	for(i:=0;i<len name2fid;i++){
		(iob,name,j)=name2fid[i];
		if (name==argv[1]) 
			break;
	}
	if (iob==nil)
		return notify(0,sys->sprint("bad file identifier \"%s\"",
						argv[1]));
	iob.flush();
	iob.close();
	iob=nil;
	name2fid[i]=(nil,"",0);
	return nil;
}

do_eof(argv : array of string) : string {
	name : string;
	j : int;
	iob : ref Iobuf;
	if (len argv!=2)
		return notify(1,"eof fileId");
	for(i:=0;i<len name2fid;i++){
		(iob,name,j)=name2fid[i];
		if (name==argv[1]) 
			return string j;
	}
	return notify(0,sys->sprint("bad file identifier \"%s\"",argv[1]));
}


do_gets(argv : array of string) : string {
	iob : ref Iobuf;
	line : string;
	if (len argv==1 || len argv > 3)
		return notify(1,"gets fileId ?varName?");
	if (argv[1]=="stdin")
		line = <- tclmod.lines;
	else{
		iob=lookup_iob(argv[1]);
		if (iob==nil)
			return notify(0,sys->sprint(
				"bad file identifier \"%s\"",argv[1]));
		line=iob.gets('\n');
	}
	if (line==nil){ 			
		set_eof(iob);
		return nil;
	}
	return line[0:len line -1];
}	

do_seek(argv : array of string) : string {
	iob : ref Iobuf;
	if (len argv < 3 || len argv > 4)
		return notify(1,"seek fileId offset ?origin?");
	iob=lookup_iob(argv[1]);
	if (iob==nil)
		return notify(0,sys->sprint(
				"bad file identifier \"%s\"",argv[1]));
	flag := Sys->SEEKSTART;
	if (len argv == 4) {
		case argv[3] {
			"SEEKSTART" =>
				flag = Sys->SEEKSTART;
			"SEEKRELA" =>
				flag = Sys->SEEKRELA;
			"SEEKEND" =>
				flag = Sys->SEEKEND;
			 * =>
				return notify(0,sys->sprint(
				"illegal access mode \"%s\"",
					argv[3]));
		}
	}
	iob.seek(big argv[2],flag);
	return nil;
}
	
do_open(argv : array of string) : string {
	flag : int;
	if (len argv==1 || len argv > 3)
		return notify(1,
			"open filename ?access? ?permissions?");
	name:=argv[1];
	if (len argv == 2)
		flag = bufmod->OREAD;
	else {
		case argv[2] {
			"OREAD" =>
				flag = bufmod->OREAD;		
			"OWRITE" =>		
				flag = bufmod->OWRITE;		
			"ORDWR"	=>	
				flag = bufmod->ORDWR;
			 * =>
				return notify(0,sys->sprint(
				"illegal access mode \"%s\"",
					argv[2]));
		}
	}
	iob := bufmod->open(name,flag);
	if (iob==nil)
		return notify(0,
			sys->sprint("couldn't open \"%s\": No" +
			      " such file or directory.",name));
	for (i:=0;i<len name2fid;i++){
		(iob2,name2,j):=name2fid[i];
		if (iob2==nil){
			name2fid[i]=(iob,"file"+string i,0);
			return "file"+string i;
		}
	}
	return notify(0,"File table full!");
}
	
do_puts(argv : array of string) : string {
	iob : ref Iobuf;
	if (len argv==1 || len argv >4)
		return notify(1,
			"puts ?-nonewline? ?fileId? string");
	if (argv[1]=="-nonewline"){
		if (len argv==2)
			return notify(1,
			"puts ?-nonewline? ?fileId? string");
		if (len argv==3)
			sys->print("%s",argv[2]);
		else{
			iob=lookup_iob(argv[2]);	
			if (iob==nil)
				return notify(0,sys->sprint(
				   "bad file identifier \"%s\"",
					argv[2]));
			iob.puts(argv[3]);
			iob.flush();
		}
	} else {
		if (len argv==2)
			sys->print("%s\n",argv[1]);
		if (len argv==3){
			iob=lookup_iob(argv[1]);	
			if (iob==nil)
				return notify(0,sys->sprint(
				   "bad file identifier \"%s\"",
					argv[1]));
			iob.puts(argv[2]+"\n");
			iob.flush();
		
		}
		if (len argv==4)
			return notify(0,sys->sprint(
			"bad argument \"%s\": should be"+
			" \"nonewline\"",argv[3]));
	}
	return nil;
}

do_read(argv : array of string) : string {
	iob : ref Iobuf;
	line :string;
	if (len argv<2 || len argv>3)
		return notify(1,
		  "read fileId ?numBytes?\" or \"read ?-nonewline? fileId");
	if (argv[1]!="-nonewline"){
		iob=lookup_iob(argv[1]);
		if (iob==nil)
			return notify(0,sys->sprint(
				"bad file identifier \"%s\"", argv[1]));
		if (len argv == 3){
			buf := array[int argv[2]] of byte;
			n:=iob.read(buf,len buf);
			if (n==0){
				set_eof(iob);
				return nil;
			}
			return string buf[0:n];
		}
		line=iob.gets('\n');
		if (line==nil) 
			set_eof(iob);
		else
			line[len line]='\n';
		return line;
	}else{
		iob=lookup_iob(argv[2]);
		if (iob==nil)
			return notify(0,sys->sprint(
				"bad file identifier \"%s\"", argv[2]));
		line=iob.gets('\n');
		if (line==nil)
			set_eof(iob);
		return line;
	}
}



		

		


notify(num : int,s : string) : string {
	error=1;
	case num{
		1 =>
			return sys->sprint(
			"wrong # args: should be \"%s\"",s);
		* =>
			return s;
	}
}


lookup_iob(s:string) : ref Iobuf{
	iob : ref Iobuf;
	name : string;
	j : int;
	for(i:=0;i<len name2fid;i++){
		(iob,name,j)=name2fid[i];
		if (name==s)
			break;
	}
	if (i==len name2fid)
		return nil;
	return iob;
}

set_eof(iob : ref Iobuf) {
	iob2 : ref Iobuf;
	name : string;
	j : int;
	for(i:=0;i<len name2fid;i++){
		(iob2,name,j)=name2fid[i];
		if (iob==iob2)
			break;
	}
	if (i!=len name2fid)
		name2fid[i]=(iob,name,1);
	return;
}

