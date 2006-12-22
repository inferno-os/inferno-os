Allow: module {
	PATH:	con "/dis/spree/lib/allow.dis";
	init:		fn(srvmod: Spree, g: ref Spree->Clique);
	add:		fn(tag: int, member: ref Spree->Member, action: string);
	del:		fn(tag: int, member: ref Spree->Member);
	action:	fn(member: ref Spree->Member, cmd: string): (string, int, list of string);
	archive:	fn(archiveobj: ref Object);
	unarchive: fn(archiveobj: ref Object);
};
