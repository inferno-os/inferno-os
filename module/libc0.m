Libc0: module
{
	PATH: con "/dis/lib/libc0.dis";

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

	strlen: fn(s: array of byte): int;
	strcmp: fn(s1: array of byte, s2: array of byte): int;
	strcpy: fn(s1: array of byte, s2: array of byte): array of byte;
	strcat: fn(s1: array of byte, s2: array of byte): array of byte;
	strncmp: fn(s1: array of byte, s2: array of byte, n: int): int;
	strncpy: fn(s1: array of byte, s2: array of byte, n: int): array of byte;
	strncat: fn(s1: array of byte, s2: array of byte, n: int): array of byte;
	strdup: fn(s: array of byte): array of byte;
	strchr: fn(s: array of byte, n: int): array of byte;
	strrchr: fn(s: array of byte, n: int): array of byte;

	abs: fn(n: int): int;
	min: fn(m: int, n: int): int;
	max: fn(m: int, n: int): int;

	ls2aab: fn(argl: list of string): array of array of byte;
	s2ab: fn(s: string): array of byte;
	ab2s: fn(a: array of byte): string;
};
