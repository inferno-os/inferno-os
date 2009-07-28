implement Cache;

include "sys.m";
	sys : Sys;

include "bufio.m";
	bufio : Bufio;
Iobuf : import bufio;

include "lock.m";
	locks: Lock;
	Semaphore: import locks;

dbg_log : ref Sys->FD;

include "cache.m";

HASHSIZE : con 1019;

lru ,cache_size : int; # lru link, and maximum size of cache.
cur_size, cur_tag : int; # current size of cache and current number.

lock: ref Semaphore;

Cache_link : adt{
	name : string; 			# name of file
	contents : array of byte; 	# contents
	length : int; 			# length of file
	qid:Sys->Qid;			
	tag : int;
};

tab := array[HASHSIZE] of list of Cache_link;

hashasu(key : string,n : int): int
{
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


insert(name: string, ctents: array of byte , length : int, qid:Sys->Qid) : int
{
	tmp : Cache_link;
	hash : int;
	lock.obtain();
	hash = hashasu(name,HASHSIZE);
	if (dbg_log!=nil){
		sys->fprint(dbg_log,"current size is %d, adding %s\n", cur_size,name);
	}
	while (cur_size+length > cache_size)
		throw_out();
	tmp.name =name;
	tmp.contents = ctents;
	tmp.length = length;
	tmp.qid = qid;
	tmp.tag = cur_tag;
	cur_size+=length;
	cur_tag++;
	if (cur_tag<0) cur_tag=0;
	tab[hash]= tmp :: tab[hash];
	lock.release();
	return 1;
}

find(name : string, qid:Sys->Qid) : (int, array of byte)
{
	hash,flag,stale : int;
	nlist : list of Cache_link;
	retval : array of byte;
	flag=0;
	nlist=nil;
	retval=nil;
	stale=0;
	lock.obtain();
	hash = hashasu(name,HASHSIZE);
	tmp:=tab[hash];
	for(;tmp!=nil;tmp = tl tmp){
		link:=hd tmp;
		if (link.name==name){
			if(link.qid.path==qid.path && link.qid.vers==qid.vers){
				link.tag=cur_tag;
				cur_tag++;
				flag = 1;
				retval = (hd tmp).contents;
			} else { # cache is stale
				lru--;  if(lru<0) lru = 0;
				link.tag = lru;
				stale = 1;
			}
		}
		nlist = link :: nlist;
	}
	tab[hash]=nlist;
	if (flag && (dbg_log!=nil))
		sys->fprint(dbg_log,"Found %s in cache, cur_tag is %d\n",name,cur_tag);
	if (stale){
		if (dbg_log!=nil)
			sys->fprint(dbg_log,"Stale %s in cache\n",name);
		throw_out();
	}
	lock.release();
	return (flag,retval);
}	

throw_out()
{
	nlist : list of Cache_link;
	for(i:=0;i<HASHSIZE;i++){
		tmp:=tab[i];
		for(;tmp!=nil;tmp = tl tmp)
			if ((hd tmp).tag==lru)
				break;
		if (tmp!=nil)
			break;
	}
	# now, the lru is in tab[i]...
	nlist=nil;
	if(i < len tab){
		for(;tab[i]!=nil;tab[i]=tl tab[i]){
			if ((hd tab[i]).tag==lru){
				if (dbg_log!=nil)
					sys->fprint(dbg_log,"Throwing out %s\n",(hd tab[i]).name);
				cur_size-=(hd tab[i]).length;	
				tab[i] = tl tab[i];
			}
			if (tab[i]!=nil)
				nlist = (hd tab[i]) :: nlist;
			if (tab[i]==nil) break;
		}
	}
	lru=find_lru();
	if (dbg_log!=nil)
		sys->fprint(dbg_log,"New lru is %d",lru);
	tab[i] = nlist;
}

find_lru() : int
{
	min := cur_tag;
	for(i:=0;i<HASHSIZE;i++){
		tmp:=tab[i];
		for(;tmp!=nil;tmp = tl tmp)
			if ((hd tmp).tag<min)
				min=(hd tmp).tag;
	}
	return min;
}

cache_init(log : ref Sys->FD, csize : int)
{
	n : int;
	for(n=0;n<HASHSIZE;n++)
		tab[n]= nil;
	lru=0;
	cur_size=0;
	cache_size = csize*1024;
	sys = load Sys Sys->PATH;
	locks = load Lock Lock->PATH;
	locks->init();
	lock = Semaphore.new();
	dbg_log = log;
	if (dbg_log!=nil)
		sys->fprint(dbg_log,"Cache initialised, max size is %d K\n",cache_size);
}

dump() : list of (string,int,int)
{
	retval: list of (string,int,int);
	lock.obtain();
	for(i:=0;i<HASHSIZE;i++){
		tmp:=tab[i];
		while(tmp!=nil){
			retval = ((hd tmp).name, (hd tmp).length,
					(hd tmp).tag) :: retval;
			tmp = tl tmp;
		}
	}
	lock.release();
	return retval;
}
