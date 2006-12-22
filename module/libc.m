Libc: module
{
	PATH: con "/dis/lib/libc.dis";

	isalnum: fn(c: int): int;
	isalpha: fn(c: int): int;
	isascii: fn(c: int): int;
	iscntrl: fn(c: int): int;
	isdigit: fn(c: int): int;
	isgraph: fn(c: int): int;
	islower: fn(c: int): int;
	isprint: fn(c: int): int;
	ispunct: fn(c: int): int;
	isspace: fn(c: int): int;
	isupper: fn(c: int): int;
	isxdigit: fn(c: int): int;

	tolower: fn(c: int): int;
	toupper: fn(c: int): int;
	toascii: fn(c: int): int;

	strchr: fn(s: string, n: int): int;
	strrchr: fn(s: string, n: int): int;
	strncmp: fn(s1: string, s2: string, n: int): int;

	abs: fn(n: int): int;
	min: fn(m: int, n: int): int;
	max: fn(m: int, n: int): int;

};
