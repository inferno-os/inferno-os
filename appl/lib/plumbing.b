implement Plumbing;

include "sys.m";
	sys: Sys;

include "regex.m";
	regex: Regex;

include "plumbing.m";

init(regexmod: Regex, args: list of string): (list of ref Rule, string)
{
	sys = load Sys Sys->PATH;
	regex = regexmod;

	if(args == nil){
		user := readfile("/dev/user");
		if(user == nil)
			return (nil, sys->sprint("can't read /dev/user: %r"));
		filename := "/usr/"+user+"/plumbing";
		(rc, nil) := sys->stat(filename);
		if(rc < 0)
			filename = "/usr/"+user+"/lib/plumbing";
		args = filename :: nil;
	}
	r, rules: list of ref Rule;
	err: string;
	while(args != nil){
		filename := hd args;
		args = tl args;
		file := readfile(filename);
		if(file == nil)
			return (nil, sys->sprint("can't read %s: %r", filename));
		(r, err) = parse(filename, file);
		if(err != nil)
			return (nil, err);
		while(r != nil){
			rules = hd r :: rules;
			r = tl r;
		}
	}
	# reverse the rules
	r = nil;
	while(rules != nil){
		r = hd rules :: r;
		rules = tl rules;
	}
	return (r, nil);
}

readfile(filename: string): string
{
	fd := sys->open(filename, Sys->OREAD);
	if(fd == nil)
		return nil;
	(ok, dir) := sys->fstat(fd);
	if(ok < 0)
		return nil;
	size := int dir.length;
	if(size == 0)	# devices have length 0 sometimes
		size = 1000;
	b := array[size] of byte;
	n := sys->read(fd, b, len b);
	if(n <= 0)
		return nil;
	return string b[0:n];
}

parse(filename, file: string): (list of ref Rule, string)
{
	line: string;
	lineno := 0;
	i := 0;
	pats: list of ref Pattern;
	rules: list of ref Rule;
	while(i < len file){
		lineno++;
		(line, i) = nextline(file, i);
		(pat, err) := pattern(line);
		if(err != nil)
			return (nil, sys->sprint("%s:%d: %s", filename, lineno, err));
		if(pat == nil){
			if(pats==nil || !blank(line))	# comment line
				continue;
			(rul, err1) := rule(pats);
			if(err1 != nil)
				return (nil, sys->sprint("%s:%d: %s", filename, lineno-1, err1));
			rules = rul :: rules;
			pats = nil;
		}else
			pats = pat :: pats;
	}
	if(pats != nil){
		(rul, err1) := rule(pats);
		if(err1 != nil)
			return (nil, sys->sprint("%s:%d: %s", filename, lineno-1, err1));
		rules = rul :: rules;
	}
	# reverse the rules
	r: list of ref Rule;
	while(rules != nil){
		r = hd rules :: r;
		rules = tl rules;
	}
	return (r, nil);
}

nextline(file: string, i: int): (string, int)
{
	for(j:=i; j<len file; j++)
		if(file[j] == '\n')
			return (file[i:j], j+1);
	return (file[i:], len file);
}

blank(line: string): int
{
	for(i:=0; i<len line; i++)
		if(line[i]!=' ' && line[i]!='\t')
			return 0;
	return 1;
}

pattern(line: string): (ref Pattern, string)
{
	expand := 0;
	for(i:=0; i<len line; i++)
		if(line[i] == '$'){
			expand = 1;
			break;
		}
	(w, err) := words(line);
	if(err != nil)
		return (nil, err);
	if(w == nil)
		return (nil, nil);
	if(len w < 3)
		return (nil, "syntax error: too few words on line");
	pat := ref Pattern;
	pat.field = hd w;
	pat.pred = hd tl w;
	pat.arg = hd tl tl w;
	pat.extra = tl tl tl w;
	pat.expand = expand;
	return (pat, nil);
}

rule(pats: list of ref Pattern): (ref Rule, string)
{
	# pats is in reverse order on arrival
	actionpred := list of {"alwaysstart", "start", "to"};
	patternpred := list of {"is", "isdir", "isfile", "matches", "set"};
	npats := 0;
	nacts := 0;
	haveto := 0;
	for(l:=pats; l!=nil; l=tl l){
		pat := hd l;
		pred := pat.pred;
		noextra := 1;
		case pat.field {
		"plumb" =>
			nacts++;
			if(!oneof(pred, actionpred))
				return (nil, "illegal predicate "+pred+" in action");
			case pred {
			"to" or "alwaysstart" =>
				if(len pat.arg == 0)
					return (nil, "\"plumb "+pred+"\" must have non-empty target");
				haveto = 1;
			"start" =>
				noextra = 0;
			}
			if(npats != 0)
				return (nil, "actions must follow patterns in rule");
		"src" or "dst" or "dir" or "kind" or "attr" or "data" =>
			if(!oneof(pred, patternpred))
				return (nil, "illegal predicate "+pred+" in pattern");
			if(pred == "matches"){
				(pat.regex, nil) = regex->compile(pat.arg, 1);
				if(pat.regex == nil)
					return (nil, sys->sprint("error in regular expression '%s'", pat.arg));
			}
			npats++;
		}
		if(noextra && pat.extra != nil)
			return (nil, sys->sprint("too many words in '%s' pattern", pat.field));
	}
	if(haveto == 0)
		return (nil, "rule must have \"plumb to\" action");
	rule := ref Rule;
	rule.action = array[nacts] of ref Pattern;
	for(i:=nacts; --i>=0; ){
		rule.action[i] = hd pats;
		pats = tl pats;
	}
	rule.pattern = array[npats] of ref Pattern;
	for(i=npats; --i>=0; ){
		rule.pattern[i] = hd pats;
		pats = tl pats;
	}
	return (rule, nil);
}

oneof(word: string, words: list of string): int
{
	while(words != nil){
		if(word == hd words)
			return 1;
		words = tl words;
	}
	return 0;
}

words(line: string): (list of string, string)
{
	ws: list of string;
	i := 0;
	for(;;){
		# not in word; find beginning of word
		while(i<len line && (line[i]==' ' || line[i]=='\t'))
			i++;
		if(i==len line || line[i]=='#')
			break;
		# i is first character of word; is it quoted?
		if(line[i] == '\''){
			word := "";
			i++;
			while(i < len line){
				c := line[i++];
				if(c=='\''){
					if(i==len line || line[i]!='\'')
						break;
					# else it's a literal quote
					if(i < len line)
						i++;
				}
				word[len word] = c;
			}
			ws = word :: ws;
			continue;
		}
		# regular word; continue until white space or end
		start := i;
		while(i<len line && (line[i]!=' ' && line[i]!='\t'))
			i++;
		ws = line[start:i] :: ws;
	}
	r: list of string;
	while(ws != nil){
		r = hd ws :: r;
		ws = tl ws;
	}
	return (r, nil);
}
