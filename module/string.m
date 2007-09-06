String: module
{
	PATH:		con	"/dis/lib/string.dis";

	# the second arg of the following is a character class
	#    e.g., "a-zA-Z", or "^ \t\n"
	# (ranges indicated by - except in first position;
	#  ^ is first position means "not in" the following class)
	# splitl splits just before first char in class;  (s, "") if no split
	# splitr splits just after last char in class; ("", s) if no split
	# drop removes maximal prefix in class
	# take returns maximal prefix in class

	splitl:		fn(s, cl: string): (string, string);
	splitr:		fn(s, cl: string): (string, string);
	drop:		fn(s, cl: string): string;
	take:		fn(s, cl: string): string;
	in:		fn(c: int, cl: string): int;

	# in these, the second string is a string to match, not a class
	splitstrl:	fn(s, t: string): (string, string);
	splitstrr:	fn(s, t: string): (string, string);

	# is first arg a prefix of second?
	prefix:		fn(pre, s: string): int;

	tolower:	fn(s: string): string;
	toupper:	fn(s: string): string;

	# string to int returning value, remainder
	toint:		fn(s: string, base: int): (int, string);
	tobig:		fn(s: string, base: int): (big, string);
	toreal:		fn(s: string, base: int): (real, string);

	# append s to end of l
	append:		fn(s: string, l: list of string): list of string;
	quoted:		fn(argv: list of string): string;
	quotedc:		fn(argv: list of string, cl: string): string;
	unquoted:		fn(args: string): list of string;
};
