Plumbmsg: module
{
	PATH:	con "/dis/lib/plumbmsg.dis";

	# Message format:
	#	source application\n
	#	destination application\n
	#	working directory\n
	#	type\n
	#	properties\n
	#	nbytes\n
	#	n bytes

	Msg: adt
	{
		src:		string;
		dst:		string;
		dir:		string;
		kind:		string;
		attr:		string;
		data:		array of byte;

		# used by applications
		send: 	fn(msg: self ref Msg): int;
		recv: 	fn(): ref Msg;

		# used by plumb and send, recv
		pack: 	fn(msg: self ref Msg): array of byte;
		unpack: 	fn(b: array of byte): ref Msg;
	};

	Attr: adt
	{
		name:	string;
		val:		string;
	};

	init:	fn(doinput: int, rcvport: string, maxdata: int): int;
	shutdown:	fn();

	string2attrs:	fn(s: string): list of ref Attr;
	attrs2string:	fn(l: list of ref Attr): string;
	lookup:	fn(attrs: list of ref Attr, name: string): (int, string);
};
