Spree: module
{
	MAXPLAYERS: con 100;
	Attribute: adt {
		name:	string;
		val:		string;
		visibility:	Sets->Set;			# set of members that can see attr
		needupdate:	Sets->Set;		# set of members that have not got an update queued
	};
	
	Attributes: adt {
		a:		array of list of ref Attribute;
		set:		fn(attr: self ref Attributes, name, val: string, vis: Sets->Set): (int, ref Attribute);
		get:		fn(attr: self ref Attributes, name: string): ref Attribute;
		new:		fn(): ref Attributes;
	};
	
	Range: adt {
		start:		int;
		end:		int;
	};
	
	Object: adt {
		id:		int;
		attrs:		ref Attributes;
		visibility:	Sets->Set;
		parentid:	int;
		children:	cyclic array of ref Object;		# not actually cyclic
		cliqueid:	int;
		objtype:	string;
	
		transfer:		fn(o: self ref Object, r: Range, dst: ref Object, i: int);
		setvisibility:	fn(o: self ref Object, visibility: Sets->Set);
		setattrvisibility:	fn(o: self ref Object, name: string, visibility: Sets->Set);
		setattr:		fn(o: self ref Object, name: string, val: string, vis: Sets->Set);
		getattr:		fn(o: self ref Object, name: string): string;
		delete:		fn(o: self ref Object);
		deletechildren:	fn(o: self ref Object, r: Range);
	};

	Rq: adt {
		pick {
		Init =>
			opts: string;
		Command =>
			member: ref Member;
			cmd: string;
		Join =>
			member: ref Member;
			cmd:	string;
			suspended: int;
		Leave =>
			member: ref Member;
		Notify =>
			srcid: int;
			cmd:	string;
		}
	};
	
	# this might also be known as a "group", as there's nothing
	# inherently clique-like about it; it's just a group of members
	# mutually creating and manipulating objects.
	Clique: adt {
		id:		int;
		fileid:	int;
		fname:	string;
		objects:	array of ref Object;
		archive:	ref Archives->Archive;
		freelist:	list of int;
		mod:	Engine;
		memberids:	Sets->Set;				# set of allocated member ids
		suspended: list of ref Member;
		request:	chan of ref Rq;
		reply:	chan of string;
		hungup:	int;
		started:	int;
		parentid:	int;
		notes:	list of (int, int, string);	# (src, dest, note)

		new:			fn(parent: self ref Clique, archive: ref Archives->Archive, owner: string): (int, string, string);	# returns (cliqueid, filename, error)
		newobject:	fn(clique: self ref Clique, parent: ref Object, visibility: Sets->Set, objtype: string): ref Object;
		start:			fn(clique: self ref Clique);
		action:		fn(clique: self ref Clique, cmd: string,
						objs: list of int, rest: string, whoto: Sets->Set);
		breakmsg:	fn(clique: self ref Clique, whoto: Sets->Set);
		show:		fn(clique: self ref Clique, member: ref Member);
		member:	fn(clique: self ref Clique, id: int): ref Member;
		membernamed:	fn(clique: self ref Clique, name: string): ref Member;
		members:	fn(clique: self ref Clique): list of ref Member;
		owner:	fn(clique: self ref Clique): string;
		hangup:	fn(clique: self ref Clique);
		fcreate:	fn(clique: self ref Clique, i: int, pq: int, d: Sys->Dir): string;
		fremove:	fn(clique: self ref Clique, i: int): string;
		notify:	fn(clique: self ref Clique, cliqueid: int, msg: string);
	};

	# a Member is involved in one clique only
	Member: adt {
		id:		int;
		cliqueid:	int;
		obj2ext:	array of int;
		ext2obj:	array of ref Object;
		freelist:	list of int;
		name:	string;
		updating:	int;
		suspended:	int;

		ext:		fn(member: self ref Member, id: int): int;
		obj:		fn(member: self ref Member, id: int): ref Object;
		del:		fn(member: self ref Member, suspend: int);
	};

	init:   fn(ctxt: ref Draw->Context, argv: list of string);
	archivenames: fn(): list of string;
	newarchivename: fn(): string;
	rand:	fn(n: int): int;
};

Engine: module {
	init:			fn(srvmod: Spree, clique: ref Spree->Clique, argv: list of string): string;
	command:	fn(member: ref Spree->Member, e: string): string;
	join:			fn(member: ref Spree->Member , e: string, suspended: int): string;
	leave:		fn(member: ref Spree->Member): int;
	notify:		fn(fromid: int, s: string);
	readfile:		fn(f: int, offset: big, count: int): array of byte;
};

Archives: module {
	PATH:	con "/dis/spree/archives.dis";
	Archive: adt {
		argv:		list of string;			# how to restart the session.
		members:	array of string;			# members involved.
		info:		list of (string, string);	# any other information.
		objects:	array of ref Spree->Object;
	};
	init:			fn(mod: Spree);
	write:		fn(clique: ref Spree->Clique, info: list of (string, string), file: string, members: Sets->Set): string;
	read:			fn(file: string): (ref Archive, string);
	readheader:	fn(file: string): (ref Archive, string);
};
