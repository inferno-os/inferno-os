implement Int_Hashtab;

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

alloc(size : int) : ref IHash {
	h : IHash;
	t : list of H_link;
	t=nil;
	h.size= size;
	h.tab = array[size]  of {* => t};
	return ref h;
}


IHash.insert(h : self ref IHash,name: string,val:int) : int {
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
		}
		nlist = link :: nlist;
	}
	if (!found){
		link.name=name;
		link.val=val;
		(h.tab)[hash]= link :: (h.tab)[hash];
	}else
		(h.tab)[hash]=nlist;
	return 1;
}

IHash.find(h : self ref IHash,name : string) : (int, int){
	hash,flag : int;
	nlist : list of H_link;
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
		}
		nlist = link :: nlist;
	}
	(h.tab)[hash]=nlist;
	return (flag,retval);
}	

IHash.delete(h : self ref IHash,name : string) : int {
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

