implement Sym_Hashtab;

include "sys.m";
include "draw.m";
include "tk.m";
include "tcl.m";
include "tcllib.m";
include "utils.m";


hashasu(key : string,n : int): int{
        i, h : int;
	h=0;
	i=0;
        while(i<len key){
                h = 10*h + key[i];
		h = h%n;
		i++;
	}
        return h%n;
}

alloc(size : int) : ref SHash {
	h : SHash;
	t : list of H_link;
	t=nil;
	h.size= size;
	h.tab = array[size]  of {* => t};
	return ref h;
}


SHash.insert(h : self ref SHash,name,alias: string,val:int) : int {
	link : H_link;
	hash,found : int;
	nlist : list of H_link;
	nlist=nil;
	found=0;
	hash = hashasu(name,h.size);
	tmp:=(h.tab)[hash];
	for(;tmp!=nil;tmp = tl tmp){
		link=hd tmp;
		if (link.name==name){
			found=1;
			link.val = val;
			link.alias = alias;
		}
		nlist = link :: nlist;
	}
	if (!found){
		link.name=name;
		link.val=val;
		link.alias = alias;
		(h.tab)[hash]= link :: (h.tab)[hash];
	}else
		(h.tab)[hash]=nlist;
	return 1;
}

SHash.find(h : self ref SHash,name : string) : (int, int,string){
	hash,flag : int;
	nlist : list of H_link;
	al : string;
	retval:=0;
	flag=0;
	nlist=nil;
	hash = hashasu(name,h.size);
	tmp:=(h.tab)[hash];
	for(;tmp!=nil;tmp = tl tmp){
		link:=hd tmp;
		if ((hd tmp).name==name){
			flag = 1;
			retval = (hd tmp).val;
			al = (hd tmp).alias;
		}
		nlist = link :: nlist;
	}
	(h.tab)[hash]=nlist;
	return (flag,retval,al);
}	

SHash.delete(h : self ref SHash,name : string) : int {
	hash,flag : int;
	nlist : list of H_link;
	flag=0;
	nlist=nil;
	hash = hashasu(name,h.size);
	tmp:=(h.tab)[hash];
	for(;tmp!=nil;tmp = tl tmp){
		link:=hd tmp;
		if (link.name==name)
			flag = 1;
		else
			nlist = link :: nlist;
	}
	(h.tab)[hash]=nlist;
	return flag;
}

