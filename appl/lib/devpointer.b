implement Devpointer;

include "sys.m";
	sys: Sys;

include "draw.m";
	Pointer: import Draw;

include "devpointer.m";

init()
{
	sys = load Sys Sys->PATH;
}

reader(file: string, posn: chan of ref Pointer, pid: chan of (int, string))
{
	if(file == nil)
		file = "/dev/pointer";
	dfd := sys->open(file, sys->OREAD);
	if(dfd == nil){
		if(pid != nil){
			pid <-= (-1, sys->sprint("cannot open %s: %r", file));
			return;
		}
	}
	if(pid != nil)
		pid <-= (sys->pctl(0, nil), nil);
	b:= array[Size] of byte;
	while((n := sys->read(dfd, b, len b)) == Size)
		posn <-= bytes2ptr(b);
}

bytes2ptr(b: array of byte): ref Pointer
{
	if(len b < Size || int b[0] != 'm')
		return nil;
	x := int string b[1:13];
	y := int string b[13:25];
	but := int string b[25:37];
	msec := int string b[37:49];
	return ref Pointer (but, (x, y), msec);
}

ptr2bytes(p: ref Pointer): array of byte
{
	if(p == nil)
		return nil;
	return sys->aprint("m%11d %11d %11d %11ud ", p.xy.x, p.xy.y, p.buttons, p.msec);
}

srv(c: chan of ref Pointer, f: ref Sys->FileIO)
{
	ptrq := ref Ptrqueue;
	dummy := chan of (int, int, int, Sys->Rread);
	sys = load Sys Sys->PATH;

	for(;;){
		r := dummy;
		if(ptrq.nonempty())
			r = f.read;
		alt{
		p := <-c =>
			if(p == nil)
				exit;
			ptrq.put(p);
		(nil, n, nil, rc) := <-r =>
			if(rc != nil){
				alt{
				rc <-= (ptr2bytes(ptrq.get()), nil) =>;
				* =>;
				}
			}
		(nil, nil, nil, rc) := <-f.write =>
			if(rc != nil)
				rc <-= (0, "read only");
		}
	}
}

Ptrqueue.put(q: self ref Ptrqueue, s: ref Pointer)
{
	if(q.last != nil && s.buttons == q.last.buttons)
		*q.last = *s;
	else{
		q.t = s :: q.t;
		q.last = s;
	}
}

Ptrqueue.get(q: self ref Ptrqueue): ref Pointer
{
	s: ref Pointer;
	h := q.h;
	if(h == nil){
		for(t := q.t; t != nil; t = tl t)
			h = hd t :: h;
		q.t = nil;
	}
	if(h != nil){
		s = hd h;
		h = tl h;
		if(h == nil)
			q.last = nil;
	}
	q.h = h;
	return s;
}
Ptrqueue.peek(q: self ref Ptrqueue): ref Pointer
{
	s: ref Pointer;
	if (q.h == nil && q.t == nil)
		return s;
	t := q.last;
	s = q.get();
	q.h = s :: q.h;
	q.last = t;
	return s;
}
Ptrqueue.nonempty(q: self ref Ptrqueue): int
{
	return q.h != nil || q.t != nil;
}
