Daytime: module
{
	PATH:	con "/dis/lib/daytime.dis";

	Tm: adt {
		sec:	int;	# seconds (0 to 59)
		min:	int;	# minutes (0 to 59)
		hour:	int;	# hours (0 to 23)
		mday:	int;	# day of the month (1 to 31)
		mon:	int;	# month (0 to 11)
		year:	int;	# year-1900; 2000AD is 100
		wday:	int;	# day of week (0 to 6, Sunday is 0)
		yday:	int;	# day of year (0 to 365)
		zone:	string;	# time zone name
		tzoff:	int;	# time zone offset (seconds from GMT)
	};

	# now:
	# return the time in seconds since the epoch
	#
	# time:
	# return the current local time as string
	#
	# text:
	# convert a time structure from local or gmt
	# into a text string
	#
	# filet:
	# return a string containing the file time
	# prints mon day hh:mm if the file is < 6 months old
	# 	 mon day year  if > 6 months old
	#
	# local:
	# uses /locale/timezone to convert an epoch time in seconds into
	# a local time structure
	#
	# gmt:
	# return a time structure for GMT
	#
	# tm2epoch:
	# convert a time structure to an epoch time in seconds
	#
	# string2tm:
	# parse a string representing a date into a time structure
	now:		fn(): int;
	time:		fn(): string;
	text:		fn(tm: ref Tm): string;
	filet:		fn(now, file: int): string;
	local:		fn(tim: int): ref Tm;
	gmt:		fn(tim: int): ref Tm;
	tm2epoch:	fn(tm: ref Tm): int;
	string2tm:	fn(date: string): ref Tm;
};
