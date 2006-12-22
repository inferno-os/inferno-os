Plumbing: module
{

	PATH:	con "/dis/lib/plumbing.dis";

	Pattern: adt
	{
		field:		string;
		pred:	string;
		arg:		string;
		extra:	list of string;
		expand:	int;
		regex:	Regex->Re;
	};

	Rule:	adt
	{
		pattern:	array of ref Pattern;
		action:	array of ref Pattern;
	};

	init:	fn(regexmod: Regex, args: list of string): (list of ref Rule, string);
};
