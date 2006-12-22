implement Redirect;

include "sys.m";
	sys : Sys;

include "bufio.m";
	bufio : Bufio;
Iobuf : import bufio; 

include "string.m";	
	str : String;

include "redirect.m";

HASHSIZE : con 1019;


Redir: adt{
	pat, repl : string;
};

tab := array[HASHSIZE] of list of Redir;


hashasu(key : string,n : int): int
{
        i,h : int;
	i=0;
	h=0;
        while(i<len key){
                h = 10*h + key[i];
		h%= n;
		i++;
	}
        return h;
}

insert(pat, repl : string)
{
	hash := hashasu(pat,HASHSIZE);
	tab[hash]= Redir(pat, repl) :: tab[hash];
}

redirect_init(file : string)
{
	sys = load Sys Sys->PATH;
	line : string;
	flist : list of string;
	n : int;
	bb : ref Iobuf;
	for(n=0;n<HASHSIZE;n++)
		tab[n]= nil; 
	stderr := sys->fildes(2);
	bufio = load Bufio Bufio->PATH;	
	if (bufio==nil){
		sys->fprint(stderr,"redirect: cannot load %s: %r\n", Bufio->PATH);
		raise "fail:bad module";
	}
	str = load String String->PATH;	
	if (str==nil){
		sys->fprint(stderr,"redirect: cannot load %s: %r\n", String->PATH);
		raise "fail:bad module";
	}
	bb = bufio->open(file,bufio->OREAD);
	if (bb==nil)
		return;
	while((line = bb.gets('\n'))!=nil){
		line = line[0:len line -1]; #chop newline 
		if (str->in('#',line)){
			(line,nil) = str->splitl(line, "#");
			if (line!=nil){
				n = len line;
				while(line[n]==' '||line[n]=='\t') n--; 
					 # and preceeding blanks 
				line = line[0:n];
			}
		}
		if (line!=nil){
			(n,flist)=sys->tokenize(line,"\t ");
			if (n==2)
				insert(hd flist,hd tl flist);
		}
	}
	
}

lookup(pat : string):  ref Redir
{
	srch : list of Redir;
	tmp :  Redir;
	hash : int;
	hash = hashasu(pat,HASHSIZE);
	for(srch = tab[hash]; srch!=nil; srch = tl srch){
		tmp =  hd srch;
		if(tmp.pat==nil)
			return nil;
		if(pat==tmp.pat)
			return ref tmp;
	}
	return nil;
}


redirect(path : string): string {
	redir :  ref Redir;
	newpath, oldp : string;
	s : int;
	if((redir = lookup(path))!=nil)
		if(redir.repl==nil)
			return nil;
		else
			return redir.repl;
	for(s = len path - 1; s>0; s--){
		if(path[s]=='/'){
			oldp = path[s+1:];
			path = path[0:s];	
			if((redir = lookup(path))!=nil){
				if(redir.repl!=nil)
					newpath=sys->sprint("%s/%s",
						redir.repl,oldp);
				else
					newpath = nil;
				path = path+"/"+oldp;
				return newpath;
			}
			path = path+"/"+oldp;
		}
	}
	return nil;
}
