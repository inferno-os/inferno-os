Arg : module
{
	PATH: con "/dis/lib/arg.dis";

	init: fn(argv: list of string);
	setusage: fn(usage: string);
	usage: fn();
	opt: fn(): int;
	arg: fn(): string;
	earg: fn(): string;

	progname: fn(): string;
	argv: fn(): list of string;
};
