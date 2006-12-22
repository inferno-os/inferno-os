implement Mod_Hashtab;

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

alloc(size : int) : ref MHash {
	h : MHash;
	t : list of H_link;
	t=nil;
	h.size= size;
	h.tab = array[size]  of {* => t};
	return ref h;
}

MHash.dump(h : self ref MHash) : string {
	retval :string;
	for (i:=0;i<h.size;i++){
		tmp:=(h.tab)[i];
		for(;tmp!=nil;tmp = tl tmp){
			if ((hd tmp).name!=nil){
				retval+=(hd tmp).name;
				retval[len retval]=' ';
			}
		}
	}
	if (retval!=nil)
		retval=retval[0:len retval-1];
	return retval;
}

		

MHash.insert(h : self ref MHash,name: string, val:TclLib) : int {
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

MHash.find(h : self ref MHash,name : string) : (int, TclLib){
	hash,flag : int;
	nlist : list of H_link;
	retval : TclLib;
	retval=nil;
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

MHash.delete(h : self ref MHash,name : string) : int {
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

