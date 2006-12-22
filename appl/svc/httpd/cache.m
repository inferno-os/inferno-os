Cache : module
{
	PATH: con "/dis/svc/httpd/cache.dis";

	cache_init: fn(log : ref Sys->FD,  size : int);
	insert : fn(name: string, ctents: array of byte, length : int, qid:Sys->Qid) : int;
	find: fn(name : string, qid:Sys->Qid) : (int,array of byte);
	dump : fn() : list of (string,int,int);
};
