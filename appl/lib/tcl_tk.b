implement TclLib;

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str : String;

include "tk.m";
	tk: Tk;

include	"tkclient.m";
	tkclient: Tkclient;

include "tcl.m";

include "tcllib.m";

error,started : int;
w_cfg := array[] of {
	"pack .Wm_t -side top -fill x", 
	"update",
};

tclmod : ref Tcl_Core->TclData;

windows := array[100] of (string, ref Tk->Toplevel, chan of string);

valid_commands:= array[] of {
		"bind" , "bitmap" , "button" ,
		"canvas" , "checkbutton" , "destroy" ,
		"entry" , "focus", "frame" , "grab", "image" , "label" ,
		"listbox" ,"lower", "menu" , "menubutton" ,
		"pack" , "radiobutton" , "raise", "scale" ,
		"scrollbar" , "text" , "update" ,
		"toplevel" , "variable"
};

about() : array of string {
	return valid_commands;
}

init() : string {
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient==nil || str==nil || tk==nil)
		return "Not Initialised";
	# set up Draw context
	tkclient->init();
	started=1;
	return nil;
}	

exec(tcl : ref Tcl_Core->TclData,argv : array of string) : (int,string) {
	retval : string;
	retval="";
	han,whan : ref Tk->Toplevel;
	whan=nil;
	msg : string;
	c : chan of string;
	msg=nil;
	error=0;
	tclmod=tcl;
	if (!started) 
		if (init()!=nil)
			return (1,"Can't Initialise TK");
	if (argv[0][0]!='.')
		case argv[0] {
			"destroy" =>
				for (j:=1;j<len argv;j++){
					(msg,han)=sweepthru(argv[j]);
					if (msg==nil){
						if (argv[j][0]=='.')
							argv[j]=argv[j][1:];
						for(i:=0;i<100;i++){
							(retval,nil,c)=windows[i];
							if (retval==argv[1]){
								c <-= "exit";
								break;
							}
						}
					}
					else
						msg=tkcmd(whan,"destroy "+msg);
				}
				return (error,msg);	
			"bind" or "bitmap" or "button" or
			"canvas" or "checkbutton" or "entry" or 
			"focus" or "frame" or "grab" or
			"image" or "label" or "listbox" or "lower" or
			"menu" or "menubutton" or "pack" or 
			"radiobutton" or "raise" or "scale" or
			"scrollbar" or "text" or "update" or 
			"variable" =>
					; # do nothing
			"toplevel" =>
				msg=do_toplevel(argv);
				return (error,msg);
			* =>
				return (0,"Unknown");
		}
	# so it's a tk-command ... replace any -command with
	# a send on the tcl channel.
	if (argv[0]=="bind")
		argv[3]="{send Tcl_Chan "+argv[3]+"}";
	for (i:=0;i<len argv;i++){
		(argv[i],han)=sweepthru(argv[i]);
		if (han!=nil) whan=han;
		if (argv[i]!="-tcl")
			retval+=argv[i];
		if (i+1<len argv &&
			(argv[i]=="-command" || argv[i]=="-yscrollcommand"
			|| argv[i]=="-tcl" || argv[i]=="-xscrollcommand"))
			argv[i+1]="{send Tcl_Chan "+argv[i+1]+"}";
		if (argv[i]!="-tcl")
			retval[len retval]=' ';
	}
	retval=retval[0:len retval -1];
	if (tclmod.debug==1)
		sys->print("Sending [%s] to tkcmd.\n",retval);
	msg=tkcmd(whan,retval);
	if (msg!="" && msg[0]=='!')
		error=1;
	return (error,msg);
}

	
sweepthru(s: string) : (string,ref Tk->Toplevel) {
	han : ref Tk->Toplevel;
	ret : string;
	if (s=="" || s=="." || s[0]!='.')
		return (s,nil);
	(wname,rest):=str->splitl(s[1:],".");
	for (i:=0;i<len windows;i++){
		(ret,han,nil)=windows[i];
		if (ret==wname) 
			break;
	}
	if (i==len windows)
		return (s,nil);
	return (rest,han);
}
		
do_toplevel(argv : array of string): string
{
	name : string;
	whan : ref Tk->Toplevel;
	if (len argv!=2)
		return notify(1,"toplevel name");
	if (argv[1][0]=='.')
		argv[1]=argv[1][1:];
	for(i:=0;i<len windows;i++){
		(name,whan,nil)=windows[i];
		if(whan==nil || name==argv[1])
			break;
	}
	if (i==len windows)
		return notify(0,"Too many top level windows");
	if (name==argv[1])
		return notify(0,argv[1]+" is already a window name in use.");

	(top, menubut) := tkclient->toplevel(tclmod.context, "", argv[1], Tkclient->Appl);
	whan = top;

	windows[i]=(argv[1],whan,menubut);
	if (tclmod.debug==1)
		sys->print("creating window %d, name %s, handle %ux\n",i,argv[1],whan);
	cmd := chan of string;
	tk->namechan(whan, cmd, argv[1]);
	for(i=0; i<len w_cfg; i++)
		tk->cmd(whan, w_cfg[i]);
	tkclient->onscreen(whan, nil);
	tkclient->startinput(whan, "kbd"::"ptr"::nil);
	stop := chan of int;
	spawn tkclient->handler(whan, stop);
	spawn menulisten(whan,menubut, stop);
	return nil;
}


menulisten(t : ref Tk->Toplevel, menubut : chan of string, stop: chan of int) {
	for(;;) alt {
	menu := <-menubut =>
		if(menu == "exit"){
			for(i:=0;i<len windows;i++){
			(name,whan,nil):=windows[i];
				if(whan==t)
				break;
			}
			if (i!=len windows)
				windows[i]=("",nil,nil);
			stop <-= 1;
			exit;
		}
		tkclient->wmctl(t, menu);
	}
}

tkcmd(t : ref Tk->Toplevel, cmd: string): string {
	if (len cmd ==0 || tclmod.top==nil) return nil;
	if (t==nil){
		 t=tclmod.top;
		#sys->print("Sending to WishPad\n");
	}
	s := tk->cmd(t, cmd);
	tk->cmd(t,"update");
	return s;
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
