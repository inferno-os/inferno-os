implement Tcl_Core;

# these are the outside modules, self explanatory..
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;

include "bufio.m";
	bufmod : Bufio;
Iobuf : import bufmod;

include "string.m";
	str : String;

include "tk.m";
	tk: Tk;

include	"wmlib.m";
	wmlib: Wmlib;

# these are stand alone Tcl libraries, for Tcl pieces that
# are "big" enough to be called their own.

include "tcl.m";

include "tcllib.m";

include "utils.m";
	htab: Str_Hashtab;
	mhtab : Mod_Hashtab; 
	shtab : Sym_Hashtab;
	stack : Tcl_Stack;
	utils : Tcl_Utils;

Hash: import htab;
MHash : import mhtab;
SHash : import shtab;




# global error flag and message. One day, this will be stack based..
errmsg : string;
error, mypid : int;

sproc : adt {
	name : string;
	args : string;
	script : string;
};

TCL_UNKNOWN, TCL_SIMPLE, TCL_ARRAY : con iota;

# Global vars. Simple variables, and associative arrays.
libmods : ref MHash;
proctab := array[100] of sproc;
retfl : int;
symtab : ref SHash;
nvtab : ref Hash;
avtab : array of (ref Hash,string);
tclmod : TclData;

core_commands:=array[] of {		
	"append" , "array", "break" , "continue" , "catch", "dumpstack",  
	"exit" , "expr" , "eval" ,
	"for" , "foreach" , 
	"global" , "if" , "incr" , "info", 
	"lappend" , "level" , "load" ,
	"proc" , "return" , "set" ,
	"source" ,"switch" , "time" ,
	"unset" , "uplevel", "upvar", "while" , "#" 
};
		

about() : array of string {
	return core_commands;
}
		
init(ctxt: ref Draw->Context, argv: list of string) {
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	bufmod = load Bufio Bufio->PATH;
	htab = load Str_Hashtab Str_Hashtab->PATH;
	mhtab = load Mod_Hashtab Mod_Hashtab->PATH;
	shtab = load Sym_Hashtab Sym_Hashtab->PATH;
	stack = load Tcl_Stack Tcl_Stack->PATH;
	str = load String String->PATH;
	utils = load Tcl_Utils Tcl_Utils->PATH;
	tk = load Tk Tk->PATH;
	wmlib= load Wmlib Wmlib->PATH;
	if (bufmod == nil || htab == nil || stack == nil ||
		str == nil || utils == nil || tk == nil ||
		wmlib==nil || mhtab == nil || shtab == nil){
		sys->print("can't load initial modules %r\n");
		exit;
	}	

	# get a new stack frame.
	stack->init();
	(nvtab,avtab,symtab)=stack->newframe();
	
	libmods=mhtab->alloc(101);

	# grab my pid, and set a new group to make me easy to kill.
	mypid=sys->pctl(sys->NEWPGRP, nil);

	# no default top window.
	tclmod.top=nil;
	tclmod.context=ctxt;
	tclmod.debug=0;

	# set up library modules.
	args:=array[] of {"do_load","io"};
	do_load(args);
	args=array[] of {"do_load","string"};
	do_load(args);
	args=array[] of {"do_load","calc"};
	do_load(args);
	args=array[] of {"do_load","list"};
	do_load(args);
	args=array[] of {"do_load","tk"};
	do_load(args);
	arr:=about();
	for(i:=0;i<len arr;i++)
		libmods.insert(arr[i],nil);

	# cmd line args...
	if (argv != nil)
		argv = tl argv;
	while (argv != nil) {
		loadfile(hd argv);
		argv = tl argv;
	}
	
}

set_top(win:ref Tk->Toplevel){
	tclmod.top=win;
}

clear_error(){
	error=0;
	errmsg="";
}

notify(num : int,s : string) : string {
	error=1;
	case num{
		1 =>
			errmsg=sys->sprint(
			"wrong # args: should be \"%s\"",s);
		* =>
			errmsg= s;
	}
	return errmsg;
}
			
grab_lines(new_inp,unfin: string ,lines : chan of string){
	error=0;
	tclmod.lines=lines;
	input,line : string;
	if (new_inp==nil)
		new_inp = "tcl%";
	if (unfin==nil)
		unfin = "tcl>";
	sys->print("%s ", new_inp);
	iob := bufmod->fopen(sys->fildes(0),bufmod->OREAD);
	if (iob==nil){
		sys->print("cannot open stdin for reading.\n");
		return;
	}
	while((input=iob.gets('\n'))!=nil){
		line+=input;
		if (!finished(line,0))
			sys->print("%s ", unfin);
		else{
			lines <- = line;
			line=nil;
		}
	}
}

# this is the main function. Its input is a complete (i.e. matching 
# brackets etc) tcl script, and its output is a message - if there 
# is one.
evalcmd(s: string, termchar: int) : string {
	msg : string;
	i:=0;
	retfl=0;
	if (tclmod.debug==2)
		sys->print("Entered evalcmd, s=%s, termchar=%c\n",s,termchar);
	# strip null statements..
	while((i<len s) && (s[i]=='\n' || s[i]==';')) i++;
	if (i==len s) return nil;

	# parse the script statement by statement
	for(;s!=nil;i++){
		# wait till we have a complete statement
		if (i==len s || ((s[i]==termchar || s[i]==';' || s[i]=='\n')
			&& finished(s[0:i],termchar))){
			# throw it away if its a comment...
			if (s[0]!='#')
				argv := parsecmd(s[0:i],termchar,0);
			msg = nil;			
			if (tclmod.debug==2)
				for(k:=0;k<len argv;k++)
				sys->print("argv[%d]: (%s)\n",k,argv[k]);

			# argv is now a completely parsed array of arguments
			# for the Tcl command..
			
			# find the module that the command is in and 
			# 	execute it.
			if (len argv != 0){
				mod:=lookup(argv[0]);
				if (mod!=nil){
					(error,msg)= 
					   mod->exec(ref tclmod,argv);
					if (error)
						errmsg=msg;
				} else {
					if (argv[0]!=nil && 
						argv[0][0]=='.')
						msg=do_tk(argv);
					else
						msg=exec(argv);
				}
			}

			# was there an error?
			if (error) {
				if (len argv > 0 && argv[0]!=""){
					stat : string;
					stat = "In function "+argv[0];
					if (len argv >1 && argv[1]!=""){
						stat[len stat]=' ';
						stat+=argv[1];
					}
					stat+=".....\n\t";
					errmsg=stat+errmsg;
				}
				msg=errmsg;
			}

			# we stop parsing if we hit a break, continue, return,
			# error, termchar or end of string.
			if (msg=="break" || msg=="continue" || error || retfl==1
				|| len s <= i || (len s > i && s[i]==termchar))
				return msg;

			# otherwise eat up the parsed statement and continue
			s=s[i+1:];
			i=-1;
		}
	}
	return msg;
}

				
# returns 1 if the line has matching braces, brackets and 
# double-quotes and does not end in "\\\n"
finished(s : string, termchar : int) : int {
	cb:=0;
	dq:=0;
	sb:=0;
	if (s==nil) return 1;
	if (termchar=='}') cb++;
	if (termchar==']') sb++;
	if (len s > 1 && s[len s -2]=='\\')
		return 0;
	if (s[0]=='{') cb++;
	if (s[0]=='}' && cb>0) cb--;
	if (s[0]=='[') sb++;
	if (s[0]==']' && sb>0) sb--;
	if (s[0]=='"') dq=1-dq;
	for(i:=1;i<len s;i++){
		if (s[i]=='{' && s[i-1]!='\\') cb++;
		if (s[i]=='}' && s[i-1]!='\\' && cb>0) cb--;
		if (s[i]=='[' && s[i-1]!='\\') sb++;
		if (s[i]==']' && s[i-1]!='\\' && sb>0) sb--;
		if (s[i]=='"' && s[i-1]!='\\') dq=1-dq;
	}
	return (cb==0 && sb==0 && dq==0);
}

# counts the offset till the next matching ']'
strip_to_match(s : string, ptr: int) : int {
	j :=0;
	nb:=0;
	while(j<len s){
		if (s[j]=='{')
			while (j < len s && s[j]!='}') j++;
		if (s[j]=='[') nb++;
		if (s[j]==']'){
			nb--;
			if (nb==-1) return ptr+j;
		}
		j++;
	}
	return ptr+j;
}

# returns the type of variable represented by the string s, which is
# a name.
isa(s: string) : (int,int,string) {
	found,val : int;
	name,al : string;
	curlev:=stack->level();
	if (tclmod.debug==2)
		sys->print("Called isa with %s, current stack level is %d\n",s,curlev);
	(found,nil)=nvtab.find(s);
	if (found) return (TCL_SIMPLE,curlev,s);
	for (i:=0;i<len avtab;i++){
		(nil,name)=avtab[i];
		if (name==s) return (TCL_ARRAY,curlev,s);	
	}
	if (symtab==nil)
		return (TCL_UNKNOWN,curlev,s);
	(found,val,al)=symtab.find(s);
	if (!found)
		return (TCL_UNKNOWN,curlev,s);
	(tnv,tav,nil):=stack->examine(val);
	if (tclmod.debug==2)
		sys->print("have a level %d for %s\n",val,al);
	if (tnv!=nil){
		(found,nil)=tnv.find(al);
		if (found) return (TCL_SIMPLE,val,al);
	}
	if (tav!=nil){
		for (i=0;i<len tav;i++){
			(nil,name)=tav[i];
			if (name==al) return (TCL_ARRAY,val,al);	
		}
	}	
	if (tclmod.debug==2)
		sys->print("%s not found, creating at stack level %d\n",al,val);
	return (TCL_UNKNOWN,val,al);
}

# This function only works if the string is already parsed!
# takes a var_name and returns the hash table for it and the
# name to look up. This is one of two things:
# for simple variables:
# findvar(foo) ---> (nvtab,foo)
# for associative arrays:
# findvar(foo(bar)) -----> (avtab[i],bar)
# where avtab[i].name==foo
# if create is 1, then an associative array is created upon first
# reference.
# returns (nil,error message) if there is a problem.

find_var(s : string,create : int) : (ref Hash,string) {
	rest,name,index : string;
	retval,tnv : ref Hash;
	tav : array of (ref Hash,string);
	i,tag,lev: int;
	(name,index)=str->splitl(s,"(");
	if (index!=nil){
		(index,rest)=str->splitl(index[1:],")");
		if (rest!=")")
			return (nil,"bad variable name");
	}
	(tag,lev,name) = isa(name);
	case tag {
		TCL_SIMPLE =>
			if (index!=nil)
				return (nil,"variable isn't array");
			(tnv,nil,nil)=stack->examine(lev);
			return (tnv,name);
		TCL_ARRAY =>
			if (index==nil)
				return (nil,"variable is array");
			(nil,tav,nil)=stack->examine(lev);
			for(i=0;i<len tav;i++){
				(retval,rest)=tav[i];
				if (rest==name)
					return (retval,index);
			}
			return (nil,"find_var: impossible!!");
		# if we get here, the variable needs to be
		# created.
		TCL_UNKNOWN =>
			if (!create)
				return (nil,"no such variable");
			(tnv,tav,nil)=stack->examine(lev);
			if (index==nil)
				return (tnv,name);
		
	}
	# if we get here, we are creating an associative variable in the
	# tav array.
	for(i=0;i<len tav;i++){
		(retval,rest)=tav[i];
		if (rest==nil){
			retval=htab->alloc(101);
			tav[i]=(retval,name);
			return (retval,index);	
		}
	}
	return (nil,"associative array table full!");
}

# the main parsing function, a la ousterhouts man pages. Takes a 
# string that is meant to be a tcl statement and parses it, 
# reevaluating and quoting upto the termchar character. If disable 
# is true, then whitespace is not ignored.	
parsecmd(s: string, termchar,disable: int) : array of string {
	argv:= array[200] of string;
	buf,nm,id: string;
	argc := 0;
	nc := 0;
	c :=0;
	tab : ref Hash;
	
	if (disable && (termchar=='\n' || termchar==';')) termchar=0;
   outer:
	for (i := 0; i<len s ;) {
		if ((i>0 &&s[i-1]!='\\' &&s[i]==termchar)||(s[0]==termchar))
			break;
		case int s[i] {
		' ' or '\t' or '\n' =>
			if (!disable){
				if (nc > 0) {	# end of a word?
					argv[argc++] = buf;
					buf = nil;
					nc = 0;
				}
				i++;
			}
			else 
				buf[nc++]=s[i++];
		'$' =>
			if (i>0 && s[i-1]=='\\') 
				buf[nc++]=s[i++];
			else {
				(nm,id) = parsename(s[i+1:], termchar);
				if (id!=nil)
					nm=nm+"("+id+")";
				(tab,nm)=find_var(nm,0); #don't create var!
				if (len nm > 0 && tab!=nil) {
					(found, val) := tab.find(nm);
					buf += val;
					nc += len val;
					#sys->print("Here s[i:] is (%s)\n",s[i:]);
					if(nm==id)
						while(s[i]!=')') i++;
					else
						if (s[i+1]=='{')
							while(s[i]!='}') i++;
						else
							i += len nm;
					if (nc==0 && (i==len s-1 ||
							s[i+1]==' ' || 
							s[i+1]=='\t'|| 
							s[i+1]==termchar))
						argv[argc++]=buf;
				} else {
					buf[nc++] = '$';
				}
				i++;
			}
		'{' =>
			if (i>0 && s[i-1]=='\\') 
				buf[nc++]=s[i++];
			else if (s[i+1]=='}'){
				argv[argc++] = nil;
				buf = nil;
				nc = 0;	
				i+=2;
			} else {
				nbra := 1;
				for (i++; i < len s; i++) {
					if (s[i] == '{')
						nbra++;
					else if (s[i] == '}') {
						nbra--;
						if (nbra == 0) {
							i++;
							continue outer;
						}
					}
					buf[nc++] = s[i];
				}
			}
		'[' =>
			if (i>0 && s[i-1]=='\\') 
				buf[nc++]=s[i++];
			else{
				a:=evalcmd(s[i+1:],']');
				if (error)
					return nil;
				if (nc>0){
					buf+=a;
					nc += len a;
				} else {
					argv[argc++] = a;
					buf = nil;
					nc = 0;
				}
				i++;
				i=strip_to_match(s[i:],i);
				i++;
			}
		'"' =>
			if (i>0 && s[i-1]!='\\' && nc==0){
				ans:=parsecmd(s[i+1:],'"',1);
				#sys->print("len ans is %d\n",len ans);
				if (len ans!=0){
					for(;;){
						i++;
						if(s[i]=='"' && 
							s[i-1]!='\\')
						break;
					}
					i++;
					argv[argc++] = ans[0];
				} else {
					argv[argc++] = nil;
					i+=2;
				}
				buf = nil;
				nc = 0;
			}
			else buf[nc++] = s[i++];	
		* =>
			if (s[i]=='\\'){
				c=unesc(s[i:]);
				if (c!=0){
					buf[nc++] = c;
					i+=2;
				} else {
					if (i+1 < len s && !(s[i+1]=='"'
						|| s[i+1]=='$' || s[i+1]=='{' 
						|| s[i+1]=='['))
						buf[nc++]=s[i];
					i++;
				}
				c=0;
			} else
				buf[nc++]=s[i++];
		}
	}
	if (nc > 0)	# fix up last word if present
		argv[argc++] = buf;
	ret := array[argc] of string;
	ret[0:] = argv[0:argc];
	return ret;
}

# parses a name by Tcl rules, a valid name is either $foo, $foo(bar)
# or ${foo}.
parsename(s: string, termchar: int) : (string,string) {
	ret,arr,rest: string;
	rets : array of string;
	if (len s == 0)
		return (nil,nil);
	if (s[0]=='{'){
		(ret,nil)=str->splitl(s,"}");
		#sys->print("returning [%s]\n",ret[1:]);
		return (ret[1:],nil);
	}
	loop: for (i := 0; i < len s && s[i] != termchar; i++) {
		case (s[i]) {
		'a' to 'z' or 'A' to 'Z' or '0' to '9' or '_' =>
			ret[i] = s[i];
		* =>
			break loop;
		'(' =>
			arr=ret[0:i];
			rest=s[i+1:];
			rets=parsecmd(rest,')',0);
			# should always be len 1?
			if (len rets >1)
				sys->print("len rets>1 in parsename!\n");
			return (arr,rets[0]);
		}
	}
	return (ret,nil);
}

loadfile(file :string) : string {
	iob : ref Iobuf;
	msg,input,line : string;
	if (file==nil)
		return nil;	
	iob = bufmod->open(file,bufmod->OREAD);
	if (iob==nil)
		return notify(0,sys->sprint(
			"couldn't read file \"%s\":%r",file));
	while((input=iob.gets('\n'))!=nil){
		line+=input;
		if (finished(line,0)){
			# put in a return catch here...
			line = prepass(line);
			msg=evalcmd(line,0);
			if (error) return errmsg;
			line=nil;
		}
	}
	return msg;
}


#unescapes a string. Can do better.....
unesc(s: string) : int {
	c: int;
	if (len s == 1) return 0;
	case s[1] {
		'a'=>   c = '\a';
		'n'=>	c = '\n';
		't'=>	c = '\t';
		'r'=>	c = '\r';
		'b'=>	c = '\b';
		'\\'=>	c = '\\';
		'}' =>  c = '}';
		']' =>  c=']';
		# do hex and octal.
		* =>	c = 0;
	}
	return c;
}

# prepass a string and replace "\\n[ \t]*" with ' '
prepass(s : string) : string {
	for(i := 0; i < len s; i++) {
		if(s[i] != '\\')
			continue;
		j:=i;
		if (s[i+1] == '\n') {
			s[j]=' ';  
			i++;
			while(i<len s && (s[i]==' ' || s[i]=='\t'))
				i++;
			if (i==len s)
				s = s[0:j];
			else
				s=s[0:j]+s[i+1:];
		i=j;
		}
	}
	return s;
}

exec(argv : array of string) : string {
	msg : string;
	if (argv[0]=="")
		return nil;
	case (argv[0]) {		
		"append" =>
			msg= do_append(argv);
		"array" =>
			msg= do_array(argv);
		"break" or "continue" =>
			return argv[0];
		"catch" =>
			msg=do_catch(argv);
		"debug" =>
			msg=do_debug(argv);
		"dumpstack" =>
			msg=do_dumpstack(argv);
		"exit" =>
			do_exit();
		"expr" =>
			msg = do_expr(argv);
		"eval" =>
			msg = do_eval(argv);
		"for" =>
			msg = do_for(argv);
		"foreach" =>
			msg = do_foreach(argv);
		"format" =>
			msg = do_string(argv);
		"global" =>
			msg = do_global(argv);
		"if" =>
			msg = do_if(argv);
		"incr" =>
			msg = do_incr(argv);
		"info" =>
			msg = do_info(argv);
		"lappend" =>
			msg = do_lappend(argv);
		"level" =>
			msg=sys->sprint("Current Stack "+
			    "level is %d",
				stack->level());
		"load" =>
			msg=do_load(argv);
		"proc" =>
			msg=do_proc(argv);
		"return" =>
			msg=do_return(argv);
			retfl =1;
		"set" =>
			msg = do_set(argv);
		"source" =>
			msg = do_source(argv);
		"string" =>
			msg = do_string(argv);
		"switch" => 
			msg = do_switch(argv);
		"time" =>
			msg=do_time(argv);
		"unset" =>
			msg = do_unset(argv);
		"uplevel" =>
			msg=do_uplevel(argv);
		"upvar" =>
			msg=do_upvar(argv);		
		"while" =>
			msg = do_while(argv);
		"#" => 
			msg=nil;
		* =>	
			msg = uproc(argv);
	}
	return msg;
}

# from here on is the list of commands, alpahabetised, we hope.

do_append(argv :array of string) : string {
	tab : ref Hash;
	if (len argv==1 || len argv==2)
		 return notify(1,
			"append varName value ?value ...?");
	name := argv[1];
	(tab,name)=find_var(name,1);
	if (tab==nil)
		return notify(0,name);
	(found, val) := tab.find(name);
	for (i:=2;i<len argv;i++)
		val+=argv[i];
	tab.insert(name,val);	
	return val;
}

do_array(argv : array of string) : string {
	tab : ref Hash;
	name : string;
	flag : int;
	if (len argv!=3)
		return notify(1,"array [names, size] name");
	case argv[1] {
		"names" =>
			flag=1;
		"size" =>
			flag=0;
		* =>
			return notify(0,"expexted names or size, got "+argv[1]);
			
	}
	(tag,lev,al) := isa(argv[2]);
	if (tag!=TCL_ARRAY)
		return notify(0,argv[2]+" isn't an array");
	(nil,tav,nil):=stack->examine(lev);
	for (i:=0;i<len tav;i++){
		(tab,name)=tav[i];
		if (name==al) break;
	}
	if (flag==0)
		return string tab.lsize;
	return tab.dump();
}

do_catch(argv : array of string) : string {
	if (len argv==1 || len argv > 3)
		return notify(1,"catch command ?varName?");
	msg:=evalcmd(argv[1],0);
	if (len argv==3 && error){
		(tab,name):=find_var(argv[2],1);
		if (tab==nil)
			return notify(0,name);
		tab.insert(name, msg);
	}
	ret:=string error;
	error=0;
	return ret;
}

do_debug(argv : array of string) : string {
	add : string;
	if (len argv!=2)
		return notify(1,"debug");
	(i,rest):=str->toint(argv[1],10);
	if (rest!=nil)
		return notify(0,"Expected integer and got "+argv[1]);
	tclmod.debug=i;
	if (tclmod.debug==0)
		add="off";
	else
		add="on";
	return "debugging is now "+add+" at level"+ string i;
} 

do_dumpstack(argv : array of string) : string {
	if (len argv!=1)
		return notify(1,"dumpstack");
	stack->dump();
	return nil;
}
	
do_eval(argv : array of string) : string {
	eval_str : string;
	for(i:=1;i<len argv;i++){
		eval_str += argv[i];
		eval_str[len eval_str]=' ';
	}
	return evalcmd(eval_str[0:len eval_str -1],0);
}

do_exit(){
	kfd := sys->open("#p/"+string mypid+"/ctl", sys->OWRITE);
	if(kfd == nil) 
		sys->print("error opening pid %d (%r)\n",mypid);
	sys->fprint(kfd, "killgrp");
	exit;
}



do_expr(argv : array of string) : string {
	retval : string;
	for (i:=1;i<len argv;i++){
		retval+=argv[i];
		retval[len retval]=' ';
	}
	retval=retval[0: len retval -1];
	argv=parsecmd(retval,0,0);
	cal:=lookup("calc");
	(err,ret):= cal->exec(ref tclmod,argv);
	if (err) return notify(0,ret);
	return ret;
}


do_for(argv : array of string) : string {
	if (len argv!=5)
		return notify(1,"for start test next command");
	test := array[] of {"expr",argv[2]};
	evalcmd(argv[1],0);
	for(;;){
		msg:=do_expr(test);
		if (msg=="Error!")
		return notify(0,sys->sprint(
			"syntax error in expression \"%s\"",
					argv[2]));
		if (msg=="0")
			return nil;
		msg=evalcmd(argv[4],0);
		if (msg=="break")
			return nil;
		if (msg=="continue"); #do nothing!
		evalcmd(argv[3],0);
		if (error)
			return errmsg;
	}
}



do_foreach(argv: array of string) : string{
	tab : ref Hash;
	if (len argv!=4)
		return notify(1,"foreach varName list command");
	name := argv[1];
	(tab,name)=find_var(name,1);
	if (tab==nil)
		return notify(0,name);
	arr:=utils->break_it(argv[2]);
	for(i:=0;i<len arr;i++){
		tab.insert(name,arr[i]);
		evalcmd(argv[3],0);
	}	
	return nil;
}



do_global(argv : array of string) : string {
	if (len argv==1)
		return notify(1,"global varName ?varName ...?");
	if (symtab==nil)
		return nil;
	for (i:=1 ; i < len argv;i++)
		symtab.insert(argv[i],argv[i],0);
	return nil;
}


	
do_if(argv : array of string) : string {
	if (len argv==1)
		return notify(1,"no expression after \"if\" argument");
	expr1 := array[] of {"expr",argv[1]};
	msg:=do_expr(expr1);
	if (msg=="Error!")
		return notify(0,sys->sprint(
			"syntax error in expression \"%s\"",
					argv[1]));
	if (len argv==2)
		return notify(1,sys->sprint(
			"no script following \""+
					"%s\" argument",msg));
	if (msg=="0"){
		if (len argv>3){
			if (argv[3]=="else"){
				if (len argv==4)
					return notify(1,
					"no script"+
				" following \"else\" argument");
				return evalcmd(argv[4],0);
			}
			if (argv[3]=="elseif"){
				argv[3]="if";
				return do_if(argv[3:]);
			}
		}
		return nil;
	}
	return evalcmd(argv[2],0);
}

do_incr(argv :array of string) : string {
	num,xtra : int;
	rest :string;
	tab : ref Hash;
	if (len argv==1)
		return notify(1,"incr varName ?increment?");
	name := argv[1];
	(tab,name)=find_var(name,0); #doesn't create!!
	if (tab==nil)
		return notify(0,name);
	(found, val) := tab.find(name);
	if (!found)
		return notify(0,sys->sprint("can't read \"%s\": "
			+"no such variable",name));
	(num,rest)=str->toint(val,10);
	if (rest!=nil)
		return notify(0,sys->sprint(
			"expected integer but got \"%s\"",val));
	if (len argv == 2){	
		num+=1;
		tab.insert(name,string num);
	}
	if (len argv == 3) {
		val = argv[2];
		(xtra,rest)=str->toint(val,10);
		if (rest!=nil)
			return notify(0,sys->sprint(
				"expected integer but got \"%s\""
							,val));
		num+=xtra;
		tab.insert(name, string num);
	} 
	return string num;
}

do_info(argv : array of string) : string {
	if (len argv==1)
		return notify(1,"info option ?arg arg ...?");
	case argv[1] {
		"args" =>
			return do_info_args(argv,0);
		"body" =>
			return do_info_args(argv,1); 
		"commands" =>
			return do_info_commands(argv);
		"exists" =>
			return do_info_exists(argv);
		"procs" =>
			return do_info_procs(argv);

	}
	return sys->sprint(
	"bad option \"%s\": should be args, body, commands, exists, procs",
			argv[1]);
}

do_info_args(argv : array of string,body :int) : string { 
	name: string;
	s : sproc;
	if (body)
		name="body";
	else
		name="args";
	if (len argv!=3)
		return notify(1,"info "+name+" procname");
	for(i:=0;i<len proctab;i++){
		s=proctab[i];
		if (s.name==argv[2])
			break;
	}
	if (i==len proctab)
		return notify(0,argv[2]+" isn't a procedure.");
	if (body)
		return s.script;
	return s.args;
}
	
do_info_commands(argv : array of string) : string { 
	if (len argv==1 || len argv>3)
		return notify(1,"info commands [pattern]");
	return libmods.dump();
}		

do_info_exists(argv : array of string) : string { 
	name, index : string;
	tab : ref Hash;
	if (len argv!=3)
		return notify(1,"info exists varName");
	(name,index)=parsename(argv[2],0);
	(i,nil,nil):=isa(name);
	if (i==TCL_UNKNOWN)
		return "0";
	if (index==nil)
		return "1";
	(tab,name)=find_var(argv[2],0);
	if (tab==nil)
		return "0";
	(found, val) := tab.find(name);
	if (!found)
		return "0";
	return "1";	
	
}

do_info_procs(argv : array of string) : string { 
	if (len argv==1 || len argv>3)
		return notify(1,"info procs [pattern]");
	retval : string;
	for(i:=0;i<len proctab;i++){
		s:=proctab[i];
		if (s.name!=nil){
			retval+=s.name;
			retval[len retval]=' ';
		}
	}
	return retval;			
}
	
do_lappend(argv : array of string) : string{
	tab : ref Hash;
	retval :string;
	retval=nil;
	if (len argv==1 || len argv==2)
		return notify(1,
			"lappend varName value ?value ...?");
	name := argv[1];
	(tab,name)=find_var(name,1);
	if (tab==nil)
		return notify(0,name);
	(found, val) := tab.find(name);
	for(i:=2;i<len argv;i++){
		flag:=0;
		if (spaces(argv[i])) flag=1;
		if (flag) retval[len retval]='{';
		retval += argv[i];
		if (flag) retval[len retval]='}';
		retval[len retval]=' ';
	}
	if (retval!=nil)
		retval=retval[0:len retval-1];	
	if (val!=nil)
		retval=val+" "+retval;
	tab.insert(name,retval);	
	return retval;
}

spaces(s : string) : int{
	if (s==nil) return 1;
	for(i:=0;i<len s;i++)
		if (s[i]==' ' || s[i]=='\t') return 1;
	return 0;
}

do_load(argv : array of string) : string {
	# look for a dis library to load up, then
	# add to library array.
	if (len argv!=2)
		return notify(1,"load libname");
	fname:="/dis/lib/tcl_"+argv[1]+".dis";
	mod:= load TclLib fname;
	if (mod==nil)
		return notify(0,
			sys->sprint("Cannot load %s",fname));
	arr:=mod->about();
	for(i:=0;i<len arr;i++)
		libmods.insert(arr[i],mod);
	return nil;
}
	
	
do_proc(argv : array of string) : string {
	if (len argv != 4)
		return notify(1,"proc name args body");
	for(i:=0;i<len proctab;i++)
		if (proctab[i].name==nil || 
			proctab[i].name==argv[1]) break;
	if (i==len proctab)
		return notify(0,"procedure table full!");
	proctab[i].name=argv[1];
	proctab[i].args=argv[2];
	proctab[i].script=argv[3];
	return nil;
}

do_return(argv : array of string) : string {
	if (len argv==1)
		return nil;
	# put in options here.....
	return argv[1];
}
	
do_set(argv : array of string) : string {
	tab : ref Hash;
	if (len argv == 1 || len argv > 3)
		return notify(1,"set varName ?newValue?");
	name := argv[1];
	(tab,name)=find_var(name,1);
	if (tab==nil)
		return notify(0,name);
	(found, val) := tab.find(name);
	if (len argv == 2)
		if (!found)
			val = notify(0,sys->sprint(
				"can't read \"%s\": "
				+"no such variable",name));
	if (len argv == 3) {
		val = argv[2];
		tab.insert(name, val);
	} 
	return val;
}

do_source(argv : array of string) : string {
	if (len argv !=2)
		return notify(1,"source fileName");
	return loadfile(argv[1]);
}

do_string(argv : array of string) : string {
	stringmod := lookup("string");
	if (stringmod==nil)
		return notify(0,sys->sprint(
		"String Package not loaded (%r)"));
	(err,retval):= stringmod->exec(ref tclmod,argv);
	if (err) return notify(0,retval);
	return retval;
}

do_switch(argv : array of string) : string {
	i:=0;
	arr : array of string;
	if (len argv < 3)
		return notify(1,"switch "
			+"?switches? string pattern body ... "+
			"?default body?\"");
	if (len argv == 3)
		arr=utils->break_it(argv[2]);
	else 
		arr=argv[2:];
	if (len arr % 2 !=0)
		return notify(0,
			"extra switch pattern with no body");
	for (i=0;i<len arr;i+=2)
		if (argv[1]==arr[i])
			break;
	if (i==len arr){
		if (arr[i-2]=="default")
			return evalcmd(arr[i-1],0);
		else return nil;
	}
	while (i<len arr && arr[i+1]=="-") i+=2;
	return evalcmd(arr[i+1],0);
}	

do_time(argv : array of string) : string {
	rest : string;
	end,start,times : int;
	if (len argv==1 || len argv>3)
		return notify(1,"time command ?count?");
	if (len argv==2)
		times=1;
	else{
		(times,rest)=str->toint(argv[2],10);
		if (rest!=nil)
			return notify(0,sys->sprint(
				"expected integer but got \"%s\"",argv[2]));
	}
	start=sys->millisec();
	for(i:=0;i<times;i++)
		evalcmd(argv[1],0);
	end=sys->millisec();
	r:= (real end - real start) / real times;
	return sys->sprint("%g milliseconds per iteration", r);
}

do_unset(argv : array of string) : string {
	tab : ref Hash;
	name: string;
	if (len argv == 1)
		return notify(1,"unset "+
			"varName ?varName ...?");
	for(i:=1;i<len argv;i++){
		name = argv[i];
		(tab,name)=find_var(name,0);
		if (tab==nil)
			return notify(0,sys->sprint("can't unset \"%s\": no such" +
					" variable",name));
		tab.delete(name);

	}
	return nil;
}

do_uplevel(argv : array of string) : string {
	level: int;
	rest,scr : string;
	scr=nil;
	exact:=0;
	i:=1;
	if (len argv==1)
		return notify(1,"uplevel ?level? command ?arg ...?");
	if (len argv==2)
		level=-1;
	else {
		lev:=argv[1];
		if (lev[0]=='#'){
			exact=1;
			lev=lev[1:];
		}
		(level,rest)=str->toint(lev,10);
		if (rest!=nil){
			i=2;	
			level =-1;
		}
	}
	oldlev:=stack->level();
	if (!exact)
		level+=oldlev;
	(tnv,tav,sym):=stack->examine(level);
	if (tnv==nil && tav==nil)
		return notify(0,"bad level "+argv[1]);
	if (tclmod.debug==2)
		sys->print("In uplevel, current level is %d, moving to level %d\n",
				oldlev,level);
	stack->move(level);
	oldav:=avtab;
	oldnv:=nvtab;
	oldsym:=symtab;
	avtab=tav;
	nvtab=tnv;
	symtab=sym;
	for(;i<len argv;i++)
		scr=scr+argv[i]+" ";
	msg:=evalcmd(scr[0:len scr-1],0);
	avtab=oldav;
	nvtab=oldnv;
	symtab=oldsym;
	ok:=stack->move(oldlev);
	if (tclmod.debug==2)
		sys->print("Leaving uplevel, current level is %d, moving back to"+
				" level %d,move was %d\n",
				level,oldlev,ok);
	return msg;
}
				
do_upvar(argv : array of string) : string {
	level:int;
	rest:string;
	i:=1;
	exact:=0;
	if (len argv<3 || len argv>4)
		return notify(1,"upvar ?level? ThisVar OtherVar");
	if (len argv==3)
		level=-1;
	else {
		lev:=argv[1];
		if (lev[0]=='#'){
			exact=1;
			lev=lev[1:];
		}
		(level,rest)=str->toint(lev,10);
		if (rest!=nil){
			i=2;	
			level =-1;
		}
	}
	if (!exact)
		level+=stack->level();
	symtab.insert(argv[i],argv[i+1],level);
	return nil;
}	
				
do_while(argv : array of string) : string {
	if (len argv!=3)
		return notify(1,"while test command");
	for(;;){
		expr1 := array[] of {"expr",argv[1]};
		msg:=do_expr(expr1);
		if (msg=="Error!")
			return notify(0,sys->sprint(
			"syntax error in expression \"%s\"",
					argv[1]));
		if (msg=="0")
			return nil;
		evalcmd(argv[2],0);
		if (error)
			return errmsg;
	}
}

uproc(argv : array of string) : string {
	cmd,add : string;
	for(i:=0;i< len proctab;i++)
		if (proctab[i].name==argv[0])
			break;
	if (i==len proctab)
		return notify(0,sys->sprint("invalid command name \"%s\"",
				argv[0]));
	# save tables
	# push a newframe
	# bind args to arguments
	# do cmd
	# pop frame
	# return msg

	# globals are supported, but upvar and uplevel are not!

	arg_arr:=utils->break_it(proctab[i].args);
	j:=len arg_arr;
	if (len argv < j+1 && arg_arr[j-1]!="args"){
		j=len argv-1;
		return notify(0,sys->sprint(
			"no value given for"+
			" parameter \"%s\" to \"%s\"",
			arg_arr[j],proctab[i].name));
	}
	if ((len argv > j+1) && arg_arr[j-1]!="args")
		return notify(0,"called "+proctab[i].name+
					" with too many arguments");
	oldavtab:=avtab;
	oldnvtab:=nvtab;
	oldsymtab:=symtab;
	(nvtab,avtab,symtab)=stack->newframe();
	for (j=0;j< len arg_arr-1;j++){
		cmd="set "+arg_arr[j]+" {"+argv[j+1]+"}";
		evalcmd(cmd,0);
	}
	if (len arg_arr>j && arg_arr[j] != "args") {
		cmd="set "+arg_arr[j]+" {"+argv[j+1]+"}";
		evalcmd(cmd,0);
	}
	else {
		if (len arg_arr > j) {
			if (j+1==len argv)
				add="";
			else
				add=argv[j+1];
			cmd="set "+arg_arr[j]+" ";
			arglist:="{"+add+" ";
			j++;
			while(j<len argv-1) {
				arglist+=argv[j+1];
				arglist[len arglist]=' ';
				j++;
			}
			arglist[len arglist]='}';
			cmd+=arglist;
			evalcmd(cmd,0);
		}
	}
	msg:=evalcmd(proctab[i].script,0);
	stack->pop();
	avtab=oldavtab;
	nvtab=oldnvtab;
	symtab=oldsymtab;
	#sys->print("Error is %d, msg is %s\n",error,msg);
	return msg;
}
		
do_tk(argv : array of string) : string {
	tkpack:=lookup("button");
	(err,retval):= tkpack->exec(ref tclmod,argv);
	if (err) return notify(0,retval);
	return retval;
}


lookup(s : string) : TclLib {
	(found,mod):=libmods.find(s);
	if (!found)
		return nil;
	return mod;
}
