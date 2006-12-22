implement Str_Hashtab;

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

alloc(size : int) : ref Hash {
	h : Hash;
	t : list of H_link;
	t=nil;
	h.size= size;
	h.lsize=0;
	h.tab = array[size]  of {* => t};
	return ref h;
}

Hash.dump(h : self ref Hash) : string {
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

Hash.insert(h : self ref Hash,name,val: string) : int {
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
		h.lsize++;
		link.name=name;
		link.val=val;
		(h.tab)[hash]= link :: (h.tab)[hash];
	}else
		(h.tab)[hash]=nlist;
	return 1;
}

Hash.find(h : self ref Hash,name : string) : (int, string){
	hash,flag : int;
	nlist : list of H_link;
	retval : string;
	flag=0;
	nlist=nil;
	retval=nil;
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

Hash.delete(h : self ref Hash,name : string) : int {
	hash,flag : int;
	nlist : list of H_link;
	retval : string;
	flag=0;
	nlist=nil;
	retval=nil;
	hash = hashasu(name,h.size);
	tmp:=(h.tab)[hash];
	for(;tmp!=nil;tmp = tl tmp){
		link:=hd tmp;
		if (link.name==name){
			flag = 1;
			h.lsize--;
		}else
			nlist = link :: nlist;
	}
	(h.tab)[hash]=nlist;
	return flag;
}

