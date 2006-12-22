Profile: module
{
	PATH: con "/dis/lib/profile.dis";

	Range: adt{
		l: int;
		u: int;
		f: int;
		n: cyclic ref Range;
	};

	Funprof: adt{
		name: string;
		# file: string;
		line: int;
		count: int;
		counte: int;
	};

	Modprof: adt{
		name: string;
		path: string;
		srcpath: string;
		rawtab: array of (int, int);
		linetab: array of int;
		rngtab: array of ref Range;
		funtab: array of Funprof;
		total: int;
		totals: array of int;
		coverage: int;
	};

	Prof: adt{
		mods: list of Modprof;
		total: int;
		totals: array of int;
	};

	Coverage: type list of (string, int, list of (list of (int, int, int), string));

	# constants to or into second arg of show()
	MODULE: con 1;	# give stats for each module
	FUNCTION: con 2;	# give stats for each function
	LINE: con 4;		# give stats for each line
	VERBOSE: con 8;	# full stats
	FULLHDR: con 16;	# file:lineno: on each line of output
	FREQUENCY: con 32;	# show frequency rather than coverage

	init: fn(): int;
	lasterror: fn(): string;
	profile: fn(m: string): int;
	sample: fn(i: int): int;
	start: fn(): int;
	stop: fn(): int;
	stats: fn() : Prof;
	show: fn(p: Prof, v: int): int;
	end: fn(): int;

	# coverage profiling specific functions

	cpstart: fn(pid: int): int;
	cpstats: fn(rec: int, v: int): Prof;
	cpfstats: fn(v: int): Prof;
	cpshow: fn(p: Prof, v: int): int;

	coverage: fn(p: Prof, v: int): Coverage;

	# memory profiling specific functions

	MAIN: con 1;
	HEAP: con 2;
	IMAGE: con 4;

	memstart: fn(mem: int): int;
	memstats: fn(): Prof;
	memshow: fn(p: Prof, v: int): int;

};
