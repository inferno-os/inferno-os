tohex(c: int): int
{
	if(c > 9)
		return c-10+'A';
	return c+'0';
}

fromhex(ex: ref Exec, c1: int, c2: int): int
{
	c1 = hexdigit(c1);
	c2 = hexdigit(c2);
	if(c1 < 0 || c2 < 0)
		runtime(ex, URIError, "bad hex digit");
	return 16*c1+c2;
}

isres(c: int): int
{
	return c == ';' || c == '/' || c == '?' || c == ':' || c == '@' || c == '&' || c == '=' || c == '+' || c == '$' || c == ',' || c == '#';		# add '#' here for convenience
}

isunesc(c: int): int
{
	return isalpha(c) || isdigit(c) || c == '-' || c == '_' || c == '.' || c == '!' || c == '~' || c == '*' || c == ''' || c == '(' || c == ')';
}

encode(ex: ref Exec, s: string, flag: int): string
{
	m := len s;
	r := "";
	n := len r;
	for(k := 0; k < m; k++){
		c := s[k];
		if(isunesc(c) || (flag && isres(c)))
			r[n++] = c;
		else{
			if(c >= 16rdc00 && c <= 16rdfff)
				runtime(ex, URIError, "char out of range");
			if(c < 16rd800 || c > 16rdbff)
				;
			else{
				if(++k == m)
					runtime(ex, URIError, "char missing");
				if(s[k] < 16rdc00 || s[k] > 16rdfff)
					runtime(ex, URIError, "char out of range");
				c = (c-16rd800)*16r400 + (s[k]-16rdc00) + 16r10000;
			}
			s1 := "Z";
			s1[0] = c;
			o := array of byte s1;
			for(j := 0; j < len o; j++){
				r += sys->sprint("%%%c%c", tohex(int o[j]/16), tohex(int o[j]%16));
				n += 3;
			}
		}
	}
	return r;
}

decode(ex: ref Exec, s: string, flag: int): string
{
	m := len s;
	r := "";
	n := len r;
	for(k := 0; k < m; k++){
		c := s[k];
		if(c != '%')
			r[n++] = c;
		else{
			start := k;
			if(k+2 >= m)
				runtime(ex, URIError, "char missing");
			c = fromhex(ex, s[k+1], s[k+2]);
			k += 2;
			if((c&16r80 == 0)){
				if(flag && isres(c)){
					r += s[start: k+1];
					n += k+1-start;
				}
				else
					r[n++] = c;
			}
			else{
				for(i := 1; ((c<<i)&16r80) == 0; i++)
					;
				if(i == 1 || i > 4)
					runtime(ex, URIError, "bad hex number");
				o := array[i] of byte;
				o[0] = byte c;
				if(k+3*(n-1) >= m)
					runtime(ex, URIError, "char missing");
				for(j := 1; j < i; j++){
					if(s[++k] != '%')
						runtime(ex, URIError, "% missing");
					c = fromhex(ex, s[k+1], s[k+2]);
					k += 2;
					if((c&16rc0) != 2)
						runtime(ex, URIError, "bad hex number");
					o[j] = byte c;
				}
				(c, nil, nil) = sys->byte2char(o, 0);
				if(c < 16r10000){
					if(flag && isres(c)){
						r += s[start: k+1];
						n += k+1-start;
					}
					else
						r[n++] = c;
				}
				else if(c > 16r10ffff)
					runtime(ex, URIError, "bad byte sequence");
				else{
					r[n++] = ((c-16r10000)&16r3ff)+16rdc00;
					r[n++] = (((c-16r10000)>>10)&16r3ff)+16rd800;
				}
			}
		}
	}
	return r;
}

cdecodeuri(ex: ref Exec, nil, nil: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	return strval(decode(ex, toString(ex, biarg(args, 0)), 1));
}

cdecodeuric(ex: ref Exec, nil, nil: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	return strval(decode(ex, toString(ex, biarg(args, 0)), 0));
}

cencodeuri(ex: ref Exec, nil, nil: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	return strval(encode(ex, toString(ex, biarg(args, 0)), 1));
}

cencodeuric(ex: ref Exec, nil, nil: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	return strval(encode(ex, toString(ex, biarg(args, 0)), 0));
}
