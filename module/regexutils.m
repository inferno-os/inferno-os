
include "regex.m";
	regex: Regex;
	
RegexUtils: module
{
	PATH:		con "/dis/lib/regexutils.dis";
	init:		fn();
	
	match:		fn(pattern: Regex->Re, s: string): string;
	match_mult:	fn(pattern: Regex->Re, s: string): array of (int, int);
	sub:		fn(text, pattern, new: string): string;
	sub_re:		fn(text: string, pattern: Regex->Re, new: string): string;
	subg:		fn(text, pattern, new: string): string;
	subg_re:	fn(text: string, pattern: Regex->Re, new: string): string;
};

