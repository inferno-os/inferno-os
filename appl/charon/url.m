Url: module
{
	PATH : con "/dis/charon/url.dis";

	# "Common Internet Scheme" url syntax (rfc 1808)
	#
	#    <scheme>://<user>:<passwd>@<host>:<port>/<path>;<params>?<query>#<fragment>
	#
	# relative urls might omit some prefix of the above
	# the path of absolute urls include the leading '/'
	Parsedurl: adt
	{
		scheme:	string;
		user:		string;
		passwd:	string;
		host:		string;
		port:		string;
		path:	string;
		params:	string;
		query:	string;
		frag:		string;

		tostring: fn(u: self ref Parsedurl): string;
	};

	init: fn(): string;	# call before anything else
	parse: fn(url: string): ref Parsedurl;
	mkabs: fn(u, base: ref Parsedurl): ref Parsedurl;
};

