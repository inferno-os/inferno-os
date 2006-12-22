Str_Hashtab : module
{
	PATH: con "/dis/lib/tcl_strhash.dis";
	
	H_link : adt{
		name : string;
		val : string;
	};

	Hash : adt {
		size : int;
		lsize : int;
		tab : array of list of H_link;
		insert : fn(h:self ref Hash,name,val: string) : int;
		dump: fn(h:self ref Hash) : string;
		find: fn(h:self ref Hash,name : string) : (int,string);
		delete: fn(h:self ref Hash,name : string) : int;
	};

	alloc : fn(size : int) : ref Hash;
};

Int_Hashtab : module
{
	PATH: con "/dis/lib/tcl_inthash.dis";
	
	H_link : adt{
		name : string;
		val : int;
	};

	IHash : adt {
		size : int;
		tab : array of list of H_link;
		insert : fn(h:self ref IHash,name: string,val : int) : int;
		find: fn(h:self ref IHash,name : string) : (int,int);
		delete: fn(h:self ref IHash,name : string) : int;
	};

	alloc : fn(size : int) : ref IHash;
};

Sym_Hashtab : module
{
	PATH: con "/dis/lib/tcl_symhash.dis";
	
	H_link : adt{
		name : string;
		alias : string;
		val : int;
	};

	SHash : adt {
		size : int;
		tab : array of list of H_link;
		insert : fn(h:self ref SHash,name,alias: string,val : int) : int;
		find: fn(h:self ref SHash,name : string) : (int,int,string);
		delete: fn(h:self ref SHash,name : string) : int;
	};

	alloc : fn(size : int) : ref SHash;
};

Mod_Hashtab : module
{
	PATH: con "/dis/lib/tcl_modhash.dis";
	
	H_link : adt{
		name : string;
		val : TclLib;
	};

	MHash : adt {
		size : int;
		tab : array of list of H_link;
		insert : fn(h:self ref MHash,name: string,val : TclLib) 
								: int;
		dump: fn(h:self ref MHash) : string;
		find: fn(h:self ref MHash,name : string) : (int,TclLib);
		delete: fn(h:self ref MHash,name : string) : int;
	};

	alloc : fn(size : int) : ref MHash;
};

Tcl_Stack : module
{
	PATH: con "/dis/lib/tcl_stack.dis";
	
	level : fn() : int;
	examine : fn(lev : int) : 
	      (ref Str_Hashtab->Hash,array of (ref Str_Hashtab->Hash,string),ref Sym_Hashtab->SHash);
	push  : fn(s:ref Str_Hashtab->Hash, 
			a:array of (ref Str_Hashtab->Hash,string),t: ref Sym_Hashtab->SHash);
	init : fn();
	move : fn(lev :int) : int;
	newframe : fn() : 
	      (ref Str_Hashtab->Hash,array of (ref Str_Hashtab->Hash,string),ref Sym_Hashtab->SHash);
	pop   : fn() : (ref Str_Hashtab->Hash,
			array of (ref Str_Hashtab->Hash,string),ref Sym_Hashtab->SHash);
	dump : fn();
};



Tcl_Utils : module
{
	PATH: con "/dis/lib/tcl_utils.dis";
	break_it : fn(s : string) : array of string;
	arr_resize : fn(argv : array of string) : array of string;
};

