IPattr: module
{

	PATH: con "/dis/lib/ipattr.dis";

	Netattr: adt {
		name:	string;
		pairs:	list of ref Attrdb->Attr;
		net:	IP->IPaddr;
		mask:	IP->IPaddr;
	};

	init:	fn(attrdb: Attrdb, ip: IP);

	dbattr:	fn(s: string): string;
	findnetattr:	fn(db: ref Attrdb->Db, attr: string, val: string, rattr: string): (string, string);
	findnetattrs:	fn(db: ref Attrdb->Db, attr: string, val: string, rattrs: list of string): (list of (IP->IPaddr, list of ref Netattr), string);
	valueof:	fn(l: list of ref Netattr, attr: string): list of string;
	netvalueof:	fn(l: list of ref Netattr, attr: string, ip: IP->IPaddr): list of string;
};
