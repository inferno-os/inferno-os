#
# HTTPS/HTTP client module
#
Webclient: module {
	PATH: con "/dis/lib/webclient.dis";

	init: fn(): string;

	MAXBODY: con 1048576;	# 1MB

	Header: adt {
		name:	string;
		value:	string;
	};

	Response: adt {
		statuscode:	int;
		status:		string;
		headers:	list of Header;
		body:		array of byte;

		hdrval:	fn(r: self ref Response, name: string): string;
	};

	request:	fn(method, url: string, hdrs: list of Header,
			   body: array of byte): (ref Response, string);
	get:		fn(url: string): (ref Response, string);
	post:		fn(url, contenttype: string,
			   body: array of byte): (ref Response, string);

	# TLS-integrated dial: connect TCP + TLS handshake
	tlsdial:	fn(addr, servername: string): (ref Sys->FD, string);
};
