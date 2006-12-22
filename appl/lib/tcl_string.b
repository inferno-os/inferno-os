implement TclLib;

include "sys.m";
	sys: Sys;
include "draw.m";
include "tk.m";
include "bufio.m";
	bufmod : Bufio;
Iobuf : import bufmod;

include "string.m";
	str : String;
include "tcl.m";
include "tcllib.m";

error : int;
started : int;
valid_commands:=array[] of {"format","string"};

about() : array of string{
	return valid_commands;
}

init(){
	started=1;
	sys=load Sys Sys->PATH;
}

exec(tcl : ref Tcl_Core->TclData,argv : array of string) : (int,string) {
	if (tcl.context==nil);
	if (!started) init();
	error=0;
	str=load String String->PATH;
	if (str==nil)
		return(1,"String module not loaded.");
	if (len argv==1 && argv[0]=="string")
		return (error,
			notify(1,"string option arg ?arg ...?"));
	case argv[0]{
		"format" =>
			return (error,do_format(argv));
		"string" =>
			return (error,do_string(argv));
	}
	return (1,nil);
}


do_string(argv : array of string) : string{
	case argv[1]{
		"compare" =>
			if (len argv == 4){
				i:= - (argv[2]<argv[3])+ (argv[2]>argv[3]);
				return string i;
			}
			return notify(1,
			     "string compare string1 string2");
		"first" =>
			return nil;
		"last" =>
			return nil;
		"index" =>
			if (len argv == 4){
				if (len argv[2] > int argv[3])
					return argv[2][int argv[3]:int argv[3]+1];
				return nil;
			}
			return notify(1,
			     "string index string charIndex");
		"length" =>
			if (len argv==3)
				return string len argv[2];
			return notify(1,"string length string");
		"match" =>
			return nil;
		"range" =>
			if (len argv==5){
				end :int;
				if (argv[4]=="end") 
					end=len argv[2];
				else
					end=int argv[4];
				if (end>len argv[2]) end=len argv[2];
				beg:=int argv[3];
				if (beg<0) beg=0;
				if (beg>end)
					return nil;
				return argv[2][int argv[3]:end];
			}
			return notify(1,
			     "string range string first last");
		"tolower" =>
			if (len argv==3)
				return str->tolower(argv[2]);
			return notify(1,"string tolower string");
		"toupper" =>
			if (len argv==3)
				return str->tolower(argv[2]);
			return notify(1,"string tolower string");
		"trim" =>
			return nil;
		"trimleft" =>
			return nil;
		"trimright" =>
			return nil;
		"wordend" =>
			return nil;
		"wordstart" =>
			return nil;
	}
	return nil;
}

do_format(argv : array of string) : string {
	retval,num1,num2,rest,curfm : string;
	i,j : int;
	if (len argv==1)
		return notify(1,
			"format formatString ?arg arg ...?");
	j=2;
	i1:=-1;
	i2:=-1;
	(retval,rest)=str->splitl(argv[1],"%");
	do {
		(curfm,rest)=str->splitl(rest[1:],"%");
		i=0;
		num1="";
		num2="";
		if (curfm[i]=='-'){
			num1[len num1]=curfm[i];
			i++;
		}
		while(curfm[i]>='0' && curfm[i]<='9'){
			num1[len num1]=curfm[i];
			i++;
		}
		if (num1!="")
			(i1,nil) = str->toint(num1,10);
		if (curfm[i]=='.'){
			i++;
			while(curfm[i]>='0' && curfm[i]<='9'){
				num2[len num2]=curfm[i];
				i++;
			}
			(i2,nil) = str->toint(num2,10);
		} else {
			i2=i1;
			i1=-1;
		}
		case curfm[i] {
			's' =>
				retval+=print_string(i1,i2,argv[j]);
			'd' => 
				retval+=print_int(i1,i2,argv[j]);
			'f' =>
				retval+=print_float(i1,i2,argv[j]);
			'x' =>
				retval+=print_hex(i1,i2,argv[j]);
		}
		j++;
	} while (rest!=nil && j<len argv);
	return retval;
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

print_string(i1,i2 : int, s : string) : string {
	retval : string;
	if (i1==-1 && i2==-1)
		retval=sys->sprint("%s",s);
	if (i1==-1 && i2!=-1)
		retval=sys->sprint("%*s",i1,s);
	if (i1!=-1 && i2!=-1)
		retval=sys->sprint("%*.*s",i1,i2,s);
	if (i1!=-1 && i2==-1)
		retval=sys->sprint("%.*s",i2,s);	
	return retval;
}

print_int(i1,i2 : int, s : string) : string {
	retval,ret2 : string;
	n : int;
	(num,nil):=str->toint(s,10);
	width:=1;
	i:=num;
	while((i/=10)!= 0) width++;
	if (i2 !=-1 && width<i2) width=i2;
	for(i=0;i<width;i++)
		retval[len retval]='0';
	while(width!=0){
		retval[width-1]=num%10+'0';
		num/=10;
		width--;
	}
	if (i1 !=-1 && i1>i){
		for(n=0;n<i1-i;n++)
			ret2[len ret2]=' ';
		ret2+=retval;
		retval=ret2;
	}
	return retval;
}


print_float(i1,i2 : int, s : string) : string {
	r:= real s;
	retval:=sys->sprint("%*.*f",i1,i2,r);
	return retval;
}

print_hex(i1,i2 : int, s : string) : string {
	retval,ret2 : string;
	n : int;
	(num,nil):=str->toint(s,10);
	width:=1;
	i:=num;
	while((i/=16)!= 0) width++;
	if (i2 !=-1 && width<i2) width=i2;
	for(i=0;i<width;i++)
		retval[len retval]='0';
	while(width!=0){
		n=num%16;
		if (n>=0 && n<=9)
			retval[width-1]=n+'0';
		else
			retval[width-1]=n+'a'-10;
		num/=16;
		width--;
	}
	if (i1 !=-1 && i1>i){
		for(n=0;n<i1-i;n++)
			ret2[len ret2]=' ';
		ret2+=retval;
		retval=ret2;
	}
	return retval;
}
