implement CSV;

include "sys.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "csv.m";

init(b: Bufio)
{
	bufio = b;
}

getline(fd: ref Iobuf): list of string
{
	rl: list of string;
	for(;;){
		(w, end) := getfield(fd);
		if(rl == nil && w == nil && end < 0)
			return nil;
		rl = w :: rl;
		if(end != ',')
			break;
	}
	l: list of string;
	for(; rl != nil; rl = tl rl)
		l = hd rl :: l;
	return l;
}

getfield(fd: ref Iobuf): (string, int)
{
	w := "";
	if((c := getcr(fd)) == '"'){	# quoted field
		while((c = getcr(fd)) >= 0){
			if(c == '"'){
				c = getcr(fd);
				if(c != '"')
					break;
			}
			w[len w] = c;
		}
	}
	# unquoted text, possibly following quoted text above
	for(; c >= 0 && c != ',' && c != '\n'; c = getcr(fd))
		w[len w] = c;
	return (w, c);
}

getcr(fd: ref Iobuf): int
{
	c := fd.getc();
	if(c == '\r'){
		nc := fd.getc();
		if(nc >= 0 && nc != '\n')
			fd.ungetc();
		c = '\n';
	}
	return c;
}

quote(s: string): string
{
	sep := 0;
	for(i := 0; i < len s; i++)
		if((c := s[i]) == '"')
			return innerquote(s);
		else if(c == ',' || c == '\n')
			sep = 1;
	if(sep)
		return "\""+s+"\"";
	return s;
}

innerquote(s: string): string
{
	w := "\"";
	for(i := j := 0; i < len s; i++)
		if(s[i] == '"'){
			w += s[j: i+1];	# including "
			j = i;		# including " again
		}
	return w+s[j:i]+"\"";
}
