Env: module {
	getenv:	fn(var: string): string;		# returns nil if var not set
	setenv:	fn(var: string, val: string): int;	# returns -1 on failure
	getall: fn(): list of (string, string);

	clone:	fn(): int;					# forks a copy of the environment, returns -1 on failure
	new:		fn(): int;					# sets up new empty environment, returns -1 on failure

	PATH:	con "/dis/lib/env.dis";
};
