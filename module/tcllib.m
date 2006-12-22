TclLib : module
{
	exec : fn(tcl : ref Tcl_Core->TclData,argv : array of string) : 
			(int,string);
	about : fn() : array of string;
};
