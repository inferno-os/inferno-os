Registries: module {
	PATH:	con "/dis/lib/registries.dis";
	init:			fn();

	Attributes: adt {
		attrs: list of (string, string);

		get:	fn(a: self ref Attributes, attr: string): string;
		set:	fn(a: self ref Attributes, attr, val: string);
		new:	fn(attrs: list of (string, string)): ref Attributes;
	};

	Attached: adt {
		fd:			ref Sys->FD;
		signerpkhash:	string;
		localuser:		string;
		remoteuser:	string;
	};

	Service: adt {
		addr: string;			# dial this to connect to the service.
		attrs: ref Attributes;		# information about the nature of the service.

		attach:	fn(s: self ref Service, user: string, keydir: string): ref Attached;
	};

	Registered: adt {
		addr:	string;
		reg:		ref Registry;
		fd:		ref Sys->FD;
	};

	Registry: adt {
		dir:		string;
		indexfd:	ref Sys->FD;

		new:		fn(dir: string): ref Registry;
		connect:	fn(svc: ref Service, user: string, keydir: string): ref Registry;
		services:	fn(r: self ref Registry): (list of ref Service, string);
		find:		fn(r: self ref Registry, a: list of (string, string)): (list of ref Service, string);
		register:	fn(r: self ref Registry, addr: string, attrs: ref Attributes, persist: int): (ref Registered, string);
		unregister:	fn(r: self ref Registry, addr: string): string;
	};
};
