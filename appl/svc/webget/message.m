Message: module
{
	PATH:	con "/dis/svc/webget/message.dis";

	init: fn(bufio: Bufio, smod: String);

	Nameval: adt {
		name: string;
		value: string;
	};

	Msg: adt {
		prefixline: string;
		prefixbytes: array of byte;
		fields: array of Nameval;
		body: array of byte;
		bodylen: int;

		readhdr: fn(io: ref Bufio->Iobuf, withprefix: int) : (ref Msg, string);
		readbody: fn(m: self ref Msg, io: ref Bufio->Iobuf) : string;
		writemsg: fn(m: self ref Msg, io: ref Bufio->Iobuf) : string;
		header: fn(m: self ref Msg) : string;
		addhdrs: fn(m: self ref Msg, hdrs: list of Nameval);
		newmsg: fn() : ref Msg;
		fieldval: fn(m: self ref Msg, name: string) : (int, string);
		update: fn(m: self ref Msg, name, value: string);
	};
};
