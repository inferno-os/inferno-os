Messages:  module
{
	PATH:	con "/dis/collab/lib/messages.dis";

	Msg: adt {
		from:	cyclic ref User;
		data:		array of byte;
		next:		cyclic ref Msg;
	};

	Msglist: adt {
		tail:		ref Msg;
		readers:	list of (ref User, ref Readreq);

		new:		fn(): ref Msglist;
		flushfid:	fn(nil: self ref Msglist, fid: int);
		flushtag:	fn(nil: self ref Msglist, tag: int);
		wait:		fn(nil: self ref Msglist, u: ref User, r: ref Readreq);
		write:	fn(nil: self ref Msglist, m: ref Msg): list of (ref User, ref Readreq);
		queue:	fn(nil: self ref Msglist): ref Msg;
	};

	Readreq: adt {
		tag:	int;
		fid:	int;
		count:	int;
		offset:	big;
	};

	User: adt {
		id:	int;
		fid:	int;
		name:	string;
		queue:	cyclic ref Msg;

		new:	fn(fid: int, name: string): ref User;
		initqueue:	fn(nil: self ref User, msgs: ref Msglist);
		read:	fn(nil: self ref User): ref Msg;
	};

	init:	fn();
};
