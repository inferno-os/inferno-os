Cookiesrv: module {
	PATH: con "/dis/charon/cookiesrv.dis";

	Client: adt {
		fd: ref Sys->FD;
		set: fn(c: self ref Client,host, path, cookie: string);
		getcookies: fn(c: self ref Client, host, path: string, secure: int): string;
	};

	# save interval is in minutes
	start: fn(path: string, saveinterval: int): ref Client;
};
