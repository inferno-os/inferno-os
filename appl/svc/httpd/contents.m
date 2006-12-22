Contents: module
{
	PATH:		con	"/dis/svc/httpd/contents.dis";

	Content: adt{
		generic: string;
		specific: string;
		q: real;
	};
	
	contentinit: fn(log : ref Sys->FD);
	mkcontent: fn(specific,generic : string): ref Content;
	uriclass:  fn(name : string): (ref Content, ref Content);
	checkcontent: fn(me: ref Content,oks :list of ref Content, 
			clist : string): int;
};
