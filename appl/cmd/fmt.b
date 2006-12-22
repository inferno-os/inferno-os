implement Fmt;

#
#	Copyright © 2002 Lucent Technologies Inc.
#	based on the Plan 9 command; subject to the Lucent Public License 1.02
#	this Vita Nuova variant uses Limbo channels and processes to avoid accumulating words
#

#
#  block up paragraphs, possibly with indentation
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "arg.m";

Fmt: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

extraindent := 0;	# how many spaces to indent all lines
indent := 0;	# current value of indent, before extra indent
length := 70;	# how many columns per output line
join := 1;	# can lines be joined?
maxtab := 8;
bout: ref Iobuf;

Word: adt {
	text:	string;
	indent:	int;
	bol:	int;
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg := load Arg Arg->PATH;

	arg->init(args);
	arg->setusage("fmt [-j] [-i indent] [-l length] [file...]");
	while((c := arg->opt()) != 0) 
		case(c){
		'i' =>
			extraindent = int arg->earg();
		'j' =>
			join = 0;
		'w' or 'l' =>
			length = int arg->earg();
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(length <= extraindent){
		sys->fprint(sys->fildes(2), "fmt: line length<=indentation\n");
		raise "fail:length";
	}
	arg = nil;

	err := "";
	bout = bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	if(args == nil){
		bin := bufio->fopen(sys->fildes(0), Bufio->OREAD);
		fmt(bin);
	}else
		for(; args != nil; args = tl args){
			bin := bufio->open(hd args, Bufio->OREAD);
			if(bin == nil){
				sys->fprint(sys->fildes(2), "fmt: can't open %s: %r\n", hd args);
				err = "open";
			}else{
				fmt(bin);
				if(tl args != nil)
					bout.putc('\n');
			}
		}
	bout.flush();
	if(err != nil)
		raise "fail:"+err;
}

fmt(f: ref Iobuf)
{
	words := chan of ref Word;
	spawn parser(f, words);
	printwords(words);
}

parser(f: ref Iobuf, words: chan of ref Word)
{
	while((s := f.gets('\n')) != nil){
		if(s[len s-1] == '\n')
			s = s[0:len s-1];
		parseline(s, words);
	}
	words <-= nil;
}

parseline(line: string, words: chan of ref Word)
{
	ind: int;
	(line, ind) = indentof(line);
	indent = ind;
	bol := 1;
	for(i:=0; i < len line;){
		# find next word
		if(line[i] == ' ' || line[i] == '\t'){
			i++;
			continue;
		}
		# where does this word end?
		for(l:=i; l < len line; l++)
			if(line[l]==' ' || line[l]=='\t')
				break;
		words <-= ref Word(line[i:l], indent, bol);
		bol = 0;
		i = l;
	}
	if(bol)
		words <-= ref Word("", -1, bol);
}

indentof(line: string): (string, int)
{
	ind := 0;
	for(i:=0; i < len line; i++)
		case line[i] {
		' ' =>
			ind++;
		'\t' =>
			ind += maxtab;
			ind -= ind%maxtab;
		* =>
			return (line, ind);
		}
	# plain white space doesn't change the indent
	return (line, indent);
}
	
printwords(words: chan of ref Word)
{
	# one output line per loop
	nw := <-words;
	while((w := nw) != nil){
		# if it's a blank line, print it
		if(w.indent == -1){
			bout.putc('\n');
			nw = <-words;
			continue;
		}
		# emit leading indent
		col := extraindent+w.indent;
		printindent(col);
		# emit words until overflow; always emit at least one word
		for(n:=0;; n++){
			bout.puts(w.text);
			col += len w.text;
			if((nw = <-words) == nil)
				break;	# out of words
			if(nw.indent != w.indent)
				break;	# indent change
			nsp := nspaceafter(w.text);
			if(col+nsp+len nw.text > extraindent+length)
				break;	# fold line
			if(!join && nw.bol)
				break;
			for(j:=0; j<nsp; j++)
				bout.putc(' ');	# emit space; another word will follow
			col += nsp;
			w = nw;
		}
		bout.putc('\n');
	}
}

printindent(w: int)
{
	while(w >= maxtab){
		bout.putc('\t');
		w -= maxtab;
	}
	while(--w >= 0)
		bout.putc(' ');
}

# give extra space if word ends with punctuation
nspaceafter(s: string): int
{
	if(len s < 2)
		return 1;
	if(len s < 4 && s[0] >= 'A' && s[0] <= 'Z')
		return 1;	# assume it's a title, not full stop
	if((c := s[len s-1]) == '.' || c == '!' || c == '?')
		return 2;
	return 1;
}
