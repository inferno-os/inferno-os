implement Bufio;

include "sys.m";
	sys: Sys;

include "bufio.m";

UTFself:	con 16r80;	# ascii and UTF sequences are the same (<)
Maxrune:	con 8;	# could probably be Sys->UTFmax
Bufsize:	con Sys->ATOMICIO;

Filler: adt
{
	iobuf:	ref Iobuf;
	fill:	BufioFill;
	next:	cyclic ref Filler;
};

fillers:	ref Filler;

create(filename: string, mode, perm: int): ref Iobuf
{
	if (sys == nil)
		sys = load Sys Sys->PATH;
	if ((fd := sys->create(filename, mode, perm)) == nil)
		return nil;
	return ref Iobuf(fd, array[Bufsize+Maxrune] of byte, 0, 0, 0, big 0, big 0, mode, mode);
}

open(filename: string, mode: int): ref Iobuf
{
	if (sys == nil)
		sys = load Sys Sys->PATH;
	if ((fd := sys->open(filename, mode)) == nil)
		return nil;
	return ref Iobuf(fd, array[Bufsize+Maxrune] of byte, 0, 0, 0, big 0, big 0, mode, mode);
}

fopen(fd: ref Sys->FD, mode: int): ref Iobuf
{
	if (sys == nil)
		sys = load Sys Sys->PATH;
	if ((filpos := sys->seek(fd, big 0, 1)) < big 0)
		filpos = big 0;
	return ref Iobuf(fd, array[Bufsize+Maxrune] of byte, 0, 0, 0, filpos, filpos, mode, mode);
}

sopen(input: string): ref Iobuf
{
	return aopen(array of byte input);
}

aopen(b: array of byte): ref Iobuf
{
	if (sys == nil)
		sys = load Sys Sys->PATH;
	return ref Iobuf(nil, b, 0, len b, 0, big 0, big 0, OREAD, OREAD);
}

readchunk(b: ref Iobuf): int
{
	if (b.fd == nil){
		if ((f := filler(b)) != nil){
			if ((n := f.fill->fill(b)) == EOF)
				nofill(b);
			return n;
		}
		return EOF;
	}
	if (b.filpos != b.bufpos + big b.size) {
		s := b.bufpos + big b.size;
		if (sys->seek(b.fd, s, 0) != s)
			return ERROR;
		b.filpos = s;
	}
	i := len b.buffer - b.size - 1;
	if(i > Bufsize)
		i = Bufsize;
	if ((i = sys->read(b.fd, b.buffer[b.size:], i)) <= 0) {
		if(i < 0)
			return ERROR;
		return EOF;
	}
	b.size += i;
	b.filpos += big i;
	return i;
}

writechunk(b: ref Iobuf): int
{
	err := (b.fd == nil);
	if (b.filpos != b.bufpos) {
		if (sys->seek(b.fd, b.bufpos, 0) != b.bufpos)
			err = 1;
		b.filpos = b.bufpos;
	}
	if ((size := b.size) > Bufsize)
		size = Bufsize;
	if (sys->write(b.fd, b.buffer, size) != size)
		err = 1;
	b.filpos += big size;
	b.size -= size;
	if (b.size) {
		b.dirty = 1;
		b.buffer[0:] = b.buffer[Bufsize:Bufsize+b.size];
	} else
		b.dirty = 0;
	b.bufpos += big size;
	b.index -= size;
	if(err)
		return ERROR;
	return size;
}

Iobuf.close(b: self ref Iobuf)
{
	if (b.fd == nil) {
		nofill(b);
		return;
	}
	if (b.dirty)
		b.flush();
	b.fd = nil;
	b.buffer = nil;
}

Iobuf.flush(b: self ref Iobuf): int
{
	if (b.fd == nil)
		return ERROR;
	if (b.lastop == OREAD){
		b.bufpos = b.filpos;
		b.size = 0;
		return 0;
	}
	while (b.dirty) {
		if (writechunk(b) < 0)
			return ERROR;
		if (b.index < 0) {
			b.bufpos += big b.index;
			b.index = 0;
		}
	}
	return 0;
}

Iobuf.seek(b: self ref Iobuf, off: big, start: int): big
{
	npos: big;

	if (b.fd == nil){
		if(filler(b) != nil)
			return big ERROR;
	}
	case (start) {
	0 =>	# absolute address
		npos = off;
	1 =>	# offset from current location
		npos = b.bufpos + big b.index + off;
		off = npos;
		start = Sys->SEEKSTART;
	2 =>	# offset from EOF
		npos = big -1;
	* =>	return big ERROR;
	}
	if (b.bufpos <= npos && npos < b.bufpos + big b.size) {
		b.index = int(npos - b.bufpos);
		return npos;
	}
	if (b.fd == nil || b.dirty && b.flush() < 0)
		return big ERROR;
	b.size = 0;
	b.index = 0;
	if ((s := sys->seek(b.fd, off, start)) < big 0) {
		b.filpos = b.bufpos = big 0;
		return big ERROR;
	}
	b.bufpos = b.filpos = s;
	return b.bufpos = b.filpos = s;
}

Iobuf.offset(b: self ref Iobuf): big
{
	return b.bufpos + big b.index;
}

write2read(b: ref Iobuf): int
{
	while (b.dirty) 
		if (b.flush() < 0)
			return ERROR;
	b.bufpos = b.filpos;
	b.size = 0;
	b.lastop = OREAD;
	if ((r := readchunk(b)) < 0)
		return r;
	if (b.index > b.size)
		return EOF;
	return 0;
}

Iobuf.read(b: self ref Iobuf, buf: array of byte, n: int): int
{
	if (b.mode == OWRITE)
		return ERROR;
	if (b.lastop != OREAD){
		if ((r := write2read(b)) < 0)
			return r;
	}
	k := n;
	while (b.size - b.index < k) {
		buf[0:] = b.buffer[b.index:b.size];
		buf = buf[b.size - b.index:];
		k -= b.size - b.index;

		b.bufpos += big b.size;
		b.index = 0;
		b.size = 0;
		if ((r := readchunk(b)) < 0) {
			if(r == EOF || n != k)
				return n-k;
			return ERROR;
		}
	}
	buf[0:] = b.buffer[b.index:b.index+k];
	b.index += k;
	return n;
}

Iobuf.getb(b: self ref Iobuf): int
{
	if(b.lastop != OREAD){
		if(b.mode == OWRITE)
			return ERROR;
		if((r := write2read(b)) < 0)
			return r;
	}
	if (b.index == b.size) {
		b.bufpos += big b.index;
		b.index = 0;
		b.size = 0;
		if ((r := readchunk(b)) < 0)
			return r;
	}
	return int b.buffer[b.index++];
}

Iobuf.ungetb(b: self ref Iobuf): int
{
	if(b.mode == OWRITE || b.lastop != OREAD)
		return ERROR;
	b.index--;
	return 1;
}

Iobuf.getc(b: self ref Iobuf): int
{
	r, i, s:	int;

	if(b.lastop != OREAD){
		if(b.mode == OWRITE)
			return ERROR;
		if((r = write2read(b)) < 0)
			return r;
	}
	for(;;) {
		if(b.index < b.size) {
			r = int b.buffer[b.index];
			if(r < UTFself){
				b.index++;
				return r;
			}
			(r, i, s) = sys->byte2char(b.buffer[0:b.size], b.index);
			if (i != 0) {
				b.index += i;
				return r;
			}
			b.buffer[0:] = b.buffer[b.index:b.size];
		}
		b.bufpos += big b.index;
		b.size -= b.index;
		b.index = 0;
		if ((r = readchunk(b)) < 0)
			return r;
	}
	# Not reached:
	return -1;
}

Iobuf.ungetc(b: self ref Iobuf): int
{
	if(b.index == 0 || b.mode == OWRITE || b.lastop != OREAD)
		return ERROR;
	stop := b.index - Sys->UTFmax;
	if(stop < 0)
		stop = 0;
	buf := b.buffer[0:b.size];
	for(i := b.index-1; i >= stop; i--){
		(nil, n, s) := sys->byte2char(buf, i);
		if(s && i + n == b.index){
			b.index = i;
			return 1;
		}
	}
	b.index--;

	return 1;
}

# optimised when term < UTFself (common case)
tgets(b: ref Iobuf, t: int): string
{
	str: string;
	term := byte t;
	for(;;){
		start := b.index;
		end := start + sys->utfbytes(b.buffer[start:], b.size-start);
		buf := b.buffer;
		# XXX could speed up by adding extra byte to end of buffer and
		# placing a sentinel there (eliminate one test, perhaps 35% speedup).
		# (but not when we've been given the buffer externally)
		for(i := start; i < end; i++){
			if(buf[i] == term){
				i++;
				str += string buf[start:i];
				b.index = i;
				return str;
			}
		}
		str += string buf[start:i];
		if(i < b.size)
			b.buffer[0:] = buf[i:b.size];
		b.size -= i;
		b.bufpos += big i;
		b.index = 0;
		if(readchunk(b) < 0)
			break;
	}
	return str;
}
		
Iobuf.gets(b: self ref Iobuf, term: int): string
{
	i: int;

	if(b.mode == OWRITE)
		return nil;
	if(b.lastop != OREAD && write2read(b) < 0)
		return nil;
#	if(term < UTFself)
#		return tgets(b, term);
	str: string;
	ch := -1;
	for (;;) {
		start := b.index;
		n := 0;
		while(b.index < b.size){
			(ch, i, nil) = sys->byte2char(b.buffer[0:b.size], b.index);
			if(i == 0)	# too few bytes for full Rune
				break;
			n += i;
			b.index += i;
			if(ch == term)
				break;
		}
		if(n > 0)
			str += string b.buffer[start:start+n];
		if(ch == term)
			return str;
		b.buffer[0:] = b.buffer[b.index:b.size];
		b.bufpos += big b.index;
		b.size -= b.index;
		b.index = 0;
		if (readchunk(b) < 0)
			break;
	}
	return str;	# nil at EOF
}

Iobuf.gett(b: self ref Iobuf, s: string): string
{
	r := "";
	if (b.mode == OWRITE || (ch := b.getc()) < 0)
		return nil;
	do {
		r[len r] = ch;
		for (i:=0; i<len(s); i++)
			if (ch == s[i])
				return r;
	} while ((ch = b.getc()) >= 0);
	return r;
}

read2write(b: ref Iobuf)
{
	# last operation was a read
	b.bufpos += big b.index;
	b.size = 0;
	b.index = 0;
	b.lastop = OWRITE;
}

Iobuf.write(b: self ref Iobuf, buf: array of byte, n: int): int
{
	if(b.lastop != OWRITE) {
		if(b.mode == OREAD)
			return ERROR;
		read2write(b);
	}
	start := 0;
	k := n;
	while(k > 0){
		nw := Bufsize - b.index;
		if(nw > k)
			nw = k;
		end := start + nw;
		b.buffer[b.index:] = buf[start:end];
		start = end;
		b.index += nw;
		k -= nw;
		if(b.index > b.size)
			b.size = b.index;
		b.dirty = 1;
		if(b.size == Bufsize && writechunk(b) < 0)
			return ERROR;
	}
	return n;
}

Iobuf.putb(b: self ref Iobuf, c: byte): int
{
	if(b.lastop != OWRITE) {
		if(b.mode == OREAD)
			return ERROR;
		read2write(b);
	}
	b.buffer[b.index++] = c;
	if(b.index > b.size)
		b.size = b.index;
	b.dirty = 1;
	if(b.size >= Bufsize) {
		if (b.fd == nil)
			return ERROR;
		if (writechunk(b) < 0)
			return ERROR;
	}
	return 0;
}

Iobuf.putc(b: self ref Iobuf, c: int): int
{
	if(b.lastop != OWRITE) {
		if (b.mode == OREAD)
			return ERROR;
		read2write(b);
	}
	if(c < UTFself)
		b.buffer[b.index++] = byte c;
	else
		b.index += sys->char2byte(c, b.buffer, b.index);
	if (b.index > b.size)
		b.size = b.index;
	b.dirty = 1;
	if (b.size >= Bufsize) {
		if (writechunk(b) < 0)
			return ERROR;
	}
	return 0;
}

Iobuf.puts(b: self ref Iobuf, s: string): int
{
	if(b.lastop != OWRITE) {
		if (b.mode == OREAD)
			return ERROR;
		read2write(b);
	}
	n := len s;
	if (n == 0)
		return 0;
	ind := b.index;
	buf := b.buffer;
	for(i := 0; i < n; i++){
		c := s[i];
		if(c < UTFself)
			buf[ind++] = byte c;
		else
			ind += sys->char2byte(c, buf, ind);
		if(ind >= Bufsize){
			b.index = ind;
			if(ind > b.size)
				b.size = ind;
			b.dirty = 1;
			if(writechunk(b) < 0)
				return ERROR;
			ind = b.index;
		}
	}
	b.dirty = b.index != ind;
	b.index = ind;
	if (ind > b.size)
		b.size = ind;
	return n;
}

filler(b: ref Iobuf): ref Filler
{
	for (f := fillers; f != nil; f = f.next)
		if(f.iobuf == b)
			return f;
	return nil;
}

Iobuf.setfill(b: self ref Iobuf, fill: BufioFill)
{
	if ((f := filler(b)) != nil)
		f.fill = fill;
	else
		fillers = ref Filler(b, fill, fillers);
}

nofill(b: ref Iobuf)
{
	prev: ref Filler;
	for(f := fillers; f != nil; f = f.next) {
		if(f.iobuf == b) {
			if (prev == nil)
				fillers = f.next;
			else
				prev.next = f.next;
		}
		prev = f;
	}
}
