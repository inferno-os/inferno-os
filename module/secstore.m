Secstore: module
{
	PATH:	con "/dis/lib/secstore.dis";

	Maxfilesize: con 128*1024;	# default
	Maxmsg:	con 4096;

	init:		fn();
	privacy:	fn(): int;
	cansecstore:	fn(addr: string, user: string): int;
	mkseckey:	fn(pass: string): array of byte;
	connect:		fn(addr: string, user: string, pwhash: array of byte): (ref Dial->Connection, string, string);
	dial:		fn(addr: string): ref Dial->Connection;
	auth:		fn(conn: ref Dial->Connection, user: string, pwhash: array of byte): (string, string);
	sendpin:	fn(conn: ref Dial->Connection, pin: string): int;
	files:		fn(conn: ref Dial->Connection): list of (string, int, string, string, array of byte);
	getfile:	fn(conn: ref Dial->Connection, filename: string, maxsize: int): array of byte;
	remove:	fn(conn: ref Dial->Connection, filename: string): int;
#	putfile:	fn(conn: ref Dial->Connection, filename: string, data: array of byte,): int;
	bye:		fn(conn: ref Dial->Connection);

	mkfilekey:	fn(pass: string): array of byte;
	decrypt:	fn(a: array of byte, key: array of byte): array of byte;
#	encrypt:	fn(a: array of byte, key: array of byte): array of byte;
	erasekey:	fn(a: array of byte);

	lines:	fn(file: array of byte): list of array of byte;
};
