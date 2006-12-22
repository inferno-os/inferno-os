Url: module
{
	PATH : con "/dis/lib/url.dis";

	# scheme ids
	NOSCHEME, HTTP, HTTPS, FTP, FILE, GOPHER, MAILTO, NEWS,
		NNTP, TELNET, WAIS, PROSPERO, JAVASCRIPT, UNKNOWN: con iota;

	# general url syntax:
	#    <scheme>://<user>:<passwd>@<host>:<port>/<path>?<query>#<fragment>
	#
	# relative urls might omit some prefix of the above
	ParsedUrl: adt
	{
		scheme:	int;
		utf8:		int;		# strings not in us-ascii
		user:		string;
		passwd:	string;
		host:		string;
		port:		string;
		pstart:	string;	# what precedes <path>: either "/" or ""
		path:		string;
		query:	string;
		frag:		string;

		makeabsolute: fn(url: self ref ParsedUrl, base: ref ParsedUrl);
		tostring: fn(url: self ref ParsedUrl) : string;
	};

	schemes: array of string;

	init: fn();	# call before anything else
	makeurl: fn(s: string) : ref ParsedUrl;
};
