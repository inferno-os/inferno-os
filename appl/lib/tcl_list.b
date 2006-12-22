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

include "utils.m";
	utils : Tcl_Utils;


error : int;

DEF,DEC,INT : con iota;
valid_commands:= array[] of {
		"concat" , 
		"join" , 
		"lindex" , 
		"linsert" , 
		"list" , 
		"llength" ,
		"lrange" , 
		"lreplace" , 
		"lsearch" , 
		"lsort" , 
		"split"
};

about() : array of string {
	return valid_commands;
}

exec(tcl : ref Tcl_Core->TclData,argv : array of string) : (int,string) {
	if (tcl.context==nil);
	str = load String String->PATH;
	sys = load Sys Sys->PATH;
	utils = load Tcl_Utils Tcl_Utils->PATH;
	if (str==nil || utils==nil)
		return (1,"Can't load modules\n");
	case argv[0] {
		"concat" => 
			return (error,do_concat(argv,0));					
		"join" => 
			return (error,do_join(argv));
		"lindex" => 
			return (error,do_lindex(argv));		 
		"linsert" => 
			return (error,do_linsert(argv));
		"list" => 
			return (error,do_concat(argv,1));
		"llength" =>
			return (error,do_llength(argv));					
		"lrange" => 
			return (error,do_lrange(argv));
		"lreplace" => 
			return (error,do_lreplace(argv));
		"lsearch" => 
			return (error,do_lsearch(argv));
		"lsort" => 
			return (error,do_lsort(argv));
		"split" =>
			return (error,do_split(argv));
	}
	return (1,nil);
}

spaces(s : string) : int{
	if (s==nil) return 1;
	for(i:=0;i<len s;i++)
		if (s[i]==' ' || s[i]=='\t') return 1;
	return 0;
}
	

sort(a: array of string, key: int): array of string {
	m: int;
	n := len a;
	for(m = n; m > 1; ) {
		if(m < 5)
			m = 1;
		else
			m = (5*m-1)/11;
		for(i := n-m-1; i >= 0; i--) {
			tmp := a[i];
			for(j := i+m; j <= n-1 && greater(tmp, a[j], key); j += m)
				a[j-m] = a[j];
			a[j-m] = tmp;
		}
	}
	return a;
}

greater(x, y: string, sortkey: int): int {
	case (sortkey) {
	DEF => return(x > y);
	DEC => return(x < y);
	INT => return(int x > int y);
	}
	return 0;
}

# from here on are the commands in alphabetical order...

# turns an array into a string with spaces between the elements.
# in braces is non-zero, the elements will be enclosed in braces.
do_concat(argv : array of string, braces : int) : string {
	retval :string;
	retval=nil;
	for(i:=1;i<len argv;i++){
		flag:=0;
		if (spaces(argv[i])) flag=1;
		if (braces && flag) retval[len retval]='{';
		retval += argv[i];
		if (braces && flag) retval[len retval]='}';
		retval[len retval]=' ';
	}
	if (retval!=nil)
		retval=retval[0:len retval-1];
	return retval;
}

do_join(argv : array of string) : string {
	retval : string;
	if (len argv ==1 || len argv >3)
		return notify(1,"join list ?joinString?");
	if (len argv == 2) 
		return argv[1];
	if (argv[1]==nil) return nil;
	arr := utils->break_it(argv[1]);
	for (i:=0;i<len arr;i++){
		retval+=arr[i];
		if (i!=len arr -1)
			retval+=argv[2];
	}
	return retval;
}

do_lindex(argv : array of string) : string {
	if (len argv != 3)
		return notify(1,"lindex list index");
	(num,rest):=str->toint(argv[2],10);
	if (rest!=nil)
		return notify(2,argv[2]);
	arr:=utils->break_it(argv[1]);
	if (num>=len arr)
		return nil;
	return arr[num];
}

do_linsert(argv : array of string) : string {
	if (len argv < 4){
		return notify(1,
			"linsert list index element ?element ...?");
	}
	(num,rest):=str->toint(argv[2],10);
	if (rest!=nil)
		return notify(2,argv[2]);
	arr:=utils->break_it(argv[1]);
	narr := array[len arr + len argv - 2] of string;
	narr[0]="do_concat";
	if (num==0){
		narr[1:]=argv[3:];
		narr[len argv -2:]=arr[0:];
	}else if (num>= len arr){
		narr[1:]=arr[0:];
		narr[len arr+1:]=argv[3:];
	}else{
		narr[1:]=arr[0:num];
		narr[num+1:]=argv[3:];
		narr[num+len argv -2:]=arr[num:];
	}
	return do_concat(narr,1);
}

do_llength(argv : array of string) : string {
	if (len argv !=2){
		return notify(1,"llength list");
	}
	arr:=utils->break_it(argv[1]);
	return string len arr;
}

do_lrange(argv :array of string) : string {
	beg,end : int;
	rest : string;
	if (len argv != 4)
		return notify(1,"lrange list first last");
	(beg,rest)=str->toint(argv[2],10);
	if (rest!=nil)
		return notify(2,argv[2]);
	(end,rest)=str->toint(argv[3],10);
	if (rest!=nil)
		return notify(2,argv[3]);
	if (beg <0) beg=0;
	if (end < 0) return nil;
	if (beg > end) return nil;
	arr:=utils->break_it(argv[1]);
	if (beg>len arr) return nil;
	narr:=array[end-beg+2] of string;
	narr[0]="do_concat";
	narr[1:]=arr[beg:end+1];
	return do_concat(narr,1);
}

do_lreplace(argv : array of string) : string {
	beg,end : int;
	rest : string;
	if (len argv < 3)
		return notify(1,"lreplace list "+
			"first last ?element element ...?");
	arr:=utils->break_it(argv[1]);
	(beg,rest)=str->toint(argv[2],10);
	if (rest!=nil)
		return notify(2,argv[2]);
	(end,rest)=str->toint(argv[3],10);
	if (rest!=nil)
		return notify(2,argv[3]);
	if (beg <0) beg=0;
	if (end < 0) return nil;
	if (beg > end) 
		return notify(0,
		       "first index must not be greater than second");
	if (beg>len arr) 
		return notify(1,
			"list doesn't contain element "+string beg);
	narr:=array[len arr-(end-beg+1)+len argv - 3] of string;
	narr[1:]=arr[0:beg];
	narr[beg+1:]=argv[4:];
	narr[beg+1+len argv-4:]=arr[end+1:];
	narr[0]="do_concat";
	return do_concat(narr,1);
}

do_lsearch(argv : array of string) : string {
	if (len argv!=3) 
		return notify(1,"lsearch ?mode? list pattern");
	arr:=utils->break_it(argv[1]);
	for(i:=0;i<len arr;i++)
		if (arr[i]==argv[2])
			return string i;
	return "-1";
}

do_lsort(argv : array of string) : string {
	lis : array of string;
	key : int;
	key=DEF;
	if (len argv == 1) 
		return notify(1,"lsort ?-ascii? ?-integer? ?-real?"+
			" ?-increasing? ?-decreasing?"+
			" ?-command string? list");
	for(i:=1;i<len argv;i++)
		if (argv[i][0]=='-')
			case argv[i]{
				"-decreasing" =>
					key = DEC;
				* =>
					if (len argv != i+1)
					return notify(0,sys->sprint(
					"bad switch \"%s\": must be"+
					" -ascii, -integer, -real, "+
					"-increasing -decreasing, or"+
					" -command" ,argv[i]));
			}
	lis=utils->break_it(argv[len argv-1]);
	arr:=sort(lis,key);
	narr:= array[len arr+1] of string;
	narr[0]="list";
	narr[1:]=arr[0:];
	return do_concat(narr,1);
}



do_split(argv : array of string) : string {
	arr := array[20] of string;
	narr : array of string;
	if (len argv ==1 || len argv>3)
		return notify(1,"split string ?splitChars?");
	if (len argv == 2)
		return argv[1];
	s:=argv[1];
	if (s==nil) return nil;
	if (argv[2]==nil){
		arr=array[len s+1] of string;
		for(i:=0;i<len s;i++)
			arr[i+1][len arr[i+1]]=s[i];
		arr[0]="do_concat";
		return do_concat(arr,1);
	}
	i:=1;
	while(s!=nil){
		(piece,rest):=str->splitl(s,argv[2]);
		arr[i]=piece;
		if (len rest>1)
			s=rest[1:];
		if (len rest==1) 
			s=nil;
		i++;
		if (i==len arr){
			narr=array[i+10] of string;
			narr[0:]=arr[0:];
			arr=array[i+10] of string;
			arr=narr;
		}
	}
	narr = array[i] of string;
	arr[0]="do_concat";
	narr = arr[0:i+1];
	return do_concat(narr,1);
}

notify(num : int,s : string) : string {
	error=1;
	case num{
		1 =>
			return sys->sprint(
			"wrong # args: should be \"%s\"",s);		
		2 =>
			return sys->sprint(
			"expected integer but got \"%s\"",s);
		* =>
			return s;
	}
}

