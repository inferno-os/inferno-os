implement Plumbmsg;

include "sys.m";
	sys: Sys;

include "plumbmsg.m";

input: ref Sys->FD;
port: ref Sys->FD;
portname: string;
maxdatasize: int;

init(doinput: int, rcvport: string, maxdata: int): int
{
	sys = load Sys Sys->PATH;

	if(!doinput && rcvport == nil)	# server, not client
		return 1;
	input = sys->open("/chan/plumb.input", Sys->OWRITE);
	if(input == nil)
		return -1;
	if(rcvport == nil)	# sending messages but never receiving them
		return 1;
	port = sys->open("/chan/plumb."+rcvport, Sys->OREAD);
	if(port == nil){
		input = nil;
		return -1;
	}
	maxdatasize = maxdata;
	portname = rcvport;
	msg := ref Msg;
	msg.src = portname;
	msg.dst = "plumb";
	msg.kind = "text";
	msg.data = array of byte "start";
	if(msg.send() < 0){
		port = nil;
		input = nil;
		return -1;
	}
	return 1;
}

shutdown()
{
	msg := ref Msg;
	msg.src = portname;
	msg.dst = "plumb";
	msg.kind = "text";
	msg.data = array of byte "stop";
	msg.send();
}

Msg.send(msg: self ref Msg): int
{
	hdr :=
		msg.src+"\n"+
		msg.dst+"\n"+
		msg.dir+"\n"+
		msg.kind+"\n"+
		msg.attr+"\n"+
		string len msg.data+"\n";
	ahdr := array of byte hdr;
	b := array[len ahdr+len msg.data] of byte;
	b[0:] = ahdr;
	b[len ahdr:] = msg.data;
	return sys->write(input, b, len b);
}

Msg.recv(): ref Msg
{
	b := array[maxdatasize+1000] of byte;
	n := sys->read(port, b, len b);
	if(n <= 0)
		return nil;
	return Msg.unpack(b[0:n]);
}

Msg.unpack(b: array of byte): ref Msg
{
	(hdr, data) := unpack(b, 6);
	if(hdr == nil)
		return nil;

	msg := ref Msg;
	msg.src = hdr[0];
	msg.dst = hdr[1];
	msg.dir = hdr[2];
	msg.kind = hdr[3];
	msg.attr = hdr[4];
	msg.data = data;

	return msg;
}

Msg.pack(msg: self ref Msg): array of byte
{
	hdr :=
		msg.src+"\n"+
		msg.dst+"\n"+
		msg.dir+"\n"+
		msg.kind+"\n"+
		msg.attr+"\n"+
		string len msg.data+"\n";
	ahdr := array of byte hdr;
	b := array[len ahdr+len msg.data] of byte;
	b[0:] = ahdr;
	b[len ahdr:] = msg.data;
	return b;
}

# unpack message from array of bytes.  last string in message
# is number of bytes in data portion of message
unpack(b: array of byte, ns: int): (array of string, array of byte)
{
	i := 0;
	a := array[ns] of string;
	for(n:=0; n<ns; n++){
		(i, a[n]) = unpackstring(b, i);
		if(i < 0)
			return (nil, nil);
	}
	nb := int a[ns-1];
	if((len b)-i != nb){
		sys->print("unpack: bad message format: wrong nbytes\n");
		return (nil, nil);
	}
	# copy data so b can be reused or freed
	data := array[nb] of byte;
	data[0:] = b[i:];
	return (a, data);
}

unpackstring(b: array of byte, i: int): (int, string)
{
	starti := i;
	while(i < len b){
		if(b[i] == byte '\n')
			return (i+1, string b[starti:i]);
		i++;
	}
	return (-1, nil);
}

string2attrs(s: string): list of ref Attr
{
	(nil, pairs) := sys->tokenize(s, "\t");
	if(pairs == nil)
		return nil;
	attrs: list of ref Attr;
	while(pairs != nil){
		pair := hd pairs;
		pairs = tl pairs;
		a := ref Attr;
		for(i:=0; i<len pair; i++)
			if(pair[i] == '='){
				a.name = pair[0:i];
				if(++i < len pair)
					a.val = pair[i:];
				break;
			}
		attrs = a :: attrs;
	}
	return attrs;
}

attrs2string(l: list of ref Attr): string
{
	s := "";
	while(l != nil){
		a := hd l;
		l = tl l;
		if(s == "")
			s = a.name + "=" + a.val;
		else
			s += "\t" + a.name + "=" + a.val;
	}
	return s;
}

lookup(attrs: list of ref Attr, name: string): (int, string)
{
	while(attrs != nil){
		a := hd attrs;
		attrs = tl attrs;
		if(a.name == name)
			return (1, a.val);
	}
	return (0, nil);
}
