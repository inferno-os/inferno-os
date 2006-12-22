
Date: module{
	PATH : con "/dis/svc/httpd/date.dis";

	init: fn();
	dateconv: fn(secs :int): string; # returns an http formatted
					 # date representing secs.
	date2sec: fn(foo:string): int;   # parses a date and returns
					 # number of secs since the 
					 # epoch that it represents. 
};
