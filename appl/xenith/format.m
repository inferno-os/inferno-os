Format: module {
	PATH: con "/dis/xenith/format.dis";

	init: fn();

	# Find a text formatter for the given file path (by extension).
	# Returns (loaded Formatter module, nil) or (nil, error).
	find: fn(path: string): (Formatter, string);

	# Check if a path has a text formatter available.
	hasformatter: fn(path: string): int;
};
