implement Tcl_Stack;

include "sys.m";
	sys : Sys;
include "draw.m";
include "tk.m";
include "tcl.m";
include "tcllib.m";
include "utils.m";
	htab: Str_Hashtab;
	shtab: Sym_Hashtab;
Hash: import htab;
SHash: import shtab;

sframe : adt {
	simple : ref Hash;
	assoc  : array of (ref Hash,string);
	symtab : ref SHash;
};

stack := array[100] of sframe;
curlevel : int;
nlev : int;

init() {
	curlevel=-1;
	nlev=-1;
	htab = load Str_Hashtab Str_Hashtab->PATH;
	shtab = load Sym_Hashtab Sym_Hashtab->PATH;
	sys = load Sys Sys->PATH;
	if (htab == nil){
		sys->print("can't load Hashtab %r\n");
		exit;
	}
	if (shtab == nil){
		sys->print("can't load Sym_Hashtab %r\n");
		exit;
	}
}

newframe() : (ref Hash,array of (ref Hash,string),ref SHash) {
	nv := htab->alloc(101);
	av := array[100] of (ref Hash,string);
	st := shtab->alloc(101);
	#sys->print("New frame, curlevel is %d\n",curlevel);
	push (nv,av,st);
	return (nv,av,st);
}

level() : int {
	return curlevel;
}

move(lev :int) : int {
	if (lev <0 || lev>nlev)
		return 0;
	curlevel=lev;
	return 1;
}

push(sv : ref Hash, av : array of (ref Hash,string), st :ref SHash){
	curlevel++;
	nlev++;
	stack[curlevel].simple=sv;
	stack[curlevel].assoc=av;
	stack[curlevel].symtab=st;
}

pop() : (ref Hash,array of (ref Hash,string),ref SHash) {
	s:=stack[curlevel].simple;
	a:=stack[curlevel].assoc;
	t:=stack[curlevel].symtab;
	stack[curlevel].simple=nil;
	stack[curlevel].assoc=nil;
	stack[curlevel].symtab=nil;
	curlevel--;
	nlev--;
	return (s,a,t);
}

examine(lev : int) : (ref Hash,array of (ref Hash,string),ref SHash) {
	if (lev <0 || lev > nlev)
		return (nil,nil,nil);
	return (stack[lev].simple,stack[lev].assoc,stack[lev].symtab);
}

dump() {
	for (i:=0;i<100;i++){
		if (stack[i].simple!=nil){
			sys->print("simple table at %d\n",i);
			for (j:=0;j<101;j++)
				if (stack[i].simple.tab[j]!=nil){
					sys->print("\tH_link at %d\n",j);
					l:=stack[i].simple.tab[j];
					while(l!=nil){
					    sys->print("\tname [%s], value [%s]\n",
						(hd l).name,(hd l).val);
					    l=tl l;
					}
				}
		}
		if (stack[i].assoc!=nil){
			sys->print("assoc table at %d\n",i);
			for(j:=0;j<100;j++){
				(rh,s):=stack[i].assoc[j];
				if (rh!=nil){
					sys->print(
					      "\tassoc array at %d, name %s\n",
							j,s);
					for (k:=0;k<101;k++)
						if (rh.tab[k]!=nil){
							sys->print(
							 "\t\tH_link at %d\n",k);
							l:=rh.tab[k];
							while(l!=nil){
					    			sys->print(
						     "\t\tname [%s], value [%s]\n",
						       (hd l).name,(hd l).val);
					    			l=tl l;
							}
						}

				}
			}
		}
		if (stack[i].symtab!=nil){
			sys->print("Symbol table at %d\n",i);
			for (j:=0;j<101;j++)
				if (stack[i].symtab.tab[j]!=nil){
					sys->print("\tH_link at %d\n",j);
					l:=stack[i].symtab.tab[j];
					while(l!=nil){
					    sys->print("\tname [%s], alias [%s], "+
						"value [%d]\n",(hd l).name,
							(hd l).alias,(hd l).val);
					    l=tl l;
					}
				}
		}
	}
}

