implement Translate;

#
# prototype string translation for natural language substitutions
#
# Copyright © 2000 Vita Nuova Limited.  All rights reserved.
#

include "sys.m";
	sys:	Sys;

include "bufio.m";

include "translate.m";

NTEXT: con 131;	# prime
NNOTE: con 37;

init()
{
	sys = load Sys Sys->PATH;
}

opendict(file: string): (ref Dict, string)
{
	d := Dict.new();
	return (d, d.add(file));
}


opendicts(files: list of string): (ref Dict, string)
{
	d := Dict.new();
	err: string;
	for(; files != nil; files = tl files){
		e := d.add(hd files);
		if(e != nil){
			if(err != nil)
				err += "; ";
			err += (hd files)+":"+e;
		}
	}
	return (d, err);
}

Dict.new(): ref Dict
{
	d := ref Dict;
	d.texts = array[NTEXT] of list of ref Phrase;
	d.notes = array[NNOTE] of list of ref Phrase;
	return d;
}

Dict.xlate(d: self ref Dict, text: string): string
{
	return d.xlaten(text, nil);
}

Dict.xlaten(d: self ref Dict, text: string, note: string): string
{
	nnote := 0;
	if(note != nil){
		pnote := look(d.notes, note);
		if(pnote != nil)
			nnote = pnote.n + 1;
	}
	(h, code) := hash(text, len d.texts);
	for(l := d.texts[h]; l != nil; l = tl l){
		p := hd l;
		if(p.hash == code && p.key == text && p.note == nnote)
			return p.text;
	}
	return text;
}

mkdictname(locale, app: string): string
{
	if(locale == nil || locale == "default")
		return "/locale/dict/"+app;	# looks better
	return "/locale/"+locale+"/dict/"+app;
}

#
# eventually could load a compiled version of the tables
# (allows some consistency checking, etc)
#
Dict.add(d: self ref Dict, file: string): string
{
	bufio := load Bufio Bufio->PATH;
	if(bufio == nil)
		return "can't load Bufio";
	fd := bufio->open(file, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("%r");
	ntext := 0;
	nnote := 0;
	errs: string;
	for(lineno := 1; (line := bufio->fd.gets('\n')) != nil; lineno++){
		if(line[0] == '#' || line[0] == '\n')
			continue;
		(key, note, text, err) := parseline(line);
		if(err != nil){
			if(errs != nil)
				errs += ",";
			errs += string lineno+":"+err;
		}
		pkey := look(d.texts, key);
		if(pkey != nil)
			key = pkey.key;		# share key strings (useful with notes)
		pkey = insert(d.texts, key);
		if(note != nil){
			pnote := look(d.notes, note);
			if(pnote == nil){
				pnote = insert(d.notes, note);
				pnote.n = nnote++;
			}
			pkey.note = pnote.n+1;
		}
		pkey.text = text;
		pkey.n = ntext++;
	}
	return errs;
}

parseline(line: string): (string, string, string, string)
{
	note, text: string;

	(key, i) := quoted(line, 0);
	if(i < 0)
		return (nil, nil, nil, "bad key field");
	i = skipwhite(line, i);
	if(i < len line && line[i] == '('){
		(note, i) = delimited(line, i+1, ')');
		if(note == nil)
			return (nil, nil, nil, "bad note syntax");
	}
	i = skipwhite(line, i);
	if(i >= len line)
		return (key, note, key, nil);	# identity
	if(line[i] != '=')
		return (nil, nil, nil, "missing/misplaced '='");
	(text, i) = quoted(line, i+1);
	if(i < 0)
		return (nil, nil, nil, "missing translation");
	return (key, note, text, nil);
}

quoted(s: string, i: int): (string, int)
{
	i = skipwhite(s, i);
	if(i >= len s || (qc := s[i]) != '"' && qc != '\'')
		return (nil, -1);
	return delimited(s, i+1, qc);
}

delimited(s: string, i: int, qc: int): (string, int)
{
	o := "";
	b := i;
	for(; i < len s; i++){
		c := s[i];
		if(c == qc)
			return (o, i+1);
		if(c == '\\' && i+1 < len s){
			i++;
			c = s[i];
			case c {
			'n' =>	c = '\n';
			'r' =>	c = '\r';
			't' =>	c = '\t';
			'b' => c = '\b';
			'a' => c = '\a';
			'v' => c = '\v';
			'u' =>
				(c, i)  = hex2c(s, i + 1);
				i--;
			'0' => c = '\0';
			* => ;
			}
		}
		o[len o] = c;
	}
	return (nil, -1);
}

hex2c(s: string, i: int): (int, int)
{
	x := 0;
	for (j := i; j < i + 4; j++) {
		if (j >= len s)
			return (Sys->UTFerror, j);
		c := s[j];
		if (c >= '0' && c <= '9')
			c = c - '0';
		else if (c >= 'a' && c <= 'f')
			c = c - 'a' + 10;
		else if (c >= 'A' && c <= 'F')
			c = c - 'A' + 10;
		else
			return (Sys->UTFerror, j);
		x = (x * 16) + c;
	}
	return (x, j);
}

skipwhite(s: string, i: int): int
{
	for(; i<len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n'); i++)
		;
	return i;
}

look(tab: array of list of ref Phrase, key: string): ref Phrase
{
	(h, code) := hash(key, len tab);
	for(l := tab[h]; l != nil; l = tl l){
		p := hd l;
		if(p.hash == code && p.key == key)
			return p;
	}
	return nil;
}

insert(tab: array of list of ref Phrase, key: string): ref Phrase
{
	(h, code) := hash(key, len tab);
	p := ref Phrase;
	p.n = 0;
	p.note = 0;
	p.key = key;
	p.hash = code;
	#sys->print("%s = %ux [%d]\n", key, code, h);
	tab[h] = p :: tab[h];
	return p;
}

# hashpjw from aho & ullman
hash(s: string, n: int): (int, int)
{
	h := 0;
	for(i:=0; i<len s; i++){
		h = (h<<4) + s[i];
		if((g := h & int 16rF0000000) != 0)
			h ^= ((g>>24) & 16rFF) | g;
	}
	return ((h&~(1<<31))%n, h);
}
