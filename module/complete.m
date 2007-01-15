Complete: module
{
	PATH:	con "/dis/lib/complete.dis";

	Completion: adt {
		advance: int;	# whether forward progress has been made
		complete: int;	# whether the completion now represents a file or directory
		str:	string;	# string to advance, suffixed " " (file) or "/" (directory)
		nmatch: int;	# number of files that matched
		filename:	array of string;	# their names
	};

	init: fn();
	complete: fn(dir, s: string): (ref Completion, string);
};
