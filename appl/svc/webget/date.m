
Date: module{
	PATH : con "/dis/svc/webget/date.dis";

	dateconv: fn(secs :int): string; # returns an http formatted
					 # date representing secs.
	date2sec: fn(foo:string): int;   # parses a date and returns
					 # number of secs since the 
					 # epoch that it represents. 
	now: fn(): int;		# so don't have to load daytime too
	init: fn();			# to load needed modules
};
