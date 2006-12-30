URIs: module
{
	PATH: con "/dis/lib/w3c/uris.dis";

	# URI Generic Syntax (RFC 3986)
	#
	#	scheme://authority/path?query#fragment
	#
	URI: adt
	{
		scheme:	string;
		userinfo:	string;	# authority, part I
		host:		string;	# authority, part II
		port:		string;	# authority, part III
		path:		string;	# starts with / if path-abempty or path-absolute
		query:	string;	# includes ? if not nil
		fragment:	string;	# includes # if not nil

		parse:	fn(s: string): ref URI;
		text: fn(u: self ref URI): string;
		authority:	fn(u: self ref URI): string;
		addbase:	fn(u: self ref URI, base: ref URI): ref URI;
		copy:	fn(u: self ref URI): ref URI;
		hasauthority:	fn(u: self ref URI): int;
		isabsolute:	fn(u: self ref URI): int;
		nodots:	fn(u: self ref URI): ref URI;
		pathonly:	fn(u: self ref URI): ref URI;
		userpw:	fn(u: self ref URI): (string, string);	# ``deprecated format''
		eq:	fn(u: self ref URI, v: ref URI): int;
		eqf:	fn(u: self ref URI, v: ref URI): int;
	};

	init:	fn();
	dec:	fn(s: string): string;
	enc:	fn(s: string, safe: string): string;
};
