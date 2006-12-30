RFC822: module
{
	PATH: con "/dis/lib/rfc822.dis";

	init: fn(b: Bufio);

	# TO DO: multipart ...

	# token values reserved to represent a word and a quoted string
	Word, QString: con 1+iota;

	Maxrequest: con 16*1024;	# more than enough for anything sensible

	Rfclex: adt {
		fd:	ref Bufio->Iobuf;	# open on a single line
		wordval:	string;		# text if Word or QString
		tok:	int;				# last token seen
		eof:	int;				# end of file (ignore subsequent ungetc)

		seen:	list of (int, string);	# pushback

		mk:		fn(a: array of byte): ref Rfclex;
		getc:		fn(p: self ref Rfclex): int;
		ungetc:	fn(p: self ref Rfclex);
		lex:		fn(p: self ref Rfclex): int;
		unlex:	fn(p: self ref Rfclex);
		skipws:	fn(p: self ref Rfclex): int;

		line:		fn(p: self ref Rfclex): string;
	};

	readheaders:	fn(fd: ref Bufio->Iobuf, limit: int): array of (string, array of byte);
	parseparams:	fn(ps: ref Rfclex): list of (string, string);
	parsecontent:	fn(ps: ref Rfclex, multipart: int, head: list of ref Content): list of ref Content;
	mimefields:	fn(ps: ref Rfclex): list of (string, list of (string, string));
	# TO DO: parse addresses

	quotable:	fn(s: string): int;
	quote:	fn(s: string): string;

	# convert an epoch time into http-formatted text
	sec2date: fn(secs: int): string;

	# convert a date in http text format to seconds from epoch
	date2sec: fn(s: string): int;

	# current time
	now:	fn(): int;

	# current time as a string
	time:	fn(): string;

	#
	# mime-related things
	#
	Content: adt{
		generic: string;
		specific: string;
		params: list of (string, string);

		mk:	fn(generic: string, specific: string, params: list of (string, string)): ref Content;
		check: fn(c: self ref Content, oks: list of ref Content): int;
		text:	fn(c: self ref Content): string;
	};

	suffixclass: fn(name: string): (ref Content, ref Content);
	dataclass:	fn(a: array of byte): (ref Content, ref Content);
};
