implement Messages;

#
# message queues and their users
#

include "messages.m";

clientidgen := 1;

init()
{
	clientidgen = 1;
}

Msglist.new(): ref Msglist
{
	msgs := ref Msglist;
	msgs.tail = ref Msg;	# valid Msg when .next != nil
	return msgs;
}

Msglist.queue(msgs: self ref Msglist): ref Msg
{
	return msgs.tail;
}

Msglist.wait(msgs: self ref Msglist, u: ref User, rd: ref Readreq)
{
	msgs.readers = (u, rd) :: msgs.readers;	# list reversed, but currently does not matter
}

Msglist.write(msgs: self ref Msglist, m: ref Msg): list of (ref User, ref Readreq)
{
	tail := msgs.tail;
	tail.from = m.from;
	tail.data = m.data;
	tail.next = ref Msg(nil, nil, nil);
	msgs.tail = tail.next;	# next message will be formed in tail.next
	rl := msgs.readers;
	msgs.readers = nil;
	return rl;
}

Msglist.flushtag(msgs: self ref Msglist, tag: int)
{
	rl := msgs.readers;
	msgs.readers = nil;
	for(; rl != nil; rl = tl rl){
		(nil, req) := hd rl;
		if(req.tag != tag)
			msgs.readers = hd rl :: msgs.readers;
	}
}

Msglist.flushfid(msgs: self ref Msglist, fid: int)
{
	rl := msgs.readers;
	msgs.readers = nil;
	for(; rl != nil; rl = tl rl){
		(nil, req) := hd rl;
		if(req.fid != fid)
			msgs.readers = hd rl :: msgs.readers;
	}
}

User.new(fid: int, name: string): ref User
{
	return ref User(clientidgen++, fid, name, nil);
}

User.initqueue(u: self ref User, msgs: ref Msglist)
{
	u.queue = msgs.tail;
}

User.read(u: self ref User): ref Msg
{
	if((m := u.queue).next != nil){
		u.queue = m.next;
		m = ref *m;	# copy to ensure no aliasing
		m.next = nil;
		return m;
	}
	return nil;
}
